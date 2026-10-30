using Enabled;
using NUnit.Framework;

namespace Enabled.Tests;

[TestFixture]
public sealed class EnabledTests
{
    [Test]
    public void ImplicitUsingsCompileLibraryAndTest()
    {
        var expected = new List<int> { 2, 3 };
        CollectionAssert.AreEqual(expected, Values.All());
        Assert.AreEqual(5, Values.SumAsync().Result);
    }
}
