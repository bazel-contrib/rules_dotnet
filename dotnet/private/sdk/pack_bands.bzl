"""The .NET release band that each target framework's packs come from.

A band is what one .NET release shipped: its packs, keyed by the field holding
each one's version, and the runtime identifiers it shipped them for.

Bands up to .NET 5 are frozen history with irregularities of their own, so they
are spelled out with the versions they were last serviced at. From .NET 6
onwards a release ships all of its packs, for every runtime identifier, at
every patch, so those bands follow from SDK_NETCOREAPP_FRAMEWORKS, and which
patch a band is at is left to the SDK in use, the way the SDK picks the packs it
bundles. See `pack_bands`.

That includes the releases declared ahead of time, which are taken to need what
the newest release in `_PACKS_SINCE` and `_PACKS_DROPPED` does. An SDK only knows
the bands up to its own, so the others have no version until an SDK that knows
them is registered.
"""

load("//dotnet/private/sdk:frameworks.bzl", "SDK_NETCOREAPP_FRAMEWORKS")

_ALL_RIDS = [
    "linux-arm64",
    "linux-musl-arm64",
    "linux-musl-x64",
    "linux-x64",
    "osx-arm64",
    "osx-x64",
    "win-arm64",
    "win-x64",
]

# Apple silicon packs only exist from .NET 6 onwards.
_PRE_NET6_RIDS = [rid for rid in _ALL_RIDS if rid != "osx-arm64"]

_HISTORICAL_BANDS = {
    "netcoreapp1.0": {"ref": "1.0.16"},
    "netcoreapp1.1": {"ref": "1.1.13"},
    "netcoreapp2.0": {"ref": "2.0.9"},
    "netcoreapp2.1": {"ref": "2.1.30", "web_ref": "2.1.34"},
    "netcoreapp2.2": {"ref": "2.2.8", "web_ref": "2.2.8"},
    "netcoreapp3.0": {
        "ref": "3.0.1",
        "web_ref": "3.0.1",
        "runtime": "3.0.3",
        "rids": _PRE_NET6_RIDS,
        # ASP.NET Core did not ship a win-arm64 runtime pack for 3.0.
        "web_rids": [rid for rid in _PRE_NET6_RIDS if rid != "win-arm64"],
        # crossgen2 first shipped as a package in .NET 5.
        "crossgen2_rids": [],
    },
    "netcoreapp3.1": {
        "ref": "3.1.0",
        "web_ref": "3.1.10",
        "runtime": "3.1.32",
        "rids": _PRE_NET6_RIDS,
        "crossgen2_rids": [],
    },
    "net5.0": {
        "ref": "5.0.0",
        "web_ref": "5.0.0",
        "runtime": "5.0.17",
        "rids": _PRE_NET6_RIDS,
        # The Crossgen2RuntimeIdentifiers the .NET SDK lists for net5.0: it
        # first shipped for x64 hosts alone.
        "crossgen2_rids": ["linux-musl-x64", "linux-x64", "win-x64"],
    },
}

# The packs a band ships from .NET 6 onwards, by the major release that
# introduced them.
_PACKS_SINCE = [
    (6, ["ref", "web_ref", "runtime"]),
    # NativeAOT ships a runtime pack of its own, built alongside ilc.
    (9, ["ilcompiler"]),
    # Blazor WebAssembly, from when every piece of its toolchain shipped as a
    # package of its own.
    (10, ["wasm", "wasm_sdk", "illink", "internal_assets", "devserver"]),
]

# The packs a band from .NET 6 onwards no longer needs, by the major release
# that stopped needing them.
_PACKS_DROPPED = [
    # .NET 11 serves `blazor.webassembly.js` from the application's own
    # Microsoft.AspNetCore.Components.WebAssembly package.
    (11, ["internal_assets"]),
]

def _major(tfm):
    return int(tfm[len("net"):].split(".")[0])

# The bands whose version the SDK in use picks, oldest first.
SDK_BAND_TFMS = [
    tfm
    for tfm in SDK_NETCOREAPP_FRAMEWORKS
    if not tfm.startswith("netcoreapp") and _major(tfm) >= 6
]

def sdk_band_tfms(sdk_tfm):
    """The bands an SDK picks the version of: those up to its own.

    A release after the SDK's had not shipped when the SDK did, so the SDK
    cannot build for it.

    Args:
      sdk_tfm: The target framework the SDK's runtime is.

    Returns:
      A list of target frameworks, oldest first.
    """
    return [tfm for tfm in SDK_BAND_TFMS if _major(tfm) <= _major(sdk_tfm)]

def _sdk_band(tfm, version):
    band = {"rids": _ALL_RIDS}

    for (major, packs) in _PACKS_SINCE:
        if _major(tfm) >= major:
            for pack in packs:
                band[pack] = version

    for (major, packs) in _PACKS_DROPPED:
        if _major(tfm) >= major:
            for pack in packs:
                band.pop(pack)

    return band

def pack_bands(versions = {}):
    """Every band, with those from .NET 6 onwards at the versions given.

    Args:
      versions: The version of each band in `SDK_BAND_TFMS`, by target
        framework. A band left out has a version of None: one the SDK does not
        know, or one of the tables of which packs exist rather than of what to
        download.

    Returns:
      A dict of target framework to band, oldest first.
    """
    return _HISTORICAL_BANDS | {tfm: _sdk_band(tfm, versions.get(tfm)) for tfm in SDK_BAND_TFMS}

# Every band, with those the SDK picks the version of left unversioned: enough
# for the tables built while loading, which only care which packs exist.
PACK_BANDS = pack_bands()
