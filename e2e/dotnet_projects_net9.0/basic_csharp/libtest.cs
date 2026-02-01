using BasicCsharp;
using NUnit.Framework;

[TestFixture]
public sealed class LibTests
{
    [Test]
    public void GetMessage_ReturnsExpectedMessage()
    {
        Assert.AreEqual("Hello from library!", Lib.GetMessage());
    }
}
