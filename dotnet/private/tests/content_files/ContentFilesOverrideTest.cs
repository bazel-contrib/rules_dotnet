using System;
using System.IO;
using NUnit.Framework;

// Verifies a test's own content file replaces the one a library it depends on ships at the same path.
[TestFixture]
public sealed class ContentFilesOverrideTest
{
    [Test]
    public void ShouldStageOwnContentFileOverLibrarys()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "content", "settings.json");
        Assert.That(File.ReadAllText(path), Does.Contain("top-level-content"));
    }
}
