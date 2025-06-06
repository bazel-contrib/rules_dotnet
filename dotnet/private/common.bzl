"""
Rules for compatability resolution of dependencies for .NET frameworks.
"""

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:shell.bzl", "shell")
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "DotnetDepVariantInfo",
    "DotnetTargetingPackInfo",
    "NuGetInfo",
)
load("//dotnet/private:semver.bzl", "semver")
load("//dotnet/private/sdk:rids.bzl", "RUNTIME_GRAPH")

def _collect_transitive():
    t = {}
    for (framework, compat) in FRAMEWORK_COMPATIBILITY.items():
        # the transitive closure of compatible frameworks
        t[framework] = sets.union(sets.make([framework]), *[t[c] for c in compat])
    return t

DEFAULT_TFM = "net9.0"
DEFAULT_RID = "base"

# A dict of target frameworks to the set of other framworks it can compile
# against. This relationship is transitive. The order of this dictionary also
# matters. netstandard should appear first, and keys within a family should
# proceed from oldest to newest
FRAMEWORK_COMPATIBILITY = {
    # .NET Standard
    "netstandard": [],
    "netstandard1.0": ["netstandard"],
    "netstandard1.1": ["netstandard1.0"],
    "netstandard1.2": ["netstandard1.1"],
    "netstandard1.3": ["netstandard1.2"],
    "netstandard1.4": ["netstandard1.3"],
    "netstandard1.5": ["netstandard1.4"],
    "netstandard1.6": ["netstandard1.5"],
    "netstandard2.0": ["netstandard1.6"],
    "netstandard2.1": ["netstandard2.0"],

    # .NET Framework
    "net11": [],
    "net20": ["net11"],
    "net30": ["net20"],
    "net35": ["net30"],
    "net40": ["net35"],
    "net403": ["net40"],
    "net45": ["net403", "netstandard1.1"],
    "net451": ["net45", "netstandard1.2"],
    "net452": ["net451"],
    "net46": ["net452", "netstandard1.3"],
    "net461": ["net46", "netstandard2.0"],
    "net462": ["net461"],
    "net47": ["net462"],
    "net471": ["net47"],
    "net472": ["net471"],
    "net48": ["net472"],
    "net481": ["net48"],

    # .NET Core
    "netcoreapp1.0": ["netstandard1.6"],
    "netcoreapp1.1": ["netcoreapp1.0"],
    "netcoreapp2.0": ["netcoreapp1.1", "netstandard2.0"],
    "netcoreapp2.1": ["netcoreapp2.0"],
    "netcoreapp2.2": ["netcoreapp2.1"],
    "netcoreapp3.0": ["netcoreapp2.2", "netstandard2.1"],
    "netcoreapp3.1": ["netcoreapp3.0"],
    "net5.0": ["netcoreapp3.1"],
    "net6.0": ["net5.0"],
    "net7.0": ["net6.0"],
    "net8.0": ["net7.0"],
    "net9.0": ["net8.0"],
}

_subsystem_version = {
    "netstandard": None,
    "netstandard1.0": None,
    "netstandard1.1": None,
    "netstandard1.2": None,
    "netstandard1.3": None,
    "netstandard1.4": None,
    "netstandard1.5": None,
    "netstandard1.6": None,
    "netstandard2.0": None,
    "netstandard2.1": None,
    "net11": None,
    "net20": None,
    "net30": None,
    "net35": None,
    "net40": None,
    "net403": None,
    "net45": "6.00",
    "net451": "6.00",
    "net452": "6.00",
    "net46": "6.00",
    "net461": "6.00",
    "net462": "6.00",
    "net47": "6.00",
    "net471": "6.00",
    "net472": "6.00",
    "net48": "6.00",
    "net481": "6.00",
    "netcoreapp1.0": None,
    "netcoreapp1.1": None,
    "netcoreapp2.0": None,
    "netcoreapp2.1": None,
    "netcoreapp2.2": None,
    "netcoreapp3.0": None,
    "netcoreapp3.1": None,
    "net5.0": None,
    "net6.0": None,
    "net7.0": None,
    "net8.0": None,
    "net9.0": None,
}

