module BasicFsharp.Tests

open NUnit.Framework
open BasicFsharp

[<TestFixture>]
type LibTests() =
    [<Test>]
    member _.GetMessage_ReturnsExpectedMessage() =
        Assert.AreEqual("Hello from .NET 10.0 F# library!", Lib.getMessage())
