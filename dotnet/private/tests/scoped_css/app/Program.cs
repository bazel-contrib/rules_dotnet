using System;
using System.IO;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.Web.HtmlRendering;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

// Scoped CSS only works if the identifier the stylesheet was rewritten with is
// the same one the component renders. Those are produced by two different
// pieces of the build - the SDK's tasks and the Razor source generator - so the
// test renders the component and matches it against the bundle rather than
// trusting either in isolation.
public static class Program
{
    public static int Main()
    {
        var root = AppContext.BaseDirectory;
        var failures = 0;

        var libBundle = Path.Combine(root, "wwwroot/_content/lib/lib.bundle.scp.css");
        var appBundle = Path.Combine(root, "wwwroot/app.styles.css");

        foreach (var path in new[] { libBundle, appBundle })
        {
            if (!File.Exists(path))
            {
                Console.Error.WriteLine($"missing bundle: {path}");
                failures++;
            }
        }

        if (failures > 0)
        {
            return failures;
        }

        failures += CheckScopeMatches(libBundle, typeof(Scoped.Lib.Widget), "widget");
        failures += CheckScopeMatches(appBundle, typeof(Scoped.App.Page), "title");

        // The application bundle pulls in each library's bundle rather than
        // inlining it, so a library ships its own scoped styles. The path is
        // relative to where the application bundle is served, which is the
        // root, so it carries no leading segments.
        var appText = File.ReadAllText(appBundle);
        if (!appText.Contains("@import '_content/lib/lib.bundle.scp.css';"))
        {
            Console.Error.WriteLine($"app bundle does not import the library bundle:\n{appText}");
            failures++;
        }

        return failures;
    }

    private static int CheckScopeMatches(string bundle, Type component, string cssClass)
    {
        var css = File.ReadAllText(bundle);
        var inCss = Regex.Match(css, $@"\.{cssClass}\[(b-[a-z0-9]+)\]");
        if (!inCss.Success)
        {
            Console.Error.WriteLine($"no scope on .{cssClass} in {Path.GetFileName(bundle)}:\n{css}");
            return 1;
        }

        var html = Render(component);
        var scope = inCss.Groups[1].Value;
        if (!html.Contains(scope))
        {
            Console.Error.WriteLine($"{component.FullName} rendered without {scope}: {html}");
            return 1;
        }

        Console.WriteLine($"{component.Name}: {scope} in both the bundle and the rendered markup");
        return 0;
    }

    private static string Render(Type component)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        using var provider = services.BuildServiceProvider();

        using var renderer = new HtmlRenderer(provider, provider.GetRequiredService<ILoggerFactory>());
        return renderer.Dispatcher.InvokeAsync(async () =>
        {
            var output = await renderer.RenderComponentAsync(component);
            return output.ToHtmlString();
        }).GetAwaiter().GetResult();
    }
}
