using System;
using System.IO;
using NUnit.Framework;

// Verifies dotnet_content_files remaps destinations (strip_prefix + prefix) next to the assembly.
[TestFixture]
public sealed class ContentFilesRuleTest
{
    [Test]
    public void ShouldStripAndPrefixContentFileDestination()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "config", "settings.json");
        Assert.That(File.Exists(path), Is.True, $"Expected remapped content file at {path}");
    }

    [Test]
    public void ShouldPreserveNestedStructureUnderNewPrefix()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "config", "nested", "data.txt");
        Assert.That(File.Exists(path), Is.True, $"Expected remapped nested content file at {path}");
        Assert.That(File.ReadAllText(path).Trim(), Is.EqualTo("nested content"));
    }
}
