using NUnit.Framework;
using System.Linq;

namespace SourceGeneratorTest
{

    public static partial class TestGenerator
    {
        public static partial string HelloFrom(string name);
    }

    [TestFixture]
    public sealed class Test
    {
        [Test]
        public void LibCompilesAndValueIsSet()
        {
            Assert.AreEqual("Generator says: Hi from source generator", TestGenerator.HelloFrom("source generator"));
        }
    }
}


