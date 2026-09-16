using NUnit.Framework;
using System.Linq;
using AB;
using AC;
using D;

[TestFixture]
public sealed class LibTests
{
    [Test]
    public void ShouldResolveDToNet80()
    {
        // Since A directly depends on D and A targets net8.0 we should get the net8.0 version of D
        Assert.AreEqual("net8.0", AB.AB.GetLibDFramework(), "Wrong framework from AB");
        Assert.AreEqual("net8.0", AC.AC.GetLibDFramework(), "Wrong framework from AC");
        Assert.AreEqual("net8.0", D.D.DFramework(), "Wrong framework from D");
    }
}

