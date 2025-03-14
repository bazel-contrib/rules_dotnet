module Program

let private assertEqual<'T when 'T : equality> (expected: 'T) (actual: 'T) =
    if not (expected.Equals(actual)) then
        raise (System.Exception(sprintf "Expected %A but got %A" expected actual))

let private assertContains<'T when 'T : equality> (haystack: seq<'T>) (needle: 'T) =
    if not (Seq.contains needle haystack) then
        let itemsStr = haystack |> Seq.map (fun x -> x.ToString()) |> String.concat ", "
        raise (System.Exception(sprintf "Expected %A to be in [%s]" needle itemsStr))

[<EntryPoint>]
let main _ =
    let assembly = System.Reflection.Assembly.GetExecutingAssembly()
    let resources = assembly.GetManifestResourceNames()
    assertContains resources "EmbeddedResource.Library.nested.path.to.resource.txt"

    use stream = assembly.GetManifestResourceStream(
        "EmbeddedResource.Library.nested.path.to.resource.txt"
    )
    use reader = new System.IO.StreamReader(stream)
    let content = reader.ReadToEnd().Trim()
    assertEqual "Well hello friends! :^)" content
    0
