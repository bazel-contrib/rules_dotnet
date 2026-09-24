// Checks a request before anything is written, collecting every problem so
// that one run reports them all.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace RulesDotnet.NuGetPack;

internal static partial class Validation
{
    // NuGet's PackageIdValidator.
    [GeneratedRegex(@"^\w+([_.-]\w+)*$")]
    private static partial Regex PackageId();

    private const int MaxPackageIdLength = 100;

    private static readonly string[] LicenseTypes = { "expression", "file" };

    /// <summary>Validates <paramref name="request"/>.</summary>
    /// <returns>The problems found; empty when the request is good, in which case <paramref name="version"/> is set.</returns>
    public static List<string> Run(Request request, out NuGetVersion? version)
    {
        var errors = new List<string>();
        version = null;

        var metadata = request.Metadata;
        if (!PackageId().IsMatch(metadata.Id) || metadata.Id.Length > MaxPackageIdLength)
        {
            errors.Add($"package id '{metadata.Id}' is not a valid NuGet package id: letters, digits and '_' separated by single '.', '-' or '_', at most {MaxPackageIdLength} characters");
        }

        var versionText = metadata.Version;
        if (request.VersionFile != null)
        {
            if (!File.Exists(request.VersionFile))
            {
                errors.Add($"version file '{request.VersionFile}' does not exist");
            }
            else
            {
                versionText = File.ReadLines(request.VersionFile).Select(line => line.Trim()).FirstOrDefault(line => line.Length > 0) ?? "";
                if (versionText.Length == 0)
                {
                    errors.Add($"version file '{request.VersionFile}' is empty");
                }
            }
        }

        if (!NuGetVersion.TryParse(versionText, out version))
        {
            errors.Add($"'{versionText}' is not a valid NuGet version: major.minor[.patch[.revision]][-prerelease][+metadata], components at most 65535");
        }

        if (!request.Output.EndsWith(".nupkg", StringComparison.Ordinal))
        {
            errors.Add($"output '{request.Output}' must end in .nupkg");
        }
        if (request.SymbolsOutput != null && !request.SymbolsOutput.EndsWith(".snupkg", StringComparison.Ordinal))
        {
            errors.Add($"symbols output '{request.SymbolsOutput}' must end in .snupkg");
        }

        // With the version known at analysis time the rule names the file
        // after it; make sure the two agree, so the name never lies.
        if (version != null && request.VersionFile == null)
        {
            var expected = $"{metadata.Id}.{version.Normalized}.nupkg";
            if (Path.GetFileName(request.Output) != expected)
            {
                errors.Add($"output '{request.Output}' should be named '{expected}'");
            }
            if (request.SymbolsOutput != null && Path.GetFileName(request.SymbolsOutput) != $"{metadata.Id}.{version.Normalized}.snupkg")
            {
                errors.Add($"symbols output '{request.SymbolsOutput}' should be named '{metadata.Id}.{version.Normalized}.snupkg'");
            }
        }

        if (string.IsNullOrWhiteSpace(metadata.Description))
        {
            errors.Add("a description is required");
        }
        if (metadata.Authors.Count == 0 || metadata.Authors.Any(string.IsNullOrWhiteSpace))
        {
            errors.Add("at least one author is required, and none may be blank");
        }

        var targets = ValidateFiles(request.Files, "files", errors);
        ValidateFiles(request.SymbolFiles, "symbolFiles", errors);

        if (metadata.License != null)
        {
            if (!LicenseTypes.Contains(metadata.License.Type))
            {
                errors.Add($"license type '{metadata.License.Type}' must be 'expression' or 'file'");
            }
            else if (metadata.License.Value.Length == 0)
            {
                errors.Add("the license has no value");
            }
            else if (metadata.License.Type == "file" && !targets.Contains(metadata.License.Value))
            {
                errors.Add($"license file '{metadata.License.Value}' is not among the packed files");
            }
        }
        if (metadata.Icon != null && !targets.Contains(metadata.Icon))
        {
            errors.Add($"icon '{metadata.Icon}' is not among the packed files");
        }
        if (metadata.Readme != null && !targets.Contains(metadata.Readme))
        {
            errors.Add($"readme '{metadata.Readme}' is not among the packed files");
        }
        if (metadata.Repository != null && metadata.Repository.Url.Length == 0)
        {
            errors.Add("a repository needs a url");
        }

        ValidateGroups(request.DependencyGroups.Select(group => group.TargetFramework), "dependency", errors);
        foreach (var group in request.DependencyGroups)
        {
            var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var dependency in group.Dependencies)
            {
                if (!PackageId().IsMatch(dependency.Id))
                {
                    errors.Add($"dependency id '{dependency.Id}' in group '{group.TargetFramework}' is not a valid package id");
                }
                if (!ids.Add(dependency.Id))
                {
                    errors.Add($"dependency '{dependency.Id}' appears twice in group '{group.TargetFramework}'");
                }
                if (dependency.VersionFile == null && dependency.Version.Length == 0)
                {
                    errors.Add($"dependency '{dependency.Id}' in group '{group.TargetFramework}' has no version");
                }
                if (dependency.VersionFile != null && !File.Exists(dependency.VersionFile))
                {
                    errors.Add($"version file '{dependency.VersionFile}' of dependency '{dependency.Id}' does not exist");
                }
            }
        }
        ValidateGroups(request.FrameworkReferenceGroups.Select(group => group.TargetFramework), "framework reference", errors);

