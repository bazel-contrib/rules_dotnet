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

        // Whichever SDK is registered: the one whose runtime this runs on.
        Assert.That(
            Environment.GetEnvironmentVariable("TEMPLATED_VARIABLE"),
            Does.Match(sprintf @"^%d\.\d+\.\d+" Environment.Version.Major)
        )
