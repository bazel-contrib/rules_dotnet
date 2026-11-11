using NUnit.Framework;

namespace Probe;

[TestFixture]
public class OutsiderTest
{
    [Test]
    public void CompilesAgainstThePublicReferenceAssembly()
    {
        Assert.That(new Secrets(), Is.Not.Null);
    }
}
