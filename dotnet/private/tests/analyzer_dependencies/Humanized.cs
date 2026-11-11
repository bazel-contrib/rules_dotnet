using NUnit.Framework;

namespace AnalyzerDependencies;

[TestFixture]
public class HumanizedTest
{
    [Test]
    public void TheGeneratorRanWithHumanizer()
    {
        Assert.That(Humanized.Value, Is.EqualTo("Pascal case input"));
    }
}
