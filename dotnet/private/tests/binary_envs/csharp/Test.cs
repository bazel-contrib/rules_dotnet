using NUnit.Framework;
using System;

[TestFixture]
public sealed class Tests
{
    [Test]
    public void Test()
    {
        Assert.AreEqual("not_templated", Environment.GetEnvironmentVariable("NOT_TEMPLATED"));
        Assert.AreEqual("dotnet/private/tests/binary_envs/test.txt", Environment.GetEnvironmentVariable("TEMPLATED_FILE"));
        Assert.AreEqual("8.0.402", Environment.GetEnvironmentVariable("TEMPLATED_VARIABLE"));
    }
}

