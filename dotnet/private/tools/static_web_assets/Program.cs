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

internal sealed class Request
{
    public string Manifest { get; set; } = "";
    public List<AssetRequest> Assets { get; set; } = new();
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
    // identical inputs, which is the one thing that stops MSBuild's own output
    // being reproducible. The header still has to be present, because the
    // runtime assigns it unconditionally and would otherwise emit year 0001.
    // Conditional requests stay correct: every response also carries a
    // content-derived ETag, and If-None-Match takes precedence over
    // If-Modified-Since.
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

        var endpoints = new List<Endpoint>();
        foreach (var asset in request.Assets.OrderBy(a => a.Route, StringComparer.Ordinal))
        {
            endpoints.AddRange(Describe(asset));
        }

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

    private static IEnumerable<Endpoint> Describe(AssetRequest asset)
    {
        var content = File.ReadAllBytes(asset.File);
        var hash = SHA256.HashData(content);
        var integrity = Convert.ToBase64String(hash);
        var fingerprint = ToBase36(hash);
        var contentType = ContentTypes.ForRoute(asset.Route);

        var fingerprinted = Fingerprinting.Apply(asset.Route, fingerprint);

        // `AssetFile` is where the file sits under `wwwroot`, which for us is
        // always the route: the fingerprint lives in the route alone, so
        // nothing is ever renamed on disk.
        yield return Plain(asset.Route, asset.Route, content.Length, contentType, integrity);
        yield return Immutably(fingerprinted, asset.Route, content.Length, contentType, integrity, fingerprint, asset.Route);

        foreach (var (path, encoding) in Compressed(asset))
        {
            var compressed = File.ReadAllBytes(path);
            var compressedIntegrity = Convert.ToBase64String(SHA256.HashData(compressed));

            // A shorter body wins content negotiation, so quality is the
            // reciprocal of the length.
            var quality = (1.0 / (compressed.Length + 1)).ToString("F12", CultureInfo.InvariantCulture);
            var selectors = new List<Selector> { new("Content-Encoding", encoding, quality) };

            // Served in place of the asset when the client accepts it. The
            // integrity stays the *original's*, because that is what the client
            // ends up with once it decompresses.
            var suffix = encoding == "gzip" ? ".gz" : ".br";
            var assetFile = asset.Route + suffix;

            var negotiated = Plain(asset.Route, assetFile, compressed.Length, contentType, integrity, encoding);
            negotiated.Selectors = selectors;
            negotiated.EndpointProperties.Add(new Property("original-resource", Quote(integrity)));
            yield return negotiated;

            var negotiatedImmutable = Immutably(fingerprinted, assetFile, compressed.Length, contentType, integrity, fingerprint, asset.Route, encoding);
            negotiatedImmutable.Selectors = selectors;
            negotiatedImmutable.EndpointProperties.Add(new Property("original-resource", Quote(integrity)));
            yield return negotiatedImmutable;

            // And addressable directly, where it is its own resource.
            yield return Plain(assetFile, assetFile, compressed.Length, contentType, compressedIntegrity, encoding);
            yield return Immutably(fingerprinted + suffix, assetFile, compressed.Length, contentType, compressedIntegrity, fingerprint, assetFile, encoding);
        }
    }

    private static IEnumerable<(string Path, string Encoding)> Compressed(AssetRequest asset)
    {
        if (asset.Gzip is { } gzip)
        {
            Write(asset.File, gzip, path => new GZipStream(path, CompressionLevel.SmallestSize));
            yield return (gzip, "gzip");
        }

        if (asset.Brotli is { } brotli)
        {
            Write(asset.File, brotli, path => new BrotliStream(path, CompressionLevel.SmallestSize));
            yield return (brotli, "br");
        }
    }

    private static void Write(string source, string destination, Func<Stream, Stream> compress)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(destination))!);

        using var input = File.OpenRead(source);
        using var output = File.Create(destination);
        using var compressor = compress(output);
        input.CopyTo(compressor);
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
