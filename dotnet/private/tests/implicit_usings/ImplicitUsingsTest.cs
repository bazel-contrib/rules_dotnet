[TestFixture]
public sealed class ImplicitUsingsTests
{
    [Test]
    public async Task UsesSdkAndCustomGlobalUsings()
    {
        List<string> items = DefaultSdkLibrary.Describe("child");
        Assert.That(items, Is.EqualTo(new List<string> { "root/child", "custom", "6" }));

        string greeting = await DefaultSdkLibrary.InternalGreetingAsync("Bazel");
        Assert.That(greeting, Is.EqualTo("Hello, Bazel!"));
    }
}
