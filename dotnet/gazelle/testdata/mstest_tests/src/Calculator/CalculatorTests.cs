using Calculator;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Calculator.Tests;

[TestClass]
public sealed class ArithmeticTests
{
    [TestMethod]
    public void AddWorks()
    {
        Assert.AreEqual(4, Arithmetic.Add(2, 2));
    }
}
