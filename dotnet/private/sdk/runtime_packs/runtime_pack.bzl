".Net Runtime Pack"

load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "DotnetRuntimePackInfo", "NuGetInfo")
load("//dotnet/private/sdk:framework_list.bzl", "framework_assembly_key")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _assembly_name(file):
    return file.basename[:-len(".dll")].lower() if file.basename.lower().endswith(".dll") else None

def _without_shadowed_assemblies(runtime_infos, nuget_infos):
    """Drops each assembly that another of the packs ships a newer copy of.

    All packs share one directory in a self-contained publish. As in the SDK,
    the copy with the higher assembly version, then file version, wins.
    """
    if len(runtime_infos) < 2:
        return runtime_infos

    winners = {}
    for (i, runtime_info) in enumerate(runtime_infos):
        for lib in runtime_info.libs:
            name = _assembly_name(lib)
            if name == None or name not in nuget_infos[i].framework_list:
                continue

            key = framework_assembly_key(nuget_infos[i], name)
            if name not in winners or key > winners[name][1]:
                winners[name] = (i, key)

    narrowed = []
    for (i, runtime_info) in enumerate(runtime_infos):
        libs = [
            lib
            for lib in runtime_info.libs
            if _assembly_name(lib) not in winners or winners[_assembly_name(lib)][0] == i
        ]
        if len(libs) == len(runtime_info.libs):
            narrowed.append(runtime_info)
            continue

        fields = {
            field: getattr(runtime_info, field)
            for field in dir(runtime_info)
            if field not in ["to_json", "to_proto"]
        }
        fields["libs"] = libs
        narrowed.append(DotnetAssemblyRuntimeInfo(**fields))

    return narrowed

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
        assembly_runtime_infos = _without_shadowed_assemblies(runtime_infos, nuget_infos),
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
