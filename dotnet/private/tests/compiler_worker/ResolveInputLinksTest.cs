using System;
using System.Collections.Generic;
using System.IO;
using NUnit.Framework;

namespace RulesDotnet.Tests;

[TestFixture]
public class ResolveInputLinksTest
{
    private string _directory = "";
    private string _target = "";
    private string _link = "";

    [SetUp]
    public void StageALinkTheWayASandboxedWorkerIsHandedOne()
    {
        _directory = Directory.CreateTempSubdirectory("resolve_input_links").FullName;
        _target = Path.Combine(_directory, "external", "Humanizer.dll");
        _link = Path.Combine(_directory, "bazel-workers", "worker-1", "Humanizer.dll");

        Directory.CreateDirectory(Path.GetDirectoryName(_target)!);
        Directory.CreateDirectory(Path.GetDirectoryName(_link)!);
        File.WriteAllText(_target, "");

        try
        {
            File.CreateSymbolicLink(_link, _target);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Assert.Ignore("Symlinks cannot be created here: " + e.Message);
        }
    }

    [TearDown]
    public void RemoveTheLink() => Directory.Delete(_directory, recursive: true);

    private static List<string> Resolve(string argument) =>
        Worker.ResolveInputLinks(new List<string> { argument }, "-r:", "/analyzer:");

    [Test]
    public void AQuotedReferenceIsPointedAtItsTarget() =>
        Assert.That(Resolve($"-r:\"{_link}\""), Is.EqualTo(new[] { $"-r:\"{_target}\"" }));

    [Test]
    public void AQuotedAnalyzerIsPointedAtItsTarget() =>
        Assert.That(Resolve($"/analyzer:\"{_link}\""), Is.EqualTo(new[] { $"/analyzer:\"{_target}\"" }));

    [Test]
    public void AnUnquotedReferenceIsPointedAtItsTarget() =>
        Assert.That(Resolve($"-r:{_link}"), Is.EqualTo(new[] { $"-r:{_target}" }));

    [Test]
    public void AnArgumentOfAnotherKindIsLeftAlone() =>
        Assert.That(Resolve($"\"{_link}\""), Is.EqualTo(new[] { $"\"{_link}\"" }));

    [Test]
    public void AFileThatIsNoLinkIsLeftAlone() =>
        Assert.That(Resolve($"-r:\"{_target}\""), Is.EqualTo(new[] { $"-r:\"{_target}\"" }));

    [Test]
    public void AMissingFileIsLeftForTheCompilerToReport()
    {
        var missing = Path.Combine(_directory, "missing.dll");
        Assert.That(Resolve($"-r:\"{missing}\""), Is.EqualTo(new[] { $"-r:\"{missing}\"" }));
    }
}
