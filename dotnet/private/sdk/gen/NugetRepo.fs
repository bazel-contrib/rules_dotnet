module NugetRepo

open System.Text
open System.IO
open Thoth.Json.Core

type NugetRepoTool =
    { name: string
      entrypoint: string
      runner: string }

type NugetRepoPackage =
    { name: string
      id: string
      version: string
      sha512: string
      sources: string seq
      netrc: string option
      dependencies: Map<string, string seq>
      targeting_pack_overrides: string seq
      framework_list: string seq
      tools: Map<string, NugetRepoTool seq> }

let private encodeStringSeq values =
    values
    |> Seq.map Encode.string
    |> Seq.toList
    |> Encode.list

let private encodeMap encodeValue values =
    values
    |> Map.toList
    |> List.map (fun (key, value) -> key, encodeValue value)
    |> Encode.object

let private encodeTool (tool: NugetRepoTool) =
    Encode.object [
        yield "name", Encode.string tool.name
        yield "entrypoint", Encode.string tool.entrypoint
        yield "runner", Encode.string tool.runner
    ]

let private encodePackage (package: NugetRepoPackage) =
    Encode.object [
        yield "name", Encode.string package.name
        yield "id", Encode.string package.id
        yield "version", Encode.string package.version
        yield "sha512", Encode.string package.sha512
        yield "sources", encodeStringSeq package.sources

        match package.netrc with
        | Some netrc -> yield "netrc", Encode.string netrc
        | None -> ()

        yield "dependencies", encodeMap encodeStringSeq package.dependencies
        yield "targeting_pack_overrides", encodeStringSeq package.targeting_pack_overrides
        yield "framework_list", encodeStringSeq package.framework_list

        yield
            "tools",
            package.tools
            |> encodeMap (fun tools ->
                tools
                |> Seq.map encodeTool
                |> Seq.toList
                |> Encode.list)
    ]

let private toGeneratedJson value =
    value
    |> Encode.toString 0
    // The replacements are so that the Bazel formatter does not have anything to format.
    |> fun json ->
        json
            .Replace("\":\"", "\": \"")
            .Replace("\",\"", "\", \"")
            .Replace("\":[", "\": [")
            .Replace("],", "], ")
            .Replace("\":{", "\": {")
            .Replace("},", "}, ")

let generateTarget (packages: NugetRepoPackage seq) (repoName: string) (repoPrefix: string) =
    let i = "    "
    let sb = new StringBuilder()
    sb.Append($"{i}nuget_repo(\n") |> ignore

    sb.Append($"{i}    name = \"{repoPrefix}{repoName}\",\n") |> ignore

    sb.Append($"{i}    packages = [\n") |> ignore

    for package in packages do
        sb.Append($"{i}        ") |> ignore

        sb.Append(package |> encodePackage |> toGeneratedJson)
        |> ignore

        sb.Append(",\n") |> ignore


    sb.Append($"{i}    ],\n") |> ignore
    sb.Append($"{i})\n") |> ignore

    sb.ToString()

let addFileHeaderContent (sb: StringBuilder) (fileName: string) =
    sb.Append($"\"GENERATED\"\n") |> ignore

    sb.Append($"\n") |> ignore

    sb.Append("load(\"@rules_dotnet//dotnet:defs.bzl\", \"nuget_repo\")") |> ignore

    sb.Append("\n") |> ignore
    sb.Append("\n") |> ignore
    sb.Append($"def {fileName}():") |> ignore
    sb.Append("\n") |> ignore
    sb.Append($"    \"{fileName}\"") |> ignore
    sb.Append("\n") |> ignore

let addExtensionFileContent (sb: StringBuilder) (repoName: string) (repoPrefix: string) =
    sb.Append($"\"Generated\"\n") |> ignore

    sb.Append($"\n") |> ignore

    sb.Append($"load(\":{repoPrefix}{repoName}.bzl\", _{repoName} = \"{repoName}\")")
    |> ignore

    sb.Append("\n") |> ignore
    sb.Append("\n") |> ignore
    sb.Append($"def _{repoName}_impl(module_ctx):") |> ignore
    sb.Append("\n") |> ignore
    sb.Append($"    _{repoName}()") |> ignore
    sb.Append("\n") |> ignore

    sb.Append($"    return module_ctx.extension_metadata(reproducible = True)")
    |> ignore

    sb.Append("\n") |> ignore
    sb.Append("\n") |> ignore
    sb.Append($"{repoName}_extension = module_extension(") |> ignore
    sb.Append("\n") |> ignore
    sb.Append($"    implementation = _{repoName}_impl,") |> ignore
    sb.Append("\n") |> ignore
    sb.Append(")") |> ignore
    sb.Append("\n") |> ignore


let addGroupToFileContent (sb: StringBuilder) (repoName: string) (repoPrefix: string) (packages: NugetRepoPackage seq) =

    sb.Append(generateTarget packages repoName repoPrefix) |> ignore

let generateBazelFiles (repoName: string) (packages: NugetRepoPackage seq) (outputFolder: string) (repoPrefix: string) =
    // Create the output directory if it does not exist
    Directory.CreateDirectory(outputFolder) |> ignore

    let sb = new StringBuilder()
    addFileHeaderContent sb (repoName)
    addGroupToFileContent sb repoName repoPrefix packages
    File.WriteAllText($"{outputFolder}/{repoPrefix}{repoName}.bzl", sb.ToString())

    let extensionSb = new StringBuilder()
    addExtensionFileContent extensionSb (repoName) repoPrefix
    File.WriteAllText($"{outputFolder}/{repoPrefix}{repoName}_extension.bzl", extensionSb.ToString())
