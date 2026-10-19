using Calculator;
using Xunit;

namespace Calculator.Tests;

public sealed class ArithmeticTests
{
    [Fact]
    public void AddWorks()
    {
        Assert.Equal(4, Arithmetic.Add(2, 2));
    }
}
