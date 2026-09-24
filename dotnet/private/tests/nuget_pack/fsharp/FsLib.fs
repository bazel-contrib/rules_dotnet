namespace RulesDotnet.Tests.NuGetPack

/// The F# library that gets packed.
module FsLib =
    /// A type to find the assembly by.
    type Marker =
        class
        end

    /// Greets.
    let greet (name: string) = sprintf "Hello, %s" name
