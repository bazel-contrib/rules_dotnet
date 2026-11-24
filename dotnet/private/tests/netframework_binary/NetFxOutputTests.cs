using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Xml.Linq;
using NUnit.Framework;

namespace NetFxBinaryTests;

/// <summary>
/// Checks the output directories of .NET Framework binaries, which every
/// platform can build even though only Windows can run them.
/// </summary>
[TestFixture]
public sealed class NetFxOutputTests
{
    private static readonly XNamespace Asm = "urn:schemas-microsoft-com:asm.v1";

    private static string[] Files(string envVar)
    {
        string raw = Environment.GetEnvironmentVariable(envVar) ?? "";
        return raw.Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(Path.GetFullPath).ToArray();
    }

    private static string FindOutputDir(string envVar, string marker = "/net48/")
    {
        string? file = Files(envVar).FirstOrDefault(p => p.Replace('\\', '/').Contains(marker));
        Assert.That(file, Is.Not.Null, $"Expected a {marker} path in {envVar}");
        return Path.GetDirectoryName(file!)!;
    }

    private static Version AssemblyVersion(string path) => AssemblyName.GetAssemblyName(path).Version!;

    private static (string? Token, string? OldVersion, string? NewVersion)? Redirect(XDocument config, string name)
    {
        XElement? dependentAssembly = config
            .Descendants(Asm + "dependentAssembly")
            .SingleOrDefault(d => (string?)d.Element(Asm + "assemblyIdentity")?.Attribute("name") == name);
        if (dependentAssembly is null)
        {
            return null;
        }

        return (
            (string?)dependentAssembly.Element(Asm + "assemblyIdentity")?.Attribute("publicKeyToken"),
            (string?)dependentAssembly.Element(Asm + "bindingRedirect")?.Attribute("oldVersion"),
            (string?)dependentAssembly.Element(Asm + "bindingRedirect")?.Attribute("newVersion"));
    }

    private static void AssertSupportedRuntime(XDocument config)
    {
        XElement? supportedRuntime = config.Root!.Element("startup")?.Element("supportedRuntime");
        Assert.That(supportedRuntime, Is.Not.Null, "Expected <startup><supportedRuntime>");
        Assert.That((string?)supportedRuntime!.Attribute("version"), Is.EqualTo("v4.0"));
        Assert.That((string?)supportedRuntime.Attribute("sku"), Is.EqualTo(".NETFramework,Version=v4.8"));
    }

    [Test]
    public void CSharpNet48BinaryProducesExeStagedLibsAndBindingRedirects()
    {
        string outDir = FindOutputDir("CSHARP_APP_FILES");
        string exePath = Path.Combine(outDir, "app.exe");
        string configPath = Path.Combine(outDir, "app.exe.config");

        foreach (string name in new[] { "app.exe", "app.exe.config", "SharedDep.dll", "Consumer.dll", "unsigned_dep.dll" })
        {
            Assert.That(File.Exists(Path.Combine(outDir, name)), Is.True, name);
        }

        // Dependency PDBs, for line numbers in stack traces.
        Assert.That(File.Exists(Path.Combine(outDir, "SharedDep.pdb")), Is.True);
        Assert.That(File.Exists(Path.Combine(outDir, "unsigned_dep.pdb")), Is.True);

        // One copy of SharedDep: its satellite assemblies are at the usual paths.
        foreach (string culture in new[] { "de", "fr" })
        {
            Assert.That(AssemblyVersion(Path.Combine(outDir, culture, "SharedDep.resources.dll")), Is.EqualTo(new Version(2, 0, 0, 0)), culture);
        }

        // .NET Framework does not look in runtimes/<rid>/native.
        Assert.That(Directory.Exists(Path.Combine(outDir, "runtimes")), Is.False);

        // The embedded resource inside app.exe has the assembly-prefixed manifest name.
        using (var stream = File.OpenRead(exePath))
        using (var peReader = new PEReader(stream))
        {
            MetadataReader metadata = peReader.GetMetadataReader();
            string[] resourceNames = metadata.ManifestResources
                .Select(h => metadata.GetString(metadata.GetManifestResource(h).Name))
                .ToArray();
            Assert.That(resourceNames, Does.Contain("app.resource.txt"));
        }

        XDocument config = XDocument.Load(configPath);
        AssertSupportedRuntime(config);

        // Consumer references SharedDep 1.0.0.0 and the application ships 2.0.0.0.
        Assert.That(AssemblyVersion(Path.Combine(outDir, "SharedDep.dll")), Is.EqualTo(new Version(2, 0, 0, 0)));
        var sharedRedirect = Redirect(config, "SharedDep");
        Assert.That(sharedRedirect, Is.Not.Null, "Expected a bindingRedirect for SharedDep");
        Assert.That(sharedRedirect!.Value.Token, Has.Length.EqualTo(16));
        Assert.That(sharedRedirect.Value.OldVersion, Is.EqualTo("0.0.0.0-2.0.0.0"));
        Assert.That(sharedRedirect.Value.NewVersion, Is.EqualTo("2.0.0.0"));

        // An assembly without a strong name binds by name alone.
        Assert.That(Redirect(config, "unsigned_dep"), Is.Null);
    }

