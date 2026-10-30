/// Generates the framework tables that rules_dotnet needs to reproduce the
/// SDK's implicit preprocessor defines and its per-framework C# language
/// version cap.
///
/// Both are SDK data. Hardcoding them means a new SDK band (net11.0, say)
/// silently keeps the old behaviour, so they are read from the SDK itself:
///
///   * the supported-framework lists come from
///     Microsoft.NET.SupportedTargetFrameworks.props, the same item groups the
///     SDK's own GenerateNETCompatibleDefineConstants target consumes;
///   * the language versions are probed out of MSBuild per framework, because
///     the mapping lives inside Roslyn rather than in any targets file.
module Frameworks

open System
open System.Diagnostics
open System.IO
open System.Text
open System.Net.Http
open System.IO.Compression
open System.Text.RegularExpressions
open System.Xml.Linq

/// Maps a TargetFrameworkIdentifier to the Starlark name we emit for it.
let private starlarkNames =
    Map [ ".NETCoreApp", "SDK_NETCOREAPP_FRAMEWORKS"
          ".NETFramework", "SDK_NETFRAMEWORK_FRAMEWORKS"
          ".NETStandard", "SDK_NETSTANDARD_FRAMEWORKS" ]

/// Downloads and extracts an SDK, returning its `sdk/<version>` directory.
///
/// Cached under the system temp directory and keyed by version -- these
/// archives are ~200MB.
let downloadSdk (version: string) (url: string) =
    let root = Path.Combine(Path.GetTempPath(), "rules_dotnet-gen-sdk", version)
    let marker = Path.Combine(root, ".extracted")

    if not (File.Exists marker) then
        if Directory.Exists root then
            Directory.Delete(root, true)

        Directory.CreateDirectory root |> ignore

        printfn $"Downloading .NET SDK {version} for {Sdk.hostRid ()}"

        let archive = Path.Combine(Path.GetTempPath(), Path.GetFileName(Uri(url).LocalPath))

        use httpClient = new HttpClient()
        httpClient.Timeout <- TimeSpan.FromMinutes 10.0

        // Streamed rather than buffered: the archive is ~200MB.
        use source = httpClient.GetStreamAsync(url).Result
        use destination = File.Create archive
        source.CopyTo destination
        destination.Close()

        printfn $"Extracting to {root}"

        if archive.EndsWith ".zip" then
            ZipFile.ExtractToDirectory(archive, root)
        else
            // .tar.gz: shell out, because the framework has no gzip+tar reader
            // that preserves the executable bits the SDK needs.
            let psi = Diagnostics.ProcessStartInfo("tar")
            psi.WorkingDirectory <- root

            for arg in [ "-xzf"; archive ] do
                psi.ArgumentList.Add arg

            use proc = Diagnostics.Process.Start psi
            proc.WaitForExit()

            if proc.ExitCode <> 0 then
                failwith $"Failed to extract {archive}"

        File.Delete archive
        File.WriteAllText(marker, version)

    let sdkDir = Path.Combine(root, "sdk")

    if not (Directory.Exists sdkDir) then
        failwith $"Downloaded SDK {version} has no sdk/ directory under {root}"

    // The archive contains exactly one SDK.
    DirectoryInfo(Directory.GetDirectories sdkDir |> Array.exactlyOne)

/// Which item group the SDK's define-generation target reads, per framework
/// identity.
///
/// Not hardcoded: .NET 11 moved the .NET Core defines from
/// `SupportedNETCoreAppTargetFramework` to `_NETCoreAppVersionsForDefines`,
/// and reading the SDK's own wiring picks up the next such reshuffle.
let private defineItemNames (targetsPath: string) =
    let pattern =
        Regex(
            """_SupportedFrameworkVersions\s+Include="@\((?<item>[A-Za-z_][A-Za-z0-9_]*)->.*?TargetFrameworkIdentifier\)'\s*==\s*'(?<identity>\.[A-Za-z]+)'""",
            RegexOptions.Singleline)

    let found =
        File.ReadAllLines targetsPath
        |> Array.choose (fun line ->
            let m = pattern.Match line

            if m.Success then
                Some(m.Groups.["identity"].Value, m.Groups.["item"].Value)
            else
                None)
        |> Map.ofArray

    for identity in starlarkNames.Keys do
        if not (found.ContainsKey identity) then
            failwith $"Could not determine which item group feeds {identity} defines in {targetsPath}"

    found

