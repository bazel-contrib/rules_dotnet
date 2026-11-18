module Greeter

open System
open System.Globalization
open System.IO
open System.Reflection
open System.Resources
open System.Text

let private self = Assembly.GetExecutingAssembly()

let private get (baseName: string) (key: string) (culture: string) =
    match ResourceManager(baseName, self).GetString(key, CultureInfo.GetCultureInfo(culture)) with
    | null -> "<null>"
    | s -> s

[<EntryPoint>]
let main argv =
    // Force '\n' so the output matches on every platform.
    use writer = new StreamWriter(argv.[0])
    writer.NewLine <- "\n"

    // Named after `root_namespace`, not the assembly name.
    writer.WriteLine("neutral: " + get "ResxFsTest.Strings" "Hello" "")
    writer.WriteLine("fr: " + get "ResxFsTest.Strings" "Hello" "fr")

    // Cultures with a script, a numeric region or three parts.
    writer.WriteLine("sr-Latn-RS: " + get "ResxFsTest.Strings" "Hello" "sr-Latn-RS")
    writer.WriteLine("es-419: " + get "ResxFsTest.Strings" "Hello" "es-419")

    // `api` is no culture, so Strings.api.resx is a resource of its own.
    writer.WriteLine("api: " + get "ResxFsTest.Strings.api" "Hello" "")

    // A directory becomes an identifier: My-Res/9lives is My_Res._9lives.
    writer.WriteLine("directory: " + get "ResxFsTest.My_Res._9lives.Thing" "Hello" "")

    // `ResXFileRef` entries pull in the file beside the .resx.
    let fileRef = ResourceManager("ResxFsTest.fileref.FileRef", self)
    writer.WriteLine("file ref string: " + fileRef.GetString("Notes").Trim())
    writer.WriteLine("file ref bytes: " + Encoding.UTF8.GetString(fileRef.GetObject("Blob") :?> byte[]).Trim())

    // `logical_names` of a resx_resource, which the culture takes too.
    writer.WriteLine("messages neutral: " + get "MyApp.Messages" "Greeting" "")
    writer.WriteLine("messages fr: " + get "MyApp.Messages" "Greeting" "fr")

    // `cultures` of a resx_resource makes Legacy.fr.resx neutral.
    writer.WriteLine("legacy: " + get "ResxFsTest.Legacy.fr" "Hello" "")

    self.GetManifestResourceNames()
    |> Array.filter (fun name -> name.EndsWith(".resources") || name.EndsWith(".txt"))
    |> Array.sortWith (fun a b -> String.CompareOrdinal(a, b))
    |> Array.iter (fun name -> writer.WriteLine("embedded: " + name))

    0
