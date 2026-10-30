using System;
using Lib;
using NUnit.Framework;

[TestFixture]
public sealed class LibTests
{
    [Test]
    public void RunsOnNet11()
    {
        Assert.AreEqual(11, Environment.Version.Major);
        Assert.AreEqual("net11.0", Library.Framework);
    }

    [Test]
    public void ChoosesNearestCompatibleDependency()
    {
        Assert.AreEqual("net10.0", Library.DependencyFramework);
    }

    [Test]
    public void CanSeeInternals()
    {
        Assert.AreEqual(42, Library.NonPublicMethod());
    }
}
