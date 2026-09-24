using System;
using System.Linq;
using System.Reflection;
using NUnit.Framework;
using RulesDotnet.Tests.NuGetPack;

[TestFixture]
public sealed class VersionTest
{
    private static T Attribute<T>(Assembly assembly) where T : Attribute =>
        assembly.GetCustomAttributes<T>().Single();

    [Test]
    public void VersionAttributeGeneratesAssemblyAttributes()
    {
        var assembly = typeof(Lib).Assembly;
        Assert.AreEqual(new Version(1, 2, 3, 0), assembly.GetName().Version);
        Assert.AreEqual("1.2.3.0", Attribute<AssemblyFileVersionAttribute>(assembly).Version);
        Assert.AreEqual("1.2.3-beta.1+abc", Attribute<AssemblyInformationalVersionAttribute>(assembly).InformationalVersion);
    }

    [Test]
    public void NoVersionGeneratesNothing()
    {
        var assembly = typeof(Bundled).Assembly;
        Assert.AreEqual(new Version(0, 0, 0, 0), assembly.GetName().Version);
        Assert.IsEmpty(assembly.GetCustomAttributes<AssemblyFileVersionAttribute>());
        Assert.IsEmpty(assembly.GetCustomAttributes<AssemblyInformationalVersionAttribute>());
    }

    [Test]
    public void LibraryStillWorks()
    {
        Assert.AreEqual("[Hello, WORLD]", Lib.Greet("world"));
    }
}
