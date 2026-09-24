"""
Rules for compatability resolution of dependencies for .NET frameworks.
"""

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "DotnetDepVariantInfo",
    "DotnetTargetingPackInfo",
    "NuGetInfo",
)
load("//dotnet/private:semver.bzl", "semver")
load(
    "//dotnet/private/sdk:frameworks.bzl",
    "SDK_LANG_VERSIONS",
    "SDK_NETCOREAPP_FRAMEWORKS",
    "SDK_NETFRAMEWORK_FRAMEWORKS",
    "SDK_NETSTANDARD_FRAMEWORKS",
    _DEFAULT_TARGET_FRAMEWORK = "DEFAULT_TARGET_FRAMEWORK",
    _FRAMEWORK_COMPATIBILITY = "FRAMEWORK_COMPATIBILITY",
)
load("//dotnet/private/sdk:packs.bzl", "WEB_SDK", "normalize_project_sdk")
load("//dotnet/private/sdk:rids.bzl", "RUNTIME_GRAPH")

def _collect_transitive():
    t = {}
    for (framework, compat) in FRAMEWORK_COMPATIBILITY.items():
        # the transitive closure of compatible frameworks
        t[framework] = sets.union(sets.make([framework]), *[t[c] for c in compat])
    return t

# Generated; see dotnet/private/sdk/frameworks.bzl.
DEFAULT_TFM = _DEFAULT_TARGET_FRAMEWORK
DEFAULT_RID = "base"

# Re-exported so the many modules that read it keep loading it from here.
FRAMEWORK_COMPATIBILITY = _FRAMEWORK_COMPATIBILITY

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
    "net10.0": None,
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
    return _tfm_family(tfm) == _NETSTANDARD

def is_core_framework(tfm):
    return _tfm_family(tfm) == _NETCOREAPP

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

# The first SDK that gives an F# reference assembly a deterministic MVID.
# https://github.com/dotnet/fsharp/pull/19801
_DETERMINISTIC_FSHARP_REF_ASSEMBLY_SDK = "10.0.400"

def fsharp_ref_assemblies_are_deterministic(sdk_version):
    """Whether this SDK's F# reference assemblies are worth producing.

    Args:
        sdk_version: The version of the .Net SDK, as `DotnetInfo.sdk_version`.

    Returns:
        True if `--refout` output is deterministic on this SDK.
    """
    return semver.to_comparable(sdk_version, relaxed = True) >= \
           semver.to_comparable(_DETERMINISTIC_FSHARP_REF_ASSEMBLY_SDK, relaxed = True)

def get_toolchain(ctx):
    """The .Net toolchain a target compiles with.

    Args:
        ctx: The rule context.

    Returns:
        The `ToolchainInfo` of the resolved .Net toolchain.
    """

    return ctx.toolchains["//dotnet:toolchain_type"]

def targets_windows(ctx):
    """Whether the target platform is Windows.

    Args:
        ctx: The rule context.

    Returns:
        True if the target platform is Windows.
    """

    return ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])

def get_compiler_wrapper(ctx):
    """The script that invokes the compiler with an execution time pathmap.

    Args:
        ctx: The rule context.

    Returns:
        The wrapper script for the target platform.
    """

    return ctx.executable._compiler_wrapper_bat if targets_windows(ctx) else ctx.executable._compiler_wrapper_sh

def _worker_executable(worker):
    files_to_run = worker[DefaultInfo].files_to_run

    return files_to_run if files_to_run.executable != None else None

def get_csharp_compiler_worker(ctx):
    """The persistent worker to compile C# with, if it is enabled and usable.

    Args:
        ctx: The rule context.

    Returns:
        A struct with an `executable` and a `prune_unused_references` flag, or
        None when the compile should use the wrapper script instead.
    """

    prune_unused_references = ctx.attr._prune_unused_references[BuildSettingInfo].value

    # compiler_worker_binary drops the attribute: the workers are the targets
    # that cannot be compiled by the worker.
    if not hasattr(ctx.attr, "_csharp_compiler_worker"):
        return None

    executable = _worker_executable(ctx.attr._csharp_compiler_worker)

    if executable == None:
        if prune_unused_references:
            fail("//dotnet/settings:prune_unused_references needs //dotnet/settings:use_compiler_worker, " +
                 "because it is the worker that reads the compiled output to work out which references went unused.")
        return None

    return struct(
        executable = executable,
        prune_unused_references = prune_unused_references,
    )

