"""The NuGet packs that back each target framework.

A .NET release publishes its packs under a handful of predictable names, so a
band only has to say what version each target framework resolves to and which
runtime identifiers that release shipped. The pack ids, the set of targets, and
the tables the pack transitions read are all derived from the bands.

Which packs exist does not depend on the SDK in use, so the tables built while
loading read `PACK_BANDS`. Which version of them to download does, so the
functions that return one have to be given bands: those `pack_bands` resolves
for the SDK, or `PACK_BANDS`, with no versions, where only existence matters.

`netstandard` and .NET Framework are frozen reference assemblies rather than
release packs, so their versions are literals here.
"""

load("//dotnet/private/sdk:pack_bands.bzl", "PACK_BANDS")

DEFAULT_SDK = "default"
WEB_SDK = "web"
RAZOR_SDK = "razor"
BLAZORWASM_SDK = "blazorwasm"

# The SDKs that have a pack set of their own. `razor` and `blazorwasm` resolve
# the same packs as `web`, so they have no set of their own and are normalized
# away before lookup.
PROJECT_SDKS = [DEFAULT_SDK, WEB_SDK]

# What a user may write in `project_sdk`.
USER_PROJECT_SDKS = PROJECT_SDKS + [RAZOR_SDK, BLAZORWASM_SDK]

# Shared frameworks beyond Microsoft.NETCore.App, in the order their packs are listed.
NETCORE_FRAMEWORK = "Microsoft.NETCore.App"
ASPNETCORE_FRAMEWORK = "Microsoft.AspNetCore.App"
WINDOWSDESKTOP_FRAMEWORK = "Microsoft.WindowsDesktop.App"
SHARED_FRAMEWORKS = [ASPNETCORE_FRAMEWORK, WINDOWSDESKTOP_FRAMEWORK]

# Shared frameworks that need a Windows target framework and runtime identifier.
WINDOWS_ONLY_FRAMEWORKS = [WINDOWSDESKTOP_FRAMEWORK]

# The SDK's KnownFrameworkReference items: shared framework and profile. A
# profile narrows the reference assemblies and analyzers to those its
# FrameworkList.xml marks; at run time the whole framework is used.
FRAMEWORK_REFERENCES = {
    "Microsoft.AspNetCore.App": (ASPNETCORE_FRAMEWORK, None),
    "Microsoft.WindowsDesktop.App": (WINDOWSDESKTOP_FRAMEWORK, None),
    "Microsoft.WindowsDesktop.App.WPF": (WINDOWSDESKTOP_FRAMEWORK, "WPF"),
    "Microsoft.WindowsDesktop.App.WindowsForms": (WINDOWSDESKTOP_FRAMEWORK, "WindowsForms"),
}

# How each shared framework appears in pack repository package names.
_FRAMEWORK_KEYS = {
    ASPNETCORE_FRAMEWORK: "aspnetcore",
    WINDOWSDESKTOP_FRAMEWORK: "windowsdesktop",
}

# The profiles each shared framework's FrameworkList.xml defines.
_FRAMEWORK_PROFILES = {
    ASPNETCORE_FRAMEWORK: [],
    WINDOWSDESKTOP_FRAMEWORK: ["WPF", "WindowsForms"],
}

# The pack repository package for targets referencing only Microsoft.NETCore.App.
NO_SHARED_FRAMEWORKS = "default"

def resolve_framework_references(project_sdk, framework_references):
    """The shared frameworks a target references, and the profiles of each.

    The web SDK, and the SDKs based on it, imply Microsoft.AspNetCore.App.
    References to one framework combine: one without a profile takes the
    whole framework.

    Args:
      project_sdk: The `project_sdk` of the target.
      framework_references: The `framework_references` of the target.

    Returns:
      A dict of shared framework to a sorted list of profiles, or None for
      the whole framework. Microsoft.NETCore.App is never included.
    """
    references = list(framework_references)
    if normalize_project_sdk(project_sdk) == WEB_SDK:
        references.append(ASPNETCORE_FRAMEWORK)

    frameworks = {}
    for reference in references:
        if reference == NETCORE_FRAMEWORK:
            fail("Microsoft.NETCore.App is referenced implicitly; leave it out of `framework_references`.")

        if reference not in FRAMEWORK_REFERENCES:
            fail("Unknown framework reference {}. Known ones are {}.".format(
                repr(reference),
                ", ".join(FRAMEWORK_REFERENCES.keys()),
            ))

        (framework, profile) = FRAMEWORK_REFERENCES[reference]
        if profile == None or frameworks.get(framework, []) == None:
            frameworks[framework] = None
        else:
            frameworks[framework] = sorted({p: None for p in frameworks.get(framework, []) + [profile]}.keys())

    return {framework: frameworks[framework] for framework in SHARED_FRAMEWORKS if framework in frameworks}

