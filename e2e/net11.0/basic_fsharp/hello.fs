open System
open Lib

[<EntryPoint>]
let main args =
    printfn $"F# {Library.framework} -> {Library.dependencyFramework}; runtime={Environment.Version.Major}"

    if Environment.Version.Major <> 11 || Library.dependencyFramework <> "net10.0" || Library.unexpectedDefines then
        1
    elif args.Length = 0 then
        0
    else
        int args.[0]
