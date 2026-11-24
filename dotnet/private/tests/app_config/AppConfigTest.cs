using System;
using System.IO;
using System.Linq;
using NUnit.Framework;

namespace RulesDotnet.Tests;

[TestFixture]
public sealed class AppConfigTest
{
    private static string[] Files(string envVar) =>
        (Environment.GetEnvironmentVariable(envVar) ?? "")
            .Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(Path.GetFullPath)
            .ToArray();

    private static string Config(string envVar)
    {
        string? config = Files(envVar).SingleOrDefault(path => Path.GetFileName(path) == "app.dll.config");
        Assert.That(config, Is.Not.Null, $"Expected app.dll.config in {envVar}");
        return File.ReadAllText(config!);
    }

    [Test]
    public void TheBinaryHasItsAppConfigBesideTheAssembly()
    {
        // `$(rootpaths)` of a binary names its launcher, beside the assembly.
        string launcher = Files("APP_FILES").Single();
        string config = Path.Combine(Path.GetDirectoryName(launcher)!, "app.dll.config");
        Assert.That(File.ReadAllText(config), Does.Contain("hello-from-app-config"));
    }

    [Test]
    public void ThePublishHasItsAppConfigBesideTheAssembly() =>
        Assert.That(Config("PUBLISH_FILES"), Does.Contain("hello-from-app-config"));
}
