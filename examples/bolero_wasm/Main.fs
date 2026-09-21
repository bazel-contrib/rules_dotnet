module BoleroWasm.Main

open Elmish
open Microsoft.AspNetCore.Components.WebAssembly.Hosting
open Bolero
open Bolero.Html

type Model = { count: int }

type Message =
    | Increment
    | Decrement

let initModel = { count = 0 }

let update message model =
    match message with
    | Increment -> { model with count = model.count + 1 }
    | Decrement -> { model with count = model.count - 1 }

let view model dispatch =
    div {
        h1 { "Bolero on Bazel" }
        p { $"Count: {model.count}" }
        button {
            on.click (fun _ -> dispatch Decrement)
            "-"
        }
        button {
            on.click (fun _ -> dispatch Increment)
            "+"
        }
    }

/// Bolero writes components in F# rather than Razor, which is what makes this
/// a useful check: the WebAssembly publish has to work from an F# binary.
type Counter() =
    inherit ProgramComponent<Model, Message>()

    override _.Program = Program.mkSimple (fun _ -> initModel) update view

[<EntryPoint>]
let main args =
    let builder = WebAssemblyHostBuilder.CreateDefault(args)
    builder.RootComponents.Add<Counter>("#main")
    builder.Build().RunAsync() |> ignore
    0
