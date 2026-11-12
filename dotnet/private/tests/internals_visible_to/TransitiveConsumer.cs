using NUnit.Framework;

namespace Probe;

[TestFixture]
public class TransitiveConsumerTest
{
    [Test]
    public void SeesTheInternalsOfSecretsThroughRelay()
    {
        Assert.That(Secrets.Secret, Is.EqualTo(42));
    }
}
