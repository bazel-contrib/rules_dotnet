using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace ImplicitUsings;

[TestClass]
public sealed class MSTestTests
{
    [TestMethod]
    public void ListComesFromImplicitUsings()
    {
        Assert.AreEqual(2, new List<int> { 1, 2 }.Count);
    }
}
