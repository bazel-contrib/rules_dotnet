module DotnetPacks.Main

open System.IO

[<EntryPoint>]
let main argv =
    let sdkFolder = argv.[0]

    // Get the supported SDKs and generate sdk_versions.bzl
    Sdk.generateSdks (Path.Combine(sdkFolder, "versions.bzl"))

    // // Generate the RID graph
    Sdk.generateRids (Path.Combine(sdkFolder, "rids.bzl"))


    // Generate the targeting pack targets
    let targetingPacksFile = Path.Combine(sdkFolder, "gen", "targeting-packs.json")
    TargetingPacks.updateTargetingPacks targetingPacksFile

    TargetingPacks.writeTargetingPackLookupTable
        targetingPacksFile
        (Path.Combine(sdkFolder, "targeting_packs", "targeting_pack_lookup_table.bzl"))

    TargetingPacks.generateTargetingPackTargets
        targetingPacksFile
        (Path.Combine(sdkFolder, "targeting_packs", "targeting_packs.bzl"))

    TargetingPacks.generateTargetingPacksNugetRepo targetingPacksFile (Path.Combine(sdkFolder, "targeting_packs"))

    // Generate the runtime pack targets
    let runtimePacksFile = Path.Combine(sdkFolder, "gen", "runtime-packs.json")
    RuntimePacks.updateRuntimePacks runtimePacksFile

    RuntimePacks.writeRuntimePackLookupTable
        runtimePacksFile
        (Path.Combine(sdkFolder, "runtime_packs", "runtime_pack_lookup_table.bzl"))

    RuntimePacks.generateRuntimePackTargets
        runtimePacksFile
        (Path.Combine(sdkFolder, "runtime_packs", "runtime_packs.bzl"))

    RuntimePacks.generateRuntimePacksNugetRepo runtimePacksFile (Path.Combine(sdkFolder, "runtime_packs"))

    // Generate the apphost pack targets
    let apphostPacksFile = Path.Combine(sdkFolder, "gen", "apphost-packs.json")
    ApphostPacks.updateApphostPacks apphostPacksFile

    ApphostPacks.writeApphostPackLookupTable
        apphostPacksFile
        (Path.Combine(sdkFolder, "apphost_packs", "apphost_pack_lookup_table.bzl"))

    ApphostPacks.generateApphostPackTargets
        apphostPacksFile
        (Path.Combine(sdkFolder, "apphost_packs", "apphost_packs.bzl"))

    ApphostPacks.generateApphostPacksNugetRepo apphostPacksFile (Path.Combine(sdkFolder, "apphost_packs"))

    // Generate the crossgen2 pack targets
    let crossgen2PacksFile = Path.Combine(sdkFolder, "gen", "crossgen2-packs.json")
    Crossgen2Packs.updateCrossgen2Packs crossgen2PacksFile

    Crossgen2Packs.writeCrossgen2PackLookupTable
        crossgen2PacksFile
        (Path.Combine(sdkFolder, "crossgen2_packs", "crossgen2_pack_lookup_table.bzl"))

    Crossgen2Packs.generateCrossgen2PackTargets
        crossgen2PacksFile
        (Path.Combine(sdkFolder, "crossgen2_packs", "crossgen2_packs.bzl"))

    Crossgen2Packs.generateCrossgen2PacksNugetRepo crossgen2PacksFile (Path.Combine(sdkFolder, "crossgen2_packs"))
    0
