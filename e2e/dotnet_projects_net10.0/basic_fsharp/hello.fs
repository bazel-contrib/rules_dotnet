open BasicFsharp

[<EntryPoint>]
let main args =
    printfn "%s" (Lib.getMessage())
    printfn "Hello from fsproj auto-integration (.NET 10.0)!"
    0
