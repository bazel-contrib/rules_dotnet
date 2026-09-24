using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.RegularExpressions;
using System.Xml.Linq;
using Bazel;
using NUnit.Framework;

/// <summary>Opens the packages the BUILD file builds and checks what is in them.</summary>
[TestFixture]
public sealed class PackTest
{
    private const string Package = "rules_dotnet/dotnet/private/tests/nuget_pack/";
    private static readonly DateTimeOffset Epoch = new(1980, 1, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly Regex CoreProperties = new(@"^package/services/metadata/core-properties/[0-9a-f]{32}\.psmdcp$");

    private static ZipArchive Open(string path) =>
        ZipFile.OpenRead(Runfiles.Create().Rlocation(Package + path));

    private static XElement Metadata(ZipArchive archive, string id)
    {
        using var stream = archive.GetEntry(id + ".nuspec")!.Open();
        return XDocument.Load(stream).Root!.Elements().Single(element => element.Name.LocalName == "metadata");
    }

    private static string? Element(XElement metadata, string name) =>
        metadata.Elements().SingleOrDefault(element => element.Name.LocalName == name)?.Value;

    private static Dictionary<string, Dictionary<string, string>> DependencyGroups(XElement metadata)
    {
        var dependencies = metadata.Elements().SingleOrDefault(element => element.Name.LocalName == "dependencies");
        return dependencies == null
            ? new Dictionary<string, Dictionary<string, string>>()
            : dependencies.Elements().ToDictionary(
                group => (string)group.Attribute("targetFramework")!,
                group => group.Elements().ToDictionary(
                    dependency => (string)dependency.Attribute("id")!,
                    dependency => (string)dependency.Attribute("version")!));
    }

    private static void AssertWellFormed(ZipArchive archive, string id)
    {
        var names = archive.Entries.Select(entry => entry.FullName).ToList();
        Assert.That(names, Is.Ordered.Using<string>(StringComparer.Ordinal), "entries are in ordinal order");
        Assert.That(names, Does.Contain(id + ".nuspec"));
        Assert.That(names, Does.Contain("[Content_Types].xml"));
        Assert.That(names, Does.Contain("_rels/.rels"));
        Assert.That(names.Count(CoreProperties.IsMatch), Is.EqualTo(1), "one content-hashed core-properties part");
        Assert.That(names.Where(name => name.EndsWith(".nuspec")), Has.Exactly(1).Items, "one manifest");
        foreach (var entry in archive.Entries)
        {
            Assert.That(entry.LastWriteTime, Is.EqualTo(Epoch), entry.FullName);
        }
    }

    private static IEnumerable<string> Payload(ZipArchive archive) =>
        archive.Entries.Select(entry => entry.FullName)
            .Where(name => !name.EndsWith(".nuspec") && name != "[Content_Types].xml" && name != "_rels/.rels" && !CoreProperties.IsMatch(name));

    [Test]
    public void BundledPackage()
    {
        using var archive = Open("pack/RulesDotnet.Tests.Lib.1.2.3-beta.1.nupkg");
        AssertWellFormed(archive, "RulesDotnet.Tests.Lib");

        var expected = new List<string> { "README.md" };
        foreach (var tfm in new[] { "netstandard2.0", "net9.0" })
        {
            foreach (var assembly in new[] { "lib", "bundled", "referenced" })
            {
                expected.Add($"lib/{tfm}/{assembly}.dll");
                expected.Add($"lib/{tfm}/{assembly}.xml");
                expected.Add($"ref/{tfm}/{assembly}.dll");
            }
        }
        Assert.That(Payload(archive), Is.EquivalentTo(expected));

        var metadata = Metadata(archive, "RulesDotnet.Tests.Lib");
        Assert.That(Element(metadata, "id"), Is.EqualTo("RulesDotnet.Tests.Lib"));
        Assert.That(Element(metadata, "version"), Is.EqualTo("1.2.3-beta.1+abc"), "metadata is kept in the manifest");
        Assert.That(Element(metadata, "authors"), Is.EqualTo("rules_dotnet,contributors"));
        Assert.That(Element(metadata, "readme"), Is.EqualTo("README.md"));
        Assert.That(Element(metadata, "license"), Is.EqualTo("Apache-2.0"));
        Assert.That(Element(metadata, "tags"), Is.EqualTo("test rules_dotnet"));
        Assert.That(Element(metadata, "packageTypes"), Is.Null);

        var groups = DependencyGroups(metadata);
        Assert.That(groups.Keys, Is.EquivalentTo(new[] { ".NETStandard2.0", "net9.0" }));
        foreach (var group in groups.Values)
        {
            Assert.That(group, Is.EquivalentTo(new Dictionary<string, string>
            {
                ["RulesDotnet.Tests.Mapped"] = "3.0.0",
                ["System.Memory"] = "4.5.5",
            }));
        }
    }

    [Test]
    public void SymbolPackage()
    {
        using var archive = Open("pack/RulesDotnet.Tests.Lib.1.2.3-beta.1.snupkg");
        AssertWellFormed(archive, "RulesDotnet.Tests.Lib");

        Assert.That(Payload(archive), Is.EquivalentTo(new[]
        {
            "lib/netstandard2.0/lib.pdb", "lib/netstandard2.0/bundled.pdb", "lib/netstandard2.0/referenced.pdb",
            "lib/net9.0/lib.pdb", "lib/net9.0/bundled.pdb", "lib/net9.0/referenced.pdb",
        }));

        var metadata = Metadata(archive, "RulesDotnet.Tests.Lib");
        Assert.That(Element(metadata, "version"), Is.EqualTo("1.2.3-beta.1+abc"));
        Assert.That(metadata.Elements().Single(element => element.Name.LocalName == "packageTypes").Elements().Single().Attribute("name")!.Value, Is.EqualTo("SymbolsPackage"));
        foreach (var absent in new[] { "authors", "license", "readme", "requireLicenseAcceptance", "dependencies" })
        {
            Assert.That(Element(metadata, absent), Is.Null, absent);
        }
    }

    [Test]
    public void ReferencingPackage()
    {
        using var archive = Open("pack_ref/RulesDotnet.Tests.Lib.1.2.3-beta.1.nupkg");
        AssertWellFormed(archive, "RulesDotnet.Tests.Lib");

        Assert.That(Payload(archive), Is.EquivalentTo(new[]
        {
            "lib/netstandard2.0/lib.dll", "lib/netstandard2.0/lib.xml", "ref/netstandard2.0/lib.dll",
            "lib/net9.0/lib.dll", "lib/net9.0/lib.xml", "ref/net9.0/lib.dll",
        }));

        foreach (var group in DependencyGroups(Metadata(archive, "RulesDotnet.Tests.Lib")).Values)
        {
            Assert.That(group, Is.EquivalentTo(new Dictionary<string, string>
            {
                ["bundled"] = "1.0.0",
                ["referenced"] = "2.0.0",
                ["RulesDotnet.Tests.Mapped"] = "3.0.0",
                ["System.Memory"] = "4.5.5",
            }));
        }
    }

    [Test]
    public void RidSpecificPackage()
    {
        using var archive = Open("rid_pack/RulesDotnet.Tests.RidLib.1.0.0.nupkg");
        AssertWellFormed(archive, "RulesDotnet.Tests.RidLib");

        Assert.That(Payload(archive), Is.EquivalentTo(new[]
        {
            "ref/net9.0/ridlib.dll",
            "ref/net9.0/ridlib.xml",
            "runtimes/linux-x64/lib/net9.0/ridlib.dll",
            "runtimes/win-x64/lib/net9.0/ridlib.dll",
        }));

        Assert.That(
            archive.GetEntry("runtimes/linux-x64/lib/net9.0/ridlib.dll")!.Crc32,
            Is.Not.EqualTo(archive.GetEntry("runtimes/win-x64/lib/net9.0/ridlib.dll")!.Crc32),
            "the select on the runtime identifier produced different assemblies");

        Assert.That(DependencyGroups(Metadata(archive, "RulesDotnet.Tests.RidLib")), Is.EquivalentTo(new Dictionary<string, Dictionary<string, string>>
        {
            ["net9.0"] = new(),
        }));
    }

    [Test]
    public void ToolPackage()
    {
        using var archive = Open("tool_pack/RulesDotnet.Tests.Tool.0.1.0.nupkg");
        AssertWellFormed(archive, "RulesDotnet.Tests.Tool");

        Assert.That(Payload(archive), Is.EquivalentTo(new[]
        {
            "tools/net9.0/any/DotnetToolSettings.xml",
            "tools/net9.0/any/tool.dll",
            "tools/net9.0/any/tool.pdb",
            "tools/net9.0/any/tool.deps.json",
            "tools/net9.0/any/tool.runtimeconfig.json",
            "tools/net9.0/any/referenced.dll",
            "tools/net9.0/any/referenced.pdb",
        }));

        using var settingsStream = archive.GetEntry("tools/net9.0/any/DotnetToolSettings.xml")!.Open();
        var command = XDocument.Load(settingsStream).Root!.Element("Commands")!.Elements("Command").Single();
        Assert.That((string)command.Attribute("Name")!, Is.EqualTo("rdtool"));
        Assert.That((string)command.Attribute("EntryPoint")!, Is.EqualTo("tool.dll"));
        Assert.That((string)command.Attribute("Runner")!, Is.EqualTo("dotnet"));

        var metadata = Metadata(archive, "RulesDotnet.Tests.Tool");
        Assert.That(metadata.Elements().Single(element => element.Name.LocalName == "packageTypes").Elements().Single().Attribute("name")!.Value, Is.EqualTo("DotnetTool"));
        Assert.That(DependencyGroups(metadata), Is.EquivalentTo(new Dictionary<string, Dictionary<string, string>> { ["net9.0"] = new() }));
    }

    [Test]
    public void AnalyzerPackage()
    {
        using var archive = Open("generator_pack/RulesDotnet.Tests.Generator.1.0.0.nupkg");
        AssertWellFormed(archive, "RulesDotnet.Tests.Generator");

        // Nothing under lib/: the consumer hands these to the compiler. The
        // Roslyn assemblies the generator compiles against are the compiler's
        // own, so they are not in the package.
        Assert.That(Payload(archive), Is.EquivalentTo(new[]
        {
            "analyzers/dotnet/cs/generator.dll",
            "analyzers/dotnet/cs/generator.pdb",
            "analyzers/dotnet/cs/generator_support.dll",
        }));

        var metadata = Metadata(archive, "RulesDotnet.Tests.Generator");
        Assert.That(Element(metadata, "developmentDependency"), Is.EqualTo("true"));
        Assert.That(DependencyGroups(metadata), Is.EquivalentTo(new Dictionary<string, Dictionary<string, string>>
        {
            [".NETStandard2.0"] = new(),
        }));
    }

    [Test]
    public void RazorClassLibraryPackage()
    {
        using var archive = Open("components_pack/RulesDotnet.Tests.Components.1.0.0.nupkg");
        AssertWellFormed(archive, "RulesDotnet.Tests.Components");

        Assert.That(Payload(archive), Is.EquivalentTo(new[]
        {
            "lib/net10.0/RulesDotnet.Tests.Components.dll",
            "lib/net10.0/RulesDotnet.Tests.Components.xml",
            "ref/net10.0/RulesDotnet.Tests.Components.dll",
            "build/Microsoft.AspNetCore.StaticWebAssets.props",
            "staticwebassets/RulesDotnet.Tests.Components.bundle.scp.css",
            "staticwebassets/css/widget.css",
            "staticwebassets/widget.js",
        }));

        // Served under the package id, wherever the consuming project reads the
        // files from: the props names every one of them.
        using var propsStream = archive.GetEntry("build/Microsoft.AspNetCore.StaticWebAssets.props")!.Open();
        var assets = XDocument.Load(propsStream).Root!.Elements().Single().Elements().ToList();
        Assert.That(
            assets.Select(asset => asset.Element("RelativePath")!.Value),
            Is.EquivalentTo(new[] { "RulesDotnet.Tests.Components.bundle.scp.css", "css/widget.css", "widget.js" }));
        foreach (var asset in assets)
        {
            Assert.That(asset.Element("BasePath")!.Value, Is.EqualTo("_content/RulesDotnet.Tests.Components"));
            Assert.That(asset.Element("SourceId")!.Value, Is.EqualTo("RulesDotnet.Tests.Components"));
            Assert.That(asset.Element("SourceType")!.Value, Is.EqualTo("Package"));
        }

        // A Razor class library compiles against the shared framework, so its
        // consumers have to reference it too.
        var references = Metadata(archive, "RulesDotnet.Tests.Components")
            .Elements().Single(element => element.Name.LocalName == "frameworkReferences")
            .Elements().Single();
        Assert.That((string)references.Attribute("targetFramework")!, Is.EqualTo("net10.0"));
        Assert.That((string)references.Elements().Single().Attribute("name")!, Is.EqualTo("Microsoft.AspNetCore.App"));
    }

    [Test]
    public void FSharpPackage()
    {
        using var archive = Open("fs_pack/RulesDotnet.Tests.FsLib.2.0.0.nupkg");
        AssertWellFormed(archive, "RulesDotnet.Tests.FsLib");

        Assert.That(Payload(archive), Is.EquivalentTo(new[]
        {
            "lib/netstandard2.0/fslib.dll", "lib/netstandard2.0/fslib.xml", "ref/netstandard2.0/fslib.dll",
            "lib/net9.0/fslib.dll", "lib/net9.0/fslib.xml", "ref/net9.0/fslib.dll",
        }));

        var groups = DependencyGroups(Metadata(archive, "RulesDotnet.Tests.FsLib"));
        Assert.That(groups.Keys, Is.EquivalentTo(new[] { ".NETStandard2.0", "net9.0" }));
        foreach (var group in groups.Values)
        {
            Assert.That(group.Keys, Is.EquivalentTo(new[] { "FSharp.Core" }));
        }
    }
}
