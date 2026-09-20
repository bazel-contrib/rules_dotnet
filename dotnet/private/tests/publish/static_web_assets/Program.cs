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

// Run from inside an extracted publish directory, so what it exercises is the
// published layout: `wwwroot/` beside the assembly with the endpoint manifest
// next to it, which is what `MapStaticAssets` expects to find.
public static class Program
{
    private static int _failures;

    public static async Task<int> Main()
    {
        var root = AppContext.BaseDirectory;

        foreach (var expected in new[]
        {
            "wwwroot/app.css",
            "wwwroot/app.css.gz",
            "wwwroot/app.css.br",
            "wwwroot/_content/lib/css/site.css",
            "app_to_publish.staticwebassets.endpoints.json",
        })
        {
            Expect(File.Exists(Path.Combine(root, expected)), $"published: {expected}");
        }

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
            using var response = await client.GetAsync("_content/lib/css/site.css");
            Expect(response.StatusCode == HttpStatusCode.OK, $"serves a library asset: {response.StatusCode}");
            Expect(
                response.Headers.CacheControl?.ToString() == "no-cache",
                $"cache-control: {response.Headers.CacheControl}");
        }

        await app.StopAsync();

        Console.WriteLine(_failures == 0 ? "published static web assets serve correctly" : "FAILED");
        return _failures;
    }

    private static void Expect(bool condition, string description)
    {
        Console.WriteLine((condition ? "ok: " : "FAILED: ") + description);
        if (!condition)
        {
            _failures++;
        }
    }
}
