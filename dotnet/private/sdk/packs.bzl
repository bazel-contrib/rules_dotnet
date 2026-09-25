"""The NuGet packs that back each target framework.

A .NET release publishes its packs under a handful of predictable names, so
`PACK_BANDS` only has to pin the version each target framework resolves to and
which runtime identifiers that release shipped. The pack ids, the set of
targets, and the tables the pack transitions read are all derived from it.

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

def targeting_packs(tfm, project_sdk = DEFAULT_SDK):
    """Returns the targeting packs a target framework compiles against.

    Args:
      tfm: The target framework.
      project_sdk: The project SDK, `default` or `web`.

    Returns:
      A list of (package id, version) tuples, empty if the combination has no
      targeting pack.
    """
    if project_sdk not in PROJECT_SDKS:
        return []

    if project_sdk == DEFAULT_SDK:
        if tfm in _NETSTANDARD_PACKS:
            return [_NETSTANDARD_PACKS[tfm]]

        if tfm in _NETFRAMEWORK_TFMS:
            return [("Microsoft.NETFramework.ReferenceAssemblies." + tfm, _NETFRAMEWORK_PACK_VERSION)]

    band = PACK_BANDS.get(tfm)
    if band == None:
        return []

    if project_sdk == DEFAULT_SDK:
        return [(_app_pack_id(tfm, False), band["ref"])]

    if "web_ref" not in band:
        return []

    return [
        (_app_pack_id(tfm, True), band["web_ref"]),
        (_app_pack_id(tfm, False), band["ref"]),
    ]

def runtime_packs(tfm, rid, project_sdk = DEFAULT_SDK):
    """Returns the runtime packs a self-contained publish needs.

    Args:
      tfm: The target framework.
      rid: The runtime identifier.
      project_sdk: The project SDK, `default` or `web`.

    Returns:
      A list of (package id, version) tuples, empty if the combination has no
      runtime pack.
    """
    if rid not in runtime_pack_rids(tfm, project_sdk):
        return []

    band = PACK_BANDS[tfm]

    packs = [(_app_pack_id(tfm, False, "Runtime." + rid), band["runtime"])]

    if project_sdk == WEB_SDK:
        packs.insert(0, (_app_pack_id(tfm, True, "Runtime." + rid), band["runtime"]))

    return packs

# Blazor WebAssembly has exactly one target, so unlike every other runtime pack
# this one's runtime identifier is fixed.
WASM_RID = "browser-wasm"

def wasm_pack_tfms():
    """Returns the target frameworks that can run on WebAssembly.

    Returns:
      A list of target frameworks.
    """
    return [tfm for tfm in PACK_BANDS if "wasm" in PACK_BANDS[tfm]]

def wasm_runtime_pack(tfm):
    """Returns the runtime pack a Blazor WebAssembly application runs on.

    Args:
      tfm: The target framework.

    Returns:
      A (package id, version) tuple, or None if the band predates Blazor
      WebAssembly.
    """
    band = PACK_BANDS.get(tfm)
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

def wasm_tool_packs(tfm):
    """Returns the tool packs a Blazor WebAssembly publish runs.

    Args:
      tfm: The target framework.

    Returns:
      A list of (name, (package id, version)) tuples, empty if the band carries
      no WebAssembly toolchain.
    """
    band = PACK_BANDS.get(tfm, {})

    return [
        (name, (id, band[name]))
        for (name, id) in _WASM_TOOL_PACKS.items()
        if name in band
    ]

def apphost_pack(tfm, rid):
    """Returns the apphost pack that produces a native executable.

    Args:
      tfm: The target framework.
      rid: The runtime identifier.

    Returns:
      A (package id, version) tuple, or None if there is no apphost pack.
    """
    if rid not in runtime_pack_rids(tfm):
        return None

    return (_app_pack_id(tfm, False, "Host." + rid), PACK_BANDS[tfm]["runtime"])

def crossgen2_pack(tfm, rid):
    """Returns the crossgen2 pack that compiles ReadyToRun images.

    Keyed by the *host* runtime identifier, not the target: crossgen2 runs on
    the build machine and cross-compiles via --targetos/--targetarch.

    Args:
      tfm: The target framework.
      rid: The runtime identifier of the machine crossgen2 will run on.

    Returns:
      A (package id, version) tuple, or None if there is no crossgen2 pack.
    """
    rids = PACK_BANDS.get(tfm, {}).get("crossgen2_rids", runtime_pack_rids(tfm))
    if rid not in rids:
        return None

    return (_app_pack_id(tfm, False, "Crossgen2." + rid), PACK_BANDS[tfm]["runtime"])

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

def ilcompiler_pack(tfm, rid):
    """Returns the ILCompiler pack that compiles IL to native code.

    Keyed by the *host* runtime identifier, not the target: ilc runs on the
    build machine and cross-compiles via --targetos/--targetarch.

    Args:
      tfm: The target framework.
      rid: The runtime identifier of the machine ilc will run on.

    Returns:
      A (package id, version) tuple, or None if there is no ILCompiler pack.
    """
    if rid not in aot_pack_rids(tfm):
        return None

    return (
        "runtime.{}.Microsoft.DotNet.ILCompiler".format(rid),
        PACK_BANDS[tfm]["ilcompiler"],
    )

def nativeaot_pack(tfm, rid):
    """Returns the runtime pack a NativeAOT publish compiles and links against.

    Distinct from the JIT runtime pack: the assemblies are built for AOT, and
    the pack carries the static libraries the native link needs. It is built
    alongside ilc and shares its version.

    Args:
      tfm: The target framework.
      rid: The runtime identifier being published for.

    Returns:
      A (package id, version) tuple, or None if there is no NativeAOT pack.
    """
    if rid not in aot_pack_rids(tfm):
        return None

    return (
        _app_pack_id(tfm, False, "Runtime.NativeAOT." + rid),
        PACK_BANDS[tfm]["ilcompiler"],
    )

def runtime_pack_rids(tfm, project_sdk = DEFAULT_SDK):
    """Returns the runtime identifiers a target framework shipped packs for.

    Args:
      tfm: The target framework.
      project_sdk: The project SDK, `default` or `web`.

    Returns:
      A list of runtime identifiers, empty if there are no runtime packs.
    """
    if project_sdk not in PROJECT_SDKS:
        return []

    band = PACK_BANDS.get(tfm)
    if band == None or "runtime" not in band:
        return []

    if project_sdk == WEB_SDK:
        return band.get("web_rids", band["rids"])

    return band["rids"]

def targeting_pack_tfms(project_sdk = DEFAULT_SDK):
    """Returns the target frameworks that have a targeting pack.

    Args:
      project_sdk: The project SDK, `default` or `web`.

    Returns:
      A list of target frameworks.
    """
    if project_sdk == WEB_SDK:
        return [tfm for tfm in PACK_BANDS if "web_ref" in PACK_BANDS[tfm]]

    if project_sdk not in PROJECT_SDKS:
        return []

    return list(_NETSTANDARD_PACKS.keys()) + _NETFRAMEWORK_TFMS + list(PACK_BANDS.keys())

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

TARGETING_PACK_LOOKUP_TABLE = {
    pack_set: {
        project_sdk: {
            tfm: "@{}//{}/{}:{}".format(TARGETING_PACK_REPO, pack_set, project_sdk, tfm)
            for tfm in targeting_pack_tfms(project_sdk)
        }
        for project_sdk in PROJECT_SDKS
    }
    for pack_set in PACK_SETS
}

# The runtime identifiers a build can run on, and so the ones the tool packs
# are fetched for. Matches the platforms the `crossgen2_pack` and
# `ilcompiler_pack` aliases select over; a musl host is not distinguishable as
# a Bazel platform here.
_HOST_RIDS = [
    "linux-arm64",
    "linux-x64",
    "osx-arm64",
    "osx-x64",
    "win-arm64",
    "win-x64",
]

def host_rids():
    """The runtime identifiers the tool packs are fetched for.

    Returns:
      A list of runtime identifiers.
    """
    return _HOST_RIDS

RUNTIME_PACK_LOOKUP_TABLE = {
    project_sdk: {
        tfm: {
            rid: "@{}//{}/{}:{}".format(RUNTIME_PACK_REPO, project_sdk, tfm, rid)
            for rid in runtime_pack_rids(tfm, project_sdk)
        }
        for tfm in runtime_pack_tfms()
    }
    for project_sdk in PROJECT_SDKS
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

def band_is_movable(tfm):
    """Returns whether a band's packs can all be moved to one version.

    A band whose packs already resolve to more than one version cannot be
    moved wholesale, so it stays where the table puts it.

    Args:
      tfm: The target framework whose band to check.

    Returns:
      True if every pack in the band resolves to the same version.
    """
    band = PACK_BANDS.get(tfm)
    if band == None:
        return False

    versions = {band[key]: None for key in ["ref", "web_ref", "runtime"] if key in band}

    return len(versions) == 1
