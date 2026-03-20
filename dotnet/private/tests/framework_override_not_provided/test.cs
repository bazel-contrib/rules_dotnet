using Lib;
using NUnit.Framework;

[TestFixture]
public sealed class LibTests
{
    [Test]
    public void LibCompilesAndValueIsNotNull()
    {
        Assert.IsNotNull(Program.GetValue());
    }
}

