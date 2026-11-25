using System;
using System.IO;
using NUnit.Framework;

[TestFixture]
public sealed class ContentFilesOverrideTest
{
    [Test]
    public void BinaryContentFileSupersedesInheritedLibraryContentFile()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "content", "settings.json");
        Assert.That(File.Exists(path), Is.True, $"Expected overridden content file at {path}");
        Assert.That(File.ReadAllText(path), Does.Contain("top-level-content"));
    }

    [Test]
    public void NonOverriddenLibraryContentFileIsStillInherited()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "content", "nested", "data.txt");
        Assert.That(File.Exists(path), Is.True, $"Expected inherited content file at {path}");
        Assert.That(File.ReadAllText(path).Trim(), Is.EqualTo("nested content"));
    }

    [Test]
    public void NonTransitiveLibraryContentFileIsNotInherited()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "private", "nested", "data.txt");
        Assert.That(File.Exists(path), Is.False, $"Did not expect non-transitive content file at {path}");
    }
}
