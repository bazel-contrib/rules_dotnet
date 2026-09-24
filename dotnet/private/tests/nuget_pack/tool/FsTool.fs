module FsTool

open System
open System.Reflection

[<EntryPoint>]
let main args =
    let version =
        Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>().InformationalVersion
    printfn "Hello %s from %s" (String.Join(" ", args)) version
    0
