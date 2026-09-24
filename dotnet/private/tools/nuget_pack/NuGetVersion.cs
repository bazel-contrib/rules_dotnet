// The version grammar of NuGet.Versioning's NuGetVersion, as far as this tool
// needs it: two to four numeric components, then SemVer 2.0's optional
// pre-release label and build metadata. Mirrors dotnet/private/nuget_version.bzl,
// which validates the same strings at analysis time.
using System;
using System.Text.RegularExpressions;

namespace RulesDotnet.NuGetPack;

internal sealed partial class NuGetVersion
{
    [GeneratedRegex(@"^(\d+)\.(\d+)(?:\.(\d+)(?:\.(\d+))?)?(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$")]
    private static partial Regex Grammar();

    private NuGetVersion(int major, int minor, int patch, int revision, string prerelease, string metadata)
    {
        Major = major;
        Minor = minor;
        Patch = patch;
        Revision = revision;
        Prerelease = prerelease;
        Metadata = metadata;
    }

    public int Major { get; }
    public int Minor { get; }
    public int Patch { get; }
    public int Revision { get; }
    public string Prerelease { get; }
    public string Metadata { get; }

    /// <summary>The version as NuGet normalizes it: three components, a fourth only when non-zero, the pre-release label, no metadata.</summary>
    public string Normalized
    {
        get
        {
            var normalized = $"{Major}.{Minor}.{Patch}";
            if (Revision != 0)
            {
                normalized += $".{Revision}";
            }
            if (Prerelease.Length > 0)
            {
                normalized += "-" + Prerelease;
            }
            return normalized;
        }
    }

    /// <summary>The normalized version with its metadata, which is what a nuspec records.</summary>
    public string Full => Metadata.Length > 0 ? Normalized + "+" + Metadata : Normalized;

    public static bool TryParse(string text, out NuGetVersion? version)
    {
        version = null;
        var match = Grammar().Match(text);
        if (!match.Success)
        {
            return false;
        }

        var components = new int[4];
        for (var i = 0; i < 4; i++)
        {
            var group = match.Groups[i + 1];
            if (!group.Success)
            {
                continue;
            }
            // AssemblyVersion stores each component in 16 bits; anything larger
            // cannot be what the assembly says.
            if (!int.TryParse(group.Value, out components[i]) || components[i] > 65535)
            {
                return false;
            }
        }

        version = new NuGetVersion(components[0], components[1], components[2], components[3], match.Groups[5].Value, match.Groups[6].Value);
        return true;
    }
}
