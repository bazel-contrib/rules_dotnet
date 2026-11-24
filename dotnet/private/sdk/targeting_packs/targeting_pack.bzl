".Net Targeting Pack"

load("//dotnet/private:common.bzl", "get_nuget_relative_path")
load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "DotnetTargetingPackInfo", "NuGetInfo")
load("//dotnet/private/sdk:framework_list.bzl", "framework_assembly_key", "in_profiles")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _parse_profiles(entries):
    """`pack id:profile` entries as a dict of pack id to its profiles."""
    profiles = {}
    for entry in entries:
        (pack, _, profile) = entry.partition(":")
        profiles.setdefault(pack, []).append(profile)

    return profiles

def _narrow_analyzers(analyzers, nuget_info, profiles):
    """The analyzers of a pack narrowed to the profiles referenced.

    As the SDK's ResolveTargetingPackAssets has it, an analyzer the pack's
    FrameworkList.xml lists is kept only if it belongs to a referenced profile.
    """
    if profiles == None or not nuget_info.framework_list_analyzer_profiles:
        return analyzers

    return [
        analyzer
        for analyzer in analyzers
        if in_profiles(nuget_info.framework_list_analyzer_profiles.get(get_nuget_relative_path(analyzer), ""), profiles)
    ]

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

    profiles_by_pack = _parse_profiles(ctx.attr.profiles)

    # Resolving the FrameworkList to ref files depends only on the pack itself,
    # so do it here rather than in every target that compiles against the pack.
    targeting_pack_overrides = {}
    framework_list = {}

    # The key of the copy of each assembly in `framework_list`, so that of two
    # packs shipping it the newer one wins, as the SDK's conflict resolution has
    # it, rather than whichever is listed last.
    framework_list_keys = {}
    framework_files = []
    analyzers = []
    analyzers_csharp = []
    analyzers_fsharp = []
    analyzers_vb = []
    compile_data = []

    for i, nuget_info in enumerate(nuget_infos):
        compile_info = compile_infos[i]
        profiles = profiles_by_pack.get(compile_info.name)

        # `parse_framework_list` lower cases the assembly names it returns, so
        # index on the same normalisation. First match wins.
        refs_by_name = {}
        for ref in compile_info.refs:
            refs_by_name.setdefault(ref.basename.lower().replace(".dll", ""), ref)

        for override_name, override_version in nuget_info.targeting_pack_overrides.items():
            targeting_pack_overrides[override_name] = override_version

        for dll_name, dll_version in nuget_info.framework_list.items():
            if not in_profiles(nuget_info.framework_list_profiles.get(dll_name, ""), profiles):
                continue

            key = framework_assembly_key(nuget_info, dll_name)
            if dll_name in framework_list_keys and framework_list_keys[dll_name] >= key:
                continue

            framework_list_keys[dll_name] = key
            framework_list[dll_name] = {"version": dll_version, "file": refs_by_name.get(dll_name)}

        if len(nuget_info.framework_list) == 0:
            framework_files.extend(compile_info.irefs)

        analyzers.extend(_narrow_analyzers(compile_info.analyzers, nuget_info, profiles))
        analyzers_csharp.extend(_narrow_analyzers(compile_info.analyzers_csharp, nuget_info, profiles))
        analyzers_fsharp.extend(_narrow_analyzers(compile_info.analyzers_fsharp, nuget_info, profiles))
        analyzers_vb.extend(_narrow_analyzers(compile_info.analyzers_vb, nuget_info, profiles))
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
        "profiles": attr.string_list(
            doc = """The profiles a pack is narrowed to, as `<pack id>:<profile>` entries.

            A pack with none keeps all its reference assemblies and analyzers;
            one with some keeps those its FrameworkList.xml marks for any of
            them, as a FrameworkReference to a profile, such as
            Microsoft.WindowsDesktop.App.WPF, does in the SDK.""",
            default = [],
        ),
        "target_framework": attr.string(
            doc = "The target framework of the targeting pack",
        ),
    },
)