def framework_references_of(frameworks):
    """The `framework_references` that reference exactly `frameworks`.

    Args:
      frameworks: The shared frameworks, as `resolve_framework_references`
        returns them.

    Returns:
      A list of framework reference names, as a NuGet package lists them.
    """
    references = []
    for (framework, profiles) in frameworks.items():
        if profiles == None:
            references.append(framework)
        else:
            references.extend(["{}.{}".format(framework, profile) for profile in profiles])

    return references

def frameworks_key(frameworks, profiles = True):
    """The package of the pack repositories that holds a set of shared frameworks.

    Args:
      frameworks: The shared frameworks, as `resolve_framework_references`
        returns them.
      profiles: Whether profiles are part of the key. Runtime packs always
        carry the whole framework.

    Returns:
      The package name, `default` for none.
    """
    parts = []
    for framework in SHARED_FRAMEWORKS:
        if framework not in frameworks:
            continue

        part = _FRAMEWORK_KEYS[framework]
        if profiles and frameworks[framework] != None:
            part += "." + ".".join([profile.lower() for profile in frameworks[framework]])

        parts.append(part)

    return "_".join(parts) if parts else NO_SHARED_FRAMEWORKS

def _framework_combinations(profiles):
    """Every set of shared frameworks a target can reference.

    Args:
      profiles: Whether sets that differ only in profiles count as different.

    Returns:
      A list of dicts, as `resolve_framework_references` returns them.
    """
    combinations = [{}]
    for framework in SHARED_FRAMEWORKS:
        choices = [None]
        if profiles:
            available = _FRAMEWORK_PROFILES[framework]

            # Every non-empty subset of the framework's profiles.
            for mask in range(1, 1 << len(available)):
                choices.append(sorted([available[i] for i in range(len(available)) if mask & (1 << i)]))

        combinations = combinations + [
            combination | {framework: choice}
            for combination in combinations
            for choice in choices
        ]

    return combinations

# Every combination of shared frameworks to compile against, and to run on.
TARGETING_FRAMEWORK_SETS = _framework_combinations(profiles = True)
RUNTIME_FRAMEWORK_SETS = _framework_combinations(profiles = False)

def normalize_project_sdk(project_sdk):
    """Maps a project SDK onto the one whose packs back it.

    Args:
      project_sdk: The SDK named on the target.

    Returns:
      The project SDK whose packs should be resolved.
    """
    return WEB_SDK if project_sdk in [RAZOR_SDK, BLAZORWASM_SDK] else project_sdk

def uses_razor(project_sdk):
    """Whether a project SDK compiles Razor sources.

    Args:
      project_sdk: The SDK named on the target.

    Returns:
      True if `.razor` and `.cshtml` sources are supported.
    """
    return normalize_project_sdk(project_sdk) == WEB_SDK

# A target compiles against the reference packs of the SDK that compiles it, so
# there is one pack set per toolchain type. The sets are built identically and
# differ only in the SDK version that moved their band.
USER_PACKS = "user"
BOOTSTRAP_PACKS = "bootstrap"
PACK_SETS = [USER_PACKS, BOOTSTRAP_PACKS]

_NETSTANDARD_PACKS = {
    "netstandard1.6": ("NETStandard.Library", "1.6.1"),
    "netstandard2.0": ("NETStandard.Library", "2.0.3"),
    "netstandard2.1": ("NETStandard.Library.Ref", "2.1.0"),
}

_NETFRAMEWORK_TFMS = [
    "net20",
    "net35",
    "net40",
    "net45",
    "net451",
    "net452",
    "net46",
    "net461",
    "net462",
    "net47",
    "net471",
    "net472",
    "net48",
    "net481",
]

_NETFRAMEWORK_PACK_VERSION = "1.0.3"

def _app_pack_id(tfm, aspnet, suffix = ""):
    base = "Microsoft.AspNetCore.App" if aspnet else "Microsoft.NETCore.App"

    if suffix:
        return "{}.{}".format(base, suffix)

    # .NET Core 3.0 split the shared framework into a reference pack and a
    # runtime pack; before that one package carried both.
    return base if tfm.startswith("netcoreapp1") or tfm.startswith("netcoreapp2") else base + ".Ref"