        foreach (var entry in request.ContentFiles)
        {
            if (entry.Include.Length == 0)
            {
                errors.Add("a contentFiles entry has an empty include");
            }
        }

        foreach (var packageType in request.PackageTypes)
        {
            if (!PackageId().IsMatch(packageType))
            {
                errors.Add($"package type '{packageType}' is not a valid package type name");
            }
        }

        if (request.ToolSettings != null)
        {
            var tool = request.ToolSettings;
            if (!request.PackageTypes.Contains("DotnetTool"))
            {
                errors.Add("a tool package must have the DotnetTool package type");
            }
            if (tool.CommandName.Length == 0)
            {
                errors.Add("a tool needs a command name");
            }
            if (tool.EntryPoint.Length == 0 || tool.EntryPoint.Contains('/'))
            {
                errors.Add($"tool entry point '{tool.EntryPoint}' must be a bare file name");
            }
            if (tool.Directories.Count == 0)
            {
                errors.Add("a tool needs at least one directory to write its settings into");
            }
            foreach (var directory in tool.Directories)
            {
                if (!targets.Contains(directory + "/" + tool.EntryPoint))
                {
                    errors.Add($"tool entry point '{directory}/{tool.EntryPoint}' is not among the packed files");
                }
                if (targets.Contains(directory + "/" + ToolSettingsWriter.FileName))
                {
                    errors.Add($"'{directory}/{ToolSettingsWriter.FileName}' is written by the tool and cannot also be packed");
                }
            }
        }

        if (request.SymbolsOutput != null && !request.SymbolFiles.Any(entry => entry.Target.EndsWith(".pdb", StringComparison.OrdinalIgnoreCase)))
        {
            errors.Add("a symbol package needs at least one .pdb; nuget.org rejects one without");
        }

        return errors;
    }

    private static void ValidateGroups(IEnumerable<string> frameworks, string kind, List<string> errors)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var framework in frameworks)
        {
            if (framework.Length == 0)
            {
                errors.Add($"a {kind} group has no target framework");
            }
            else if (!seen.Add(framework))
            {
                errors.Add($"{kind} group '{framework}' appears twice");
            }
        }
    }

    /// <summary>Checks the file entries and returns their targets, case-sensitively, for lookups.</summary>
    private static HashSet<string> ValidateFiles(List<FileEntry> files, string what, List<string> errors)
    {
        var targets = new HashSet<string>(StringComparer.Ordinal);
        // Windows extracts case-insensitively, so two targets differing only by case collide there.
        var folded = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var entry in files)
        {
            if (!File.Exists(entry.Source))
            {
                errors.Add($"{what}: source '{entry.Source}' does not exist");
            }

            var target = entry.Target;
            var segments = target.Split('/');
            if (target.Length == 0 || target.Contains('\\') || segments.Any(segment => segment.Length == 0 || segment == "." || segment == ".."))
            {
                errors.Add($"{what}: target '{target}' must be a relative path with forward slashes and no empty, '.' or '..' segments");
                continue;
            }
            if (segments[0] == "_rels" || segments[0] == "package" || target == OpcParts.ContentTypesEntry)
            {
                errors.Add($"{what}: target '{target}' is reserved for the package's own parts");
            }
            if (segments.Length == 1 && target.EndsWith(".nuspec", StringComparison.OrdinalIgnoreCase))
            {
                errors.Add($"{what}: target '{target}' would be a second manifest; the tool writes the one manifest");
            }
            if (!folded.Add(target))
            {
                errors.Add($"{what}: target '{target}' is packed twice (targets are compared ignoring case)");
            }
            targets.Add(target);
        }

        return targets;
    }
}
