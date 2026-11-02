module Tests

open Lib
open NUnit.Framework
open System.Linq

[<TestFixture>]
type LibTests () =
    [<Test>]
    member this.SomeTest() =
        CollectionAssert.AreEqual([ 0; 1; 1; 2; 3; 5; 8; 13; 21 ], Stuff.fibonacci |> Seq.take 9)
    
    [<Test>]
    member this.CanSeeInternals() =
        Assert.AreEqual(42, Stuff.nonPublicMethod())