def _has_framework(band, framework):
    """Whether a band shipped a shared framework at all."""
    if framework == ASPNETCORE_FRAMEWORK:
        return "web_ref" in band

    # Every band since .NET Core 3.0 ships Windows Forms and WPF.
    return "windowsdesktop_rids" in band

def _shared_framework_ref_pack(tfm, framework, band):
    if framework == ASPNETCORE_FRAMEWORK:
        return (_app_pack_id(tfm, True), band["web_ref"])

    return ("Microsoft.WindowsDesktop.App.Ref", band["ref"])

def targeting_packs(tfm, frameworks = {}, *, bands):
    """Returns the targeting packs a target framework compiles against.

    Windows Forms and WPF add no pack on .NET Framework, where they are part of
    the framework, or on .NET Standard.

    Args:
      tfm: The target framework.
      frameworks: The shared frameworks referenced beyond Microsoft.NETCore.App,
        as `resolve_framework_references` returns them.
      bands: The bands to take versions from: `PACK_BANDS` where only which
        packs exist matters.

    Returns:
      A list of (package id, version) tuples, empty if the combination has no
      targeting pack. The shared frameworks' packs come first.
    """

    # ASP.NET Core only exists on .NET Core and .NET.
    if tfm in _NETSTANDARD_PACKS or tfm in _NETFRAMEWORK_TFMS:
        if [framework for framework in frameworks if framework not in WINDOWS_ONLY_FRAMEWORKS]:
            return []

    if tfm in _NETSTANDARD_PACKS:
        return [_NETSTANDARD_PACKS[tfm]]

    if tfm in _NETFRAMEWORK_TFMS:
        return [("Microsoft.NETFramework.ReferenceAssemblies." + tfm, _NETFRAMEWORK_PACK_VERSION)]

    band = bands.get(tfm)
    if band == None:
        return []

    packs = []
    for framework in SHARED_FRAMEWORKS:
        if framework not in frameworks:
            continue

        if not _has_framework(band, framework):
            return []

        packs.append(_shared_framework_ref_pack(tfm, framework, band))

    return packs + [(_app_pack_id(tfm, False), band["ref"])]

def targeting_pack_profiles(tfm, frameworks):
    """The profile each targeting pack is narrowed to, where one is.

    Args:
      tfm: The target framework.
      frameworks: The shared frameworks, as `resolve_framework_references`
        returns them.

    Returns:
      A dict of package id to the list of profiles to keep.
    """
    if tfm in _NETFRAMEWORK_TFMS or tfm in _NETSTANDARD_PACKS:
        return {}

    band = PACK_BANDS.get(tfm)
    if band == None:
        return {}

    return {
        _shared_framework_ref_pack(tfm, framework, band)[0]: profiles
        for (framework, profiles) in frameworks.items()
        if profiles != None and _has_framework(band, framework)
    }

def runtime_packs(tfm, rid, frameworks = {}, *, bands):
    """Returns the runtime packs a self-contained publish needs.

    Args:
      tfm: The target framework.
      rid: The runtime identifier.
      frameworks: The shared frameworks referenced beyond Microsoft.NETCore.App,
        as `resolve_framework_references` returns them. Profiles are ignored.
      bands: The bands to take versions from: `PACK_BANDS` where only which
        packs exist matters.

    Returns:
      A list of (package id, version) tuples, empty if the combination has no
      runtime pack. The shared frameworks' packs come first.
    """
    if rid not in runtime_pack_rids(tfm, frameworks):
        return []

    band = bands[tfm]

    packs = []
    for framework in SHARED_FRAMEWORKS:
        if framework not in frameworks:
            continue

        pack_id = _app_pack_id(tfm, True, "Runtime." + rid) if framework == ASPNETCORE_FRAMEWORK else "Microsoft.WindowsDesktop.App.Runtime." + rid
        packs.append((pack_id, band["runtime"]))

    return packs + [(_app_pack_id(tfm, False, "Runtime." + rid), band["runtime"])]

# Blazor WebAssembly has exactly one target, so unlike every other runtime pack
# this one's runtime identifier is fixed.
WASM_RID = "browser-wasm"