_default_lang_version_csharp = {
    "netstandard": "7.3",
    "netstandard1.0": "7.3",
    "netstandard1.1": "7.3",
    "netstandard1.2": "7.3",
    "netstandard1.3": "7.3",
    "netstandard1.4": "7.3",
    "netstandard1.5": "7.3",
    "netstandard1.6": "7.3",
    "netstandard2.0": "7.3",
    "netstandard2.1": "7.3",
    "net11": "7.3",
    "net20": "7.3",
    "net30": "7.3",
    "net35": "7.3",
    "net40": "7.3",
    "net403": "7.3",
    "net45": "7.3",
    "net451": "7.3",
    "net452": "7.3",
    "net46": "7.3",
    "net461": "7.3",
    "net462": "7.3",
    "net47": "7.3",
    "net471": "7.3",
    "net472": "7.3",
    "net48": "7.3",
    "net481": "7.3",
    "netcoreapp1.0": "7.3",
    "netcoreapp1.1": "7.3",
    "netcoreapp2.0": "7.3",
    "netcoreapp2.1": "7.3",
    "netcoreapp2.2": "7.3",
    "netcoreapp3.0": "8.0",
    "netcoreapp3.1": "8.0",
    "net5.0": "9.0",
    "net6.0": "10.0",
    "net7.0": "11.0",
    "net8.0": "12.0",
    "net9.0": "13.0",
}

_net = FRAMEWORK_COMPATIBILITY.keys().index("net11")
_cor = FRAMEWORK_COMPATIBILITY.keys().index("netcoreapp1.0")
STD_FRAMEWORKS = FRAMEWORK_COMPATIBILITY.keys()[:_net]
NET_FRAMEWORKS = FRAMEWORK_COMPATIBILITY.keys()[_net:_cor]
COR_FRAMEWORKS = FRAMEWORK_COMPATIBILITY.keys()[_cor:]
TRANSITIVE_FRAMEWORK_COMPATIBILITY = _collect_transitive()

def tfm_to_semver(tfm):
    """Converts a target framework moniker to a semver version.

    Args:
        tfm: The target framework moniker
    Returns:
        The semver version
    """
    if tfm.startswith("netstandard"):
        return "{}.0".format(tfm.replace("netstandard", ""))
    elif tfm.startswith("netcoreapp"):
        return "{}.0".format(tfm.replace("netcoreapp", ""))
    elif tfm.startswith("net"):
        return "{}.0".format(tfm.replace("net", ""))
    else:
        fail("Could not get tfm semver version: {}", tfm)

def is_debug(ctx):
    return ctx.var["COMPILATION_MODE"] == "dbg" or ctx.var["COMPILATION_MODE"] == "fastbuild"

def use_highentropyva(tfm):
    return tfm not in ["net20", "net40"]

def is_standard_framework(tfm):
    return tfm.startswith("netstandard")

def is_core_framework(tfm):
    # TODO: Make this work with future versions
    return tfm.startswith("netcoreapp") or tfm.startswith("net5.0") or tfm.startswith("net6.0") or tfm.startswith("net7.0") or tfm.startswith("net8.0") or tfm.startswith("net9.0")

def is_greater_or_equal_framework(tfm1, tfm2):
    """Returns true if tfm1 is greater or equal to tfm2

    Args:
      tfm1: The first framework
      tfm2: The second framework
    Returns:
        True if tfm1 is greater or equal to tfm2
    """
    keys = list(FRAMEWORK_COMPATIBILITY.keys())
    if keys.index(tfm1) >= keys.index(tfm2):
        return True
    return False

def _format_ref_with_overrides(assembly):
    return "-r:" + assembly.path

