// One .nupkg or .snupkg: read, and checked for what no package may get wrong.
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using NuGet.Common;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.Packaging.Rules;

namespace RulesDotnet.Tests.Check;

internal sealed record Entry(string Name, byte[] Bytes);

internal sealed class PackageFile
{
    private const string ContentTypesEntry = "[Content_Types].xml";
    private const string RelationshipsEntry = "_rels/.rels";
    private const string SymbolsPackageType = "SymbolsPackage";

    // What `nuget_pack` stamps every entry with: the earliest time a zip can hold.
    private static readonly DateTime Epoch = new(1980, 1, 1);
    private static readonly Regex CoreProperties = new(@"^package/services/metadata/core-properties/[0-9a-f]{32}\.psmdcp$");

    private static readonly JsonSerializerOptions LaidOut = new()
    {
        WriteIndented = true,
        NewLine = "\n",
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    private readonly string _path;

    private PackageFile(string path, List<Entry> entries, string nuspec, string coreProperties, PackageIdentity identity, IReadOnlyList<string> packageTypes)
    {
        _path = path;
        Entries = entries;
        Nuspec = nuspec;
        CorePropertiesEntry = coreProperties;
        Identity = identity;
        PackageTypes = packageTypes;
    }

    public string FileName => Path.GetFileName(_path);

    public IReadOnlyList<Entry> Entries { get; }

    public string Nuspec { get; }

    public string CorePropertiesEntry { get; }

    public PackageIdentity Identity { get; }

    public IReadOnlyList<string> PackageTypes { get; }

    public InvalidDataException Bad(string message) => new($"{FileName}: {message}");

    /// <summary>Reads a package and checks what every package `nuget_pack` writes must get right.</summary>
    public static PackageFile Read(string path, bool versioned)
    {
        var name = Path.GetFileName(path);
        var entries = new List<Entry>();
        using (var archive = ZipFile.OpenRead(path))
        {
            foreach (var entry in archive.Entries)
            {
                // The clock time as the zip holds it, which has no time zone.
                if (entry.LastWriteTime.DateTime != Epoch)
                {
                    throw new InvalidDataException($"{name}: {entry.FullName} is stamped {entry.LastWriteTime.DateTime:s}, not {Epoch:s}");
                }
                using var stream = entry.Open();
                using var bytes = new MemoryStream();
                stream.CopyTo(bytes);
                entries.Add(new Entry(entry.FullName, bytes.ToArray()));
            }
        }

        for (var i = 1; i < entries.Count; i++)
        {
            if (string.CompareOrdinal(entries[i - 1].Name, entries[i].Name) >= 0)
            {
                throw new InvalidDataException($"{name}: entries are not in ordinal order, or repeat: {entries[i - 1].Name} before {entries[i].Name}");
            }
        }

        var names = entries.Select(entry => entry.Name).ToList();
        var nuspecs = names.Where(entry => !entry.Contains('/') && entry.EndsWith(".nuspec", StringComparison.OrdinalIgnoreCase)).ToList();
        if (nuspecs.Count != 1)
        {
            throw new InvalidDataException($"{name}: wants one manifest at its root, has {nuspecs.Count}");
        }

        var underPackage = names.Where(entry => entry.StartsWith("package/", StringComparison.Ordinal)).ToList();
        if (underPackage.Count != 1 || !CoreProperties.IsMatch(underPackage[0]))
        {
            throw new InvalidDataException($"{name}: wants one core-properties part named by a hash under package/, has: {string.Join(", ", underPackage)}");
        }

        foreach (var required in new[] { ContentTypesEntry, RelationshipsEntry })
        {
            if (!names.Contains(required))
            {
                throw new InvalidDataException($"{name}: has no {required}");
            }
        }

        PackageIdentity identity;
        List<string> packageTypes;
        using (var reader = new PackageArchiveReader(path))
        {
            identity = reader.GetIdentity();
            packageTypes = reader.GetPackageTypes().Select(type => type.Name).ToList();

            foreach (var group in reader.NuspecReader.GetDependencyGroups())
            {
                if (group.TargetFramework.IsUnsupported)
                {
                    throw new InvalidDataException($"{name}: NuGet cannot read the framework of a dependency group");
                }
            }
            foreach (var group in reader.NuspecReader.GetFrameworkRefGroups())
            {
                if (group.TargetFramework.IsUnsupported)
                {
                    throw new InvalidDataException($"{name}: NuGet cannot read the framework of a framework reference group");
                }
            }
        }

        var package = new PackageFile(path, entries, nuspecs[0], underPackage[0], identity, packageTypes);
        package.CheckParts(versioned);
        return package;
    }

    private void CheckParts(bool versioned)
    {
        if (Nuspec != Identity.Id + ".nuspec")
        {
            throw Bad($"the manifest is {Nuspec}, not named after the id {Identity.Id}");
        }

        if (versioned)
        {
            var expected = $"{Identity.Id}.{Identity.Version.ToNormalizedString()}{Path.GetExtension(FileName)}";
            if (FileName != expected)
            {
                throw Bad($"is not named after its id and version, {expected}");
            }
        }

        // What the packer writes has the same bytes on every platform.
        foreach (var entry in Entries.Where(entry => entry.Name == Nuspec || IsOpcPart(entry.Name) || entry.Name.EndsWith("/DotnetToolSettings.xml", StringComparison.Ordinal)))
        {
            if (entry.Bytes.Contains((byte)'\r'))
            {
                throw Bad($"{entry.Name} has a carriage return in it");
            }
        }

        // Every part has a content type: by its extension, or by its own name.
        var types = XDocument.Parse(Text(Entry(ContentTypesEntry))).Root!;
        var extensions = types.Elements().Where(element => element.Name.LocalName == "Default")
            .Select(element => ((string)element.Attribute("Extension")!).ToLowerInvariant()).ToHashSet();
        var overrides = types.Elements().Where(element => element.Name.LocalName == "Override")
            .Select(element => (string)element.Attribute("PartName")!).ToHashSet();
        foreach (var entry in Entries.Where(entry => entry.Name != ContentTypesEntry))
        {
            var extension = Path.GetExtension(entry.Name);
            var covered = extension.Length > 1
                ? extensions.Contains(extension.Substring(1).ToLowerInvariant())
                : overrides.Contains("/" + entry.Name);
            if (!covered)
            {
                throw Bad($"{ContentTypesEntry} names no content type for {entry.Name}");
            }
        }

        // The relationships point at the manifest and the core properties, and at nothing else.
        var targets = XDocument.Parse(Text(Entry(RelationshipsEntry))).Root!.Elements()
            .Select(element => (string)element.Attribute("Target")!).OrderBy(target => target, StringComparer.Ordinal);
        var wanted = new[] { "/" + Nuspec, "/" + CorePropertiesEntry }.OrderBy(target => target, StringComparer.Ordinal);
        if (!targets.SequenceEqual(wanted))
        {
            throw Bad($"{RelationshipsEntry} points at {string.Join(", ", targets)}, not at {string.Join(", ", wanted)}");
        }
    }

    /// <summary>Checks this symbol package against the package it goes with, as nuget.org does.</summary>
    public void CheckSymbolsOf(PackageFile package)
    {
        if (Identity.Id != package.Identity.Id || Identity.Version.ToFullString() != package.Identity.Version.ToFullString())
        {
            throw Bad($"is {Identity.Id} {Identity.Version.ToFullString()}, but its package is {package.Identity.Id} {package.Identity.Version.ToFullString()}");
        }

        if (!PackageTypes.SequenceEqual(new[] { SymbolsPackageType }))
        {
            throw Bad($"has the package types [{string.Join(", ", PackageTypes)}], not [{SymbolsPackageType}]");
        }

        var assemblies = package.Entries.Select(entry => entry.Name).ToHashSet();
        foreach (var entry in Entries.Where(entry => entry.Name.EndsWith(".pdb", StringComparison.OrdinalIgnoreCase)))
        {
            var stem = entry.Name.Substring(0, entry.Name.Length - ".pdb".Length);
            if (!assemblies.Contains(stem + ".dll") && !assemblies.Contains(stem + ".exe"))
            {
                throw Bad($"{entry.Name} has no assembly beside it in {package.FileName}");
            }
        }
    }

    /// <summary>The paths of what the package carries: not the manifest, nor the OPC parts every package has.</summary>
    public IReadOnlyList<string> Payload() =>
        Entries.Where(entry => entry.Name != Nuspec && !IsOpcPart(entry.Name)).Select(entry => PathOf(entry.Name)).ToList();

    /// <summary>What every assembly says it is, by path; a copy of an earlier one says that instead.</summary>
    public IReadOnlyDictionary<string, string> AssemblyIdentities()
    {
        var identities = new Dictionary<string, string>();
        var seen = new Dictionary<string, string>();
        foreach (var entry in Entries.Where(entry => Assemblies.IsAssembly(entry.Name)))
        {
            var path = PathOf(entry.Name);

            // Identical bytes say more than a second identity would: a copy,
            // or two builds that should have differed and did not.
            var hash = Convert.ToHexString(SHA256.HashData(entry.Bytes));
            if (seen.TryGetValue(hash, out var first))
            {
                identities[path] = "same bytes as " + first;
            }
            else
            {
                seen[hash] = path;
                identities[path] = Assemblies.Identity(entry.Bytes);
            }
        }
        return identities;
    }

    /// <summary>What `dotnet pack` would warn about: the rules it runs over every package it writes.</summary>
    public IReadOnlyList<Warning> NuGetWarnings()
    {
        using var reader = new PackageArchiveReader(_path);

        // Not the advice below a warning, such as a missing readme.
        return RuleSet.PackageCreationRuleSet
            .SelectMany(rule => rule.Validate(reader))
            .Where(message => message.Level >= LogLevel.Warning)
            .Select(message => new Warning(message.Code.ToString(), message.Message.ReplaceLineEndings("\n").TrimEnd()))
            .OrderBy(warning => warning.Code, StringComparer.Ordinal)
            .ToList();
    }

    /// <summary>The text of the entry at a path in the package, or null when there is none.</summary>
    public string? Content(string path)
    {
        var entry = Entries.SingleOrDefault(entry => PathOf(entry.Name) == path);
        if (entry == null)
        {
            return null;
        }

        // JSON the rule writes on one line, so it is laid out; XML as it is.
        var text = Text(entry);
        if (path.EndsWith(".json", StringComparison.Ordinal))
        {
            text = JsonNode.Parse(text)!.ToJsonString(LaidOut);
        }
        return text.EndsWith('\n') ? text : text + "\n";
    }

    /// <summary>The path of an entry in the package: its name, whose segments are URL-escaped as NuGet writes them.</summary>
    public static string PathOf(string name) => string.Join("/", name.Split('/').Select(Uri.UnescapeDataString));

    public Entry Entry(string name) => Entries.Single(entry => entry.Name == name);

    public static string Text(Entry entry) =>
        Encoding.UTF8.GetString(entry.Bytes).TrimStart('﻿').ReplaceLineEndings("\n");

    private bool IsOpcPart(string name) =>
        name == ContentTypesEntry || name == RelationshipsEntry || name == CorePropertiesEntry;
}
