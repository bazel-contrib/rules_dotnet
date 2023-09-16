using NUnit.Framework;
using System.Linq;
using AB;
using AC;

[TestFixture]
public sealed class LibTests
{
    [Test]
    public void ShouldResolveCToNetStandard21()
    {
        // Since A only depends on D transitively we should get the net6.0 version of D
        // because AC only supports net6.0
        Assert.AreEqual("net6.0", AB.AB.GetLibDFramework(), "Wrong framework from AB");
        Assert.AreEqual("net6.0", AC.AC.GetLibDFramework(), "Wrong framework from AC");
    }
}

