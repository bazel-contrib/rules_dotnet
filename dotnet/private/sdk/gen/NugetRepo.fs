module NugetRepo

open System.Text
open System.IO
open System.Collections.Generic
open System.Text.Json
open System.Text.Json.Serialization
open System.Text.Encodings.Web

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
      dependencies: Dictionary<string, string seq>
      targeting_pack_overrides: string seq
      framework_list: string seq
      tools: Dictionary<string, NugetRepoTool seq> }

let generateTarget (packages: NugetRepoPackage seq) (repoName: string) (repoPrefix: string) =
    let jsonOptions = JsonSerializerOptions()
    jsonOptions.DefaultIgnoreCondition <- JsonIgnoreCondition.WhenWritingNull
    jsonOptions.Encoder <- JavaScriptEncoder.UnsafeRelaxedJsonEscaping

    let i = "    "
    let sb = new StringBuilder()
    sb.Append($"{i}nuget_repo(\n") |> ignore

    sb.Append($"{i}    name = \"{repoPrefix}{repoName}\",\n") |> ignore

    sb.Append($"{i}    packages = [\n") |> ignore

    for package in packages do
        sb.Append($"{i}        ") |> ignore

        sb.Append(
            JsonSerializer
                .Serialize(package, jsonOptions)
                // The replacements are so that the Bazel formatter does not have anything to format
                .Replace("\":\"", "\": \"")
                .Replace("\",\"", "\", \"")
                .Replace("\":[", "\": [")
                .Replace("],", "], ")
                .Replace("\":{", "\": {")
                .Replace("},", "}, ")
        )
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
