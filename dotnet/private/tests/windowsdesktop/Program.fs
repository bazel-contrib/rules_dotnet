module Program

open System.IO
open System.Reflection.PortableExecutable

[<EntryPoint>]
let main _ =
    use stream = File.OpenRead(typeof<obj>.Assembly.Location)
    use peReader = new PEReader(stream)
    0
