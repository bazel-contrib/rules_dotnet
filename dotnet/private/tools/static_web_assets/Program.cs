// Fingerprints, compresses and describes a web application's static assets.
//
// `MapStaticAssets` serves from a manifest rather than from the file system, so
// everything it needs about an asset - its content hash, its length, its
// compressed variants and the headers to send - is computed here and written
// into `{Assembly}.staticwebassets.endpoints.json`.
//
// The fingerprint goes in the *route*, not the file name: `app.css` on disk is
// served both at `app.css` with `no-cache` and at `app.<fingerprint>.css` as
// immutable. That is what MSBuild does, and it is also what lets Bazel declare
// every output at analysis time, since a content hash is not known until the
// action runs.

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Numerics;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

internal sealed class Request
{
    public string Manifest { get; set; } = "";

    public List<AssetRequest> Assets { get; set; } = new();

    /// A whole tree to serve, rather than a listed set of files. The caller
    /// does not know what it contains, so it also says which extensions are
    /// worth compressing.
    public string? InputDirectory { get; set; }
    public string? OutputDirectory { get; set; }
    public List<string> CompressibleExtensions { get; set; } = new();
}

internal sealed class AssetRequest
{
    /// Where the asset is served from, relative to `wwwroot`.
    public string Route { get; set; } = "";

    public string File { get; set; } = "";

    /// Where to write the compressed copies, or null to leave the asset
    /// uncompressed because its format already is.
    public string? Gzip { get; set; }
    public string? Brotli { get; set; }
}

internal sealed record Header(string Name, string Value);

internal sealed record Selector(string Name, string Value, string Quality);

internal sealed record Property(string Name, string Value);

internal sealed class Endpoint
{
    public string Route { get; set; } = "";
    public string AssetFile { get; set; } = "";
    public List<Selector> Selectors { get; set; } = new();
    public List<Header> ResponseHeaders { get; set; } = new();
    public List<Property> EndpointProperties { get; set; } = new();
}

internal sealed class Manifest
{
    public int Version { get; set; } = 1;
    public string ManifestType { get; set; } = "Publish";
    public List<Endpoint> Endpoints { get; set; } = new();
}

internal static class Program
{
    // A real modification time would make the manifest differ between builds of
    // identical inputs. The header still has to be present, or the runtime emits
    // year 0001; conditional requests stay correct because every response also
    // carries a content-derived ETag, which takes precedence.
    private static readonly DateTimeOffset LastModified = DateTimeOffset.UnixEpoch;

    private const string Immutable = "max-age=31536000, immutable";
    private const string NoCache = "no-cache";