let private sdkTargetsFile (sdk: DirectoryInfo) (fileName: string) =
    let path = Path.Combine(sdk.FullName, "Sdks", "Microsoft.NET.Sdk", "targets", fileName)

    if not (File.Exists path) then
        failwith $"Could not find {path}"

    path

/// Reads the framework aliases (net10.0, net48, netstandard2.0, ...) for one
/// item group, in the order the SDK declares them, which is ascending.
let private readAliases (doc: XDocument) (itemName: string) =
    doc.Descendants()
    |> Seq.filter (fun e -> e.Name.LocalName = itemName)
    |> Seq.choose (fun e ->
        match e.Attribute(XName.Get "Alias") with
        | null -> None
        | attr -> Some attr.Value)
    |> Seq.distinct
    |> List.ofSeq

/// Asks MSBuild what C# language version it would default to for a framework.
///
/// The mapping is implemented in Roslyn, not in a targets file, so there is
/// nothing to parse -- the only reliable source is MSBuild itself.
let private probeLangVersion (dotnet: string) (workDir: string) (tfm: string) =
    let project = Path.Combine(workDir, "probe.csproj")

    let content =
        String.concat
            "\n"
            [ """<Project Sdk="Microsoft.NET.Sdk">"""
              "  <PropertyGroup>"
              $"    <TargetFramework>{tfm}</TargetFramework>"
              "  </PropertyGroup>"
              "</Project>"
              "" ]

    File.WriteAllText(project, content)

    let psi = ProcessStartInfo(dotnet)
    psi.WorkingDirectory <- workDir
    psi.RedirectStandardOutput <- true
    psi.RedirectStandardError <- true

    for arg in [ "msbuild"; project; "-getProperty:LangVersion"; "-nologo" ] do
        psi.ArgumentList.Add arg

    psi.Environment.["DOTNET_CLI_TELEMETRY_OPTOUT"] <- "1"
    psi.Environment.["DOTNET_NOLOGO"] <- "1"

    use proc = Process.Start psi
    let stdout = proc.StandardOutput.ReadToEnd()
    proc.StandardError.ReadToEnd() |> ignore
    proc.WaitForExit()

    if proc.ExitCode <> 0 then
        None
    else
        let lines =
            stdout.Trim().Split('\n')
            |> Array.filter (String.IsNullOrWhiteSpace >> not)

        if lines.Length = 0 then
            None
        else
            Some(lines.[lines.Length - 1].Trim())

/// Where a .NET Framework or .NET Core framework gains access to a .NET
/// Standard version. These are the only non-linear edges in the graph, and are
/// fixed historical facts rather than anything a release feed publishes.
let private netstandardBridges =
    Map [ "net45", "netstandard1.1"
          "net451", "netstandard1.2"
          "net46", "netstandard1.3"
          "net461", "netstandard2.0"
          "netcoreapp1.0", "netstandard1.6"
          "netcoreapp2.0", "netstandard2.0"
          "netcoreapp3.0", "netstandard2.1" ]

/// Monikers rules_dotnet accepts that the SDK's lists omit. They can be
/// depended on, but get no `*_OR_GREATER` symbol, matching the SDK.
let private legacyBefore =
    Map [ "netstandard1.0", "netstandard"; "net20", "net11"; "net45", "net403" ]

/// Splices the legacy monikers into a family's release sequence.
let private withLegacy (chain: string list) =
    chain
    |> List.collect (fun tfm ->
        match Map.tryFind tfm legacyBefore with
        | Some extra -> [ extra; tfm ]
        | None -> [ tfm ])

/// Maps each framework to the frameworks it can directly compile against.
///
/// Within a family that is simply "the previous release"; the only other edges
/// are the netstandard bridges above.
let private chainCompatibility (chain: string list) =
    let full = withLegacy chain
    let bridge tfm = Map.tryFind tfm netstandardBridges |> Option.toList

    match full with
    | [] -> []
    | first :: _ ->
        (first, bridge first)
        :: (full
            |> List.pairwise
            |> List.map (fun (previous, tfm) -> tfm, previous :: bridge tfm))

/// Keeps framework support aligned with the channels used to generate packs.
let private upToChannel (latestChannel: string) (aliases: string list) =
    let latest = Version latestChannel

    // Only netX.Y monikers parse; netstandard*, netcoreapp* and net48 fall
    // through and are always kept.
    aliases
    |> List.filter (fun alias ->
        match Version.TryParse(alias.Substring 3) with
        | true, version -> version <= latest
        | _ -> true)

