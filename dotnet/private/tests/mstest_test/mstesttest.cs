using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MSTestSmoke;

[TestClass]
public sealed class BasicTests
{
    [TestMethod]
    public void Truth()
    {
        Assert.IsTrue(true);
    }
}
