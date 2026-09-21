using System;
using System.IO;

// Run from inside an extracted NativeAOT publish directory. NativeAOT keeps
// nothing managed, so the tree does not travel through the publish layout the
// framework-dependent path builds: it is copied beside the executable instead,
// and this is what checks it arrives there intact.
//
// Managed-only and free of ASP.NET Core, because ILC has to be able to compile
// it. Serving the tree is covered by the framework-dependent test.
public static class Program
{
    private const string Manifest = "aot_app_to_publish.staticwebassets.endpoints.json";

    private static int _failures;

    public static int Main()
    {
        var root = AppContext.BaseDirectory;

        foreach (var expected in new[]
        {
            // The application's own assets, at the root of the tree.
            "wwwroot/app.css",
            "wwwroot/app.css.gz",
            "wwwroot/app.css.br",

            // A library's, under `_content/<assembly name>`. Nested deeply
            // enough to prove the copy recreates directories rather than
            // flattening them.
            "wwwroot/_content/lib/css/site.css",
            "wwwroot/_content/lib/interop.js",

            // And the manifest, beside the executable rather than inside the
            // tree it describes.
            Manifest,
        })
        {
            Expect(File.Exists(Path.Combine(root, expected)), $"published: {expected}");
        }

        // Read as text rather than parsed: reflection-based JSON does not
        // survive trimming, and a substring is enough to tell the manifest
        // describes the tree beside it.
        var manifest = Path.Combine(root, Manifest);
        Expect(
            File.Exists(manifest) && File.ReadAllText(manifest).Contains("_content/lib/css/site.css"),
            "the manifest describes the library asset");

        Console.WriteLine(_failures == 0
            ? "the NativeAOT publish carries the servable tree"
            : "FAILED");

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
