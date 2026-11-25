"""
Helpers shared by the .NET rules: target frameworks, compile inputs, deps.json
and runtimeconfig.json generation, and staging files next to an assembly.
"""

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//dotnet/private:nuget_version.bzl", "nuget_version")
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetTargetingPackInfo",
)
load("//dotnet/private:semver.bzl", "semver")
load(
    "//dotnet/private/sdk:frameworks.bzl",
    "SDK_LANG_VERSIONS",
    "SDK_NETCOREAPP_FRAMEWORKS",
    "SDK_NETFRAMEWORK_FRAMEWORKS",
    "SDK_NETSTANDARD_FRAMEWORKS",
    "WINDOWS_PLATFORM",
    "WINDOWS_PLATFORM_VERSION",
    "base_framework",
    "framework_platform",
    "normalize_platform_framework",
    _DEFAULT_TARGET_FRAMEWORK = "DEFAULT_TARGET_FRAMEWORK",
    _FRAMEWORK_COMPATIBILITY = "FRAMEWORK_COMPATIBILITY",
)
load(
    "//dotnet/private/sdk:packs.bzl",
    "FRAMEWORK_REFERENCES",
    "NETCORE_FRAMEWORK",
    "RUNTIME_PACK_LOOKUP_TABLE",
    "SHARED_FRAMEWORKS",
    "WINDOWS_ONLY_FRAMEWORKS",
    "frameworks_key",
)
load("//dotnet/private/sdk:rids.bzl", "RUNTIME_GRAPH")

def _collect_transitive():
    t = {}
    for (framework, compat) in FRAMEWORK_COMPATIBILITY.items():
        # the transitive closure of compatible frameworks
        t[framework] = sets.union(sets.make([framework]), *[t[c] for c in compat])
    return t

# See dotnet/private/sdk/frameworks.bzl.
DEFAULT_TFM = _DEFAULT_TARGET_FRAMEWORK
DEFAULT_RID = "base"

# Re-exported so the many modules that read it keep loading it from here.
FRAMEWORK_COMPATIBILITY = _FRAMEWORK_COMPATIBILITY

# The PE subsystem version each framework that needs one asks for: .NET
# Framework from 4.5 on. Every other framework leaves it to the compiler.
_subsystem_version = {
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
}

_net = FRAMEWORK_COMPATIBILITY.keys().index("net11")
_cor = FRAMEWORK_COMPATIBILITY.keys().index("netcoreapp1.0")
STD_FRAMEWORKS = FRAMEWORK_COMPATIBILITY.keys()[:_net]
NET_FRAMEWORKS = FRAMEWORK_COMPATIBILITY.keys()[_net:_cor]
COR_FRAMEWORKS = FRAMEWORK_COMPATIBILITY.keys()[_cor:]
TRANSITIVE_FRAMEWORK_COMPATIBILITY = _collect_transitive()

# Each framework's compatible frameworks, most specific first. FRAMEWORK_COMPATIBILITY
# lists each family oldest to newest, so the later a framework, the more specific.
_NEAREST_FIRST = {
    tfm: [candidate for candidate in reversed(FRAMEWORK_COMPATIBILITY.keys()) if sets.contains(compatible, candidate)]
    for (tfm, compatible) in TRANSITIVE_FRAMEWORK_COMPATIBILITY.items()
}

def tfm_to_semver(tfm):
    """Converts a target framework moniker to a semver version.

    Args:
        tfm: The target framework moniker
    Returns:
        The semver version
    """
    tfm = base_framework(tfm)
    if tfm.startswith("netstandard"):
        return "{}.0".format(tfm.replace("netstandard", ""))
    elif tfm.startswith("netcoreapp"):
        return "{}.0".format(tfm.replace("netcoreapp", ""))
    elif tfm.startswith("net"):
        return "{}.0".format(tfm.replace("net", ""))
    else:
        fail("Could not get tfm semver version: {}".format(tfm))

def is_debug(ctx):
    return ctx.var["COMPILATION_MODE"] in ["dbg", "fastbuild"]

def use_highentropyva(tfm):
    return tfm not in ["net20", "net40"]

def is_standard_framework(tfm):
    return _tfm_family(tfm) == _NETSTANDARD

def is_core_framework(tfm):
    return _tfm_family(tfm) == _NETCOREAPP

def is_netframework(tfm):
    return _tfm_family(tfm) == _NETFRAMEWORK

def netframework_runtime_identifier(runtime_identifier):
    """The Windows runtime identifier with the architecture of `runtime_identifier`.

    .NET Framework only runs on Windows: `linux-x64` gives `win-x64`.

    Args:
        runtime_identifier: A runtime identifier.

    Returns:
        The Windows runtime identifier of the same architecture.
    """
    if runtime_identifier.startswith("win") or "-" not in runtime_identifier:
        return runtime_identifier
    return "win-" + runtime_identifier.rsplit("-", 1)[-1]

def is_greater_or_equal_framework(tfm1, tfm2):
    """Returns true if tfm1 is greater or equal to tfm2

    Args:
      tfm1: The first framework
      tfm2: The second framework
    Returns:
        True if tfm1 is greater or equal to tfm2
    """
    keys = FRAMEWORK_COMPATIBILITY.keys()
    return keys.index(tfm1) >= keys.index(tfm2)

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

# The first major SDK version with F# 9, whose compiler checks nullness.
# https://devblogs.microsoft.com/dotnet/nullable-reference-types-in-fsharp-9/
_FSHARP_NULLNESS_CHECKING_SDK_MAJOR = 9

def fsharp_checks_nullness(sdk_version):
    """Whether this SDK's F# compiler can check nullness.

    Args:
        sdk_version: The version of the .Net SDK, as `DotnetInfo.sdk_version`.

    Returns:
        True if the F# compiler accepts `--checknulls`.
    """
    return int(sdk_version.split(".")[0]) >= _FSHARP_NULLNESS_CHECKING_SDK_MAJOR