def format_ref_arg(args, refs):
    """Takes

    Args:
        args: The args object that will be sent into the compilation action
        refs: List of all references that are being sent into the compilation action
    Returns:
        The updated args object
    """

    args.add_all(refs, map_each = _format_ref_with_overrides)

    return args

def _find_ref_by_file_name(refs, file_name):
    for ref in refs:
        if ref.basename.lower().replace(".dll", "") == file_name.lower():
            return ref

    return None

def collect_compile_info(name, deps, targeting_pack, exports, strict_deps):
    """Determine the transitive dependencies by the target framework.

    Args:
        name: The name of the assembly that is being compiled.
        deps: Dependencies that the compilation target depends on.
        targeting_pack: Targeting pack that the compilation target depends on.
        exports: Exported targets
        strict_deps: Whether or not to use strict dependencies.

    Returns:
        A collection of the references, analyzers and runfiles.
    """
    direct_iref = []
    direct_ref = []
    transitive_ref = []
    direct_compile_data = []
    transitive_compile_data = []
    direct_analyzers = []
    direct_analyzers_csharp = []
    direct_analyzers_fsharp = []
    direct_analyzers_vb = []
    transitive_analyzers = []
    transitive_analyzers_csharp = []
    transitive_analyzers_fsharp = []
    transitive_analyzers_vb = []

    exports_files = []

    targeting_pack_overrides = {}
    framework_list = {}
    framework_files = []

    if targeting_pack:
        targeting_pack_info = targeting_pack[DotnetTargetingPackInfo]
        for i, nuget_info in enumerate(targeting_pack_info.nuget_infos):
            compile_info = targeting_pack_info.assembly_compile_infos[i]

            for override_name, override_version in nuget_info.targeting_pack_overrides.items():
                targeting_pack_overrides[override_name] = override_version

            for dll_name, dll_version in nuget_info.framework_list.items():
                framework_list[dll_name] = {"version": dll_version, "file": _find_ref_by_file_name(compile_info.refs, dll_name)}

            if len(nuget_info.framework_list) == 0:
                framework_files.extend(compile_info.irefs)

            direct_analyzers.extend(compile_info.analyzers)
            direct_analyzers_csharp.extend(compile_info.analyzers_csharp)
            direct_analyzers_fsharp.extend(compile_info.analyzers_fsharp)
            direct_analyzers_vb.extend(compile_info.analyzers_vb)
            direct_compile_data.extend(compile_info.compile_data)

    for dep in deps:
        assembly = dep[DotnetAssemblyCompileInfo]

        add_to_output = True
        if assembly.name.lower() in targeting_pack_overrides:
            if semver.to_comparable(assembly.version) > semver.to_comparable(targeting_pack_overrides[assembly.name.lower()], relaxed = True):
                framework_list.pop(assembly.name.lower())
                add_to_output = True
            else:
                add_to_output = False
        elif assembly.name.lower() in framework_list:
            if semver.to_comparable(assembly.version) > semver.to_comparable(framework_list[assembly.name.lower()].get("version"), relaxed = True):
                framework_list.pop(assembly.name.lower())
                add_to_output = True
            else:
                add_to_output = False

        if add_to_output:
            direct_iref.extend(assembly.irefs if name in assembly.internals_visible_to else assembly.refs)
            direct_ref.extend(assembly.refs)
            direct_analyzers.extend(assembly.analyzers)
            direct_analyzers_csharp.extend(assembly.analyzers_csharp)
            direct_analyzers_fsharp.extend(assembly.analyzers_fsharp)
            direct_analyzers_vb.extend(assembly.analyzers_vb)
            direct_compile_data.extend(assembly.compile_data)

        # We take all the exports of each dependency and add them
        # to the direct refs.
        direct_iref.extend(assembly.exports)

        # This is not a complete solution since we are not comparing assembly versions
        # Transitive dependency resolution is very complicated.
        if not strict_deps:
            for transitive_assembly in assembly.transitive_refs.to_list():
                add_to_output = True
                if transitive_assembly.basename.replace(".dll", "").lower() in targeting_pack_overrides:
                    add_to_output = False
                elif transitive_assembly.basename.replace(".dll", "").lower() in framework_list:
                    add_to_output = False
                if add_to_output:
                    transitive_ref.append(transitive_assembly)
            transitive_analyzers.append(assembly.transitive_analyzers)
            transitive_analyzers_csharp.append(assembly.transitive_analyzers_csharp)
            transitive_analyzers_fsharp.append(assembly.transitive_analyzers_fsharp)
            transitive_analyzers_vb.append(assembly.transitive_analyzers_vb)
            transitive_compile_data.append(assembly.transitive_compile_data)

    for file in framework_list.values():
        if file["file"] != None:
            framework_files.append(file["file"])

    for export in exports:
        assembly = export[DotnetAssemblyCompileInfo]
        exports_files.extend(assembly.refs)

    return (
        depset(direct = direct_iref, transitive = [depset(transitive_ref)]),
        depset(direct = direct_ref, transitive = [depset(transitive_ref)]),
        depset(direct = direct_analyzers, transitive = transitive_analyzers),
        depset(direct = direct_analyzers_csharp, transitive = transitive_analyzers_csharp),
        depset(direct = direct_analyzers_fsharp, transitive = transitive_analyzers_fsharp),
        depset(direct = direct_analyzers_vb, transitive = transitive_analyzers_vb),
        depset(direct = direct_compile_data, transitive = transitive_compile_data),
        framework_files,
        exports_files,
    )