    [Test]
    public void FSharpNet48BinaryProducesExeAndNoRedirectWithoutAConflict()
    {
        string outDir = FindOutputDir("FSHARP_APP_FILES");

        Assert.That(File.Exists(Path.Combine(outDir, "fsharp_app.exe")), Is.True);
        Assert.That(File.Exists(Path.Combine(outDir, "FSharp.Core.dll")), Is.True);

        // FSharp.Core is referenced at the shipped version, so needs no redirect.
        XDocument config = XDocument.Load(Path.Combine(outDir, "fsharp_app.exe.config"));
        AssertSupportedRuntime(config);
        Assert.That(Redirect(config, "FSharp.Core"), Is.Null);
    }

    [Test]
    public void TheHighestVersionOfAnAssemblyIsShippedWhereverItComesInTheGraph()
    {
        // SharedDep 1.0.0.0 comes through Consumer, ahead of the binary's 2.0.0.0.
        string outDir = FindOutputDir("CONFLICT_APP_FILES");

        Assert.That(AssemblyVersion(Path.Combine(outDir, "SharedDep.dll")), Is.EqualTo(new Version(2, 0, 0, 0)));
        Assert.That(File.Exists(Path.Combine(outDir, "SharedDep.pdb")), Is.True);

        // The shipped copy's satellite assemblies: German, which both have, and
        // French, which only 2.0.0.0 has. 1.0.0.0's Spanish one does not ship.
        foreach (string culture in new[] { "de", "fr" })
        {
            string satellite = Path.Combine(outDir, culture, "SharedDep.resources", "SharedDep.resources.dll");
            Assert.That(AssemblyVersion(satellite), Is.EqualTo(new Version(2, 0, 0, 0)), culture);
            Assert.That(File.Exists(Path.Combine(outDir, culture, "SharedDep.resources.dll")), Is.False, culture);
        }

        Assert.That(File.Exists(Path.Combine(outDir, "es", "SharedDep.resources", "SharedDep.resources.dll")), Is.False);
        Assert.That(File.Exists(Path.Combine(outDir, "es", "SharedDep.resources.dll")), Is.False);

        XDocument config = XDocument.Load(Path.Combine(outDir, "conflict_app.exe.config"));
        var redirect = Redirect(config, "SharedDep");
        Assert.That(redirect, Is.Not.Null, "Expected a bindingRedirect for SharedDep");
        Assert.That(redirect!.Value.OldVersion, Is.EqualTo("0.0.0.0-2.0.0.0"));
        Assert.That(redirect.Value.NewVersion, Is.EqualTo("2.0.0.0"));
    }