def get_toolchain(ctx):
    """The .Net toolchain a target compiles with.

    Args:
        ctx: The rule context.

    Returns:
        The `ToolchainInfo` of the resolved .Net toolchain.
    """

    return ctx.toolchains["//dotnet/toolchain:toolchain_type"]

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
        The worker's `FilesToRunProvider`, or None when the compile should use
        the wrapper script instead.
    """

    # compiler_worker_binary drops the attribute: the workers are the targets
    # that cannot be compiled by the worker.
    if not hasattr(ctx.attr, "_csharp_compiler_worker"):
        return None

    return _worker_executable(ctx.attr._csharp_compiler_worker)

def get_fsharp_compiler_worker(ctx):
    """The persistent worker to compile F# with, if it is enabled.

    Args:
        ctx: The rule context.

    Returns:
        The worker's `FilesToRunProvider`, or None when the compile should use
        the wrapper script instead.
    """

    return _worker_executable(ctx.attr._fsharp_compiler_worker)

def resolve_tristate(value, default):
    """Resolves a `"true"`, `"false"`, or `"default"` attribute, where `"default"` takes `default`."""
    return default if value == "default" else value == "true"

def resolve_enable_net_analyzers(ctx):
    return resolve_tristate(ctx.attr.enable_net_analyzers, ctx.attr._enable_net_analyzers[BuildSettingInfo].value)

def resolve_enforce_code_style_in_build(ctx):
    return resolve_tristate(ctx.attr.enforce_code_style_in_build, ctx.attr._enforce_code_style_in_build[BuildSettingInfo].value)

# Assemblies that must not be handed to the compiler as references.
# See https://github.com/bazel-contrib/rules_dotnet/issues/405
_UNREFERENCEABLE_ASSEMBLIES = ("System.EnterpriseServices.Thunk.dll", "System.EnterpriseServices.Wrapper.dll")

def _format_ref(assembly):
    return None if assembly.path.endswith(_UNREFERENCEABLE_ASSEMBLIES) else "-r:" + assembly.path

def _format_quoted_ref(assembly):
    return None if assembly.path.endswith(_UNREFERENCEABLE_ASSEMBLIES) else "-r:\"" + assembly.path + "\""

def format_ref_arg(args, refs, quote = False):
    """Adds a `-r:` argument for each reference assembly to `args`.

    Args:
        args: The Args object of the compilation action.
        refs: A depset of the reference assemblies.
        quote: Quote each path, for compilers whose response file splits on whitespace.
    Returns:
        `args`.
    """

    args.add_all(refs, map_each = _format_quoted_ref if quote else _format_ref)

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

def _internals(assembly):
    if not assembly.internals_visible_to:
        return []
    friends = tuple(assembly.internals_visible_to)
    return [(ref, iref, friends) for ref, iref in zip(assembly.refs, assembly.irefs)]

def _friend_irefs(name, internals):
    """Maps each ref that grants `name` its internals to the iref that carries them.

    Args:
        name: The name of the assembly being compiled.
        internals: Depsets of `(ref, iref, friends)`, as in `transitive_internals`.

    Returns:
        A dict of ref File to iref File.
    """
    return {
        ref: iref
        for ref, iref, friends in depset(transitive = internals).to_list()
        if name in friends
    }

def _ref_assembly_name(file):
    return file.basename.replace(".dll", "").lower()

def _references_dependency(assembly, pack, superseded):
    """Whether to compile against a dependency rather than the targeting pack's copy of it.

    A dependency that the pack also provides wins only when it is newer than the
    pack's minimum version, and then supersedes the pack's reference assembly. One
    that sets no version is never newer.

    Args:
        assembly: The dependency's `DotnetAssemblyCompileInfo`.
        pack: The `DotnetTargetingPackInfo`, or None.
        superseded: The pack assemblies superseded so far, by lower-cased name.
            Updated in place.

    Returns:
        True if the dependency is referenced.
    """
    if not pack:
        return True

    name = assembly.name.lower()
    if name in pack.targeting_pack_overrides:
        minimum_version = pack.targeting_pack_overrides[name]
    elif name in pack.framework_list and name not in superseded:
        minimum_version = pack.framework_list[name]["version"]
    else:
        return True

    if not nuget_version.is_newer(assembly.version, minimum_version):
        return False

    superseded[name] = True
    return True

def _pack_reference_assemblies(pack, superseded):
    """The targeting pack's reference assemblies, less those a dependency supersedes."""
    if not pack:
        return depset()

    # A superseded assembly need not be in `framework_list`: System.Security.Cryptography.Xml
    # has a minimum version for net8.0, but only the `web` framework provides it.
    if not [name for name in superseded if name in pack.framework_list]:
        # Share the depset the pack resolved once.
        return pack.framework_files_depset

    files = list(pack.framework_files)
    for (name, entry) in pack.framework_list.items():
        if entry["file"] != None and name not in superseded:
            files.append(entry["file"])
    return depset(files)

_ANALYZER_FIELDS = ["analyzers", "analyzers_csharp", "analyzers_fsharp", "analyzers_vb"]

