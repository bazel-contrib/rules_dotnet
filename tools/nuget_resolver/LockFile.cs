using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace NuGetResolver;

/// <summary>One resolved package in the lock file.</summary>
public sealed record ResolvedPackage(string Id, string Version, string Sha512, IReadOnlyList<string> Urls);

/// <summary>
/// Writes nuget_resolve.json deterministically: keys in fixed order, packages
/// sorted by id (ordinal-ignore-case), frameworks sorted ordinal, two-space
/// indentation. Diffs between runs are minimal and stable.
/// </summary>
public static class LockFile
{
    public const int FormatVersion = 1;

    public static string Render(string inputHash, IReadOnlyDictionary<string, List<ResolvedPackage>> frameworks)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true, IndentSize = 2, NewLine = "\n" }))
        {
            writer.WriteStartObject();
            writer.WriteNumber("version", FormatVersion);
            writer.WriteString("inputHash", inputHash);
            writer.WriteStartObject("frameworks");
            foreach (var (tfm, packages) in frameworks.OrderBy(kv => kv.Key, StringComparer.Ordinal))
            {
                writer.WriteStartObject(tfm);
                writer.WriteStartArray("packages");
                foreach (var package in packages.OrderBy(p => p.Id, StringComparer.OrdinalIgnoreCase).ThenBy(p => p.Id, StringComparer.Ordinal))
                {
                    writer.WriteStartObject();
                    writer.WriteString("id", package.Id);
                    writer.WriteString("version", package.Version);
                    writer.WriteString("sha512", package.Sha512);
                    writer.WriteStartArray("urls");
                    foreach (var url in package.Urls)
                    {
                        writer.WriteStringValue(url);
                    }

                    writer.WriteEndArray();
                    writer.WriteEndObject();
                }

                writer.WriteEndArray();
                writer.WriteEndObject();
            }

            writer.WriteEndObject();
            writer.WriteEndObject();
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }
}
