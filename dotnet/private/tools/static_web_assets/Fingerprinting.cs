// Where the fingerprint goes in a route.
//
// Normally it precedes the single extension: `app.js` becomes
// `app.<fingerprint>.js`. Some file names end in a compound extension that has
// to stay intact, so `Counter.razor.js` becomes `Counter.<fingerprint>.razor.js`
// rather than `Counter.razor.<fingerprint>.js`. The list mirrors
// Microsoft.NET.Sdk.StaticWebAssets.FingerprintingPatterns.props.

using System;
using System.Linq;

internal static class Fingerprinting
{
    private static readonly string[] CompoundExtensions =
    {
        ".lib.module.js",
        ".cshtml.js",
        ".razor.js",
        ".cshtml.css",
        ".razor.css",
        ".modules.json",
    };

    public static string Apply(string route, string fingerprint)
    {
        var separator = route.LastIndexOf('/');
        var directory = separator < 0 ? "" : route[..(separator + 1)];
        var name = route[(separator + 1)..];

        var compound = CompoundExtensions.FirstOrDefault(
            extension => name.Length > extension.Length &&
                         name.EndsWith(extension, StringComparison.OrdinalIgnoreCase));

        if (compound != null)
        {
            return $"{directory}{name[..^compound.Length]}.{fingerprint}{compound}";
        }

        var dot = name.LastIndexOf('.');
        return dot <= 0
            ? $"{directory}{name}.{fingerprint}"
            : $"{directory}{name[..dot]}.{fingerprint}{name[dot..]}";
    }
}
