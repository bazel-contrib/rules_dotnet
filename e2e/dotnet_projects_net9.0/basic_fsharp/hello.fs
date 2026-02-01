open BasicFsharp

[<EntryPoint>]
let main args =
    printfn "%s" (Lib.getMessage())
    printfn "Hello from fsproj auto-integration!"
    0
