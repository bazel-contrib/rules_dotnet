using App;
using NUnit.Framework;

namespace App.Tests;

[TestFixture]
public sealed class ProgramTests
{
    [Test]
    public void RunWorks()
    {
        Assert.AreEqual(0, Program.Run());
    }
}
