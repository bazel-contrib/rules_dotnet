using Calculator;
using Xunit;

namespace CalculatorXunitTests;

public sealed class ArithmeticXunitTests
{
    [Fact]
    public void ResultSerializesToJson()
    {
        Assert.Equal("{\"result\":5}", Arithmetic.ResultToJson(Arithmetic.Add(2, 3)));
    }
}
