using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using NuGet.Common;
using NuGet.Configuration;
using NuGet.DependencyResolver;
using NuGet.Frameworks;
using NuGet.LibraryModel;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

namespace NuGetResolver;

/// <summary>
/// Adapts a NuGet.Protocol source repository to the IRemoteDependencyProvider
/// the graph walker resolves through. Mirrors what NuGet.Commands'
/// SourceRepositoryDependencyProvider does, but stays within NuGet.Protocol.
/// </summary>
public sealed class FeedDependencyProvider : IRemoteDependencyProvider
{
    private readonly FindPackageByIdResource _findPackageById;

    public FeedDependencyProvider(SourceRepository repository)
    {
        SourceRepository = repository;
        Source = repository.PackageSource;
        _findPackageById = repository.GetResourceAsync<FindPackageByIdResource>().GetAwaiter().GetResult();
    }

    public bool IsHttp =>
        Uri.TryCreate(Source.Source, UriKind.Absolute, out var uri) &&
        (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps);

    public PackageSource Source { get; }

    public SourceRepository SourceRepository { get; }

    public async Task<LibraryIdentity?> FindLibraryAsync(
        LibraryRange libraryRange,
        NuGetFramework targetFramework,
        SourceCacheContext cacheContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var versions = await _findPackageById.GetAllVersionsAsync(
            libraryRange.Name, cacheContext, logger, cancellationToken);
        var best = libraryRange.VersionRange?.FindBestMatch(versions ?? Enumerable.Empty<NuGetVersion>());
        return best == null ? null : new LibraryIdentity(libraryRange.Name, best, LibraryType.Package);
    }

    public async Task<LibraryDependencyInfo> GetDependenciesAsync(
        LibraryIdentity libraryIdentity,
        NuGetFramework targetFramework,
        SourceCacheContext cacheContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var info = await _findPackageById.GetDependencyInfoAsync(
            libraryIdentity.Name, libraryIdentity.Version, cacheContext, logger, cancellationToken);
        if (info == null)
        {
            return LibraryDependencyInfo.CreateUnresolved(libraryIdentity, targetFramework);
        }

        var group = NuGetFrameworkUtility.GetNearest(info.DependencyGroups, targetFramework, item => item.TargetFramework);
        var dependencies = (group?.Packages ?? Enumerable.Empty<PackageDependency>())
            .Select(PackagingUtility.GetLibraryDependencyFromNuspec);
        return LibraryDependencyInfo.Create(libraryIdentity, targetFramework, dependencies);
    }

    public Task<IPackageDownloader> GetPackageDownloaderAsync(
        PackageIdentity packageIdentity,
        SourceCacheContext cacheContext,
        ILogger logger,
        CancellationToken cancellationToken)
        => throw new NotSupportedException(
            "The resolver downloads through FindPackageByIdResource, never through the walker's providers.");

    public async Task<IEnumerable<NuGetVersion>?> GetAllVersionsAsync(
        string id,
        SourceCacheContext cacheContext,
        ILogger logger,
        CancellationToken token)
        => await _findPackageById.GetAllVersionsAsync(id, cacheContext, logger, token);
}
