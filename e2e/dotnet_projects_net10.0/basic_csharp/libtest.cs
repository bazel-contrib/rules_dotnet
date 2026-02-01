using BasicCsharp;
using NUnit.Framework;

[TestFixture]
public sealed class LibTests
{
    [Test]
    public void GetMessage_ReturnsExpectedMessage()
    {
        Assert.AreEqual("Hello from .NET 10.0 library!", Lib.GetMessage());
    }
}
