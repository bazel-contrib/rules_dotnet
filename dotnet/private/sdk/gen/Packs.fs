module Packs

open System
open System.IO
open System.Text

/// A .NET release band and the packs it shipped. The versions are looked up
/// from NuGet; only the shape of a release belongs here.
type Band =
    { tfm: string
      hasWeb: bool
      rids: string list
      /// Set only where ASP.NET Core shipped a different set to .NET.
      webRids: string list option
      /// Set only where crossgen2 shipped for fewer hosts than the runtime.
      crossgen2Rids: string list option
      /// NativeAOT ships a runtime pack of its own from .NET 9 onwards.
      hasAot: bool
      /// Blazor WebAssembly. Set only where every piece of the toolchain ships
      /// as a package of its own.
      hasWasm: bool }

let private allRids =
    [ "linux-arm64"
      "linux-musl-arm64"
      "linux-musl-x64"
      "linux-x64"
      "osx-arm64"
      "osx-x64"
      "win-arm64"
      "win-x64" ]

/// Apple silicon packs only exist from .NET 6 onwards.
let private preNet6Rids = allRids |> List.filter (fun r -> r <> "osx-arm64")

let private band tfm hasWeb rids =
    { tfm = tfm
      hasWeb = hasWeb
      rids = rids
      webRids = None
      crossgen2Rids = None
      hasAot = false
      hasWasm = false }

/// Releases before .NET 6 carry irregularities that are now frozen history:
/// Apple silicon packs did not exist yet, ASP.NET Core 3.0 shipped a
/// different RID set to .NET Core 3.0, and crossgen2 first shipped as a
/// package in .NET 5, for x64 hosts alone. Everything from .NET 6 onward is
/// uniform, so those bands are derived from the discovered channels instead of
/// being listed here, and a new .NET release needs no edit to this file.
let private historicalBands =
    [ band "netcoreapp1.0" false []
      band "netcoreapp1.1" false []
      band "netcoreapp2.0" false []
      band "netcoreapp2.1" true []
      band "netcoreapp2.2" true []
      { band "netcoreapp3.0" true preNet6Rids with
          // ASP.NET Core did not ship a win-arm64 runtime pack for 3.0.
          webRids = Some(preNet6Rids |> List.filter (fun r -> r <> "win-arm64"))
          crossgen2Rids = Some [] }
      { band "netcoreapp3.1" true preNet6Rids with
          crossgen2Rids = Some [] }
      { band "net5.0" true preNet6Rids with
          // The Crossgen2RuntimeIdentifiers the .NET SDK lists for net5.0.
          crossgen2Rids = Some [ "linux-musl-x64"; "linux-x64"; "win-x64" ] } ]

/// Bands for the given channels. Callers pass the GA channels only: a preview
/// release has no stable packs to look up.
let private bands (channels: string list) =
    let modern =
        channels
        |> List.choose (fun channel ->
            match Version.TryParse channel with
            | true, version when version.Major >= 6 ->
                Some
                    { band $"net{channel}" true allRids with
                        hasAot = version.Major >= 9
                        hasWasm = version.Major >= 10 }
            | _ -> None)

    historicalBands @ modern

let private refId (tfm: string) aspnet =
    let baseId =
        if aspnet then
            "Microsoft.AspNetCore.App"
        else
            "Microsoft.NETCore.App"

    // .NET Core 3.0 split the shared framework into a reference pack and a
    // runtime pack; before that one package carried both.
    if tfm.StartsWith "netcoreapp1" || tfm.StartsWith "netcoreapp2" then
        baseId
    else
        baseId + ".Ref"

let private bandPrefix (tfm: string) =
    let version =
        if tfm.StartsWith "netcoreapp" then
            tfm.Substring("netcoreapp".Length)
        else
            tfm.Substring("net".Length)

    version + "."

