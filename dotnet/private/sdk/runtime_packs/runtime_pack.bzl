".Net Runtime Pack"

load("//dotnet:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "DotnetRuntimePackInfo", "NuGetInfo")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _runtime_pack_impl(ctx):
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

    return [DotnetRuntimePackInfo(
        runtime_identifier = ctx.attr.runtime_identifier,
        assembly_runtime_infos = runtime_infos,
        nuget_infos = nuget_infos,
    )]

runtime_pack = rule(
    _runtime_pack_impl,
    doc = """.Net runtime Pack""",
    attrs = {
        "packs": attr.label_list(
            cfg = tfm_transition,
            doc = "List of .Net runtime Packs that make this pack",
        ),
        "target_framework": attr.string(
            doc = "The target framework of the runtime pack",
        ),
        "runtime_identifier": attr.string(
            doc = "The runtime identifier of the runtime pack",
        ),
    },
)