def get_fsharp_compiler_worker(ctx):
    """The persistent worker to compile F# with, if it is enabled.

    Args:
        ctx: The rule context.

    Returns:
        The worker's `FilesToRunProvider`, or None when the compile should use
        the wrapper script instead.
    """

    return _worker_executable(ctx.attr._fsharp_compiler_worker)

def _format_ref_with_overrides(assembly):
    # See https://github.com/bazel-contrib/rules_dotnet/issues/405
    # The following files should not be passed as references to the compiler
    if assembly.path.endswith("System.EnterpriseServices.Thunk.dll") or assembly.path.endswith("System.EnterpriseServices.Wrapper.dll"):
        return None
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

def _resolve_analyzers(direct, transitive):
    """Keeps one analyzer per file name, the way MSBuild resolves the same conflict.

    An analyzer handed to the compiler twice runs twice and emits its generated
    types twice, which fails the compilation. The same analyzer arrives twice
    whenever it ships both in a targeting pack and in a NuGet package that the
    target depends on.

    Args:
        direct: The target's own analyzers, in precedence order.
        transitive: Depsets of the dependencies' transitive analyzers, which lose
            to everything in `direct`, mirroring how the targeting pack's
            reference assemblies beat the closure's. Empty under strict deps.

    Returns:
        A depset of analyzers, no two of which share a file name.
    """
    files = direct if not transitive else direct + depset(transitive = transitive).to_list()

    resolved = {}
    for file in files:
        resolved.setdefault(file.basename, file)

    return depset(resolved.values())

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
    transitive_ref_depsets = []
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

    targeting_pack_info = None
    targeting_pack_overrides = {}
    framework_list = {}

    # The pack has already resolved its FrameworkList to ref files. A dependency
    # that supersedes one of them narrows that set, which needs a copy of the
    # pack's dict; hold the pack's own until that actually happens.
    narrowed = False

    if targeting_pack:
        targeting_pack_info = targeting_pack[DotnetTargetingPackInfo]
        targeting_pack_overrides = targeting_pack_info.targeting_pack_overrides
        framework_list = targeting_pack_info.framework_list

        direct_compile_data.extend(targeting_pack_info.compile_data)

    for dep in deps:
        assembly = dep[DotnetAssemblyCompileInfo]
        dep_name = assembly.name.lower()

        # `targeting_pack_overrides` gives minimum versions for assemblies;
        # `framework_list` gives reference assemblies the pack contributes even
        # when the target does not depend on them explicitly.
        minimum_version = None
        if dep_name in targeting_pack_overrides:
            minimum_version = targeting_pack_overrides[dep_name]
        elif dep_name in framework_list:
            minimum_version = framework_list[dep_name]["version"]

        add_to_output = True
        if minimum_version != None:
            # An explicit dependency newer than the minimum supersedes the pack's
            # own reference assembly, which has to go to avoid a conflict. The
            # pop() is a no-op when `framework_list` never contributed one: not
            # every assembly with a minimum version is in it for every
            # `project_sdk`. System.Security.Cryptography.Xml, for example, has a
            # minimum version for net8.0 but is only contributed by the
            # `project_sdk = "web"` (ASP.NET) framework.
            add_to_output = semver.to_comparable(assembly.version) > semver.to_comparable(minimum_version, relaxed = True)
            if add_to_output:
                if not narrowed:
                    framework_list = dict(framework_list)
                    narrowed = True
                framework_list.pop(dep_name, None)

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
            # The compiler must not be handed an assembly that this target's
            # targeting pack already provides, so filter the closure down to the
            # reference arguments of this compilation.
            for transitive_assembly in assembly.transitive_refs.to_list():
                transitive_name = transitive_assembly.basename.replace(".dll", "").lower()
                if transitive_name not in targeting_pack_overrides and transitive_name not in framework_list:
                    transitive_ref.append(transitive_assembly)

            # The provider keeps the deps' depsets, so every consumer shares one
            # copy of the closure and filters it against its own targeting pack.
            transitive_ref_depsets.append(assembly.transitive_refs)

            transitive_analyzers.append(assembly.transitive_analyzers)
            transitive_analyzers_csharp.append(assembly.transitive_analyzers_csharp)
            transitive_analyzers_fsharp.append(assembly.transitive_analyzers_fsharp)
            transitive_analyzers_vb.append(assembly.transitive_analyzers_vb)
            transitive_compile_data.append(assembly.transitive_compile_data)

    if targeting_pack_info:
        # Last, so a dependency wins a file name clash: it contributes analyzers
        # only once it has superseded the pack's reference assembly, so its
        # analyzer is the one that matches the refs. See `_resolve_analyzers`.
        direct_analyzers.extend(targeting_pack_info.analyzers)
        direct_analyzers_csharp.extend(targeting_pack_info.analyzers_csharp)
        direct_analyzers_fsharp.extend(targeting_pack_info.analyzers_fsharp)
        direct_analyzers_vb.extend(targeting_pack_info.analyzers_vb)

    if not narrowed:
        # Nothing was superseded, so share the depset the pack resolved once.
        framework_files = targeting_pack_info.framework_files_depset if targeting_pack_info else depset()
    else:
        narrowed_files = list(targeting_pack_info.framework_files)
        for file in framework_list.values():
            if file["file"] != None:
                narrowed_files.append(file["file"])
        framework_files = depset(narrowed_files)

    for export in exports:
        assembly = export[DotnetAssemblyCompileInfo]
        exports_files.extend(assembly.refs)

    return (
        # Filtered and flat: the compiler's reference arguments.
        depset(direct = direct_iref, transitive = [depset(transitive_ref)]),
        # Unfiltered and structurally shared: only ever read back out of a provider.
        depset(direct = direct_ref, transitive = transitive_ref_depsets),
        _resolve_analyzers(direct_analyzers, transitive_analyzers),
        _resolve_analyzers(direct_analyzers_csharp, transitive_analyzers_csharp),
        _resolve_analyzers(direct_analyzers_fsharp, transitive_analyzers_fsharp),
        _resolve_analyzers(direct_analyzers_vb, transitive_analyzers_vb),
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

    # XML documentation is a build output, not a runtime input: nothing loads it
    # and a publish does not ship it, so it stays out of the runfiles tree.
    runfiles = ctx.runfiles(files = assembly_runtime_info.data + assembly_runtime_info.native + assembly_runtime_info.libs + assembly_runtime_info.resource_assemblies)

    transitive_runfiles = [dep[DefaultInfo].default_runfiles for dep in deps]
    transitive_runfiles.extend([
        d[DefaultInfo].default_runfiles
        for d in ctx.attr.data
        if DefaultInfo in d
    ])

    return runfiles.merge_all(transitive_runfiles)

def get_framework_version_info(tfm):
    return _subsystem_version[tfm]

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

_NUGET_FRAMEWORK_IDENTIFIERS = {
    ".netcoreapp": "netcoreapp",
    ".netframework": "net",
    ".netstandard": "netstandard",
    "net": "net",
    "netcoreapp": "netcoreapp",
    "netstandard": "netstandard",
}

def nuget_framework_to_tfm(framework):
    """Normalizes a framework name from NuGet package metadata to a TFM.

    `.nuspec` files and framework lists spell frameworks out in full
    (`.NETStandard2.0`, `.NETFramework,Version=v4.7.2`), while the folders
    inside a package and rules_dotnet itself use the short form
    (`netstandard2.0`, `net472`).

    Args:
      framework: The framework name as it appears in package metadata.

    Returns:
      The matching target framework moniker, or None when it is not a
      framework that rules_dotnet supports.
    """
    framework = framework.strip().lower()

    if framework in FRAMEWORK_COMPATIBILITY:
        return framework

    # `.NETFramework,Version=v4.7.2` and `.NETFramework4.7.2` name the same
    # framework; normalize the former into the latter.
    (identifier, separator, version) = framework.partition(",version=v")
    if not separator:
        digit = -1
        for i in range(len(framework)):
            if framework[i].isdigit():
                digit = i
                break

        if digit <= 0:
            return None

        identifier = framework[:digit]
        version = framework[digit:]

    # Portable class library profiles such as `.NETPortable0.0-Profile259`.
    if version.find("-") != -1:
        return None

    identifier = _NUGET_FRAMEWORK_IDENTIFIERS.get(identifier)
    if identifier == None:
        return None

    parts = version.split(".")
    for _ in range(2 - len(parts)):
        parts.append("0")

    # A trailing zero component is not part of a framework's short name, but
    # the major and minor version always are.
    for _ in range(len(parts)):
        if len(parts) > 2 and parts[-1] == "0":
            parts.pop()
        else:
            break

    if not parts[0].isdigit():
        return None

    if identifier == "netcoreapp" and int(parts[0]) >= 5:
        # .NET 5 and later are `.NETCoreApp` in metadata but `netX.Y` in the
        # folder layout.
        tfm = "net" + ".".join(parts[:2])
    elif identifier == "net":
        tfm = "net" + "".join(parts)
    else:
        tfm = identifier + ".".join(parts)

    return tfm if tfm in FRAMEWORK_COMPATIBILITY else None

def tfm_to_nuget_framework(tfm):
    """Spells a TFM the way a `.nuspec` dependency group names it.

    The inverse of `nuget_framework_to_tfm`, and what `dotnet pack` writes:
    `.NETStandard2.0`, `.NETFramework4.7.2`, `.NETCoreApp3.1`, and from .NET 5
    on the moniker itself (`net8.0`). Every value round-trips through
    `nuget_framework_to_tfm`.

    Args:
      tfm: A target framework moniker from `FRAMEWORK_COMPATIBILITY`.

    Returns:
      The framework name for package metadata.
    """
    if tfm not in FRAMEWORK_COMPATIBILITY:
        fail("Target framework moniker is not supported/valid: {}".format(tfm))

    # A bare family name (`netstandard`) has no version to spell out.
    if tfm.isalpha():
        return tfm

    if tfm.startswith("netstandard"):
        return ".NETStandard" + tfm[len("netstandard"):]

    if tfm.startswith("netcoreapp"):
        return ".NETCoreApp" + tfm[len("netcoreapp"):]

    # `net5.0` and later carry their dot already; `net472` is `4.7.2`.
    if "." in tfm:
        return tfm

    return ".NETFramework" + ".".join(tfm[len("net"):].elems())

def get_nearest_compatible_target_framework(incoming_tfm, tfms):
    """Returns the entry of `tfms` that best matches `incoming_tfm`.

    This mirrors how NuGet picks the folder to use out of a package: of the
    frameworks that `incoming_tfm` can consume, the most specific one wins.

    Args:
      incoming_tfm: The target framework being built for.
      tfms: The frameworks to choose from.

    Returns:
      The best match, or None if none of `tfms` is compatible.
    """
    compatible = TRANSITIVE_FRAMEWORK_COMPATIBILITY.get(incoming_tfm)
    if compatible == None:
        fail("Target framework moniker is not supported/valid: {}".format(incoming_tfm))

    # FRAMEWORK_COMPATIBILITY is ordered oldest to newest within a family, so
    # the last compatible entry is the most specific match.
    for tfm in reversed(FRAMEWORK_COMPATIBILITY.keys()):
        if tfm in tfms and sets.contains(compatible, tfm):
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

_NETSTANDARD = "netstandard"
_NETCOREAPP = "netcoreapp"
_NETFRAMEWORK = "netframework"

# SDK-recognised frameworks per family, ascending. Anything absent (net11,
# net403) gets no `*_OR_GREATER` symbol. Generated -- see dotnet/private/sdk/gen.
_SDK_TFMS_BY_FAMILY = {
    _NETCOREAPP: SDK_NETCOREAPP_FRAMEWORKS,
    _NETFRAMEWORK: SDK_NETFRAMEWORK_FRAMEWORKS,
    _NETSTANDARD: SDK_NETSTANDARD_FRAMEWORKS,
}

# .NET 5 is where the netcoreapp family starts spelling its symbols NET*.
_NET5 = [5, 0]

def _tfm_family(tfm):
    """Classifies a target framework moniker into an SDK framework family."""
    if tfm.startswith("netstandard"):
        return _NETSTANDARD
    if tfm.startswith("netcoreapp"):
        return _NETCOREAPP
    if not tfm.startswith("net"):
        return None

    # net5.0+ spells the version with a dot; net48/net481 do not.
    return _NETCOREAPP if "." in tfm else _NETFRAMEWORK

def tfm_version(tfm):
    """A framework's version as a list of ints, for ordering.

    net48 -> [4, 8], net481 -> [4, 8, 1], net10.0 -> [10, 0],
    netstandard2.0 -> [2, 0], bare netstandard -> [].

    Args:
        tfm: The target framework moniker.

    Returns:
        The version as a list of ints.
    """
    digits = tfm
    for prefix in ["netstandard", "netcoreapp", "net"]:
        if tfm.startswith(prefix):
            digits = tfm[len(prefix):]
            break

    if digits == "":
        return []

    if "." in digits:
        return [int(part) for part in digits.split(".")]

    parts = [int(digits[0])]
    if len(digits) > 1:
        parts.append(int(digits[1]))
    if len(digits) > 2:
        parts.append(int(digits[2:]))
    return parts

def _versioned_symbol(family, version):
    """The versioned define for a framework: NETSTANDARD2_0, NET48, NET10_0."""
    if family == _NETSTANDARD:
        prefix = "NETSTANDARD"
    elif family == _NETCOREAPP and version < _NET5:
        prefix = "NETCOREAPP"
    else:
        prefix = "NET"

    # .NET Framework strips the separators; everything else underscores them.
    separator = "" if family == _NETFRAMEWORK else "_"
    return prefix + separator.join([str(part) for part in version])

def _or_greater_symbols(family, tfms):
    """The `_OR_GREATER` symbol each framework in a family contributes."""
    symbols = []
    for candidate in tfms:
        version = tfm_version(candidate)
        symbols.append((version, _versioned_symbol(family, version) + "_OR_GREATER"))
    return symbols

# Every framework in a family walks the whole family, so parse the versions once.
_SDK_OR_GREATER_SYMBOLS = {
    family: _or_greater_symbols(family, tfms)
    for (family, tfms) in _SDK_TFMS_BY_FAMILY.items()
}

def _compute_framework_preprocessor_symbols(tfm):
    """Gets the standard preprocessor symbols for the target framework.

    Reproduces the SDK's GenerateTargetFrameworkDefineConstants and
    GenerateNETCompatibleDefineConstants targets. FRAMEWORK_COMPATIBILITY
    records assignability, so walking it instead would emit symbols the SDK
    never defines.

    See https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/preprocessor-directives#conditional-compilation

    Args:
        tfm: The target framework moniker target being built.
    Returns:
        A list of preprocessor symbols.
    """
    family = _tfm_family(tfm)
    if family == None:
        return []

    version = tfm_version(tfm)
    is_net5_or_greater = family == _NETCOREAPP and version >= _NET5

    # GenerateTargetFrameworkDefineConstants.
    if family == _NETSTANDARD:
        versionless = "NETSTANDARD"
    elif family == _NETFRAMEWORK:
        versionless = "NETFRAMEWORK"
    elif is_net5_or_greater:
        versionless = "NET"
    else:
        versionless = "NETCOREAPP"

    defines = [versionless, _versioned_symbol(family, version)]

    if is_net5_or_greater:
        defines.append("NETCOREAPP")

    # GenerateNETCompatibleDefineConstants.
    for (candidate_version, symbol) in _SDK_OR_GREATER_SYMBOLS[family]:
        if candidate_version <= version:
            defines.append(symbol)

    return defines

def default_csharp_lang_version(tfm, sdk_default):
    """The C# language version the SDK would pick for a target framework.

    The SDK caps LangVersion per target framework -- 7.3 for netstandard2.0 and
    .NET Framework -- because newer language features need runtime support
    those targets lack.

    Args:
        tfm: The target framework moniker being built.
        sdk_default: The newest C# version this SDK supports. Used for
            frameworks the SDK does not recognise, and as a ceiling so we never
            ask for a language version this compiler does not know.
    Returns:
        The language version string to pass to csc.
    """
    selected = SDK_LANG_VERSIONS.get(tfm)
    if selected == None:
        return sdk_default

    if sdk_default == "":
        return selected

    # Never ask for a language version this compiler does not know.
    if semver.to_comparable(selected, relaxed = True) > semver.to_comparable(sdk_default, relaxed = True):
        return sdk_default

    return selected

# Both of these are called once per target per framework during analysis, and
# the input domain is the known framework set, so they are computed once here
# rather than on every call.
_FRAMEWORK_PREPROCESSOR_SYMBOLS = {
    tfm: _compute_framework_preprocessor_symbols(tfm)
    for tfm in FRAMEWORK_COMPATIBILITY
}

def framework_preprocessor_symbols(tfm):
    """The preprocessor symbols the SDK defines for a target framework.

    Args:
        tfm: The target framework moniker being built.

    Returns:
        A list of preprocessor symbols.
    """
    return _FRAMEWORK_PREPROCESSOR_SYMBOLS.get(tfm, _compute_framework_preprocessor_symbols(tfm))

def runtime_target_path(file):
    """The key a native asset takes in the `runtimeTargets` of a deps.json.

    Native assets from a NuGet package live at
    `<prefix>/runtimes/<rid>/<native|lib>/<file>`, and that suffix is both the
    deps.json key and the path the asset takes inside a publish.

    Args:
        file: (File) The native asset.
    Returns:
        The `runtimes/<rid>/<native|lib>/<file>` path.
    """
    parts = file.dirname.split("/")
    return "runtimes/{}/{}/{}".format(parts[-2], parts[-1], file.basename)

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

            target_fragment["resources"] = {(resource_assembly.basename if not use_relative_paths else to_rlocation_path(ctx, resource_assembly)): {
                "locale": _get_resource_assembly_locale(resource_assembly),
            } for resource_assembly in runtime_dep.resource_assemblies}

            # Handling of runtime files
            # If the publish is self-contained we put the native files in the `native` section of the target fragment
            # Otherwise we followe the conventions mentioned here: https://github.com/dotnet/sdk/blob/main/documentation/specs/runtime-configuration-file.md#framework-dependent-deployment-model
            if is_self_contained:
                target_fragment["native"] = {native_file.basename: {"fileVersion": "0.0.0.0"} for native_file in runtime_dep.native}
            elif runtime_dep.nuget_info == None or runtime_dep.nuget_info.nupkg == None:
                # For non self-contained binaries that are not from a NuGet package, assume we built
                # them and point to their relative location within the execroot.
                target_fragment["native"] = {(native_file.basename if not use_relative_paths else to_rlocation_path(ctx, native_file)): {"fileVersion": "0.0.0.0"} for native_file in runtime_dep.native}
            else:
                target_fragment["runtimeTargets"] = {
                    runtime_target_path(native_file): {
                        "rid": native_file.dirname.split("/")[-2],
                        "assetType": "runtime" if native_file.dirname.split("/")[-1] == "lib" else "native",
                    }
                    for native_file in runtime_dep.native
                }

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
        if normalize_project_sdk(project_sdk) == WEB_SDK:
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

def copy_files_to_dir(target_name, actions, is_windows, files, out_dir, executables = []):
    """Copies files to a specific location.

    Args:
        target_name: The name of the executing target
        actions: The actions object
        is_windows: If the OS is Windows
        files: The files to copy
        out_dir: The directory to copy the files to
        executables: Basenames to mark executable. Zip entries carry no Unix
            permissions, so a native tool extracted from a nupkg arrives
            without its bit set. Windows goes by file extension instead.

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

            if src.basename in executables:
                script_body.append("chmod +x {dst}".format(dst = shell.quote(dst.path)))

    if len(outputs) > 0:
        copy_script = actions.declare_file(target_name + ".copy.bat" if is_windows else target_name + ".copy.sh")
        actions.write(
            output = copy_script,
            content = "\r\n".join(script_body) if is_windows else "\n".join(script_body),
            is_executable = True,
        )
        actions.run(
            mnemonic = "DotnetCopyFiles",
            progress_message = "Copying %d file(s) into %s" % (len(outputs), out_dir),
            outputs = outputs,
            inputs = depset(inputs),
            executable = copy_script,
            tools = [copy_script],
        )
    return outputs

_RESOURCE_TEMPLATE_CSHARP = "/resource:%s"
_RESOURCE_TEMPLATE_FSHARP = "--resource:%s"

def add_resource_args(args, resources, target_label, out_dll, language):
    """Adds one resource argument per file to `args`.

    Args:
        args: The Args object for the compilation action.
        resources: The resource files to embed.
        target_label: (Label) The label embedding the resources.
        out_dll: (str) Basename of the output dll, or None for a ref-only compile.
        language: "csharp" or "fsharp".
    """
    for resource in resources:
        args.add(resource, format = _resource_arg_format(resource, target_label, out_dll, language))

def _resource_arg_format(file, target_label, out_dll, language):
    """The Args format string that turns a resource file into a compiler argument.

    A format rather than a finished string, so the file is still added to `args`
    as a `File` and `--experimental_output_paths=strip` can rewrite its path.

    Args:
        file: (File) The file to embed.
        target_label: (Label) The label of the target that is embedding the resource.
        out_dll: (str) The output dll file, if one exists.
        language: (str) The language of the target that is embedding the resource. Possible values are "csharp" or "fsharp".

    Returns:
        A format string with a single `%s` where the file's path goes.
    """
    if language == "csharp":
        base_resource_fmt = _RESOURCE_TEMPLATE_CSHARP
    elif language == "fsharp":
        base_resource_fmt = _RESOURCE_TEMPLATE_FSHARP
    else:
        fail("Unsupported language: {}".format(language))

    # We can only determine the embedded resource's name if we have a DLL to embed it in.
    if out_dll == None or not out_dll.endswith(".dll"):
        return base_resource_fmt

    # When the file is not within a project directory, MSBuild falls back to
    # the basename of the file.
    simple_resource_name = "{}.{}".format(out_dll[:-4], file.basename)

    if file.owner != None and file.owner.repo_name != target_label.repo_name:
        # Fallback to the basename if the file comes from a different repository.
        resource_name = simple_resource_name
    elif not file.short_path.startswith(target_label.package):
        # Fallback to the basename if the file is not in the target's package, because
        # the path will not be normalized.
        resource_name = simple_resource_name
    else:
        # Packages/Foo.Bar/BUILD.bazel importing Packages/Foo.Bar/a/b/c.txt -> a/b/c.txt
        relative_path = file.short_path[len(target_label.package) + 1:]

        # Foo.Bar.dll and a/b/c.txt -> Foo.Bar.a.b.c.txt
        parts = relative_path.split("/")
        resource_name = "{}.{}".format(out_dll[:-4], ".".join(parts))

    # `%` is the escape character in an Args format string, so a resource whose
    # name contains one has to double it to come out literal.
    return base_resource_fmt + "," + resource_name.replace("%", "%%")
