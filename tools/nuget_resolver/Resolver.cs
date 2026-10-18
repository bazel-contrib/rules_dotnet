using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using NuGet.Common;
using NuGet.Configuration;
using NuGet.DependencyResolver;
using NuGet.Frameworks;
using NuGet.LibraryModel;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.RuntimeModel;
using NuGet.Versioning;

namespace NuGetResolver;

/// <summary>
/// Resolves the full transitive graph of a resolve spec, per framework, with
/// the same walker dotnet restore uses.
/// </summary>
public static class Resolver
{
    public static async Task<IReadOnlyDictionary<string, List<ResolvedPackage>>> ResolveAsync(
        ResolveSpec spec,
        string? netrcPath,
        CancellationToken cancellationToken)
    {
        var providers = spec.Sources
            .Select(source => new FeedDependencyProvider(
                Repository.Factory.GetCoreV3(Netrc.ApplyCredentials(source, netrcPath))))
            .ToList();

        var result = new Dictionary<string, List<ResolvedPackage>>(StringComparer.Ordinal);
        foreach (var tfm in spec.Frameworks)
        {
            NuGetFramework framework;
            try
            {
                framework = NuGetFramework.Parse(tfm);
            }
            catch (ArgumentException e)
            {
                throw new ResolveException($"Invalid target framework '{tfm}': {e.Message}");
            }

            result[tfm] = await ResolveFrameworkAsync(spec, framework, providers, cancellationToken);
        }

        return result;
    }

    private static async Task<List<ResolvedPackage>> ResolveFrameworkAsync(
        ResolveSpec spec,
        NuGetFramework framework,
        List<FeedDependencyProvider> providers,
        CancellationToken cancellationToken)
    {
        using var cacheContext = new SourceCacheContext();
        var walkContext = new RemoteWalkContext(
            cacheContext,
            PackageSourceMapping.GetPackageSourceMapping(NullSettings.Instance),
            NullLogger.Instance);
        foreach (var provider in providers)
        {
            walkContext.RemoteLibraryProviders.Add(provider);
        }

        var walker = new RemoteDependencyWalker(walkContext);

        // One synthetic root holding every requested package, so version
        // conflicts across the requests are detected exactly like restore does.
        // The root needs its own resolved item: the graph analysis tracks every
        // visited node's item (restore's project root has one too).
        var rootIdentity = new LibraryIdentity(
            "nuget_resolver_root", new NuGetVersion(0, 0, 0), LibraryType.Project);
        var root = new GraphNode<RemoteResolveResult>(new LibraryRange(
            "nuget_resolver_root",
            new VersionRange(new NuGetVersion(0, 0, 0)),
            LibraryDependencyTarget.Project))
        {
            Item = new GraphItem<RemoteResolveResult>(rootIdentity)
            {
                Data = new RemoteResolveResult
                {
                    Match = new RemoteMatch { Library = rootIdentity, Path = null, Provider = null },
                    Dependencies = new List<LibraryDependency>(),
                },
            },
        };
        foreach (var package in spec.Packages)
        {
            VersionRange range;
            try
            {
                range = VersionRange.Parse(package.Range);
            }
            catch (ArgumentException e)
            {
                throw new ResolveException($"Invalid version range '{package.Range}' for {package.Id}: {e.Message}");
            }

            root.InnerNodes.Add(await walker.WalkAsync(
                new LibraryRange(package.Id, range, LibraryDependencyTarget.Package),
                framework,
                runtimeIdentifier: null,
                runtimeGraph: RuntimeGraph.Empty,
                recursive: true));
        }

        // Analyze marks nodes accepted/rejected (nearest-wins) and reports
        // cycles and version conflicts over the whole tree.
        var analysis = root.Analyze();
        if (analysis.Cycles.Count > 0)
        {
            throw new ResolveException(
                "Dependency cycle detected: " +
                string.Join(", ", analysis.Cycles.Select(c => c.GetPath())));
        }

        if (analysis.VersionConflicts.Count > 0)
        {
            throw new ResolveException(
                "Version conflict detected: " +
                string.Join(", ", analysis.VersionConflicts.Select(c => c.Conflicting.GetPath())));
        }

        var accepted = new Dictionary<string, GraphNode<RemoteResolveResult>>(StringComparer.OrdinalIgnoreCase);
        var unresolved = new List<string>();
        CollectAccepted(root, accepted, unresolved);
        if (unresolved.Count > 0)
        {
            throw new ResolveException(
                $"Unable to resolve for {framework.GetShortFolderName()}: " + string.Join(", ", unresolved));
        }

        var packages = new List<ResolvedPackage>();
        foreach (var node in accepted.Values)
        {
            packages.Add(await DescribeAsync(node, cacheContext, cancellationToken));
        }

        return packages;
    }

    private static void CollectAccepted(
        GraphNode<RemoteResolveResult> node,
        Dictionary<string, GraphNode<RemoteResolveResult>> accepted,
        List<string> unresolved)
    {
        foreach (var child in node.InnerNodes)
        {
            if (child.Disposition == Disposition.Rejected)
            {
                continue;
            }

            if (child.Item == null || child.Item.Key.Type == LibraryType.Unresolved)
            {
                unresolved.Add(child.Key.Name);
                continue;
            }

            // On a conflict-free graph each package id has exactly one accepted node.
            accepted[child.Item.Key.Name] = child;
            CollectAccepted(child, accepted, unresolved);
        }
    }