def collect_transitive_runfiles(ctx, assembly_runtime_info, deps):
    """Collect the transitive runfiles of target and its dependencies.

    Args:
        ctx: The rule context.
        assembly_runtime_info: The DotnetAssemblyRuntimeInfo provider for the target.
        deps: Dependencies of the target.

    Returns:
        A runfiles object that includes the transitive dependencies of the target
    """
    runfiles = ctx.runfiles(files = assembly_runtime_info.data + assembly_runtime_info.native + assembly_runtime_info.xml_docs + assembly_runtime_info.libs + assembly_runtime_info.resource_assemblies)

    transitive_runfiles = []
    for dep in deps:
        transitive_runfiles.append(dep[DefaultInfo].default_runfiles)

    for d in ctx.attr.data:
        if not DefaultInfo in d:
            continue
        runfiles = runfiles.merge(d[DefaultInfo].default_runfiles)

    return runfiles.merge_all(transitive_runfiles)

def get_framework_version_info(tfm):
    return (
        _subsystem_version[tfm],
        _default_lang_version_csharp[tfm],
    )

def get_highest_compatible_target_framework(incoming_tfm, tfms):
    """Returns the highest compatible framework version for the incoming_tfm.

    Args:
      incoming_tfm: The target framework of the incoming binary
      tfms: A list of target frameworks
    Returns:
        The highest compatible framework version
    """
    if incoming_tfm in tfms:
        return incoming_tfm

    if FRAMEWORK_COMPATIBILITY[incoming_tfm] == None:
        fail("Target framework moniker is not supported/valid: {}", incoming_tfm)

    incoming_tfm_index = FRAMEWORK_COMPATIBILITY.keys().index(incoming_tfm)
    for tfm in reversed(FRAMEWORK_COMPATIBILITY.keys()[:incoming_tfm_index]):
        if tfm in tfms:
            return tfm

    return None

def get_highest_compatible_runtime_identifier(incoming_rid, rids):
    """Returns the highest compatible runtime identifier for the incoming_rid.

    Args:
      incoming_rid: The runtime identifier to compare to
      rids: A list of runtime identifiers to choose from
    Returns:
        The highest compatible runtime identifier
    """
    if incoming_rid in rids:
        return incoming_rid

    compatible_rids = RUNTIME_GRAPH.get(incoming_rid)
    if compatible_rids == None:
        return None

    for compatible_rid in compatible_rids:
        if compatible_rid in rids:
            return compatible_rid

    return None

