using Lib;
using NUnit.Framework;
using System.Linq;

[TestFixture]
public sealed class LibTests {
    [Test]
    public void SomeTest() {
        CollectionAssert.AreEqual(
            new [] { 0, 1, 1, 2, 3, 5, 8, 13, 21 },
            Stuff.Fibonacci( 0, 1 ).Take( 9 )
        );
    }
    
    [Test]
    public void CanSeeInternals() {
        Assert.AreEqual(42, Stuff.NonPublicMethod());
    }
}