def collect_compile_info(name, deps, targeting_pack, exports, strict_deps):
    """Collects what a compilation references from its dependencies and targeting pack.

    Args:
        name: The name of the assembly that is being compiled.
        deps: Dependencies that the compilation target depends on.
        targeting_pack: Targeting pack that the compilation target depends on, or None.
        exports: Exported targets.
        strict_deps: Whether only direct dependencies and their exports are referenced.

    Returns:
        A tuple of: the reference assemblies to compile against; the public
        reference closure for `transitive_refs`; the common, C#, F# and VB
        analyzers; the compile data; the targeting pack's reference assemblies;
        the reference assemblies of `exports`; and `transitive_internals`.
    """
    pack = targeting_pack[DotnetTargetingPackInfo] if targeting_pack else None
    superseded = {}

    direct_iref = []
    direct_ref = []
    direct_analyzers = {field: [] for field in _ANALYZER_FIELDS}
    direct_compile_data = list(pack.compile_data) if pack else []
    direct_internals = []

    for dep in deps:
        assembly = dep[DotnetAssemblyCompileInfo]

        if _references_dependency(assembly, pack, superseded):
            direct_iref.extend(assembly.irefs if name in assembly.internals_visible_to else assembly.refs)
            direct_ref.extend(assembly.refs)
            for field in _ANALYZER_FIELDS:
                direct_analyzers[field].extend(getattr(assembly, field))
            direct_compile_data.extend(assembly.compile_data)
            direct_internals.extend(_internals(assembly))

        direct_iref.extend(assembly.exports)

    transitive_ref = []
    transitive_ref_depsets = []
    transitive_analyzers = {field: [] for field in _ANALYZER_FIELDS}
    transitive_compile_data = []
    if not strict_deps:
        dep_infos = [dep[DotnetAssemblyCompileInfo] for dep in deps]
        transitive_ref_depsets = [assembly.transitive_refs for assembly in dep_infos]
        for field in _ANALYZER_FIELDS:
            transitive_analyzers[field] = [getattr(assembly, "transitive_" + field) for assembly in dep_infos]
        transitive_compile_data = [assembly.transitive_compile_data for assembly in dep_infos]

        # Of the assemblies the targeting pack provides, the compiler only gets
        # the pack's copy or a direct dependency that supersedes it, never one
        # from the closure. Transitive assembly versions are not compared.
        if pack:
            transitive_ref = [
                ref
                for ref in depset(transitive = transitive_ref_depsets).to_list()
                if _ref_assembly_name(ref) not in pack.targeting_pack_overrides and
                   _ref_assembly_name(ref) not in pack.framework_list
            ]
        else:
            transitive_ref = depset(transitive = transitive_ref_depsets).to_list()

    # A friend reaching an assembly through an export or the closure gets its
    # iref in place of its ref, never both: of two reference assemblies with
    # the same identity, fsc keeps the first and csc the last.
    deps_internals = [dep[DotnetAssemblyCompileInfo].transitive_internals for dep in deps]
    friend_irefs = _friend_irefs(name, deps_internals)
    if friend_irefs:
        direct_iref = [friend_irefs.get(ref, ref) for ref in direct_iref]
        transitive_ref = [friend_irefs.get(ref, ref) for ref in transitive_ref]

    if pack:
        # Last, so a dependency wins a file name clash: it contributes analyzers
        # only once it has superseded the pack's reference assembly, so its
        # analyzer is the one that matches the refs. See `_resolve_analyzers`.
        for field in _ANALYZER_FIELDS:
            direct_analyzers[field].extend(getattr(pack, field))

    exports_files = []
    for export in exports:
        assembly = export[DotnetAssemblyCompileInfo]
        exports_files.extend(assembly.refs)
        direct_internals.extend(_internals(assembly))

    return (
        # Filtered and flat: the compiler's reference arguments.
        depset(direct = direct_iref, transitive = [depset(transitive_ref)]),
        # Unfiltered and structurally shared: only ever read back out of a provider.
        depset(direct = direct_ref, transitive = transitive_ref_depsets),
        _resolve_analyzers(direct_analyzers["analyzers"], transitive_analyzers["analyzers"]),
        _resolve_analyzers(direct_analyzers["analyzers_csharp"], transitive_analyzers["analyzers_csharp"]),
        _resolve_analyzers(direct_analyzers["analyzers_fsharp"], transitive_analyzers["analyzers_fsharp"]),
        _resolve_analyzers(direct_analyzers["analyzers_vb"], transitive_analyzers["analyzers_vb"]),
        depset(direct = direct_compile_data, transitive = transitive_compile_data),
        _pack_reference_assemblies(pack, superseded),
        exports_files,
        depset(direct_internals, transitive = [] if strict_deps else deps_internals),
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
    """The PE subsystem version to compile `tfm` with, or None to leave it to the compiler."""
    return _subsystem_version.get(tfm)

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
    framework = normalize_platform_framework(framework.strip().lower())

    if framework in FRAMEWORK_COMPATIBILITY:
        return framework

    # A platform specific framework whose base is spelled out in full.
    (base, separator, platform) = framework.partition("-")
    if separator and platform and not base.startswith(".netportable"):
        base_tfm = _nuget_framework_to_tfm(base)
        tfm = normalize_platform_framework("{}-{}".format(base_tfm, platform)) if base_tfm else None
        return tfm if tfm in FRAMEWORK_COMPATIBILITY else None

    return _nuget_framework_to_tfm(framework)

def _nuget_framework_to_tfm(framework):
    """`nuget_framework_to_tfm` for a lower cased framework of no platform."""
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

    # `dotnet pack` includes the Windows version: `net8.0-windows7.0`.
    if framework_platform(tfm) == WINDOWS_PLATFORM:
        return "{}-{}{}".format(base_framework(tfm), WINDOWS_PLATFORM, WINDOWS_PLATFORM_VERSION)

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
    candidates = _NEAREST_FIRST.get(incoming_tfm)
    if candidates == None:
        fail("Target framework moniker is not supported/valid: {}".format(incoming_tfm))

    for tfm in candidates:
        if tfm in tfms:
            return tfm

    return None

# The .NET Framework versions a .NET Core 2.0 or later target falls back to when
# a dependency has nothing compatible, in the order NuGet tries them. The SDK's
# `AssetTargetFallback`, from Microsoft.NET.TargetFrameworkInference.targets.
_ASSET_TARGET_FALLBACK = ["net461", "net462", "net47", "net471", "net472", "net48", "net481"]

def get_dependency_target_framework(consumer_tfm, tfms):
    """Returns the entry of `tfms` that a target built for `consumer_tfm` uses.

    As NuGet picks a project reference's framework: the nearest compatible one,
    else, for .NET Core 2.0 and later, a .NET Framework one through
    `AssetTargetFallback` (where MSBuild warns with NU1702).

    Args:
      consumer_tfm: The target framework of the depending target.
      tfms: The frameworks the dependency can be built for.

    Returns:
      The framework to build the dependency for, or None if none is usable.
    """
    nearest = get_nearest_compatible_target_framework(consumer_tfm, tfms)
    if nearest or not sets.contains(TRANSITIVE_FRAMEWORK_COMPATIBILITY[consumer_tfm], "netcoreapp2.0"):
        return nearest

    for fallback in _ASSET_TARGET_FALLBACK:
        nearest = get_nearest_compatible_target_framework(fallback, tfms)
        if nearest:
            return nearest

    return None

def get_newest_target_framework(requested_tfm, tfms):
    """Returns the newest entry of `tfms` up to `requested_tfm`, in any framework family.

    What a target builds for when no .NET target depends on it, as on the
    command line, so that a .NET Framework target still builds on its own. .NET
    ranks above .NET Framework, which ranks above .NET Standard, and `-windows`
    counts as the release it is specific to.

    Args:
      requested_tfm: The configuration's target framework.
      tfms: The frameworks the target can be built for.

    Returns:
      The framework to build the target for, or None if none qualifies.
    """
    if requested_tfm in tfms:
        return requested_tfm

    if requested_tfm not in FRAMEWORK_COMPATIBILITY:
        fail("Target framework moniker is not supported/valid: {}".format(requested_tfm))

    # FRAMEWORK_COMPATIBILITY lists .NET Standard, then .NET Framework, then
    # .NET, each oldest to newest, with a Windows specific framework right
    # after the release it is specific to and so no newer than.
    frameworks = FRAMEWORK_COMPATIBILITY.keys()
    end = frameworks.index(requested_tfm) + 1
    for tfm in frameworks[end:]:
        if base_framework(tfm) != base_framework(requested_tfm):
            break
        end += 1

    for tfm in reversed(frameworks[:end]):
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

def shipped_shared_frameworks(target_framework, runtime_identifier):
    """The shared frameworks that ship a runtime pack for a framework and runtime identifier.

    Args:
      target_framework: The target framework.
      runtime_identifier: The runtime identifier.

    Returns:
      The shared frameworks, as `resolve_framework_references` returns them.
    """
    frameworks = {}
    for framework in SHARED_FRAMEWORKS:
        candidate = frameworks | {framework: None}
        rids = RUNTIME_PACK_LOOKUP_TABLE[frameworks_key(candidate, profiles = False)].get(base_framework(target_framework), {})
        if get_highest_compatible_runtime_identifier(runtime_identifier, rids.keys()):
            frameworks = candidate

    return frameworks

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
# net403) gets no `*_OR_GREATER` symbol. See dotnet/private/sdk/frameworks.bzl.
_SDK_TFMS_BY_FAMILY = {
    _NETCOREAPP: SDK_NETCOREAPP_FRAMEWORKS,
    _NETFRAMEWORK: SDK_NETFRAMEWORK_FRAMEWORKS,
    _NETSTANDARD: SDK_NETSTANDARD_FRAMEWORKS,
}

# .NET 5 is where the netcoreapp family starts spelling its symbols NET*.
_NET5 = [5, 0]

def _tfm_family(tfm):
    """Classifies a target framework moniker into an SDK framework family."""
    tfm = base_framework(tfm)
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
    tfm = base_framework(tfm)
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

    # As the SDK's GenerateTargetPlatformDefineConstants and
    # GeneratePlatformCompatibleDefineConstants. 7.0 is the first Windows
    # version the SDK knows, so there are no lower `_OR_GREATER` symbols.
    if framework_platform(tfm) == WINDOWS_PLATFORM and is_net5_or_greater:
        platform = WINDOWS_PLATFORM.upper()
        platform_version = WINDOWS_PLATFORM_VERSION.replace(".", "_")
        defines += [platform, platform + platform_version, platform + platform_version + "_OR_GREATER"]

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

# Computed once rather than per target: the input domain is the known framework set.
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
    symbols = _FRAMEWORK_PREPROCESSOR_SYMBOLS.get(tfm)
    return symbols if symbols != None else _compute_framework_preprocessor_symbols(tfm)

def is_from_nuget_package(dep):
    """Whether a dependency was unpacked from a `.nupkg`.

    An `import_library` that names no package wraps a file this repository
    builds or checks in.

    Args:
        dep: (DotnetAssemblyRuntimeInfo) The dependency.
    Returns:
        True if the dependency came out of a NuGet package.
    """
    return dep.nuget_info != None and dep.nuget_info.nupkg != None

def get_portable_assets(dep, portable):
    """The assets a portable app takes from a dependency in place of `libs` and `native`.

    Args:
        dep: (DotnetAssemblyRuntimeInfo) The dependency.
        portable: Whether the app runs on any runtime, as a .NET tool does.
    Returns:
        The package's `NuGetPortableAssetsInfo`, or None when the app is not
        portable or the dependency has none.
    """
    if not portable or dep.nuget_info == None:
        return None

    return dep.nuget_info.portable_assets

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

def _depsjson_runtime_asset(version):
    """The properties of a `runtime` asset in a deps.json, from its library's version.

    The host reads `assemblyVersion` as a `System.Version`, two to four numbers,
    to choose between an app's assembly and a framework's of the same name: the
    higher wins. A missing value and one it cannot parse are the same to it, no
    version at all, which any framework assembly beats. So the value is written
    padded to four numbers, as the framework's own deps.json spells it, and left
    out when the library has no version that maps to one.

    Args:
        version: The library's version, a NuGet version string or "".

    Returns:
        A dict for the asset's entry in `runtime`.
    """

    # `error` also rejects a component above 65535, which `assembly_version`
    # would fail on.
    if not version or nuget_version.error(version):
        return {}
    return {"assemblyVersion": nuget_version.assembly_version(version)}

def _lib_assembly_name(file):
    return file.basename.lower().replace(".dll", "")

# A .NET application ranks the frameworks it can use in the same order whatever
# its own version, so the newest framework, which can use them all, ranks a
# library's configurations for any application. FRAMEWORK_COMPATIBILITY lists
# it last.
_ANY_APPLICATION = FRAMEWORK_COMPATIBILITY.keys()[-1]

def _library_identity(dep):
    """What every configuration of one library shares: its package or its target."""
    if is_from_nuget_package(dep):
        return dep.nuget_info.nupkg.path
    files = dep.libs + dep.native
    return str(files[0].owner) if files else None

def _variant_framework(dep):
    """The framework a configuration was built, or its package's assets picked, for.

    Read off the assembly's folder, `<target>/<tfm>/` or a package's `lib/<tfm>/`.
    """
    if not dep.libs:
        return None
    folder = dep.libs[0].dirname.rpartition("/")[2]
    return folder if folder in FRAMEWORK_COMPATIBILITY else None

def _preferred_variant(variants):
    """The position of the configuration an application loads, as NuGet would pick its assets."""
    by_framework = {}
    for (position, dep) in enumerate(variants):
        framework = _variant_framework(dep)
        if framework:
            by_framework.setdefault(framework, position)

    chosen = get_dependency_target_framework(_ANY_APPLICATION, by_framework.keys())
    return by_framework[chosen] if chosen else 0

def select_runtime_variants(transitive_runtime_deps):
    """Keeps one configuration of each library: the one the application loads.

    A library is built once per framework its consumers ask for, so a .NET
    application can reach a multi-targeted library both as `netstandard2.0`
    and, through a .NET Framework library, as `net48`. Only one `Shared.dll`
    can be loaded or published, and deps.json and the publish have to agree on
    it: the nearest framework, .NET Framework only when nothing else fits.

    Different targets that build the same assembly are all kept, for the
    publish to report.

    Args:
        transitive_runtime_deps: The application's `DotnetAssemblyRuntimeInfo`s.

    Returns:
        `transitive_runtime_deps`, in order, without the other configurations.
    """
    by_library = {}
    for (index, dep) in enumerate(transitive_runtime_deps):
        by_library.setdefault("{}/{}".format(dep.name, dep.version), []).append(index)

    dropped = {}
    for indices in by_library.values():
        if len(indices) == 1:
            continue

        by_identity = {}
        for index in indices:
            identity = _library_identity(transitive_runtime_deps[index])
            if identity != None:
                by_identity.setdefault(identity, []).append(index)

        for variants in by_identity.values():
            kept = variants[_preferred_variant([transitive_runtime_deps[index] for index in variants])]
            for index in variants:
                if index != kept:
                    dropped[index] = None

    if not dropped:
        return transitive_runtime_deps
    return [dep for (index, dep) in enumerate(transitive_runtime_deps) if index not in dropped]

def _runtime_pack_conflicts(runtime_pack_info, transitive_runtime_deps):
    """Decides, for each assembly the runtime pack and a dependency both ship, which copy the app gets.

    One copy per name, the newest. As in MSBuild, a dependency replaces the
    pack's copy only when it is newer, and one that sets no version is never
    newer. Of several dependencies of that name, the newest replaces the others
    too, so that exactly one copy is published.

    Args:
        runtime_pack_info: The `DotnetRuntimePackInfo` of a self-contained app.
        transitive_runtime_deps: The app's `DotnetAssemblyRuntimeInfo`s.

    Returns:
        A dict keyed by the lower-cased name of every such assembly: the
        `<name>/<version>` of the dependency whose copy the app loads, or None
        when it loads the pack's.
    """

    # Every pack of a runtime release shares the release's version.
    pack_version = runtime_pack_info.assembly_runtime_infos[0].version
    pack_assemblies = {
        _lib_assembly_name(lib): None
        for info in runtime_pack_info.assembly_runtime_infos
        for lib in info.libs
    }

    winners = {}
    newest = {}
    for dep in transitive_runtime_deps:
        name = dep.name.lower()
        if name not in pack_assemblies:
            continue
        winners.setdefault(name, None)
        if nuget_version.is_newer(dep.version, newest.get(name, pack_version)):
            newest[name] = dep.version
            winners[name] = "{}/{}".format(dep.name, dep.version)

    return winners

def _depsjson_library(runtime_dep, library_name, use_relative_paths):
    """The `libraries` entry of a dependency."""
    if runtime_dep.nuget_info and not use_relative_paths:
        return {
            "type": "package",
            "serviceable": True,
            "sha512": runtime_dep.nuget_info.sha512,
            "path": library_name.lower(),
            # NuGet lower-cases the whole file name, prerelease label included.
            "hashPath": "{}.{}.nupkg.sha512".format(runtime_dep.name.lower(), runtime_dep.version.lower()),
        }

    library = {
        "type": "project",
        "serviceable": False,
        "sha512": "",
    }
    if use_relative_paths:
        library["path"] = "./"
    return library

def _depsjson_target(ctx, runtime_dep, is_self_contained, use_relative_paths, portable):
    """The `targets` entry of a dependency whose own files the app loads.

    With `use_relative_paths`, files are keyed by their runfiles path rather
    than by their path inside the application directory.
    """
    portable_assets = get_portable_assets(runtime_dep, portable)
    runtime_asset = _depsjson_runtime_asset(runtime_dep.version)

    target = {"dependencies": runtime_dep.direct_deps_depsjson_fragment}

    target["runtime"] = {
        to_rlocation_path(ctx, dll) if use_relative_paths else dll.basename: dict(runtime_asset)
        for dll in (portable_assets.libs if portable_assets else runtime_dep.libs)
    }

    # A satellite assembly is keyed by its locale folder as well, as MSBuild
    # writes it: every locale's satellite has the same file name.
    target["resources"] = {}
    for resource in runtime_dep.resource_assemblies:
        locale = _get_resource_assembly_locale(resource)
        key = to_rlocation_path(ctx, resource) if use_relative_paths else "{}/{}".format(locale, resource.basename)
        target["resources"][key] = {"locale": locale}

    # A self-contained app lists its native files directly; otherwise they are
    # per-RID `runtimeTargets`, as in
    # https://github.com/dotnet/sdk/blob/main/documentation/specs/runtime-configuration-file.md#framework-dependent-deployment-model
    if is_self_contained:
        target["native"] = {native_file.basename: {"fileVersion": "0.0.0.0"} for native_file in runtime_dep.native}
    elif portable_assets:
        target["runtimeTargets"] = {
            asset.path: {
                "rid": asset.rid,
                "assetType": asset.asset_type,
            }
            for asset in portable_assets.runtime_targets
        }
    elif not is_from_nuget_package(runtime_dep):
        # Built in this workspace, so not laid out by RID.
        target["native"] = {
            to_rlocation_path(ctx, native_file) if use_relative_paths else native_file.basename: {"fileVersion": "0.0.0.0"}
            for native_file in runtime_dep.native
        }
    else:
        target["runtimeTargets"] = {
            runtime_target_path(native_file): {
                "rid": native_file.dirname.split("/")[-2],
                "assetType": "runtime" if native_file.dirname.split("/")[-1] == "lib" else "native",
            }
            for native_file in runtime_dep.native
        }

    return target

# For deps.json spec see: https://github.com/dotnet/sdk/blob/main/documentation/specs/runtime-configuration-file.md
def generate_depsjson(
        ctx,
        target_framework,
        is_self_contained,
        target_assembly_runtime_info,
        transitive_runtime_deps,
        runtime_pack_info = None,
        use_relative_paths = False,
        portable = False):
    """Generates a deps.json file.

    Args:
        ctx: The ctx object
        target_framework: The target framework moniker for the target being built.
        is_self_contained: If the target is a self-contained publish.
        target_assembly_runtime_info: The DotnetAssemblyRuntimeInfo provider for the target being built.
        transitive_runtime_deps: List of DotnetAssemblyRuntimeInfo providers which are the transitive runtime dependencies of the target.
        runtime_pack_info: The DotnetRuntimePackInfo of the runtime pack that is used for a self contained publish.
        use_relative_paths: If the paths to the dependencies should be relative to the workspace root.
        portable: List NuGet packages as a RID-less `dotnet publish` does: RID-agnostic
            assemblies as `runtime`, every runtime's assets as `runtimeTargets`.
            Not with `is_self_contained`.
    Returns:
        The deps.json file as a struct.
    """
    version = tfm_to_semver(target_framework)
    if is_self_contained:
        version += "/" + runtime_pack_info.runtime_identifier
    runtime_target = ".NETCoreApp,Version=v{}".format(version)

    targets = {}
    libraries = {}
    base = {
        "runtimeTarget": {
            "name": runtime_target,
            "signature": "",
        },
        "compilationOptions": {},
        "targets": {runtime_target: targets},
        "libraries": libraries,
    }

    transitive_runtime_deps = select_runtime_variants(transitive_runtime_deps)

    pack_conflicts = {}
    if is_self_contained:
        pack_conflicts = _runtime_pack_conflicts(runtime_pack_info, transitive_runtime_deps)

        for assembly_runtime_info in runtime_pack_info.assembly_runtime_infos:
            runtime_pack_name = "runtimepack.{}/{}".format(assembly_runtime_info.name, assembly_runtime_info.version)
            libraries[runtime_pack_name] = {
                "type": "runtimepack",
                "serviceable": False,
                "sha512": "",
            }
            targets[runtime_pack_name] = {
                "runtime": {dll.basename: {} for dll in assembly_runtime_info.libs if pack_conflicts.get(_lib_assembly_name(dll)) == None},
                "native": {native_file.basename: {} for native_file in assembly_runtime_info.native},
            }

        rid = runtime_pack_info.runtime_identifier
        base["runtimes"] = {
            graph_rid: compatible_rids
            for graph_rid, compatible_rids in RUNTIME_GRAPH.items()
            if rid == graph_rid or rid in compatible_rids
        }

    for runtime_dep in [target_assembly_runtime_info] + transitive_runtime_deps:
        library_name = "{}/{}".format(runtime_dep.name, runtime_dep.version)

        # Two targets can build the same assembly. Only the first is listed; a
        # publish fails on the pair.
        if library_name in libraries:
            continue

        libraries[library_name] = _depsjson_library(runtime_dep, library_name, use_relative_paths)
        name = runtime_dep.name.lower()
        if name in pack_conflicts and pack_conflicts[name] != library_name:
            # The app loads the runtime pack's copy, or a newer dependency's.
            targets[library_name] = {"dependencies": runtime_dep.direct_deps_depsjson_fragment}
        else:
            targets[library_name] = _depsjson_target(ctx, runtime_dep, is_self_contained, use_relative_paths, portable)

    return base

def shared_framework_version(target_framework, runtime_version):
    """The version of the shared frameworks a framework-dependent app asks for.

    That is the release's first, `x.0.0`, which the host rolls forward from. A
    preview of the release sorts before it, though, and so could never satisfy
    it: an app built for the release a preview SDK ships asks for that preview
    instead, as it does under the SDK. Since .NET 10 every shared framework of
    a release shares its version.

    Args:
        target_framework: The framework the app is built for.
        runtime_version: The version of the runtime the SDK ships.

    Returns:
        The version.
    """
    version = tfm_to_semver(target_framework)

    return runtime_version if runtime_version.startswith(version + "-") else version

def target_platform(tfm):
    """The platform for the `TargetPlatform` and `SupportedOSPlatform` assembly attributes.

    Args:
        tfm: The target framework moniker.

    Returns:
        `Windows7.0` for a Windows specific framework, None otherwise.
    """
    if framework_platform(tfm) != WINDOWS_PLATFORM or not is_core_framework(tfm) or tfm_version(tfm) < [5]:
        return None

    return "{}{}".format(WINDOWS_PLATFORM.capitalize(), WINDOWS_PLATFORM_VERSION)

def applicable_frameworks(tfm, frameworks):
    """The shared frameworks that apply to the target framework.

    Windows Forms and WPF are ignored on .NET Standard and .NET Framework, so
    that a library can also target those.

    Args:
        tfm: The target framework.
        frameworks: The shared frameworks, as `resolve_framework_references` returns them.

    Returns:
        The shared frameworks that apply.
    """
    if is_core_framework(tfm):
        return frameworks

    return {framework: profiles for (framework, profiles) in frameworks.items() if framework not in WINDOWS_ONLY_FRAMEWORKS}

def check_windows_frameworks(label, tfm, frameworks, transitively = False):
    """Fails if Windows Forms or WPF are used without a Windows specific framework, like NETSDK1136.

    Args:
        label: The label of the target, for the message.
        tfm: The target framework it is built for.
        frameworks: The shared frameworks it references or runs on.
        transitively: Whether `frameworks` includes those of its dependencies.
    """
    if not is_core_framework(tfm) or tfm_version(tfm) < [5] or framework_platform(tfm) == WINDOWS_PLATFORM:
        return

    windows_only = [framework for framework in frameworks if framework in WINDOWS_ONLY_FRAMEWORKS]
    if windows_only:
        fail("{}: {} {}, which needs a Windows specific target framework: use {}-{} rather than {}, as the SDK does for Windows Forms and WPF (NETSDK1136).".format(
            label,
            "depends on something that runs on" if transitively else "references",
            ", ".join(windows_only),
            base_framework(tfm),
            WINDOWS_PLATFORM,
            tfm,
        ))

_FRAMEWORK_REFERENCES_BY_LOWER_NAME = {name.lower(): value for (name, value) in FRAMEWORK_REFERENCES.items()}

def runtime_frameworks(assembly_runtime_info, transitive_runtime_deps):
    """The shared frameworks an application runs on, beyond Microsoft.NETCore.App.

    These are the framework references of every assembly it carries. Unknown
    references, which only NuGet packages can make, are ignored.

    Args:
        assembly_runtime_info: The application's own DotnetAssemblyRuntimeInfo.
        transitive_runtime_deps: The DotnetAssemblyRuntimeInfo of everything it carries.

    Returns:
        A list of shared framework names, in the order their packs are listed.
    """
    frameworks = {}
    for info in [assembly_runtime_info] + transitive_runtime_deps:
        for reference in getattr(info, "framework_references", None) or []:
            # NuGet compares framework reference names case-insensitively.
            known = _FRAMEWORK_REFERENCES_BY_LOWER_NAME.get(reference.lower())
            if known:
                frameworks[known[0]] = None

    return [framework for framework in SHARED_FRAMEWORKS if framework in frameworks]

def _shared_framework_of_runtime_pack(pack_id):
    """The shared framework a runtime pack carries: Microsoft.NETCore.App for Microsoft.NETCore.App.Runtime.win-x64."""
    return pack_id.partition(".Runtime.")[0]

# For runtimeconfig.json spec see https://github.com/dotnet/sdk/blob/main/documentation/specs/runtime-configuration-file.md
def generate_runtimeconfig(target_framework, frameworks, is_self_contained, roll_forward_behavior, runtime_pack_info = None, framework_version = None):
    """Generates a runtimeconfig.json file.

    Args:
        target_framework: The target framework moniker for the target being built.
        frameworks: The shared frameworks the application runs on beyond
            Microsoft.NETCore.App, from `runtime_frameworks`.
        is_self_contained: If the target is a self-contained publish.
        roll_forward_behavior: The roll forward behavior to use.
        runtime_pack_info: The DotnetRuntimePackInfo of the runtime pack that is used for a self contained publish.
        framework_version: The version of the shared frameworks to ask for when
            not self-contained, from `shared_framework_version`.
    Returns:
        The runtimeconfig.json file as a struct.
    """

    base = {
        "runtimeOptions": {
            # `net8.0` for `net8.0-windows`, as the SDK writes it.
            "tfm": base_framework(target_framework),
            "rollForward": roll_forward_behavior,
        },
    }

    if is_self_contained:
        # Named as the host knows them: `Microsoft.NETCore.App`, not the runtime pack.
        base["runtimeOptions"]["includedFrameworks"] = [
            {"name": _shared_framework_of_runtime_pack(assembly_runtime_info.name), "version": assembly_runtime_info.version}
            for assembly_runtime_info in runtime_pack_info.assembly_runtime_infos
        ]
    else:
        base["runtimeOptions"]["frameworks"] = [
            {"name": framework, "version": framework_version}
            for framework in [NETCORE_FRAMEWORK] + frameworks
        ]
    return base

def to_rlocation_path(ctx, file):
    """The path of `file` under the runfiles root, as the `rlocationpath` make variable gives it.

    Args:
        ctx: The rule context.
        file: The `File`.

    Returns:
        The path, which starts with the name of the file's repository.
    """
    if file.short_path.startswith("../"):
        return file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def package_relative_path(file, label):
    """The path of `file` relative to `label`'s package, as MSBuild's is to the project.

    Args:
        file: A `File`, or anything with its `short_path` and `basename`.
        label: The label whose package the path is relative to.

    Returns:
        The relative path, or the file name for a file outside the package, as
        MSBuild falls back to.
    """

    # A file of another repository has a `short_path` of `../<repo>/<path>`.
    prefix = "../%s/" % label.repo_name if label.repo_name else ""
    if label.package:
        prefix += label.package + "/"

    path = file.short_path[len(prefix):]
    if not file.short_path.startswith(prefix) or path.startswith("../"):
        return file.basename

    return path

def _batch_path(path):
    """`path` as it has to appear between double quotes in a batch file."""

    # cmd.exe expands `%` even inside quotes.
    return path.replace("/", "\\").replace("%", "%%")

def _copy_files_to_dir(actions, is_windows, file_mappings, out_dir, script_name, executables = []):
    """Copies files into `out_dir` using a single generated script.

    Args:
        actions: The actions object
        is_windows: If the OS is Windows
        file_mappings: A list of `(src_File, rel_path)` tuples. Each `src_File` is copied to
            `out_dir/rel_path`.
        out_dir: The directory to copy the files to
        script_name: Base name for the generated copy script; must be unique within the target.
        executables: Basenames to mark executable on Unix.

    Returns:
        A list of `struct(file, dest, src)` in the same order as `file_mappings`, where `file` is
        the copied `File`, `dest` is its `rel_path` relative to `out_dir` and `src` is the `File`
        it was copied from.
    """
    script_body = ["@echo off"] if is_windows else ["#! /usr/bin/env bash", "set -eou pipefail"]

    inputs = []
    outputs = []
    for src, rel in file_mappings:
        dst = actions.declare_file("%s/%s" % (out_dir, rel))
        inputs.append(src)
        outputs.append(struct(file = dst, dest = rel, src = src))
        if is_windows:
            # A batch file carries on past a failed command, hence `|| exit /b 1`.
            script_body.append("if not exist \"{dir}\" @mkdir \"{dir}\" >NUL || exit /b 1".format(dir = _batch_path(dst.dirname)))
            script_body.append("@copy /Y \"{src}\" \"{dst}\" >NUL || exit /b 1".format(src = _batch_path(src.path), dst = _batch_path(dst.path)))
        else:
            script_body.append("mkdir -p {dir} && cp -f {src} {dst}".format(dir = shell.quote(dst.dirname), src = shell.quote(src.path), dst = shell.quote(dst.path)))

            if src.basename in executables:
                script_body.append("chmod +x {dst}".format(dst = shell.quote(dst.path)))

    if len(outputs) > 0:
        copy_script = actions.declare_file(script_name + (".bat" if is_windows else ".sh"))
        actions.write(
            output = copy_script,
            content = "\r\n".join(script_body) if is_windows else "\n".join(script_body),
            is_executable = True,
        )
        actions.run(
            mnemonic = "DotnetCopyFiles",
            progress_message = "Copying %d file(s) into %s" % (len(outputs), out_dir),
            outputs = [entry.file for entry in outputs],
            inputs = depset(inputs),
            executable = copy_script,
            tools = [copy_script],
        )
    return outputs

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
    outputs = _copy_files_to_dir(
        actions,
        is_windows,
        [(f, f.basename) for f in files],
        out_dir,
        target_name + ".copy",
        executables = executables,
    )
    return [entry.file for entry in outputs]

def copy_appsettings_to_dir(target_name, actions, is_windows, appsetting_files, out_dir):
    """Stages appsettings files next to the assembly, flattened to their basename.

    Args:
        target_name: The name of the executing target.
        actions: The actions object.
        is_windows: If the OS is Windows.
        appsetting_files: The appsettings `File`s to stage.
        out_dir: The assembly output directory to stage into.

    Returns:
        A list of the staged `File`s.
    """
    return copy_files_to_dir(target_name + ".appsettings", actions, is_windows, appsetting_files, out_dir)

def copy_content_to_dir(target_name, actions, is_windows, content_file_mappings, out_dir):
    """Stages content files next to the assembly at their mapped destination paths.

    Args:
        target_name: The name of the executing target.
        actions: The actions object.
        is_windows: If the OS is Windows.
        content_file_mappings: A list of `struct(src = File, dest = string)`; each `src` is staged
            at `dest` relative to `out_dir`.
        out_dir: The assembly output directory to stage into.

    Returns:
        A list of `struct(file, dest, src)`, where `file` is the staged `File`, `dest` is its path
        relative to `out_dir` and `src` is the `File` it was staged from.
    """
    return _copy_files_to_dir(
        actions,
        is_windows,
        [(m.src, m.dest) for m in content_file_mappings],
        out_dir,
        target_name + ".content.copy",
    )

def collect_transitive_content_files(label, assembly_info, transitive_runtime_deps, reserved = []):
    """Collects the content files a target inherits from its dependencies.

    Every content file lands at its `dest` next to the consuming assembly, so two
    different files cannot share one. Rather than let whichever dependency comes
    first win, a clash fails the build and names both sides. The same source file
    reaching the same `dest` through several libraries is not a clash.

    Args:
        label: The `Label` of the consuming target, for error messages.
        assembly_info: The consuming target's `DotnetAssemblyRuntimeInfo`.
        transitive_runtime_deps: The `DotnetAssemblyRuntimeInfo`s of its transitive dependencies.
        reserved: Paths, relative to the output directory, that the consuming
            target writes itself (its assembly, its appsettings files, ...).

    Returns:
        The dependencies' content files as a list of `struct(file, dest, src)`,
        without the ones `assembly_info` stages itself.
    """

    # dest -> (source File or None, who put it there)
    claimed = {path: (None, "an output of %s itself" % label) for path in reserved}
    for entry in assembly_info.content_files:
        claimed[entry.dest] = (entry.src, "the `content_files` of %s" % label)

    inherited = []
    for dep in transitive_runtime_deps:
        for entry in dep.content_files:
            if entry.dest not in claimed:
                claimed[entry.dest] = (entry.src, "the `content_files` of its dependency `%s`" % dep.name)
                inherited.append(entry)
                continue

            (src, owner) = claimed[entry.dest]
            if src != entry.src:
                fail(("%s: the content file %s of its dependency `%s` would be staged at %r, " +
                      "but that path is already taken by %s%s. Give one of them another " +
                      "destination, for example with `dotnet_content_files`.") % (
                    label,
                    entry.src.short_path,
                    dep.name,
                    entry.dest,
                    owner,
                    " (%s)" % src.short_path if src else "",
                ))

    return inherited

def _resource_arg_template(language):
    """The Args format of a resource argument, with a `%s` where the file's path goes."""
    if language == "csharp":
        return "/resource:\"%s\""
    if language == "fsharp":
        return "--resource:%s"
    fail("Unsupported language: {}".format(language))

def _quote_resource_name(name, language):
    # `%` is the escape character in an Args format string. csc splits response
    # file lines on whitespace, so its names are quoted like its paths.
    name = name.replace("%", "%%")
    return "\"" + name + "\"" if language == "csharp" else name

def embedded_resource_name(file, target_label, out_dll):
    """The manifest name a resource file is embedded under, as MSBuild names it.

    `<assembly name>.<path>`, where `<path>` is the file's path relative to the
    target's package directory with `/` replaced by `.`; a subpackage's file
    counts. A file outside that directory keeps only its basename.

    Args:
        file: (File) The file to embed.
        target_label: (Label) The label of the target embedding the resource.
        out_dll: (str) Basename of the output assembly, if there is one.

    Returns:
        The name, or None when there is no `.dll` or `.exe` to name it after.
    """
    if out_dll == None or not (out_dll.endswith(".dll") or out_dll.endswith(".exe")):
        return None

    return "{}.{}".format(out_dll[:-len(".dll")], package_relative_path(file, target_label).replace("/", "."))

def add_resource_args(args, resources, target_label, out_dll, language):
    """Adds one resource argument per file to `args`, named by `embedded_resource_name`.

    Args:
        args: The Args object for the compilation action.
        resources: The resource files to embed.
        target_label: (Label) The label embedding the resources.
        out_dll: (str) Basename of the output assembly, or None for a ref-only compile.
        language: "csharp" or "fsharp".
    """
    template = _resource_arg_template(language)
    for resource in resources:
        name = embedded_resource_name(resource, target_label, out_dll)
        if name == None:
            args.add(resource, format = template)
        else:
            # The name goes in the format rather than the path, so the path is
            # still a `File` that `--experimental_output_paths=strip` can rewrite.
            args.add(resource, format = template + "," + _quote_resource_name(name, language))

def add_resx_resource_args(args, resx_resources, language):
    """Adds one resource argument per compiled `.resx` resource to `args`.

    Args:
        args: The Args object for the compilation action.
        resx_resources: List of `(File, str)` pairs of a compiled `.resources` file and
            its manifest resource name.
        language: (str) The language of the target that is embedding the resource ("csharp" or "fsharp").
    """
    template = _resource_arg_template(language)
    for (resource_file, manifest_name) in resx_resources:
        args.add(resource_file, format = template + "," + _quote_resource_name(manifest_name, language))
