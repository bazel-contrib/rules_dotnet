module Sdk

open System
open System.Net
open System.IO
open System.Text.Json.Serialization
open System.Text.Json
open System.Text
open System.Collections.Generic
open NuGet.RuntimeModel
open System.Net.Http

/// Shared so the handler and its sockets are not leaked per call.
let private http = new HttpClient()

/// One entry of the release index: a .NET channel and where it is in its
/// lifecycle. `SupportPhase` is what keeps a preview release from becoming the
/// default target framework.
type ReleaseIndexEntry =
    { [<JsonPropertyName "channel-version">]
      ChannelVersion: string
      [<JsonPropertyName "support-phase">]
      SupportPhase: string
      [<JsonPropertyName "latest-sdk">]
      LatestSdk: string }

type ReleaseIndex =
    { [<JsonPropertyName "releases-index">]
      Releases: ReleaseIndexEntry seq }

/// Channels older than this were never supported by rules_dotnet: their packs
/// are laid out differently and no pack band exists for them.
let private oldestSupportedChannel = Version "6.0"

let private releaseIndexUrl =
    "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"

let private parseChannelVersion (channel: string) =
    match Version.TryParse channel with
    | true, version -> Some version
    | _ -> None

/// The release index, newest channel first.
let downloadReleaseIndex () =
    let json = http.GetAsync(releaseIndexUrl).Result.Content.ReadAsStringAsync().Result

    JsonSerializer.Deserialize<ReleaseIndex>(json).Releases
    |> Seq.choose (fun entry ->
        parseChannelVersion entry.ChannelVersion
        |> Option.map (fun version -> version, entry))
    |> Seq.filter (fun (version, _) -> version >= oldestSupportedChannel)
    |> Seq.sortByDescending fst
    |> List.ofSeq

/// Every channel rules_dotnet tracks, oldest first. Discovered rather than
/// hardcoded so a new .NET release needs no code change here.
let supportedChannels (index: (Version * ReleaseIndexEntry) list) =
    index |> List.rev |> List.map (fun (_, entry) -> entry.ChannelVersion)

/// The newest channel that is not a preview.
///
/// This is what DEFAULT_TFM is derived from: defaulting to a preview framework
/// would make every target in every downstream repo depend on packs that are
/// still changing shape.
let latestStableChannel (index: (Version * ReleaseIndexEntry) list) =
    // Only a generally-available channel qualifies. "preview" is the obvious
    // exclusion, but "go-live" matters just as much: a release candidate is
    // supported in production yet its packs are still moving, and it must not
    // become the default every downstream target inherits.
    index
    |> List.filter (fun (_, entry) ->
        String.Equals(entry.SupportPhase, "active", StringComparison.OrdinalIgnoreCase)
        || String.Equals(entry.SupportPhase, "maintenance", StringComparison.OrdinalIgnoreCase))
    |> List.tryHead
    |> Option.map (fun (_, entry) -> entry.ChannelVersion)
    |> Option.defaultWith (fun () -> failwith "The release index contains no non-preview channel")

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
      [<JsonPropertyName "latest-runtime">]
      LatestRuntime: string
      [<JsonPropertyName "releases">]
      Releases: Release seq }

type Runtime =
    { [<JsonPropertyName "#import">]
      Import: string seq }

type Runtimes =
    { [<JsonPropertyName "runtimes">]
      Runtimes: Dictionary<string, Runtime> }

let private releaseJsonUrl channel =
    $"https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/{channel}/releases.json"


// The newest channel's feed is wanted by both generateSdks and
// newestSdkArchive, and it is several MB.
let private channelCache = Collections.Generic.Dictionary<string, Channel>()

let private downloadReleaseInfoForChannel channel =
    match channelCache.TryGetValue channel with
    | true, cached -> cached
    | _ ->
        let json = http.GetAsync(releaseJsonUrl channel).Result.Content.ReadAsStringAsync().Result
        let parsed = JsonSerializer.Deserialize<Channel>(json)
        channelCache[channel] <- parsed
        parsed

let private downloadRuntimes () =
    let json =
        http
            .GetAsync(
                "https://raw.githubusercontent.com/dotnet/runtime/main/src/libraries/Microsoft.NETCore.Platforms/src/runtime.json"
            )
            .Result.Content.ReadAsStringAsync()
            .Result

    JsonSerializer.Deserialize<Runtimes>(json)


