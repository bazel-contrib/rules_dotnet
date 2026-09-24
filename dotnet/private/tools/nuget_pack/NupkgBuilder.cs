// Assembles the archives. Every entry is either bytes the tool generated or a
// file to copy; both go through the same sorted, fixed-timestamp zip writer.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

namespace RulesDotnet.NuGetPack;

internal static class NupkgBuilder
{
    // The earliest time the zip format can hold, and what NuGet stamps in
    // deterministic mode.
    private static readonly DateTimeOffset Epoch = new(1980, 1, 1, 0, 0, 0, TimeSpan.Zero);

    private sealed record Entry(string Name, byte[]? Bytes, string? SourcePath);

    public static void Write(Request request, NuGetVersion version)
    {
        var versions = new Dictionary<string, string>(StringComparer.Ordinal);
        string ResolveVersion(string? file)
        {
            if (!versions.TryGetValue(file!, out var resolved))
            {
                var text = File.ReadLines(file!).Select(line => line.Trim()).FirstOrDefault(line => line.Length > 0) ?? "";
                if (!NuGetVersion.TryParse(text, out var parsed))
                {
                    throw new InvalidDataException($"version file '{file}' does not hold a valid version: '{text}'");
                }
                resolved = versions[file!] = parsed!.Normalized;
            }
            return resolved;
        }

        var nuspec = NuspecWriter.Write(request, version, ResolveVersion, symbols: false);
        if (request.NuspecOutput != null)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(request.NuspecOutput))!);
            File.WriteAllBytes(request.NuspecOutput, nuspec);
        }

        var payload = request.Files.Select(file => new Entry(OpcParts.EntryName(file.Target), null, file.Source)).ToList();
        if (request.ToolSettings != null)
        {
            var settings = ToolSettingsWriter.Write(request.ToolSettings);
            payload.AddRange(request.ToolSettings.Directories.Select(directory =>
                new Entry(OpcParts.EntryName(directory + "/" + ToolSettingsWriter.FileName), settings, null)));
        }
        WriteArchive(request.Output, request.Metadata, version, nuspec, payload);

        if (request.SymbolsOutput != null)
        {
            var symbolsNuspec = NuspecWriter.Write(request, version, ResolveVersion, symbols: true);
            var symbols = request.SymbolFiles.Select(file => new Entry(OpcParts.EntryName(file.Target), null, file.Source)).ToList();
            WriteArchive(request.SymbolsOutput, request.Metadata, version, symbolsNuspec, symbols);
        }
    }

    private static void WriteArchive(string output, Metadata metadata, NuGetVersion version, byte[] nuspec, List<Entry> payload)
    {
        var nuspecEntry = OpcParts.EntryName(metadata.Id + ".nuspec");
        var entries = new List<Entry>(payload) { new(nuspecEntry, nuspec, null) };

        // A content hash where NuGet would put a fresh GUID.
        var corePropertiesEntry = $"{OpcParts.CorePropertiesDirectory}/{PartName(nuspec, entries)}.psmdcp";
        entries.Add(new Entry(corePropertiesEntry, OpcParts.CoreProperties(metadata, version), null));
        entries.Add(new Entry(OpcParts.RelationshipsEntry, OpcParts.Relationships(nuspecEntry, corePropertiesEntry), null));

        // Over the entries as they stand: the content-types part is not itself
        // a package part, so it does not describe itself.
        var contentTypes = OpcParts.ContentTypes(entries.Select(entry => entry.Name).ToList());
        entries.Add(new Entry(OpcParts.ContentTypesEntry, contentTypes, null));

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
        using var stream = File.Create(output);
        using var archive = new ZipArchive(stream, ZipArchiveMode.Create);
        foreach (var entry in entries.OrderBy(entry => entry.Name, StringComparer.Ordinal))
        {
            // Not CreateEntryFromFile: that copies the source's timestamp and mode.
            var zipEntry = archive.CreateEntry(entry.Name, CompressionLevel.Optimal);
            zipEntry.LastWriteTime = Epoch;
            using var target = zipEntry.Open();
            if (entry.Bytes != null)
            {
                target.Write(entry.Bytes);
            }
            else
            {
                using var source = File.OpenRead(entry.SourcePath!);
                source.CopyTo(target);
            }
        }
    }

    /// <summary>A name for the core-properties part, derived from the manifest and the entry names.</summary>
    private static string PartName(byte[] nuspec, List<Entry> entries)
    {
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        hash.AppendData(nuspec);
        foreach (var entry in entries.OrderBy(entry => entry.Name, StringComparer.Ordinal))
        {
            hash.AppendData(Encoding.UTF8.GetBytes(entry.Name + "\n"));
        }
        return Convert.ToHexStringLower(hash.GetHashAndReset())[..32];
    }
}
