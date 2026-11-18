using System;
using System.IO;
using NUnit.Framework;

// Verifies content_files are copied next to the assembly, resolvable via AppContext.BaseDirectory.
[TestFixture]
public sealed class ContentFilesTest
{
    [Test]
    public void ShouldCopyTopLevelContentFileNextToAssembly()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "content", "settings.json");
        Assert.That(File.Exists(path), Is.True, $"Expected content file at {path}");
    }

    [Test]
    public void ShouldPreserveNestedContentFileDirectoryStructure()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "content", "nested", "data.txt");
        Assert.That(File.Exists(path), Is.True, $"Expected nested content file at {path}");
        Assert.That(File.ReadAllText(path).Trim(), Is.EqualTo("nested content"));
    }
}
