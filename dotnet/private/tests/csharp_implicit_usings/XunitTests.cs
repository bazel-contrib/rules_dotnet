using Xunit;

namespace ImplicitUsings;

public sealed class XunitTests
{
    [Fact]
    public void ListComesFromImplicitUsings()
    {
        Assert.Equal(2, new List<int> { 1, 2 }.Count);
    }
}
