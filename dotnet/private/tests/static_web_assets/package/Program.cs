using System;
using System.IO;
using System.Linq;
using System.Text.Json;

// A package's `staticwebassets` folder is served from `_content/<package id>`,
// exactly like a library target's `wwwroot`, so an application consumes both
// the same way.
public static class Program
{
    private const string Content = "wwwroot/_content/Microsoft.AspNetCore.Components.QuickGrid";

    public static int Main()
    {
        var root = AppContext.BaseDirectory;
        var failures = 0;

        // The `.razor.js` exercises the compound fingerprint extensions: the
        // hash goes before `.razor.js`, not before `.js`.
        var module = $"{Content}/QuickGrid.razor.js";
        var bundle = Directory
            .EnumerateFiles(Path.Combine(root, Content), "*.bundle.scp.css")
            .Select(Path.GetFileName)
            .FirstOrDefault();

        if (!File.Exists(Path.Combine(root, module)))
        {
            Console.Error.WriteLine($"missing: {module}");
            failures++;
        }

        if (bundle is null)
        {
            Console.Error.WriteLine($"no scoped CSS bundle under {Content}");
            return failures + 1;
        }

        Console.WriteLine($"{module} and {bundle} are served from the package");

        var routes = Routes(Path.Combine(root, "package.staticwebassets.endpoints.json"));
        foreach (var expected in new[] { module, $"{Content}/{bundle}" })
        {
            var route = expected["wwwroot/".Length..];
            if (!routes.Contains(route))
            {
                Console.Error.WriteLine($"no endpoint for {route}");
                failures++;
            }
        }

        // The fingerprinted route keeps the compound extension intact.
        var fingerprinted = routes.FirstOrDefault(r =>
            r.StartsWith($"_content/Microsoft.AspNetCore.Components.QuickGrid/QuickGrid.", StringComparison.Ordinal) &&
            r.EndsWith(".razor.js", StringComparison.Ordinal) &&
            r != $"_content/Microsoft.AspNetCore.Components.QuickGrid/QuickGrid.razor.js");

        if (fingerprinted is null)
        {
            Console.Error.WriteLine("no fingerprinted route keeping the .razor.js extension");
            failures++;
        }
        else
        {
            Console.WriteLine($"fingerprinted as {fingerprinted}");
        }

        return failures;
    }

    private static string[] Routes(string manifest)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(manifest));
        return document.RootElement
            .GetProperty("Endpoints")
            .EnumerateArray()
            .Select(e => e.GetProperty("Route").GetString()!)
            .Distinct()
            .ToArray();
    }
}