let private latestInBand (id: string) (tfm: string) =
    let prefix = bandPrefix tfm

    let candidates =
        NugetHelpers.getAllVersions id
        |> List.filter (fun v -> not v.IsPrerelease && v.ToNormalizedString().StartsWith prefix)

    match candidates with
    | [] ->
        // Almost always means the band is not generally available yet, so no
        // stable packs have been published. Say so, rather than failing with
        // "the input sequence was empty" from List.max.
        failwith
            $"No stable {id} package for {tfm}. If {tfm} is still a preview or release candidate it should not be in the channel list yet."
    | versions -> (List.max versions).ToNormalizedString()

/// The Mono runtime pack Blazor WebAssembly runs on. Unlike every other runtime
/// pack its runtime identifier is fixed, because there is only one browser.
let private wasmRuntimeId = "Microsoft.NETCore.App.Runtime.Mono.browser-wasm"

/// Converts assemblies to the Webcil container a browser will serve, and holds
/// the SDK logic that lays a published application out.
let private wasmSdkId = "Microsoft.NET.Sdk.WebAssembly.Pack"

/// Trims the application before it is converted. A Blazor WebAssembly publish
/// trims by default.
let private illinkId = "Microsoft.NET.ILLink.Tasks"

/// Carries `blazor.webassembly.js`, the script that starts the runtime.
let private internalAssetsId = "Microsoft.AspNetCore.App.Internal.Assets"

/// Serves a development build to a browser, and proxies the browser's debugger
/// onto the running application. This is what `dotnet run` starts.
let private devServerId = "Microsoft.AspNetCore.Components.WebAssembly.DevServer"

let private ridList (rids: string list) =
    rids |> List.map (sprintf "\"%s\"") |> String.concat ", "

let private header =
    "\"\"\"The .NET runtime band that each target framework's packs come from.\n\n\
     GENERATED BY SDK GENERATOR\n\
     \"\"\"\n\nPACK_BANDS = {\n"

let generatePackBands (output: string) (channels: string list) =
    let sb = StringBuilder()
    sb.Append(header) |> ignore

    for band in bands channels do
        let fields = ResizeArray<string>()

        fields.Add(sprintf "\"ref\": \"%s\"" (latestInBand (refId band.tfm false) band.tfm))

        if band.hasWeb then
            fields.Add(sprintf "\"web_ref\": \"%s\"" (latestInBand (refId band.tfm true) band.tfm))

        if not band.rids.IsEmpty then
            let runtimeId = "Microsoft.NETCore.App.Runtime." + band.rids.Head
            fields.Add(sprintf "\"runtime\": \"%s\"" (latestInBand runtimeId band.tfm))
            fields.Add(sprintf "\"rids\": [%s]" (ridList band.rids))

            match band.webRids with
            | Some webRids -> fields.Add(sprintf "\"web_rids\": [%s]" (ridList webRids))
            | None -> ()

            match band.crossgen2Rids with
            | Some crossgen2Rids -> fields.Add(sprintf "\"crossgen2_rids\": [%s]" (ridList crossgen2Rids))
            | None -> ()

            if band.hasAot then
                // ilc and the runtime pack it links against ship together, so
                // one version covers both.
                let ilcompilerId = "runtime." + band.rids.Head + ".Microsoft.DotNet.ILCompiler"
                fields.Add(sprintf "\"ilcompiler\": \"%s\"" (latestInBand ilcompilerId band.tfm))

        if band.hasWasm then
            // Blazor WebAssembly compiles against the ordinary reference packs
            // and runs on this one, so it is keyed by band rather than by RID.
            fields.Add(sprintf "\"wasm\": \"%s\"" (latestInBand wasmRuntimeId band.tfm))
            fields.Add(sprintf "\"wasm_sdk\": \"%s\"" (latestInBand wasmSdkId band.tfm))
            fields.Add(sprintf "\"illink\": \"%s\"" (latestInBand illinkId band.tfm))
            fields.Add(sprintf "\"internal_assets\": \"%s\"" (latestInBand internalAssetsId band.tfm))
            fields.Add(sprintf "\"devserver\": \"%s\"" (latestInBand devServerId band.tfm))

        sb.Append(sprintf "    \"%s\": {%s},\n" band.tfm (String.concat ", " fields))
        |> ignore

    sb.Append("}\n") |> ignore

    File.WriteAllText(output, sb.ToString())