    private static int Main(string[] args)
    {
        if (args.Length != 1)
        {
            Console.Error.WriteLine("usage: static_web_assets <request.json>");
            return 1;
        }

        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var request = JsonSerializer.Deserialize<Request>(File.ReadAllText(args[0]), options)!;

        var assets = request.InputDirectory is { } input
            ? FromDirectory(input, request.OutputDirectory!, request.CompressibleExtensions)
            : request.Assets;

        var ordered = assets.OrderBy(a => a.Route, StringComparer.Ordinal).ToList();
        var described = new List<Endpoint>[ordered.Count];
        Parallel.For(0, ordered.Count, i => described[i] = Describe(ordered[i]));
        var endpoints = described.SelectMany(e => e).ToList();

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(request.Manifest))!);
        File.WriteAllText(request.Manifest, JsonSerializer.Serialize(
            new Manifest { Endpoints = endpoints },
            new JsonSerializerOptions
            {
                DefaultIgnoreCondition = JsonIgnoreCondition.Never,
                WriteIndented = false,
            }));

        return 0;
    }

    /// Copies a tree into the served one, and describes what it finds. The
    /// compressed variants land beside each file, so the result is the same
    /// shape as a listed set of assets would produce.
    private static List<AssetRequest> FromDirectory(string input, string output, List<string> compressible)
    {
        var extensions = new HashSet<string>(compressible, StringComparer.OrdinalIgnoreCase);
        var assets = new List<AssetRequest>();
        var root = Path.GetFullPath(input);

        foreach (var source in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
        {
            var route = Path.GetRelativePath(root, source).Replace(Path.DirectorySeparatorChar, '/');
            var destination = Path.GetFullPath(Path.Combine(output, route));

            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(source, destination, overwrite: true);

            var compress = extensions.Contains(Path.GetExtension(route).TrimStart('.'));
            assets.Add(new AssetRequest
            {
                Route = route,
                File = destination,
                Gzip = compress ? destination + ".gz" : null,
                Brotli = compress ? destination + ".br" : null,
            });
        }

        return assets;
    }

    private static List<Endpoint> Describe(AssetRequest asset)
    {
        // Read once: every hash, length and compressed variant below comes from
        // this buffer rather than from the file system again.
        var content = File.ReadAllBytes(asset.File);
        var hash = SHA256.HashData(content);
        var integrity = Convert.ToBase64String(hash);
        var fingerprint = ToBase36(hash);
        var contentType = ContentTypes.ForRoute(asset.Route);

        var fingerprinted = Fingerprinting.Apply(asset.Route, fingerprint);

        // `AssetFile` is where the file sits under `wwwroot`, which for us is
        // always the route: the fingerprint lives in the route alone, so
        // nothing is ever renamed on disk.
        var endpoints = new List<Endpoint>
        {
            Plain(asset.Route, asset.Route, content.Length, contentType, integrity),
            Immutably(fingerprinted, asset.Route, content.Length, contentType, integrity, fingerprint, asset.Route),
        };

        foreach (var (path, encoding, suffix) in Variants(asset))
        {
            var compressed = Compress(content, path, encoding);
            var compressedIntegrity = Convert.ToBase64String(SHA256.HashData(compressed));

            // A shorter body wins content negotiation, so quality is the
            // reciprocal of the length.
            var quality = (1.0 / (compressed.Length + 1)).ToString("F12", CultureInfo.InvariantCulture);
            var selectors = new List<Selector> { new("Content-Encoding", encoding, quality) };

            // Served in place of the asset when the client accepts it. The
            // integrity stays the *original's*, because that is what the client
            // ends up with once it decompresses.
            var assetFile = asset.Route + suffix;

            endpoints.Add(Negotiated(
                Plain(asset.Route, assetFile, compressed.Length, contentType, integrity, encoding),
                selectors,
                integrity));
            endpoints.Add(Negotiated(
                Immutably(fingerprinted, assetFile, compressed.Length, contentType, integrity, fingerprint, asset.Route, encoding),
                selectors,
                integrity));

            // And addressable directly, where it is its own resource.
            endpoints.Add(Plain(assetFile, assetFile, compressed.Length, contentType, compressedIntegrity, encoding));
            endpoints.Add(Immutably(fingerprinted + suffix, assetFile, compressed.Length, contentType, compressedIntegrity, fingerprint, assetFile, encoding));
        }

        return endpoints;
    }

    private static Endpoint Negotiated(Endpoint endpoint, List<Selector> selectors, string integrity)
    {
        endpoint.Selectors = selectors;
        endpoint.EndpointProperties.Add(new Property("original-resource", Quote(integrity)));
        return endpoint;
    }

    private static IEnumerable<(string Path, string Encoding, string Suffix)> Variants(AssetRequest asset)
    {
        if (asset.Gzip is { } gzip)
        {
            yield return (gzip, "gzip", ".gz");
        }

        if (asset.Brotli is { } brotli)
        {
            yield return (brotli, "br", ".br");
        }
    }

    private static byte[] Compress(byte[] content, string destination, string encoding)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(destination))!);

        // Compressed into memory rather than straight to disk, because the
        // manifest needs the result's length and hash and would otherwise have
        // to read it back.
        using var buffer = new MemoryStream();
        using (var compressor = encoding == "gzip"
            ? new GZipStream(buffer, CompressionLevel.SmallestSize, leaveOpen: true)
            : (Stream)new BrotliStream(buffer, CompressionLevel.SmallestSize, leaveOpen: true))
        {
            compressor.Write(content, 0, content.Length);
        }

        var compressed = buffer.ToArray();
        File.WriteAllBytes(destination, compressed);
        return compressed;
    }

    private static Endpoint Plain(
        string route,
        string file,
        long length,
        string contentType,
        string integrity,
        string? encoding = null) =>
        new()
        {
            Route = route,
            AssetFile = file,
            ResponseHeaders = Headers(NoCache, length, contentType, integrity, encoding),
            EndpointProperties = { new Property("integrity", "sha256-" + integrity) },
        };

    private static Endpoint Immutably(
        string route,
        string file,
        long length,
        string contentType,
        string integrity,
        string fingerprint,
        string label,
        string? encoding = null) =>
        new()
        {
            Route = route,
            AssetFile = file,
            ResponseHeaders = Headers(Immutable, length, contentType, integrity, encoding),
            EndpointProperties =
            {
                new Property("fingerprint", fingerprint),
                new Property("integrity", "sha256-" + integrity),
                new Property("label", label),
            },
        };

    private static List<Header> Headers(
        string cacheControl,
        long length,
        string contentType,
        string integrity,
        string? encoding)
    {
        var headers = new List<Header>
        {
            new("Cache-Control", cacheControl),
            new("Content-Length", length.ToString(CultureInfo.InvariantCulture)),
            new("Content-Type", contentType),
            new("ETag", Quote(integrity)),
            new("Last-Modified", LastModified.ToString("R", CultureInfo.InvariantCulture)),
            new("Vary", "Accept-Encoding"),
        };

        if (encoding != null)
        {
            headers.Add(new Header("Content-Encoding", encoding));
        }

        return headers.OrderBy(h => h.Name, StringComparer.Ordinal).ToList();
    }

    private static string Quote(string value) => "\"" + value + "\"";

    /// The same base36 of the leading 9 bytes that the SDK uses, so a
    /// fingerprint computed here matches one computed by `dotnet build`.
    private static string ToBase36(byte[] hash)
    {
        const string characters = "0123456789abcdefghijklmnopqrstuvwxyz";

        var result = new char[10];
        var dividend = BigInteger.Abs(new BigInteger(hash.AsSpan()[..9]));
        for (var i = 0; i < 10; i++)
        {
            dividend = BigInteger.DivRem(dividend, 36, out var remainder);
            result[i] = characters[(int)remainder];
        }

        return new string(result);
    }
}
