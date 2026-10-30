using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using NUnit.Framework;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class ProgramTests
{
    private static string WriteSpec(string dir, string feed, params (string Id, string Range)[] packages)
    {
        var specPath = Path.Combine(dir, "spec.json");
        File.WriteAllText(specPath, JsonSerializer.Serialize(new
        {
            packages = packages.ToDictionary(p => p.Id, p => p.Range),
            frameworks = new[] { "net8.0" },
            sources = new[] { feed },
        }));
        return specPath;
    }

    [Test]
    public async Task ResolvesAndStampsTheInputHash()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));
        var specPath = WriteSpec(feed, feed, ("Widget.Core", "1.0.0"));
        var output = Path.Combine(feed, "nuget_resolve.json");

        var stderr = new StringWriter();
        var code = await NuGetResolver.Program.RunAsync(
            new[] { "--spec", specPath, "--input-hash", "737269301", "--output", output },
            new StringWriter(), stderr);

        Assert.That(code, Is.EqualTo(0), stderr.ToString());
        using var doc = JsonDocument.Parse(File.ReadAllText(output));
        Assert.That(doc.RootElement.GetProperty("version").GetInt32(), Is.EqualTo(1));
        Assert.That(doc.RootElement.GetProperty("inputHash").GetString(), Is.EqualTo("737269301"));
        var packages = doc.RootElement.GetProperty("frameworks").GetProperty("net8.0").GetProperty("packages");
        Assert.That(packages.GetArrayLength(), Is.EqualTo(1));
        Assert.That(packages[0].GetProperty("id").GetString(), Is.EqualTo("Widget.Core"));
        Assert.That(
            packages[0].GetProperty("sha512").GetString(),
            Is.EqualTo(FeedFixture.ExpectedSha512(feed, "Widget.Core", "1.0.0")));
        Assert.That(packages[0].GetProperty("urls")[0].GetString(), Does.StartWith("file://"));
    }

    [Test]
    public async Task UnknownPackageExitsNonZeroWithMessageOnStderr()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));
        var specPath = WriteSpec(feed, feed, ("Ghost.Package", "1.0.0"));

        var stderr = new StringWriter();
        var code = await NuGetResolver.Program.RunAsync(
            new[] { "--spec", specPath, "--input-hash", "0", "--output", Path.Combine(feed, "out.json") },
            new StringWriter(), stderr);

        Assert.That(code, Is.Not.EqualTo(0));
        Assert.That(stderr.ToString(), Does.Contain("Ghost.Package"));
    }

    [Test]
    public async Task MissingArgumentsExitNonZero()
    {
        var code = await NuGetResolver.Program.RunAsync(Array.Empty<string>(), new StringWriter(), new StringWriter());
        Assert.That(code, Is.Not.EqualTo(0));
    }
}
