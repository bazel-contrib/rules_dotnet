using Calculator;
using NUnit.Framework;

namespace Calculator.Tests;

[TestFixture]
public sealed class ArithmeticTests
{
    [Test]
    public void AddWorks()
    {
        Assert.AreEqual(4, Arithmetic.Add(2, 2));
    }
}
