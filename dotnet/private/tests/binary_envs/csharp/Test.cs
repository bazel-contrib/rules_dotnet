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
        Assert.AreEqual("external/_main~dotnet~dotnet_x86_64-unknown-linux-gnu/dotnet", Environment.GetEnvironmentVariable("TEMPLATED_VARIABLE"));
    }
}

