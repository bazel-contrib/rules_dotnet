using BasicCsharp;
using NUnit.Framework;

[TestFixture]
public sealed class LibTests
{
    [Test]
    public void GetMessage_ReturnsExpectedMessage()
    {
        Assert.AreEqual("Hello from .NET 8.0 library!", Lib.GetMessage());
    }
}
