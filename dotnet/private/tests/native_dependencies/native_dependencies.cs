using NUnit.Framework;
using RocksDbSharp;

[TestFixture]
public sealed class Tests
{
    [Test]
    public void TestShouldRunUsingNativeDependencies()
    {
        var options = new DbOptions().SetCreateIfMissing(true);
    }
}

