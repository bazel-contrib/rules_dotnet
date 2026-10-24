using NUnit.Framework;

namespace ImplicitUsings;

[TestFixture]
public sealed class NUnitTests
{
    [Test]
    public void ListComesFromImplicitUsings()
    {
        Assert.AreEqual(2, new List<int> { 1, 2 }.Count);
    }
}
