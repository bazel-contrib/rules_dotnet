using System;
using System.IO;
using System.Linq;
using System.Reflection.Metadata;
using System.Reflection.PortableExecutable;
using System.Resources;
using Bazel;
using NUnit.Framework;

namespace XamlTests;

// Checks what the XAML compilation embeds without running WPF, so it runs on
// any host.
[TestFixture]
public sealed class XamlResourceTests
{
    private const string Package = "rules_dotnet/dotnet/private/tests/windowsdesktop/xaml";

    private static readonly Runfiles Runfiles = Runfiles.Create();

    // The `<assembly>.g.resources` WPF loads compiled XAML and its resources from.
    private static string[] GeneratedResources(string assembly, string name)
    {
        using var stream = File.OpenRead(Runfiles.Rlocation($"{Package}/{assembly}"));
        using var pe = new PEReader(stream);
        var metadata = pe.GetMetadataReader();

        var resource = metadata.ManifestResources
            .Select(metadata.GetManifestResource)
            .Single(manifest => metadata.GetString(manifest.Name) == name);

        var directory = pe.PEHeaders.CorHeader!.ResourcesDirectory;
        var section = pe.GetSectionData(directory.RelativeVirtualAddress).GetReader();
        section.Offset = (int)resource.Offset;
        var length = section.ReadInt32();
        var bytes = section.ReadBytes(length);

        using var reader = new ResourceReader(new MemoryStream(bytes));
        return reader.Cast<System.Collections.DictionaryEntry>().Select(entry => (string)entry.Key).OrderBy(key => key).ToArray();
    }

    [Test]
    public void TheAppEmbedsItsBamlAndResources()
    {
        Assert.That(
            GeneratedResources("xaml_app/net10.0-windows/xaml_app.dll", "xaml_app.g.resources"),
            Is.EqualTo(new[]
            {
                "app.baml",
                "assets/generated.txt",
                "assets/greeting.txt",
                "themes/generated.baml",
                "views/mainwindow.baml",
            }));
    }

    [Test]
    public void ALibraryWithoutXamlEmbedsItsResources()
    {
        Assert.That(
            GeneratedResources("icons/net10.0-windows/XamlIcons.dll", "XamlIcons.g.resources"),
            Is.EqualTo(new[] { "icons/icons/app.txt" }));
    }

    [Test]
    public void ALibraryEmbedsItsBaml()
    {
        Assert.That(
            GeneratedResources("controls/net10.0-windows/XamlControls.dll", "XamlControls.g.resources"),
            Is.EqualTo(new[] { "controls/badge.baml" }));
    }

    [Test]
    public void ANetFrameworkLibraryEmbedsItsBaml()
    {
        Assert.That(
            GeneratedResources("controls_net48/net48/XamlControlsNet48.dll", "XamlControlsNet48.g.resources"),
            Is.EqualTo(new[] { "controls/badge.baml" }));
    }
}
