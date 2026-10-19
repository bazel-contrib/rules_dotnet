using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace NuGetResolver;

/// <summary>One requested package: an id and a PackageReference-style version range.</summary>
public sealed record PackageRequest(string Id, string Range);

/// <summary>The JSON specification the repository rule hands to the resolver.</summary>
public sealed record ResolveSpec(
    IReadOnlyList<PackageRequest> Packages,
    IReadOnlyList<string> Frameworks,
    IReadOnlyList<string> Sources)
{
    public static ResolveSpec Load(string path)
    {
        JsonDocument doc;
        try
        {
            doc = JsonDocument.Parse(File.ReadAllText(path));
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
        {
            throw new ResolveException($"Could not read resolve spec {path}: {e.Message}");
        }

        using (doc)
        {
            var root = doc.RootElement;
            var packages = new List<PackageRequest>();
            foreach (var package in root.GetProperty("packages").EnumerateObject())
            {
                packages.Add(new PackageRequest(package.Name, package.Value.GetString()!));
            }

            var frameworks = root.GetProperty("frameworks").EnumerateArray()
                .Select(e => e.GetString()!).ToList();
            var sources = root.GetProperty("sources").EnumerateArray()
                .Select(e => e.GetString()!).ToList();
            return new ResolveSpec(packages, frameworks, sources);
        }
    }
}