def get_nuget_relative_path(file):
    """Returns NuGet package relative path of a file that is part of a NuGet package

    Args:
        file: A file that is part of a nuget_archive/nuget_repo.

    Returns:
        The package relateive path of the file
    """

    # The path of the files is of the form external/<packagename>.v<version>/<path within nuget package>
    # So we remove the first two parts of the path to get the path within the nuget package.
    return "/".join(file.path.split("/")[2:])

def transform_deps(deps):
    """Transforms a [Target] into [DotnetDepVariantInfo].

    This helper function is used to transform ctx.attr.deps into
    [DotnetDepVariantInfo].
    Args:
        deps (list of Targets): Dependencies coming from ctx.attr.deps
    Returns:
        list of DotnetDepVariantInfos.
    """
    return [DotnetDepVariantInfo(
        label = dep.label,
        assembly_runtime_info = dep[DotnetAssemblyRuntimeInfo] if DotnetAssemblyRuntimeInfo in dep else None,
        nuget_info = dep[NuGetInfo] if NuGetInfo in dep else None,
    ) for dep in deps]

def generate_warning_args(
        args,
        treat_warnings_as_errors,
        warnings_as_errors,
        warnings_not_as_errors,
        warning_level,
        nowarn):
    """Generates the compiler arguments for warnings and errors

    Args:
        args: The args object that will be passed to the compilation action
        treat_warnings_as_errors: If all warnigns should be treated as errors
        warnings_as_errors: List of warnings that should be treated as errors
        warnings_not_as_errors: List of warnings that should not be treated as errors
        warning_level: The warning level to use
        nowarn: List of warnings to suppress
    """
    if treat_warnings_as_errors:
        if len(warnings_as_errors) > 0:
            fail("Cannot use both treat_warnings_as_errors and warnings_as_errors")

        args.add("/warnaserror+")

        for warning in warnings_not_as_errors:
            args.add("/warnaserror-:{}".format(warning))

    else:
        if len(warnings_not_as_errors) > 0:
            fail("Cannot use warnings_not_as_errors if treat_warnings_as_errors is not set")
        for warning in warnings_as_errors:
            args.add("/warnaserror+:{}".format(warning))

    args.add("/warn:{}".format(warning_level))

    if len(nowarn) > 0:
        args.add("/nowarn:{}".format(",".join(nowarn)))

def framework_preprocessor_symbols(tfm):
    """Gets the standard preprocessor symbols for the target framework.

    See https://docs.microsoft.com/en-us/dotnet/csharp/language-reference/preprocessor-directives/preprocessor-if#remarks
    for the official list.

    Args:
        tfm: The target framework moniker target being built.
    Returns:
        A list of preprocessor symbols.
    """

    defines = [tfm.upper().replace(".", "_")] + [
        # net8.0 -> NET8_0_OR_GREATER
        # net461 -> NET461_OR_GREATER
        framework.upper().replace(".", "_") + "_OR_GREATER"
        for framework in sets.to_list(TRANSITIVE_FRAMEWORK_COMPATIBILITY[tfm])
    ]

    if tfm.startswith("netstandard"):
        defines.append("NETSTANDARD")
    elif tfm.startswith("netcoreapp"):
        defines.append("NETCOREAPP")
    elif tfm.startswith("net4"):
        defines.append("NETFRAMEWORK")
    elif tfm.startswith("net"):
        defines.append("NET")

    return defines

def _get_resource_assembly_locale(file):
    """Gets the locale of a resource assembly file.

    The locale is the path fragment before the file name:
    e.g. <TFM>/<locale>/assembly.resources.dll

    Args:
        file: The resource assembly file.
    Returns:
        The locale of the resource assembly file.
    """
    return file.dirname.split("/")[-1]

