".Net Targeting Pack"

load("//dotnet:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "DotnetTargetingPackInfo", "NuGetInfo")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _targeting_pack_impl(ctx):
    compile_infos = []
    runtime_infos = []
    nuget_infos = []
    for pack in ctx.attr.packs:
        if pack[DotnetAssemblyCompileInfo]:
            compile_infos.append(pack[DotnetAssemblyCompileInfo])
        if pack[DotnetAssemblyRuntimeInfo]:
            runtime_infos.append(pack[DotnetAssemblyRuntimeInfo])
        if pack[NuGetInfo]:
            nuget_infos.append(pack[NuGetInfo])

    return [DotnetTargetingPackInfo(
        assembly_compile_infos = compile_infos,
        assembly_runtime_infos = runtime_infos,
        nuget_infos = nuget_infos,
    )]

targeting_pack = rule(
    _targeting_pack_impl,
    doc = """.Net Targeting Pack""",
    attrs = {
        "packs": attr.label_list(
            cfg = tfm_transition,
            doc = "List of .Net Targeting Packs that make this pack",
        ),
        "target_framework": attr.string(
            doc = "The target framework of the targeting pack",
        ),
    },
)
