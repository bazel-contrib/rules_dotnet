using Example;
using NUnit.Framework;

[TestFixture]
public sealed class GreeterTest
{
    [Test]
    public void GreetsEveryoneOnce()
    {
        Assert.AreEqual("¡Hello, Ada and Grace!", Greeter.Greet("Grace", "Ada", "Grace"));
    }
}
