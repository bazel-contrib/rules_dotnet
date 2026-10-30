module Tests

open System
open Lib
open NUnit.Framework

[<TestFixture>]
type LibTests() =
    [<Test>]
    member _.RunsOnNet11() =
        Assert.AreEqual(11, Environment.Version.Major)
        Assert.AreEqual("net11.0", Library.framework)
        Assert.IsFalse(Library.unexpectedDefines)

    [<Test>]
    member _.ChoosesNearestCompatibleDependency() =
        Assert.AreEqual("net10.0", Library.dependencyFramework)

    [<Test>]
    member _.CanSeeInternals() =
        Assert.AreEqual(42, Library.nonPublicMethod())
