// The request `nuget_pack` writes for the packer. Field names are the JSON
// names; the rule spells them in camelCase and the tool reads them
// case-insensitively.
using System.Collections.Generic;

namespace RulesDotnet.NuGetPack;

internal sealed class Request
{
    public string Output { get; set; } = "";

    public string? NuspecOutput { get; set; }

    public string? SymbolsOutput { get; set; }

    /// <summary>A file whose first non-empty line is the version, or null to use the metadata's.</summary>
    public string? VersionFile { get; set; }

    public Metadata Metadata { get; set; } = new();

    /// <summary>Package type names, such as "DotnetTool". Empty for a library.</summary>
    public List<string> PackageTypes { get; set; } = new();

    /// <summary>One group per framework the package targets, possibly with no dependencies.</summary>
    public List<DependencyGroup> DependencyGroups { get; set; } = new();

    public List<FrameworkReferenceGroup> FrameworkReferenceGroups { get; set; } = new();

    /// <summary>The metadata for the files under `contentFiles/`.</summary>
    public List<ContentFilesEntry> ContentFiles { get; set; } = new();

    /// <summary>The payload of the package.</summary>
    public List<FileEntry> Files { get; set; } = new();

    /// <summary>The payload of the symbol package.</summary>
    public List<FileEntry> SymbolFiles { get; set; } = new();

    /// <summary>Makes the package a .NET tool, or null.</summary>
    public ToolSettings? ToolSettings { get; set; }
}

internal sealed class Metadata
{
    public string Id { get; set; } = "";
    public string Version { get; set; } = "";
    public List<string> Authors { get; set; } = new();
    public string Description { get; set; } = "";
    public string? Title { get; set; }
    public string? Copyright { get; set; }
    public string? ProjectUrl { get; set; }
    public string? ReleaseNotes { get; set; }
    public List<string> Tags { get; set; } = new();
    public bool RequireLicenseAcceptance { get; set; }
    public bool DevelopmentDependency { get; set; }
    public License? License { get; set; }

    /// <summary>The in-package path of the icon, or null.</summary>
    public string? Icon { get; set; }

    /// <summary>The in-package path of the readme, or null.</summary>
    public string? Readme { get; set; }

    public Repository? Repository { get; set; }
    public string? MinClientVersion { get; set; }
}

internal sealed class License
{
    /// <summary>"expression" or "file".</summary>
    public string Type { get; set; } = "";

    /// <summary>The SPDX expression, or the in-package path of the license file.</summary>
    public string Value { get; set; } = "";
}

internal sealed class Repository
{
    public string Type { get; set; } = "";
    public string Url { get; set; } = "";
    public string? Branch { get; set; }
    public string? Commit { get; set; }
}

internal sealed class DependencyGroup
{
    /// <summary>The framework as a nuspec spells it, such as ".NETStandard2.0" or "net8.0".</summary>
    public string TargetFramework { get; set; } = "";

    public List<Dependency> Dependencies { get; set; } = new();
}

internal sealed class Dependency
{
    public string Id { get; set; } = "";

    /// <summary>A version range, written as given; a bare version means "at least".</summary>
    public string Version { get; set; } = "";

    /// <summary>A file whose first non-empty line is the version, or null.</summary>
    public string? VersionFile { get; set; }

    /// <summary>Asset kinds the consumer does not take from this dependency.</summary>
    public List<string> Exclude { get; set; } = new();
}

internal sealed class FrameworkReferenceGroup
{
    public string TargetFramework { get; set; } = "";
    public List<string> FrameworkReferences { get; set; } = new();
}

internal sealed class ContentFilesEntry
{
    /// <summary>A path or pattern relative to `contentFiles/`.</summary>
    public string Include { get; set; } = "";

    public string BuildAction { get; set; } = "Content";
    public bool CopyToOutput { get; set; }
    public bool Flatten { get; set; }
}

internal sealed class FileEntry
{
    /// <summary>The file on disk.</summary>
    public string Source { get; set; } = "";

    /// <summary>Its path inside the package, with forward slashes.</summary>
    public string Target { get; set; } = "";
}

internal sealed class ToolSettings
{
    /// <summary>The command the tool installs as.</summary>
    public string CommandName { get; set; } = "";

    /// <summary>The assembly to run, a bare file name resolved beside the settings file.</summary>
    public string EntryPoint { get; set; } = "";

    /// <summary>The in-package directories to write a `DotnetToolSettings.xml` into, one per framework.</summary>
    public List<string> Directories { get; set; } = new();
}
