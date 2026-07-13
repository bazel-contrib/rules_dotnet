module Greeter

open System.Globalization
open System.IO
open System.Reflection
open System.Resources

let private strings =
    ResourceManager("ResxFsTest.Strings", Assembly.GetExecutingAssembly())

// This resource uses an explicit `logical_names` override, so its manifest name is
// independent of the `.resx` file path and the assembly's root namespace.
let private messages =
    ResourceManager("MyApp.Messages", Assembly.GetExecutingAssembly())

let private get (rm: ResourceManager) (key: string) (culture: string) =
    match rm.GetString(key, CultureInfo.GetCultureInfo(culture)) with
    | null -> "<null>"
    | s -> s

[<EntryPoint>]
let main argv =
    // Force '\n' so the output matches on every platform.
    use writer = new StreamWriter(argv.[0])
    writer.NewLine <- "\n"
    writer.WriteLine("neutral: " + get strings "Hello" "")
    writer.WriteLine("fr: " + get strings "Hello" "fr")
    writer.WriteLine("messages neutral: " + get messages "Greeting" "")
    writer.WriteLine("messages fr: " + get messages "Greeting" "fr")
    0