    /// <summary>
    /// Downloads the nupkg of a resolved package, hashes the bytes, verifies
    /// the hash against the feed's registration metadata when the feed
    /// publishes one, and records the download URL.
    /// </summary>
    private static async Task<ResolvedPackage> DescribeAsync(
        GraphNode<RemoteResolveResult> node,
        SourceCacheContext cacheContext,
        CancellationToken cancellationToken)
    {
        var identity = node.Item!.Key;
        var provider = (FeedDependencyProvider)node.Item.Data.Match.Provider!;
        var version = identity.Version.ToNormalizedString();

        string? metadataHash = null;
        var urls = new List<string>();
        if (provider.IsHttp)
        {
            var serviceIndex = await provider.SourceRepository.GetResourceAsync<ServiceIndexResourceV3>(cancellationToken);
            var registrationBases = serviceIndex?.GetServiceEntryUris("RegistrationsBaseUrl/3.6.0") ?? Array.Empty<Uri>();
            if (registrationBases.Count == 0)
            {
                registrationBases = serviceIndex?.GetServiceEntryUris("RegistrationsBaseUrl") ?? Array.Empty<Uri>();
            }

            if (registrationBases.Count > 0)
            {
                var baseAddress = registrationBases[0].AbsoluteUri.TrimEnd('/') + "/";
                var leafUrl = $"{baseAddress}{identity.Name.ToLowerInvariant()}/{version.ToLowerInvariant()}.json";
                using var leaf = await GetJsonAsync(leafUrl, cancellationToken);
                if (leaf != null)
                {
                    urls.Add(leaf.RootElement.GetProperty("packageContent").GetString()!);
                    if (leaf.RootElement.TryGetProperty("catalogEntry", out var catalogEntry) &&
                        catalogEntry.ValueKind == JsonValueKind.Object &&
                        catalogEntry.TryGetProperty("packageHash", out var packageHash))
                    {
                        metadataHash = packageHash.GetString();
                    }
                }
            }

            if (urls.Count == 0)
            {
                // A V2 feed (or a V3 feed whose registration leaf did not
                // resolve): the package content lives at a fixed location.
                urls.Add($"{provider.Source.Source.TrimEnd('/')}/package/{identity.Name}/{version}");
            }
        }
        else
        {
            // A local folder feed. Flat (V2) layout: <dir>/<id>.<version>.nupkg.
            // nuget.org's flat downloads are lowercased, so probe the original
            // case first, then the lowercased flat name, then the hierarchical
            // (V3) layout: <dir>/<id>/<version>/<id>.<version>.nupkg.
            var localPath = Path.GetFullPath(
                Path.Combine(provider.Source.Source, $"{identity.Name}.{version}.nupkg"));
            if (!File.Exists(localPath))
            {
                localPath = Path.GetFullPath(Path.Combine(
                    provider.Source.Source,
                    $"{identity.Name.ToLowerInvariant()}.{version.ToLowerInvariant()}.nupkg"));
            }

            if (!File.Exists(localPath))
            {
                localPath = Path.GetFullPath(Path.Combine(
                    provider.Source.Source,
                    identity.Name.ToLowerInvariant(),
                    version.ToLowerInvariant(),
                    $"{identity.Name.ToLowerInvariant()}.{version.ToLowerInvariant()}.nupkg"));
            }

            urls.Add(new Uri(localPath).AbsoluteUri);
        }

        var findPackageById = await provider.SourceRepository
            .GetResourceAsync<FindPackageByIdResource>(cancellationToken);
        using var stream = new MemoryStream();
        var copied = await findPackageById.CopyNupkgToStreamAsync(
            identity.Name, identity.Version, stream, cacheContext, NullLogger.Instance, cancellationToken);
        if (!copied)
        {
            throw new ResolveException(
                $"Could not download {identity.Name} {version} from {provider.Source.Source}.");
        }

        var sha512 = Convert.ToBase64String(SHA512.HashData(stream.ToArray()));
        if (metadataHash != null && !string.Equals(metadataHash, sha512, StringComparison.Ordinal))
        {
            throw new ResolveException(
                $"Hash mismatch for {identity.Name} {version}: the feed publishes {metadataHash} " +
                $"but the downloaded bytes hash to {sha512}.");
        }

        return new ResolvedPackage(identity.Name, version, "sha512-" + sha512, urls);
    }

    private static async Task<JsonDocument?> GetJsonAsync(string url, CancellationToken cancellationToken)
    {
        try
        {
            var handler = new HttpClientHandler
            {
                // nuget.org's registration hives always serve gzip or deflate
                // even without an Accept-Encoding request header; match
                // NuGet.Protocol's HttpSourceResource decompression set.
                AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate,
            };
            var credentials = Netrc.CredentialsFor(new Uri(url));
            if (credentials != null)
            {
                handler.Credentials = credentials;
            }

            using var http = new HttpClient(handler);
            return JsonDocument.Parse(await http.GetStringAsync(url, cancellationToken));
        }
        catch (Exception e) when (e is HttpRequestException || e is JsonException ||
                                  (e is TaskCanceledException && !cancellationToken.IsCancellationRequested))
        {
            // Feeds without registration metadata (or a hiccup reading it)
            // fall back to the constructed URL and the bytes-only hash.
            return null;
        }
    }
}
