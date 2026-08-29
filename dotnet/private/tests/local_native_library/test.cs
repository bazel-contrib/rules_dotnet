using NUnit.Framework;
using System.Runtime.InteropServices;
using System;

[TestFixture]
public sealed class LibTests
{
    [Test]
    public void CallNative()
    {
        Assert.AreEqual(42, return42());
    }

    [DllImport("native")]
    private static extern int return42();
}
