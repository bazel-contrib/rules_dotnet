using CalculatorApp;
using NUnit.Framework;

namespace CalculatorApp.Tests;

[TestFixture]
public sealed class ProgramTests
{
    [Test]
    public void RunReturnsSerializedResult()
    {
        Assert.AreEqual("{\"result\":5}", Program.Run());
    }
}
