module BasicFsharp.Tests

open NUnit.Framework
open BasicFsharp

[<TestFixture>]
type LibTests() =
    [<Test>]
    member _.GetMessage_ReturnsExpectedMessage() =
        Assert.AreEqual("Hello from F# library!", Lib.getMessage())
