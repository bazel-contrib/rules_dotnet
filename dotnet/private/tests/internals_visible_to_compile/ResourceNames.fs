module Program

open RefAssemblyResources

[<EntryPoint>]
let main _ =
    // Leaves out the resources fsc embeds of its own.
    let names =
        typeof<Marker>.Assembly.GetManifestResourceNames()
        |> Array.filter (fun name -> name.EndsWith ".txt")
        |> Array.sort

    let expected = [| "fsharp_lib.first.strings.txt"; "fsharp_lib.second.strings.txt" |]

    if names <> expected then
        eprintfn "Expected %A but got %A" expected names
        1
    else
        0
