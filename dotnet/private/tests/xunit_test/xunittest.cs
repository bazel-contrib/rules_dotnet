using Xunit;

namespace XunitSmoke;

public sealed class BasicTests
{
    [Fact]
    public void Truth()
    {
        Assert.True(true);
    }
}
