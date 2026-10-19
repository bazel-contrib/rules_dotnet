using System;
using System.IO;
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

namespace NuGetResolver.Tests;

/// <summary>
/// Builds a flat (V2-layout) local folder feed of fabricated .nupkg files.
/// Repository.Factory.GetCoreV3 treats a flat folder of nupkgs as a local feed.
/// </summary>
public static class FeedFixture
{
    public static string Create(params (string Id, string Version, (string Id, string Range)[] Dependencies)[] packages)
    {
        var dir = Path.Combine(Path.GetTempPath(), "nuget-resolver-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        foreach (var (id, version, dependencies) in packages)
        {
            WriteNupkg(dir, id, version, dependencies);
        }

        return dir;
    }

    /// <summary>
    /// Like <see cref="Create"/>, but writes each nupkg under a lowercased
    /// file name, mimicking nuget.org's flat download layout.
    /// </summary>
    public static string CreateLowercase(params (string Id, string Version, (string Id, string Range)[] Dependencies)[] packages)
    {
        var dir = Path.Combine(Path.GetTempPath(), "nuget-resolver-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        foreach (var (id, version, dependencies) in packages)
        {
            WriteNupkg(dir, id, version, dependencies, lowerFileName: true);
        }

        return dir;
    }

    /// <summary>The SRI hash of the fixture nupkg's bytes, as the resolver must record it.</summary>
    public static string ExpectedSha512(string feedDir, string id, string version)
    {
        var bytes = File.ReadAllBytes(Path.Combine(feedDir, $"{id}.{version}.nupkg"));
        return "sha512-" + Convert.ToBase64String(SHA512.HashData(bytes));
    }

    private static void WriteNupkg(
        string dir,
        string id,
        string version,
        (string Id, string Range)[] dependencies,
        bool lowerFileName = false)
    {
        var nuspec = new StringBuilder();
        nuspec.Append("""
            <?xml version="1.0" encoding="utf-8"?>
            <package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
              <metadata>
            """);
        nuspec.Append($"\n    <id>{id}</id>\n    <version>{version}</version>\n    <description>fixture</description>\n    <authors>fixture</authors>");
        if (dependencies.Length > 0)
        {
            nuspec.Append("\n    <dependencies>\n      <group targetFramework=\"netstandard2.0\">");
            foreach (var (depId, range) in dependencies)
            {
                nuspec.Append($"\n        <dependency id=\"{depId}\" version=\"{range}\" />");
            }

            nuspec.Append("\n      </group>\n    </dependencies>");
        }

        nuspec.Append("\n  </metadata>\n</package>\n");

        var fileName = $"{id}.{version}.nupkg";
        var path = Path.Combine(dir, lowerFileName ? fileName.ToLowerInvariant() : fileName);
        using var archive = ZipFile.Open(path, ZipArchiveMode.Create);
        WriteEntry(archive, "[Content_Types].xml", """
            <?xml version="1.0" encoding="utf-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="nuspec" ContentType="application/octet-stream" />
              <Default Extension="dll" ContentType="application/octet-stream" />
            </Types>
            """);
        WriteEntry(archive, $"{id}.nuspec", nuspec.ToString());
        WriteEntry(archive, $"lib/netstandard2.0/{id}.dll", "fixture");
    }

    private static void WriteEntry(ZipArchive archive, string name, string content)
    {
        var entry = archive.CreateEntry(name);
        using var writer = new StreamWriter(entry.Open());
        writer.Write(content);
    }
}
