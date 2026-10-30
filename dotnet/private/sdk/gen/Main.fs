module DotnetPacks.Main

open System.IO

let private usage =
    """
Usage: dotnet run -- <sdk-folder> [generator ...]

Generators (all of them when none are named):
  versions      versions.bzl    -- available SDK versions   (network)
  rids          rids.bzl        -- the runtime identifier graph (network)
  packs         pack_bands.bzl  -- targeting/runtime/apphost pack bands (network)
  frameworks    frameworks.bzl  -- supported frameworks and C# language versions
  paket         paket.dependencies, dotnet-tools.json -- pin the Paket CLI

Naming a subset is useful because the networked generators take minutes and
rewrite files that are unrelated to whatever you are actually changing.
"""

[<EntryPoint>]
let main argv =
    if argv.Length = 0 then
        eprintfn $"{usage}"
        1
    else

        let sdkFolder = argv.[0]
        let requested = argv |> Array.skip 1 |> Set.ofArray

        let shouldRun name =
            Set.isEmpty requested || requested.Contains name

        let unknown = requested - set [ "versions"; "rids"; "packs"; "frameworks"; "paket" ]

        if not (Set.isEmpty unknown) then
            let names = String.concat ", " unknown
            eprintfn $"Unknown generator(s): {names}"
            eprintfn $"{usage}"
            1
        else

            // Discovered once and shared: which .NET channels exist, and which of them
            // are still previews.
            let index = Sdk.downloadReleaseIndex ()
            let channels = Sdk.supportedChannels index
            let stableChannel = Sdk.latestStableChannel index

            let channelList = String.concat ", " channels
            printfn $"channels: {channelList}"
            printfn $"newest non-preview channel: {stableChannel}"

            if shouldRun "versions" then
                Sdk.generateSdks (Path.Combine(sdkFolder, "versions.bzl")) channels

            if shouldRun "rids" then
                Sdk.generateRids (Path.Combine(sdkFolder, "rids.bzl"))

            if shouldRun "packs" then
                Packs.generatePackBands (Path.Combine(sdkFolder, "pack_bands.bzl")) channels stableChannel

            // Framework lists and the per-framework C# language version cap, both read
            // from the installed SDK rather than hardcoded in Starlark.
            if shouldRun "frameworks" then
                let sdkVersion, sdkUrl = Sdk.newestSdkArchive index

                Frameworks.generateFrameworks
                    (Path.Combine(sdkFolder, "frameworks.bzl"))
                    sdkVersion
                    sdkUrl
                    stableChannel
                    (List.last channels)

            if shouldRun "paket" then
                Paket.updatePaket (Path.Combine(sdkFolder, "..", "..", ".."))

            0
