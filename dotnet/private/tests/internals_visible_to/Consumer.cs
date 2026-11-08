using NUnit.Framework;

namespace Probe;

[TestFixture]
public class ConsumerTest
{
    [Test]
    public void SeesTheInternalsOfSecrets()
    {
        Assert.That(Secrets.Secret + Chain.Value, Is.EqualTo(43));
        Assert.That(ExportedSecrets.ExportedSecret, Is.EqualTo(10));
    }
}