def wasm_pack_tfms():
    """Returns the target frameworks that can run on WebAssembly.

    Returns:
      A list of target frameworks.
    """
    return [tfm for tfm in PACK_BANDS if "wasm" in PACK_BANDS[tfm]]

def wasm_runtime_pack(tfm, *, bands):
    """Returns the runtime pack a Blazor WebAssembly application runs on.

    Args:
      tfm: The target framework.
      bands: The bands to take versions from: `PACK_BANDS` where only which
        packs exist matters.

    Returns:
      A (package id, version) tuple, or None if the band predates Blazor
      WebAssembly.
    """
    band = bands.get(tfm)
    if band == None or "wasm" not in band:
        return None

    # A browser runs Mono rather than CoreCLR, which is why this is the one
    # runtime pack id carrying an infix.
    return (_app_pack_id(tfm, False, "Runtime.Mono." + WASM_RID), band["wasm"])

# The tools a WebAssembly publish runs, rather than anything it links against,
# keyed by the pack band field carrying each one's version.
_WASM_TOOL_PACKS = {
    "wasm_sdk": "Microsoft.NET.Sdk.WebAssembly.Pack",
    "illink": "Microsoft.NET.ILLink.Tasks",
    "internal_assets": "Microsoft.AspNetCore.App.Internal.Assets",
    "devserver": "Microsoft.AspNetCore.Components.WebAssembly.DevServer",
}

def wasm_tool_packs(tfm, *, bands):
    """Returns the tool packs a Blazor WebAssembly publish runs.

    Args:
      tfm: The target framework.
      bands: The bands to take versions from: `PACK_BANDS` where only which
        packs exist matters.

    Returns:
      A list of (name, (package id, version)) tuples, empty if the band carries
      no WebAssembly toolchain.
    """
    band = bands.get(tfm, {})

    return [
        (name, (id, band[name]))
        for (name, id) in _WASM_TOOL_PACKS.items()
        if name in band
    ]

def wasm_tool_pack_names(tfm):
    """Returns which tool packs a Blazor WebAssembly publish runs.

    Args:
      tfm: The target framework.

    Returns:
      A list of names, as `wasm_tool_packs` gives them.
    """
    return [name for (name, _) in wasm_tool_packs(tfm, bands = PACK_BANDS)]

def apphost_pack(tfm, rid, *, bands):
    """Returns the apphost pack that produces a native executable.

    Args:
      tfm: The target framework.
      rid: The runtime identifier.
      bands: The bands to take versions from: `PACK_BANDS` where only which
        packs exist matters.

    Returns:
      A (package id, version) tuple, or None if there is no apphost pack.
    """
    if rid not in runtime_pack_rids(tfm):
        return None

    return (_app_pack_id(tfm, False, "Host." + rid), bands[tfm]["runtime"])

def crossgen2_pack_rids(tfm):
    """Returns the host runtime identifiers a target framework ships crossgen2 for.

    A band lists them only where crossgen2 shipped for fewer hosts than the
    runtime did; otherwise it shipped for all of them.

    Args:
      tfm: The target framework.

    Returns:
      A list of runtime identifiers, empty if the band predates crossgen2.
    """
    band = PACK_BANDS.get(tfm, {})

    return band["crossgen2_rids"] if "crossgen2_rids" in band else runtime_pack_rids(tfm)

def crossgen2_pack(tfm, rid, *, bands):
    """Returns the crossgen2 pack that compiles ReadyToRun images.

    Keyed by the *host* runtime identifier, not the target: crossgen2 runs on
    the build machine and cross-compiles via --targetos/--targetarch.

    Args:
      tfm: The target framework.
      rid: The runtime identifier of the machine crossgen2 will run on.
      bands: The bands to take versions from: `PACK_BANDS` where only which
        packs exist matters.

    Returns:
      A (package id, version) tuple, or None if there is no crossgen2 pack.
    """
    if rid not in crossgen2_pack_rids(tfm):
        return None

    return (_app_pack_id(tfm, False, "Crossgen2." + rid), bands[tfm]["runtime"])

def aot_pack_rids(tfm):
    """Returns the runtime identifiers a target framework can publish AOT for.

    A band carries an ILCompiler version only where NativeAOT ships a runtime
    pack of its own, which is from .NET 9 onwards.

    Args:
      tfm: The target framework.

    Returns:
      A list of runtime identifiers, empty if the band predates NativeAOT.
    """
    return runtime_pack_rids(tfm) if "ilcompiler" in PACK_BANDS.get(tfm, {}) else []

