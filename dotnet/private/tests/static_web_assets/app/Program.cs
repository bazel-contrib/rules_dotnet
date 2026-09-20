using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Hosting;

// `MapStaticAssets` serves from the generated endpoint manifest rather than
// from the file system, so the only way to know the manifest is right is to
// start the real server and ask it for things.
public static class Program
{
    private static int _failures;

    public static async Task<int> Main()
    {
        var root = AppContext.BaseDirectory;

        var builder = WebApplication.CreateBuilder(new WebApplicationOptions
        {
            ContentRootPath = root,
            WebRootPath = Path.Combine(root, "wwwroot"),
        });
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();

        var app = builder.Build();
        app.MapStaticAssets();
        await app.StartAsync();

        var address = app.Services
            .GetRequiredService<IServer>()
            .Features
            .Get<IServerAddressesFeature>()!
            .Addresses
            .First();

        using (var client = new HttpClient { BaseAddress = new Uri(address) })
        {
            // A library's asset is served under `_content/<assembly>`, so the
            // application never has to know where it came from.
            var site = await Get(client, "_content/lib/css/site.css");
            Expect(site.Content == "body { color: rebeccapurple; }\n", $"library asset body: {site.Content}");
            Expect(site.CacheControl == "no-cache", $"unfingerprinted cache-control: {site.CacheControl}");
            Expect(site.ETag is not null, "unfingerprinted responses still carry an ETag");

            // The same bytes at the fingerprinted route, which is the one worth
            // caching forever.
            var fingerprint = Fingerprint(root, "_content/lib/css/site.css");
            var immutable = await Get(client, $"_content/lib/css/site.{fingerprint}.css");
            Expect(immutable.Content == site.Content, "fingerprinted route serves the same bytes");
            Expect(
                immutable.CacheControl == "max-age=31536000, immutable",
                $"fingerprinted cache-control: {immutable.CacheControl}");

            // Content negotiation picks a compressed variant without the route
            // changing.
            var compressed = await Get(client, "app.css", acceptEncoding: "br");
            Expect(compressed.ContentEncoding == "br", $"negotiated encoding: {compressed.ContentEncoding}");

            // An ETag is content derived, so an unchanged asset is not resent.
            var conditional = await GetIfNoneMatch(client, "app.css", site.ETag is null ? "" : (await Get(client, "app.css")).ETag!);
            Expect(conditional == HttpStatusCode.NotModified, $"conditional request: {conditional}");
        }

        await app.StopAsync();
        return _failures;
    }

    private static string Fingerprint(string root, string route)
    {
        // Read it back out of the manifest rather than recomputing it, so the
        // test would notice the manifest and the served routes disagreeing.
        var manifest = Path.Combine(root, "app.staticwebassets.endpoints.json");
        using var document = System.Text.Json.JsonDocument.Parse(File.ReadAllText(manifest));
        foreach (var endpoint in document.RootElement.GetProperty("Endpoints").EnumerateArray())
        {
            if (endpoint.GetProperty("AssetFile").GetString() != route ||
                endpoint.GetProperty("Selectors").GetArrayLength() != 0)
            {
                continue;
            }

            foreach (var property in endpoint.GetProperty("EndpointProperties").EnumerateArray())
            {
                if (property.GetProperty("Name").GetString() == "fingerprint")
                {
                    return property.GetProperty("Value").GetString()!;
                }
            }
        }

        throw new InvalidOperationException($"no fingerprinted endpoint for {route}");
    }

    private static async Task<Response> Get(HttpClient client, string route, string? acceptEncoding = null)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, route);
        if (acceptEncoding != null)
        {
            request.Headers.Add("Accept-Encoding", acceptEncoding);
        }

        using var response = await client.SendAsync(request);
        Expect(response.StatusCode == HttpStatusCode.OK, $"GET {route} -> {response.StatusCode}");

        var encoding = response.Content.Headers.ContentEncoding.FirstOrDefault();
        return new Response(
            encoding is null ? await response.Content.ReadAsStringAsync() : "",
            response.Headers.CacheControl?.ToString(),
            response.Headers.ETag?.ToString(),
            encoding);
    }

    private static async Task<HttpStatusCode> GetIfNoneMatch(HttpClient client, string route, string etag)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, route);
        request.Headers.TryAddWithoutValidation("If-None-Match", etag);
        using var response = await client.SendAsync(request);
        return response.StatusCode;
    }

    private static void Expect(bool condition, string description)
    {
        if (condition)
        {
            Console.WriteLine($"ok: {description}");
            return;
        }

        Console.Error.WriteLine($"FAILED: {description}");
        _failures++;
    }

    private sealed record Response(string Content, string? CacheControl, string? ETag, string? ContentEncoding);
}
