open BasicFsharp

[<EntryPoint>]
let main args =
    printfn "%s" (Lib.getMessage())
    printfn "Hello from fsproj auto-integration (.NET 8.0)!"
    0