let private filterSdkFiles (sdk: Sdk) =
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
            // Some releases publish both archive formats for the same RID.
            if f.Rid.StartsWith("win-") then
                f.Name.EndsWith(".zip")
            else
                f.Name.EndsWith(".tar.gz"))
        |> Seq.filter (fun f ->
            // There were some incorrect preview releases which had arm binaries released as x64 binaries, removing those
            not (f.Rid = "osx-x64" && f.Name.EndsWith("arm64.tar.gz")))

    // If there is no MacOS arm version of in the release then we add an entry where we use the x64
    // version since that can be run with Rosetta
    if not (Seq.exists (fun f -> f.Rid = "osx-arm64") files) then
        let x64 = Seq.find (fun f -> f.Rid = "osx-x64") files
        Seq.append [ { x64 with Rid = "osx-arm64" } ] files
    else
        files
    |> Seq.sortBy (fun f -> f.Rid)

let private convertRid rid =
    match rid with
    | "linux-x64" -> "x86_64-unknown-linux-gnu"
    | "linux-arm64" -> "arm64-unknown-linux-gnu"
    | "osx-arm64" -> "aarch64-apple-darwin"
    | "osx-x64" -> "x86_64-apple-darwin"
    | "win-x64" -> "x86_64-pc-windows-msvc"
    | "win-arm64" -> "arm64-pc-windows-msvc"
    | _ -> failwith "Unsupported platform"

let private base64Encode (input: string) =
    System.Convert.ToBase64String(System.Convert.FromHexString(input))


let private generateVersionsBzl output (channels: Channel seq) =
    let sb = StringBuilder()

    sb.AppendLine("\"\"\"Mirror of release info  (GENERATED BY SDK GENERATOR)\"\"\"")
    |> ignore

    sb.AppendLine() |> ignore

    sb.AppendLine("TOOL_VERSIONS = {") |> ignore

    for channel in channels |> Seq.sortBy (fun c -> c.ChannelVersion) do
        for release in channel.Releases do
            for sdk in release.Sdks |> Seq.sortBy (fun s -> s.Version) do
                sb.AppendLine((sprintf "    \"%s\": {" sdk.Version)) |> ignore

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

    File.WriteAllText(output, sb.ToString())

let generateRids output =
    let runtimes = downloadRuntimes ()

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

        sb.AppendLine((sprintf "    \"%s\": [%s]," key values)) |> ignore

    sb.AppendLine("}") |> ignore

    File.WriteAllText(output, sb.ToString())

/// The host RID, used to pick which SDK archive to download.
let hostRid () =
    let arch =
        match Runtime.InteropServices.RuntimeInformation.OSArchitecture with
        | Runtime.InteropServices.Architecture.Arm64 -> "arm64"
        | Runtime.InteropServices.Architecture.X64 -> "x64"
        | other -> failwith $"Unsupported host architecture: {other}"

    if Runtime.InteropServices.RuntimeInformation.IsOSPlatform Runtime.InteropServices.OSPlatform.Windows then
        $"win-{arch}"
    elif Runtime.InteropServices.RuntimeInformation.IsOSPlatform Runtime.InteropServices.OSPlatform.OSX then
        $"osx-{arch}"
    else
        $"linux-{arch}"

/// The newest SDK archive for the host, as (version, url).
///
/// Deliberately the newest *available* SDK including previews: the generator's
/// job is to describe the .NET that exists, and the preview filtering happens
/// only where it matters, when choosing the default target framework.
let newestSdkArchive (index: (Version * ReleaseIndexEntry) list) =
    let channel = index |> List.head |> snd

    let release =
        let channelInfo = downloadReleaseInfoForChannel channel.ChannelVersion

        channelInfo.Releases
        |> Seq.collect (fun release -> release.Sdks)
        |> Seq.filter (fun sdk -> sdk.Version = channel.LatestSdk)
        |> Seq.tryHead

    match release with
    | None -> failwith $"Could not find SDK {channel.LatestSdk} in channel {channel.ChannelVersion}"
    | Some sdk ->
        let rid = hostRid ()

        match filterSdkFiles sdk |> Seq.tryFind (fun f -> f.Rid = rid) with
        | None -> failwith $"No SDK archive for {rid} in {sdk.Version}"
        | Some file -> sdk.Version, file.Url

let generateSdks output (channels: string list) =
    channels
    |> Seq.map downloadReleaseInfoForChannel
    |> generateVersionsBzl output
