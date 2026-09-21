// The `Content-Type` an asset is served with.
//
// A subset of Microsoft.NET.Sdk.StaticWebAssets.ContentTypeMappings.props,
// covering what a web application actually ships. Anything unrecognised falls
// back to the same default the SDK uses.

using System;
using System.Collections.Generic;
using System.IO;

internal static class ContentTypes
{
    private const string Default = "application/octet-stream";

    private static readonly Dictionary<string, string> ByExtension = new(StringComparer.OrdinalIgnoreCase)
    {
        [".css"] = "text/css",
        [".html"] = "text/html",
        [".htm"] = "text/html",
        [".js"] = "text/javascript",
        [".mjs"] = "text/javascript",
        [".json"] = "application/json",
        [".map"] = "application/json",
        [".webmanifest"] = "application/manifest+json",
        [".txt"] = "text/plain",
        [".md"] = "text/markdown",
        [".csv"] = "text/csv",
        [".xml"] = "text/xml",
        [".svg"] = "image/svg+xml",
        [".ico"] = "image/x-icon",
        [".png"] = "image/png",
        [".jpg"] = "image/jpeg",
        [".jpeg"] = "image/jpeg",
        [".gif"] = "image/gif",
        [".webp"] = "image/webp",
        [".woff"] = "font/woff",
        [".woff2"] = "font/woff2",
        [".otf"] = "font/otf",
        [".ttf"] = "font/ttf",
        [".wasm"] = "application/wasm",
    };

    public static string ForRoute(string route) =>
        ByExtension.TryGetValue(Path.GetExtension(route), out var contentType) ? contentType : Default;
}
