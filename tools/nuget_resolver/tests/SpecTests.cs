using System;
using System.IO;
using NUnit.Framework;
using NuGetResolver;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class SpecTests
{
    [Test]
    public void LoadReadsPackagesFrameworksAndSources()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "spec.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, """
            {
              "packages": { "Newtonsoft.Json": "13.0.3", "Serilog": "4.0.*" },
              "frameworks": ["net8.0", "net10.0"],
              "sources": ["https://api.nuget.org/v3/index.json", "https://pkgs.example.com/v3/index.json"]
            }
            """);

        var spec = ResolveSpec.Load(path);

        Assert.That(spec.Packages, Is.EqualTo(new[]
        {
            new PackageRequest("Newtonsoft.Json", "13.0.3"),
            new PackageRequest("Serilog", "4.0.*"),
        }));
        Assert.That(spec.Frameworks, Is.EqualTo(new[] { "net8.0", "net10.0" }));
        Assert.That(spec.Sources, Is.EqualTo(new[]
        {
            "https://api.nuget.org/v3/index.json",
            "https://pkgs.example.com/v3/index.json",
        }));
    }

    [Test]
    public void LoadMissingFileThrowsResolveException()
    {
        var ex = Assert.Throws<ResolveException>(() => ResolveSpec.Load("/does/not/exist/spec.json"));
        Assert.That(ex!.Message, Does.Contain("/does/not/exist/spec.json"));
    }
}
