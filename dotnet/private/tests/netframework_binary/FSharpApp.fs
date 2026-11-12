module FSharpApp

[<EntryPoint>]
let main _ =
    let xs = [ 1; 2; 3 ] |> List.map ((*) 2)
    if List.sum xs = 12 then 0 else 1
