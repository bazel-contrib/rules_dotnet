#r "nuget: NuGet.Protocol"

open System
open System.Net
open System.IO
open System.Text.Json.Serialization
open System.Text.Json
open System.Text
open System.Threading
open NuGet.Common
open NuGet.Configuration
open NuGet.Protocol
open NuGet.Protocol.Core.Types
open System.Xml.Linq
open NuGet.Versioning
open NuGet.Packaging.Core
open NuGet.Packaging
open System.Security.Cryptography
open System.Collections.Generic
open NuGet.RuntimeModel

let supportedChannels = [ "6.0"; "7.0" ]

type File =
    { [<JsonPropertyName "name">]
      Name: string
      [<JsonPropertyName "rid">]
      Rid: string
      [<JsonPropertyName "url">]
      Url: string
      [<JsonPropertyName "hash">]
      Hash: string }

type Sdk =
    { [<JsonPropertyName "version">]
      Version: string
      [<JsonPropertyName "runtime-version">]
      RuntimeVersion: string
      [<JsonPropertyName "files">]
      Files: File seq
      [<JsonPropertyName "csharp-version">]
      CSharpVersion: string
      [<JsonPropertyName "fsharp-version">]
      FSharpVersion: string }

type Release =
    { [<JsonPropertyName "sdks">]
      Sdks: Sdk seq }

type Channel =
    { [<JsonPropertyName "channel-version">]
      ChannelVersion: string
      [<JsonPropertyName "releases">]
      Releases: Release seq }

type Runtime =
    { [<JsonPropertyName "#import">]
      Import: string seq }

type Runtimes =
    { [<JsonPropertyName "runtimes">]
      Runtimes: Dictionary<string, Runtime> }

let releaseJsonUrl channel =
    $"https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/{channel}/releases.json"


let downloadReleaseInfoForChannel channel =
    let webClient = new WebClient()
    let url = releaseJsonUrl channel

    let json = webClient.DownloadString(url)
    JsonSerializer.Deserialize<Channel>(json)

let downloadRuntimes () =
    let webClient = new WebClient()

    let json =
        webClient.DownloadString(
            "https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/Microsoft.NETCore.Platforms/src/runtime.json"
        )

    JsonSerializer.Deserialize<Runtimes>(json)


let filterSdkFiles (sdk: Sdk) =
    let files =
        sdk.Files
        |> Seq.filter (fun f ->
            match f.Rid with
            | "linux-x64" -> true
            | "linux-arm64" -> true
            | "osx-arm64" -> true
            | "osx-x64" -> true
            | "win-x64" -> true
            | "win-arm64" -> true
            | _ -> false)
        |> Seq.filter (fun f ->
            // We are only intersted in the compressed artifacts, not exe or pkg or similar artifacts
            f.Name.EndsWith(".zip")
            || f.Name.EndsWith(".tar.gz"))
        |> Seq.filter (fun f ->
            // Some releases have .zip and .tar.gz artifacts for linux so we remove the .zip artifacts
            not (f.Rid = "linux-x64" && f.Name.EndsWith(".zip")))
        |> Seq.filter (fun f ->
            // There were some incorrect preview releases which had arm binaries released as x64 binaries, removing those
            not (
                f.Rid = "osx-x64"
                && f.Name.EndsWith("arm64.tar.gz")
            ))

    // If there is no MacOS arm version of in the release then we add an entry where we use the x64
    // version since that can be run with Rosetta
    if not (Seq.exists (fun f -> f.Rid = "osx-arm64") files) then
        let x64 = Seq.find (fun f -> f.Rid = "osx-x64") files
        Seq.append [ { x64 with Rid = "osx-arm64" } ] files
    else
        files
    |> Seq.sortBy (fun f -> f.Rid)

let convertRid rid =
    match rid with
    | "linux-x64" -> "x86_64-unknown-linux-gnu"
    | "linux-arm64" -> "arm64-unknown-linux-gnu"
    | "osx-arm64" -> "aarch64-apple-darwin"
    | "osx-x64" -> "x86_64-apple-darwin"
    | "win-x64" -> "x86_64-pc-windows-msvc"
    | "win-arm64" -> "arm64-pc-windows-msvc"
    | _ -> failwith "Unsupported platform"

let base64Encode (input: string) =
    System.Convert.ToBase64String(System.Convert.FromHexString(input))


let generateVersionsBzl (channels: Channel seq) =
    let sb = StringBuilder()

    sb.AppendLine("\"\"\"Mirror of release info  (Generated by UpdateSdks.fsx script)\"\"\"")
    |> ignore

    sb.AppendLine() |> ignore
    sb.AppendLine("TOOL_VERSIONS = {") |> ignore

    for channel in channels |> Seq.sortBy (fun c -> c.ChannelVersion) do
        for release in channel.Releases do
            for sdk in release.Sdks |> Seq.sortBy (fun s -> s.Version) do
                sb.AppendLine((sprintf "    \"%s\": {" sdk.Version))
                |> ignore

                sb.AppendLine((sprintf "        \"runtimeVersion\": \"%s\"," sdk.RuntimeVersion))
                |> ignore

                sb.AppendLine((sprintf "        \"runtimeTfm\": \"%s\"," $"net{channel.ChannelVersion}"))
                |> ignore

                sb.AppendLine((sprintf "        \"csharpDefaultVersion\": \"%s\"," sdk.CSharpVersion))
                |> ignore

                sb.AppendLine((sprintf "        \"fsharpDefaultVersion\": \"%s\"," sdk.FSharpVersion))
                |> ignore

                for file in filterSdkFiles sdk do
                    sb.AppendLine(
                        (sprintf
                            "        \"%s\": {\"hash\": \"sha512-%s\", \"url\": \"%s\"},"
                            (convertRid file.Rid)
                            (base64Encode file.Hash)
                            file.Url)
                    )
                    |> ignore

                sb.AppendLine("    },") |> ignore

    sb.AppendLine("}") |> ignore
    sb.AppendLine() |> ignore

    File.WriteAllText("dotnet/private/versions.bzl", sb.ToString())

let generateRidsBzl () =
    let runtimes = downloadRuntimes ()
    let runtimeGraph = Dictionary<string, string seq>()

    let runtimeDescriptions: RuntimeDescription seq =
        runtimes.Runtimes
        |> Seq.map (fun entry -> RuntimeDescription(entry.Key, entry.Value.Import))

    let graph = RuntimeGraph(runtimeDescriptions)

    let sb = StringBuilder()

    sb.AppendLine("\"\"\".Net Runtime identifiers (Generated by UpdateSdks.fsx script)\"\"\"")
    |> ignore

    sb.AppendLine() |> ignore
    sb.AppendLine("RUNTIME_GRAPH = {") |> ignore

    for key in runtimes.Runtimes.Keys do
        let values =
            graph.ExpandRuntime(key)
            |> Seq.filter (fun rid -> rid <> key)
            |> Seq.fold (fun state current -> state + $"\"{current}\", ") ""
            |> (fun s ->
                if String.IsNullOrEmpty(s) then
                    s
                else
                    s.Substring(0, s.Length - 2))

        sb.AppendLine((sprintf "    \"%s\": [%s]," key values))
        |> ignore

    sb.AppendLine("}") |> ignore

    File.WriteAllText("dotnet/private/rids.bzl", sb.ToString())

supportedChannels
|> Seq.map downloadReleaseInfoForChannel
|> generateVersionsBzl

generateRidsBzl ()