def aot_pack_tfms():
    """Returns the target frameworks that can publish NativeAOT.

    Returns:
      A list of target frameworks.
    """
    return [tfm for tfm in runtime_pack_tfms() if aot_pack_rids(tfm)]

def ilcompiler_pack(tfm, rid, *, bands):
    """Returns the ILCompiler pack that compiles IL to native code.

    Keyed by the *host* runtime identifier, not the target: ilc runs on the
    build machine and cross-compiles via --targetos/--targetarch.

    Args:
      tfm: The target framework.
      rid: The runtime identifier of the machine ilc will run on.
      bands: The bands to take versions from: `PACK_BANDS` where only which
        packs exist matters.

    Returns:
      A (package id, version) tuple, or None if there is no ILCompiler pack.
    """
    if rid not in aot_pack_rids(tfm):
        return None

    return (
        "runtime.{}.Microsoft.DotNet.ILCompiler".format(rid),
        bands[tfm]["ilcompiler"],
    )

def nativeaot_pack(tfm, rid, *, bands):
    """Returns the runtime pack a NativeAOT publish compiles and links against.

    Distinct from the JIT runtime pack: the assemblies are built for AOT, and
    the pack carries the static libraries the native link needs. It is built
    alongside ilc and shares its version.

    Args:
      tfm: The target framework.
      rid: The runtime identifier being published for.
      bands: The bands to take versions from: `PACK_BANDS` where only which
        packs exist matters.

    Returns:
      A (package id, version) tuple, or None if there is no NativeAOT pack.
    """
    if rid not in aot_pack_rids(tfm):
        return None

    return (
        _app_pack_id(tfm, False, "Runtime.NativeAOT." + rid),
        bands[tfm]["ilcompiler"],
    )

def ilcompiler_build_pack(tfm, rid, *, bands):
    """Returns the package holding what the SDK's own build feeds ilc.

    ilc and the runtime ship per runtime identifier; the MSBuild targets that
    drive them, and the data files those targets hand to ilc, ship once in a
    package of their own. Only a Windows publish reads anything from it: the
    list of Windows APIs that are safe to bind directly.

    Args:
      tfm: The target framework.
      rid: The runtime identifier being published for.
      bands: The bands to take versions from: `PACK_BANDS` where only which
        packs exist matters.

    Returns:
      A (package id, version) tuple, or None if the publish needs nothing
      from the package.
    """
    if rid not in aot_pack_rids(tfm) or not rid.startswith("win-"):
        return None

    return ("Microsoft.DotNet.ILCompiler", bands[tfm]["ilcompiler"])

def runtime_pack_rids(tfm, frameworks = {}):
    """Returns the runtime identifiers a target framework shipped packs for.

    Args:
      tfm: The target framework.
      frameworks: The shared frameworks referenced beyond Microsoft.NETCore.App,
        as `resolve_framework_references` returns them. Only runtime
        identifiers all of them have runtime packs for are returned.

    Returns:
      A list of runtime identifiers, empty if there are no runtime packs.
    """
    band = PACK_BANDS.get(tfm)
    if band == None or "runtime" not in band:
        return []

    rids = band["rids"]
    for framework in SHARED_FRAMEWORKS:
        if framework not in frameworks:
            continue

        if not _has_framework(band, framework):
            return []

        shipped = band.get("web_rids", band["rids"]) if framework == ASPNETCORE_FRAMEWORK else band["windowsdesktop_rids"]
        rids = [rid for rid in rids if rid in shipped]

    return rids

def targeting_pack_tfms(frameworks = {}):
    """Returns the target frameworks that have a targeting pack.

    Args:
      frameworks: The shared frameworks referenced beyond Microsoft.NETCore.App,
        as `resolve_framework_references` returns them.

    Returns:
      A list of target frameworks.
    """
    return [
        tfm
        for tfm in list(_NETSTANDARD_PACKS.keys()) + _NETFRAMEWORK_TFMS + list(PACK_BANDS.keys())
        if targeting_packs(tfm, frameworks, bands = PACK_BANDS)
    ]

def runtime_pack_tfms():
    """Returns the target frameworks that have runtime and apphost packs.

    Returns:
      A list of target frameworks.
    """
    return [tfm for tfm in PACK_BANDS if "runtime" in PACK_BANDS[tfm]]

