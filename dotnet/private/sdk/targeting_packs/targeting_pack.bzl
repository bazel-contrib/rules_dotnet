".Net Targeting Pack"

load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "DotnetTargetingPackInfo", "NuGetInfo")
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

    # Resolving the FrameworkList to ref files depends only on the pack itself,
    # so do it here rather than in every target that compiles against the pack.
    targeting_pack_overrides = {}
    framework_list = {}
    framework_files = []
    analyzers = []
    analyzers_csharp = []
    analyzers_fsharp = []
    analyzers_vb = []
    compile_data = []

    for i, nuget_info in enumerate(nuget_infos):
        compile_info = compile_infos[i]

        # `parse_framework_list` lower cases the assembly names it returns, so
        # index on the same normalisation. First match wins.
        refs_by_name = {}
        for ref in compile_info.refs:
            refs_by_name.setdefault(ref.basename.lower().replace(".dll", ""), ref)

        for override_name, override_version in nuget_info.targeting_pack_overrides.items():
            targeting_pack_overrides[override_name] = override_version

        for dll_name, dll_version in nuget_info.framework_list.items():
            framework_list.setdefault(dll_name, {"version": dll_version, "file": refs_by_name.get(dll_name)})

        if len(nuget_info.framework_list) == 0:
            framework_files.extend(compile_info.irefs)

        analyzers.extend(compile_info.analyzers)
        analyzers_csharp.extend(compile_info.analyzers_csharp)
        analyzers_fsharp.extend(compile_info.analyzers_fsharp)
        analyzers_vb.extend(compile_info.analyzers_vb)
        compile_data.extend(compile_info.compile_data)

    # Resolved once here so that every target that does not narrow the pack
    # shares this depset.
    resolved_framework_files = list(framework_files)
    for entry in framework_list.values():
        if entry["file"] != None:
            resolved_framework_files.append(entry["file"])

    return [DotnetTargetingPackInfo(
        assembly_compile_infos = compile_infos,
        assembly_runtime_infos = runtime_infos,
        nuget_infos = nuget_infos,
        targeting_pack_overrides = targeting_pack_overrides,
        framework_list = framework_list,
        framework_files = framework_files,
        framework_files_depset = depset(resolved_framework_files),
        analyzers = analyzers,
        analyzers_csharp = analyzers_csharp,
        analyzers_fsharp = analyzers_fsharp,
        analyzers_vb = analyzers_vb,
        compile_data = compile_data,
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
