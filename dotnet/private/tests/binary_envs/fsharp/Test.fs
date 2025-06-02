module Tests

open NUnit.Framework
open System

[<TestFixture>]
type Tests() =
    [<Test>]
    member this.Test() =
        Assert.AreEqual("not_templated", Environment.GetEnvironmentVariable("NOT_TEMPLATED"))

        Assert.AreEqual(
            "dotnet/private/tests/binary_envs/test.txt",
            Environment.GetEnvironmentVariable("TEMPLATED_FILE")
        )

        Assert.AreEqual("9.0.300", Environment.GetEnvironmentVariable("TEMPLATED_VARIABLE"))