    [Test]
    public void TheGeneratedRedirectsAreMergedIntoAppConfig()
    {
        string outDir = FindOutputDir("APP_CONFIG_APP_FILES");
        XDocument config = XDocument.Load(Path.Combine(outDir, "app_config_app.exe.config"));

        // What the user wrote is kept...
        XElement? setting = config.Root!.Element("appSettings")?.Elements("add")
            .SingleOrDefault(e => (string?)e.Attribute("key") == "greeting");
        Assert.That((string?)setting?.Attribute("value"), Is.EqualTo("hello-from-app-config"));
        Assert.That(Redirect(config, "Unrelated")?.NewVersion, Is.EqualTo("9.0.0.0"));

        // ...and the build adds to it.
        AssertSupportedRuntime(config);
        Assert.That(Redirect(config, "SharedDep")?.NewVersion, Is.EqualTo("2.0.0.0"));
    }

    [Test]
    public void APublishIsTheOutputDirectoryWithoutPdbs()
    {
        string[] files = Files("PUBLISH_FILES");
        string[] names = files.Select(Path.GetFileName).ToArray()!;

        Assert.That(names, Is.SupersetOf(new[] { "app.exe", "app.exe.config", "SharedDep.dll", "Consumer.dll", "unsigned_dep.dll" }));
        Assert.That(names.Where(n => n.EndsWith(".pdb", StringComparison.OrdinalIgnoreCase)), Is.Empty);
        Assert.That(names.Where(n => n.EndsWith(".deps.json") || n.EndsWith(".runtimeconfig.json")), Is.Empty);

        // Published for Windows, flat except for satellite assemblies.
        string root = Path.GetDirectoryName(files.Single(f => Path.GetFileName(f) == "app.exe"))!;
        Assert.That(Path.GetFileName(root), Does.StartWith("win-"));
        Assert.That(files.Select(Path.GetDirectoryName).Distinct(), Is.EquivalentTo(new[] { root, Path.Combine(root, "de"), Path.Combine(root, "fr") }));

        string configPath = files.Single(f => Path.GetFileName(f) == "app.exe.config");
        Assert.That(Redirect(XDocument.Load(configPath), "SharedDep")?.NewVersion, Is.EqualTo("2.0.0.0"));
    }

    [Test]
    public void APublishCarriesTheSatelliteDirectoriesOfTheChosenCopy()
    {
        string root = Path.GetDirectoryName(Files("CONFLICT_PUBLISH_FILES").Single(f => Path.GetFileName(f) == "conflict_app.exe"))!;

        foreach (string culture in new[] { "de", "fr" })
        {
            string satellite = Path.Combine(root, culture, "SharedDep.resources", "SharedDep.resources.dll");
            Assert.That(AssemblyVersion(satellite), Is.EqualTo(new Version(2, 0, 0, 0)), culture);
        }

        Assert.That(File.Exists(Path.Combine(root, "es", "SharedDep.resources", "SharedDep.resources.dll")), Is.False);
    }

    [Test]
    public void TheLauncherSaysANetFrameworkBinaryOnlyRunsOnWindows()
    {
        if (OperatingSystem.IsWindows())
        {
            Assert.Ignore("Windows runs .NET Framework binaries: net48_runtime_test covers it.");
        }

        string launcher = Path.GetFullPath(Environment.GetEnvironmentVariable("CSHARP_APP_LAUNCHER")!);
        using Process process = Process.Start(new ProcessStartInfo(launcher)
        {
            RedirectStandardError = true,
            UseShellExecute = false,
        })!;
        string error = process.StandardError.ReadToEnd();
        process.WaitForExit();

        Assert.That(process.ExitCode, Is.EqualTo(1));
        Assert.That(error, Does.Contain("targets .NET Framework (net48), which only runs on Windows"));
    }
}