# For deps.json spec see: https://github.com/dotnet/sdk/blob/main/documentation/specs/runtime-configuration-file.md
def generate_depsjson(
        ctx,
        target_framework,
        is_self_contained,
        target_assembly_runtime_info,
        transitive_runtime_deps,
        runtime_pack_info = None,
        use_relative_paths = False):
    """Generates a deps.json file.

    Args:
        ctx: The ctx object
        target_framework: The target framework moniker for the target being built.
        is_self_contained: If the target is a self-contained publish.
        target_assembly_runtime_info: The DotnetAssemblyRuntimeInfo provider for the target being built.
        transitive_runtime_deps: List of DotnetAssemblyRuntimeInfo providers which are the transitive runtime dependencies of the target.
        runtime_pack_info: The DotnetRuntimePackInfo of the runtime pack that is used for a self contained publish.
        use_relative_paths: If the paths to the dependencies should be relative to the workspace root.
    Returns:
        The deps.json file as a struct.
    """
    version = "{}/{}".format(tfm_to_semver(target_framework), runtime_pack_info.runtime_identifier) if is_self_contained else "{}".format(tfm_to_semver(target_framework))
    runtime_target = ".NETCoreApp,Version=v{}".format(version)

    # DLLs that are overidden by the runtime pack due to the runtime pack having a higher version than the user provided dependency.
    runtime_pack_overrides = []

    # User provided dependencies that provide same DLLs as the runtime pack, but with a higher version.
    dep_overrides = []

    base = {
        "runtimeTarget": {
            "name": runtime_target,
            "signature": "",
        },
        "compilationOptions": {},
        "targets": {
        },
    }
    base["targets"][runtime_target] = {}
    base["libraries"] = {}

    if is_self_contained:
        # We need to filter out the runtime DLLs that are provided by the end user as a normal dependency
        # We only filter the DLL out if the user provided dependency has a higher version than the runtime pack.
        # This is the same behavior as in MSBuild. We only need to do this for self-contained binaries.
        runtime_dlls = [
            lib.basename.lower().replace(".dll", "")
            for assembly_runtime_info in runtime_pack_info.assembly_runtime_infos
            for lib in assembly_runtime_info.libs
        ]
        deps = [dep for dep in transitive_runtime_deps if dep.name.lower() in runtime_dlls]
        for dep in deps:
            # We can use the first assembly_runtime_info since all assembly_runtime_infos since all assembly_runtime_infos will
            # have the same version for the same runtime pack.
            if semver.to_comparable(dep.version) > semver.to_comparable(runtime_pack_info.assembly_runtime_infos[0].version, relaxed = True):
                dep_overrides.append(dep.name.lower())
            else:
                runtime_pack_overrides.append(dep.name.lower())

        for assembly_runtime_info in runtime_pack_info.assembly_runtime_infos:
            runtime_pack_name = "runtimepack.{}/{}".format(assembly_runtime_info.name, assembly_runtime_info.version)
            base["libraries"][runtime_pack_name] = {
                "type": "runtimepack",
                "serviceable": False,
                "sha512": "",
            }
            base["targets"][runtime_target][runtime_pack_name] = {
                "runtime": {dll.basename: {} for dll in assembly_runtime_info.libs if dll.basename.lower().replace(".dll", "") not in dep_overrides},
                "native": {native_file.basename: {} for native_file in assembly_runtime_info.native},
            }

        base["runtimes"] = {rid: RUNTIME_GRAPH[rid] for rid, supported_rids in RUNTIME_GRAPH.items() if runtime_pack_info.runtime_identifier in supported_rids or runtime_pack_info.runtime_identifier == rid}

    for runtime_dep in [target_assembly_runtime_info] + transitive_runtime_deps:
        library_name = "{}/{}".format(runtime_dep.name, runtime_dep.version)

        # We need to make sure that we do not include multiple versions of the same first party dll
        # in the deps.json. Using the default ordering of depsets we can be sure that the first instance
        # of a package is the one that is most compatible with the rest of the tree since our transitions
        # make it so that you can't depend on incompatible packages
        if library_name in base["libraries"]:
            continue

        library_fragment = {
            "type": "project",
            "serviceable": False,
            "sha512": "",
        }
        if use_relative_paths:
            library_fragment["path"] = "./"

        if runtime_dep.nuget_info and not use_relative_paths:
            library_fragment["type"] = "package"
            library_fragment["serviceable"] = True
            library_fragment["sha512"] = runtime_dep.nuget_info.sha512
            library_fragment["path"] = library_name.lower()
            library_fragment["hashPath"] = "{}.{}.nupkg.sha512".format(runtime_dep.name.lower(), runtime_dep.version)

        target_fragment = {
            "dependencies": runtime_dep.direct_deps_depsjson_fragment,
        }

        # Do not add the `runtime` and `native` sections if the runtime pack overrides the dependency.
        if runtime_dep.name.lower() not in runtime_pack_overrides:
            target_fragment["runtime"] = {(dll.basename if not use_relative_paths else to_rlocation_path(ctx, dll)): {
                "assemblyVersion": runtime_dep.version + ".0",
            } for dll in runtime_dep.libs}
            target_fragment["native"] = {native_file.basename if not use_relative_paths else to_rlocation_path(ctx, native_file): {} for native_file in runtime_dep.native}

            target_fragment["resources"] = {(resource_assembly.basename if not use_relative_paths else to_rlocation_path(ctx, resource_assembly)): {
                "locale": _get_resource_assembly_locale(resource_assembly),
            } for resource_assembly in runtime_dep.resource_assemblies}

        base["libraries"][library_name] = library_fragment
        base["targets"][runtime_target][library_name] = target_fragment

    return base