let generateFrameworks output sdkVersion sdkUrl stableChannel latestChannel =
    let sdk = downloadSdk sdkVersion sdkUrl
    let props = XDocument.Load(sdkTargetsFile sdk "Microsoft.NET.SupportedTargetFrameworks.props")
    let itemNames = defineItemNames (sdkTargetsFile sdk "Microsoft.NET.Sdk.BeforeCommon.targets")
    let dotnet = Path.Combine(sdk.Parent.Parent.FullName, if OperatingSystem.IsWindows() then "dotnet.exe" else "dotnet")

    printfn $"Reading supported frameworks from SDK {sdk.Name}"

    // Ordered so the emitted file reads netstandard, then .NET Framework, then
    // .NET Core -- the order FRAMEWORK_COMPATIBILITY documents as significant.
    let families = [ ".NETStandard"; ".NETFramework"; ".NETCoreApp" ]

    let groups =
        families
        |> List.map (fun identity ->
            let aliases = readAliases props itemNames.[identity] |> upToChannel latestChannel

            if List.isEmpty aliases then
                failwith $"Item group {itemNames.[identity]} for {identity} is empty"

            identity, starlarkNames.[identity], aliases)

    // Insulate the probe project from whatever is above the temp directory.
    let workDir = Path.Combine(Path.GetTempPath(), $"rd-langversion-{Guid.NewGuid():N}")
    Directory.CreateDirectory workDir |> ignore
    File.WriteAllText(Path.Combine(workDir, "Directory.Build.props"), "<Project/>\n")
    File.WriteAllText(Path.Combine(workDir, "Directory.Build.targets"), "<Project/>\n")

    let langVersions =
        try
            groups
            |> List.collect (fun (_, _, aliases) -> aliases)
            |> List.choose (fun tfm ->
                printfn $"  probing LangVersion for {tfm}"

                probeLangVersion dotnet workDir tfm |> Option.map (fun v -> tfm, v))
        finally
            try
                Directory.Delete(workDir, true)
            with _ ->
                ()

    let defaultTfm = $"net{stableChannel}"

    let compatibility =
        [ "# .NET Standard", ".NETStandard"
          "# .NET Framework", ".NETFramework"
          "# .NET Core", ".NETCoreApp" ]
        |> List.map (fun (comment, identity) ->
            let _, _, aliases = groups |> List.find (fun (i, _, _) -> i = identity)
            comment, chainCompatibility aliases)

    let sb = StringBuilder()
    let line (text: string) = sb.AppendLine text |> ignore

    line "\"\"\"Framework tables read from the .NET SDK."
    line ""
    line "GENERATED BY SDK GENERATOR -- see dotnet/private/sdk/gen."
    line ""

    line "The framework lists mirror the Supported*TargetFramework item groups in"
    line "Microsoft.NET.SupportedTargetFrameworks.props, which is what the SDK's"
    line "GenerateNETCompatibleDefineConstants target consumes. A framework absent"
    line "from these lists never gets an *_OR_GREATER symbol."

    line ""

    line "SDK_LANG_VERSIONS maps each framework to the C# language version the SDK"
    line "defaults to for it. Newer language features depend on runtime support that"
    line "older targets lack, which is why the cap exists."

    line ""

    line "DEFAULT_TARGET_FRAMEWORK is the newest generally-available framework."
    line "Preview frameworks are available for explicit targets, with matching"
    line "prerelease packs, but never become the default."

    line "\"\"\""
    line ""
    line $"# Read from .NET SDK {sdk.Name}."
    line ""
    line $"DEFAULT_TARGET_FRAMEWORK = \"{defaultTfm}\""

    for _, starlarkName, aliases in groups do
        line ""
        line $"{starlarkName} = ["

        for alias in aliases do
            line $"    \"{alias}\","

        line "]"

    line ""
    line "SDK_LANG_VERSIONS = {"

    for tfm, version in langVersions do
        line $"    \"{tfm}\": \"{version}\","

    line "}"

    line ""

    line "# Each framework mapped to the frameworks it can directly compile against."
    line "# The relationship is transitive. Order matters: netstandard first, and"
    line "# within a family oldest to newest."

    line "FRAMEWORK_COMPATIBILITY = {"

    for comment, entries in compatibility do
        line $"    {comment}"

        for tfm, deps in entries do
            let rendered = deps |> List.map (fun d -> $"\"{d}\"") |> String.concat ", "
            line $"    \"{tfm}\": [{rendered}],"

        line ""

    line "}"

    File.WriteAllText(output, sb.ToString())
    printfn $"Wrote {output}"
