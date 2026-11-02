open System
open System.Linq
open Lib

[<EntryPoint>]
let main args =
    Console.WriteLine( "Hello, world!" );
    Console.WriteLine( "Some numbers for you:" );

    Stuff.fibonacci |> Seq.take 10 |> Seq.iter (fun i -> Console.WriteLine(i))

    0