# For runtimeconfig.json spec see https://github.com/dotnet/sdk/blob/main/documentation/specs/runtime-configuration-file.md
def generate_runtimeconfig(target_framework, project_sdk, is_self_contained, roll_forward_behavior, runtime_pack_info = None):
    """Generates a runtimeconfig.json file.

    Args:
        target_framework: The target framework moniker for the target being built.
        project_sdk: The project SDK that is being used
        is_self_contained: If the target is a self-contained publish.
        roll_forward_behavior: The roll forward behavior to use.
        runtime_pack_info: The DotnetRuntimePackInfo of the runtime pack that is used for a self contained publish.
    Returns:
        The runtimeconfig.json file as a struct.
    """

    base = {
        "runtimeOptions": {
            "tfm": target_framework,
            "rollForward": roll_forward_behavior,
        },
    }

    if is_self_contained:
        frameworks = []
        for assembly_runtime_info in runtime_pack_info.assembly_runtime_infos:
            frameworks.append({"name": assembly_runtime_info.name, "version": assembly_runtime_info.version})
        base["runtimeOptions"]["includedFrameworks"] = frameworks
    else:
        runtime_version = tfm_to_semver(target_framework)
        frameworks = [
            {"name": "Microsoft.NETCore.App", "version": runtime_version},
        ]
        if project_sdk == "web":
            frameworks.append({"name": "Microsoft.AspNetCore.App", "version": runtime_version})

        base["runtimeOptions"]["frameworks"] = frameworks
    return base

