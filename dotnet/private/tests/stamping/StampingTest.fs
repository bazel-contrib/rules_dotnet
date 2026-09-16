open System
open System.Reflection

[<EntryPoint>]
let main _ =
    let expected = "1.2.3-beta.4+abcdef"
    let attribute = Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()
    let actual = if isNull attribute then null else attribute.InformationalVersion

    if actual = expected then
        0
    else
        eprintfn "Expected %s, got %s" expected (if isNull actual then "<null>" else actual)
        1