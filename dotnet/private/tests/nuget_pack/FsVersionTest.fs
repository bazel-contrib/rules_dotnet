module FsVersionTest

open System
open System.Reflection
open NUnit.Framework
open RulesDotnet.Tests.NuGetPack

let private attribute<'T when 'T :> Attribute> (assembly: Assembly) =
    assembly.GetCustomAttributes<'T>() |> Seq.exactlyOne

[<Test>]
let ``version attribute generates assembly attributes`` () =
    let assembly = typeof<FsLib.Marker>.Assembly
    Assert.AreEqual(Version(2, 0, 0, 0), assembly.GetName().Version)
    Assert.AreEqual("2.0.0.0", (attribute<AssemblyFileVersionAttribute> assembly).Version)
    Assert.AreEqual("2.0.0.0", (attribute<AssemblyInformationalVersionAttribute> assembly).InformationalVersion)

[<Test>]
let ``library still works`` () =
    Assert.AreEqual("Hello, world", FsLib.greet "world")