def to_rlocation_path(ctx, file):
    """The rlocation path for a `File`

    This produces the same value as the `rlocationpath` predefined source/output path variable.

    From https://bazel.build/reference/be/make-variables#predefined_genrule_variables:

    > `rlocationpath`: The path a built binary can pass to the `Rlocation` function of a runfiles
    > library to find a dependency at runtime, either in the runfiles directory (if available)
    > or using the runfiles manifest.

    > This is similar to root path (a.k.a. [short_path](https://bazel.build/rules/lib/File#short_path))
    > in that it does not contain configuration prefixes, but differs in that it always starts with the
    > name of the repository.

    > The rlocation path of a `File` in an external repository repo will start with `repo/`, followed by the
    > repository-relative path.

    > Passing this path to a binary and resolving it to a file system path using the runfiles libraries
    > is the preferred approach to find dependencies at runtime. Compared to root path, it has the
    > advantage that it works on all platforms and even if the runfiles directory is not available.

    Args:
        ctx: starlark rule execution context
        file: a `File` object

    Returns:
        The rlocationpath for the `File`
    """
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def copy_files_to_dir(target_name, actions, is_windows, files, out_dir):
    """Copies files to a specific location.

    Args:
        target_name: The name of the executing target
        actions: The actions object
        is_windows: If the OS is Windows
        files: The files to copy
        out_dir: The directory to copy the files to

    Returns:
        A list of the copied files in the out_dir
    """

    script_body = ["@echo off"] if is_windows else ["#! /usr/bin/env bash", "set -eou pipefail"]

    inputs = []
    outputs = []
    for src in files:
        dst = actions.declare_file("%s/%s" % (out_dir, src.basename))
        inputs.append(src)
        outputs.append(dst)
        if is_windows:
            script_body.append("if not exist \"{dir}\" @mkdir \"{dir}\" >NUL".format(dir = dst.dirname.replace("/", "\\")))
            script_body.append("@copy /Y \"{src}\" \"{dst}\" >NUL".format(src = src.path.replace("/", "\\"), dst = dst.path.replace("/", "\\")))
        else:
            script_body.append("mkdir -p {dir} && cp -f {src} {dst}".format(dir = shell.quote(dst.dirname), src = shell.quote(src.path), dst = shell.quote(dst.path)))

    if len(outputs) > 0:
        copy_script = actions.declare_file(target_name + ".copy.bat" if is_windows else target_name + ".copy.sh")
        actions.write(
            output = copy_script,
            content = "\r\n".join(script_body) if is_windows else "\n".join(script_body),
            is_executable = True,
        )
        actions.run(
            outputs = outputs,
            inputs = inputs,
            executable = copy_script,
            tools = [copy_script],
        )
    return outputs

_RESOURCE_TEMPLATE_CSHARP = "/resource:{}"
_RESOURCE_TEMPLATE_FSHARP = "--resource:{}"

def map_resource_arg(file, target_label, out_dll, language):
    """Map an embedded resource file to a resource argument for the compiler.

    Args:
        file: (File) The file to embed.
        target_label: (Label) The label of the target that is embedding the resource.
        out_dll: (str) The output dll file, if one exists.
        language: (str) The language of the target that is embedding the resource. Possible values are "csharp" or "fsharp".

    Returns:
        The resource argument to pass to the compiler.
    """
    if language == "csharp":
        base_resource_fmt = _RESOURCE_TEMPLATE_CSHARP
    elif language == "fsharp":
        base_resource_fmt = _RESOURCE_TEMPLATE_FSHARP
    else:
        fail("Unsupported language: {}", language)

    base_resource_arg = base_resource_fmt.format(file.path)

    # We can only determine the embedded resource's name if we have a DLL to embed it in.
    if out_dll == None or not out_dll.endswith(".dll"):
        return base_resource_arg

    # When the file is not within a project directory, MSBuild falls back to
    # the basename of the file.
    simple_resource_name = "{}.{}".format(out_dll[:-4], file.basename)

    if file.owner != None and file.owner.repo_name != target_label.repo_name:
        # Fallback to the basename if the file comes from a different repository.
        resource_name = simple_resource_name
    if not file.short_path.startswith(target_label.package):
        # Fallback to the basename if the file is not in the target's package, because
        # the path will not be normalized.
        resource_name = simple_resource_name
    else:
        # Packages/Foo.Bar/BUILD.bazel importing Packages/Foo.Bar/a/b/c.txt -> a/b/c.txt
        relative_path = file.short_path[len(target_label.package) + 1:]

        # Foo.Bar.dll and a/b/c.txt -> Foo.Bar.a.b.c.txt
        parts = relative_path.split("/")
        resource_name = "{}.{}".format(out_dll[:-4], ".".join(parts))

    return base_resource_arg + "," + resource_name
