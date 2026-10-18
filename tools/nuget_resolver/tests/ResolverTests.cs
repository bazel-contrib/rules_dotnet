using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using NUnit.Framework;
using NuGetResolver;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class ResolverTests
{
    private static ResolveSpec Spec(string feed, string[] frameworks, params (string Id, string Range)[] packages)
        => new(packages.Select(p => new PackageRequest(p.Id, p.Range)).ToList(), frameworks, new[] { feed });

    [Test]
    public async Task MinimumVersionResolvesToLowestApplicable()
    {
        var feed = FeedFixture.Create(
            ("Widget.Core", "1.0.0", []),
            ("Widget.Core", "1.2.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "1.0.0")), null, default);

        var packages = result["net8.0"];
        Assert.That(packages.Select(p => p.Id), Is.EqualTo(new[] { "Widget.Core" }));
        Assert.That(packages[0].Version, Is.EqualTo("1.0.0"), "a plain version is a minimum; lowest applicable wins");
    }

    [Test]
    public async Task ExactVersionResolvesExactly()
    {
        var feed = FeedFixture.Create(
            ("Widget.Core", "1.0.0", []),
            ("Widget.Core", "1.2.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "[1.2.0]")), null, default);

        Assert.That(result["net8.0"][0].Version, Is.EqualTo("1.2.0"));
    }

    [Test]
    public async Task FloatingVersionResolvesToHighestMatch()
    {
        var feed = FeedFixture.Create(
            ("Widget.Core", "4.0.1", []),
            ("Widget.Core", "4.0.3", []),
            ("Widget.Core", "4.1.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "4.0.*")), null, default);

        Assert.That(result["net8.0"][0].Version, Is.EqualTo("4.0.3"));
    }

    [Test]
    public async Task TransitiveDeepChainIsFullyResolved()
    {
        var feed = FeedFixture.Create(
            ("App.A", "1.0.0", [("Lib.B", "1.0.0")]),
            ("Lib.B", "1.0.0", [("Lib.C", "1.0.0")]),
            ("Lib.C", "1.0.0", [("Lib.D", "1.0.0")]),
            ("Lib.D", "1.0.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("App.A", "1.0.0")), null, default);

        Assert.That(
            result["net8.0"].Select(p => p.Id),
            Is.EqualTo(new[] { "App.A", "Lib.B", "Lib.C", "Lib.D" }));
    }

    [Test]
    public async Task DiamondUnifiesToTheHigherMinimum()
    {
        var feed = FeedFixture.Create(
            ("App.A", "1.0.0", [("Widget.Core", "1.0.0")]),
            ("App.B", "1.0.0", [("Widget.Core", "1.1.0")]),
            ("Widget.Core", "1.0.0", []),
            ("Widget.Core", "1.1.0", []));

        var result = await Resolver.ResolveAsync(
            Spec(feed, ["net8.0"], ("App.A", "1.0.0"), ("App.B", "1.0.0")), null, default);

        var packages = result["net8.0"];
        Assert.That(packages.Select(p => p.Id), Is.EqualTo(new[] { "App.A", "App.B", "Widget.Core" }));
        Assert.That(
            packages.Single(p => p.Id == "Widget.Core").Version,
            Is.EqualTo("1.1.0"),
            "two paths to Widget.Core unify to one version: the highest minimum");
    }

    [Test]
    public async Task EveryFrameworkIsResolvedSeparately()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0", "net9.0"], ("Widget.Core", "1.0.0")), null, default);

        Assert.That(result.Keys.OrderBy(k => k, StringComparer.Ordinal), Is.EqualTo(new[] { "net8.0", "net9.0" }));
        Assert.That(result["net8.0"][0].Id, Is.EqualTo("Widget.Core"));
        Assert.That(result["net9.0"][0].Id, Is.EqualTo("Widget.Core"));
    }

    [Test]
    public async Task Sha512MatchesTheDownloadedBytes()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "1.0.0")), null, default);

        Assert.That(result["net8.0"][0].Sha512, Is.EqualTo(FeedFixture.ExpectedSha512(feed, "Widget.Core", "1.0.0")));
    }

    [Test]
    public async Task LowercaseFlatFeedRecordsTheLowercaseUrl()
    {
        var feed = FeedFixture.CreateLowercase(("Mixed.Case", "1.0.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Mixed.Case", "1.0.0")), null, default);

        var url = result["net8.0"][0].Urls[0];
        Assert.That(url, Does.EndWith("mixed.case.1.0.0.nupkg"));
        Assert.That(File.Exists(new Uri(url).LocalPath), Is.True, "the recorded URL must be a real file");
    }

    [Test]
    public async Task NearerExactVersionWinsOverFartherMinimum()
    {
        var feed = FeedFixture.Create(
            ("App.A", "1.0.0", [("Widget.Core", "1.0.0")]),
            ("Widget.Core", "1.0.0", []),
            ("Widget.Core", "2.0.0", []));

        var result = await Resolver.ResolveAsync(
            Spec(feed, ["net8.0"], ("App.A", "1.0.0"), ("Widget.Core", "[2.0.0]")), null, default);

        var packages = result["net8.0"];
        Assert.That(packages.Select(p => p.Id), Is.EqualTo(new[] { "App.A", "Widget.Core" }));
        Assert.That(packages.Single(p => p.Id == "Widget.Core").Version, Is.EqualTo("2.0.0"));
    }

    [Test]
    public void UnknownPackageFails()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));

        var ex = Assert.ThrowsAsync<ResolveException>(
            () => Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Ghost.Package", "1.0.0")), null, default));
        Assert.That(ex!.Message, Does.Contain("Ghost.Package"));
    }

    [Test]
    public void UnsatisfiableRangeFails()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));

        var ex = Assert.ThrowsAsync<ResolveException>(
            () => Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "[2.0.0]")), null, default));
        Assert.That(ex!.Message, Does.Contain("Widget.Core"));
    }
}