# Pack targets are named for what they provide, so a version change does not
# move any label.
TARGETING_PACK_REPO = "dotnet.targeting_packs"

RUNTIME_PACK_REPO = "dotnet.runtime_packs"

APPHOST_PACK_REPO = "dotnet.apphost_packs"

CROSSGEN2_PACK_REPO = "dotnet.crossgen2_packs"

ILCOMPILER_PACK_REPO = "dotnet.ilcompiler_packs"

NATIVEAOT_PACK_REPO = "dotnet.nativeaot_packs"

WASM_PACK_REPO = "dotnet.wasm_packs"

# The package of the tool pack repositories that holds the newest band the SDK
# knows, which is its own: the tools to run on its runtime whatever the
# framework, and those for a framework older than every band.
NEWEST_BAND = "newest"

# By pack set, then by `frameworks_key`, then by target framework.
TARGETING_PACK_LOOKUP_TABLE = {
    pack_set: {
        frameworks_key(frameworks): {
            tfm: "@{}//{}/{}:{}".format(TARGETING_PACK_REPO, pack_set, frameworks_key(frameworks), tfm)
            for tfm in targeting_pack_tfms(frameworks)
        }
        for frameworks in TARGETING_FRAMEWORK_SETS
    }
    for pack_set in PACK_SETS
}

# The runtime identifiers a build can run on, and so the ones the tool packs
# are fetched for. Each has a platform `config_setting` the tool packs' `host`
# aliases select over; a musl host is not distinguishable as a Bazel platform
# here.
HOST_RIDS = [
    "linux-arm64",
    "linux-x64",
    "osx-arm64",
    "osx-x64",
    "win-arm64",
    "win-x64",
]

def host_platform_setting(rid):
    """The `config_setting` that matches the platform of a host runtime identifier.

    Args:
      rid: One of `HOST_RIDS`.

    Returns:
      The label of the `config_setting`.
    """
    return "@rules_dotnet//dotnet/private:" + rid.replace("win-", "windows-")

def host_tool_tfms(pack):
    """The target frameworks a host tool shipped for on at least one host.

    Args:
      pack: Returns the (id, version) of the tool's pack for a tfm, host rid
        and bands, or None where the tool did not ship for that combination.

    Returns:
      A list of target frameworks, oldest band first.
    """
    return [
        tfm
        for tfm in runtime_pack_tfms()
        if any([pack(tfm, rid, bands = PACK_BANDS) != None for rid in HOST_RIDS])
    ]

def _host_tool_bands(repo, pack):
    bands = {tfm: "@{}//{}:host".format(repo, tfm) for tfm in host_tool_tfms(pack)}

    # A framework older than every band, such as netstandard2.0, gets the newest
    # the SDK knows.
    bands[NEWEST_BAND] = "@{}//{}:host".format(repo, NEWEST_BAND)

    return bands

# The `host` alias of each band a host tool shipped for, by target framework,
# and that of the newest band the SDK knows under `NEWEST_BAND`.
CROSSGEN2_PACK_LOOKUP_TABLE = _host_tool_bands(CROSSGEN2_PACK_REPO, crossgen2_pack)

ILCOMPILER_PACK_LOOKUP_TABLE = _host_tool_bands(ILCOMPILER_PACK_REPO, ilcompiler_pack)

# By `frameworks_key(frameworks, profiles = False)`, then by target framework,
# then by runtime identifier.
RUNTIME_PACK_LOOKUP_TABLE = {
    frameworks_key(frameworks, profiles = False): {
        tfm: {
            rid: "@{}//{}/{}:{}".format(RUNTIME_PACK_REPO, frameworks_key(frameworks, profiles = False), tfm, rid)
            for rid in runtime_pack_rids(tfm, frameworks)
        }
        for tfm in runtime_pack_tfms()
    }
    for frameworks in RUNTIME_FRAMEWORK_SETS
}

APPHOST_PACK_LOOKUP_TABLE = {
    tfm: {
        rid: "@{}//{}:{}".format(APPHOST_PACK_REPO, tfm, rid)
        for rid in runtime_pack_rids(tfm)
    }
    for tfm in runtime_pack_tfms()
}

NATIVEAOT_PACK_LOOKUP_TABLE = {
    tfm: {
        rid: "@{}//{}:{}".format(NATIVEAOT_PACK_REPO, tfm, rid)
        for rid in aot_pack_rids(tfm)
    }
    for tfm in aot_pack_tfms()
}
