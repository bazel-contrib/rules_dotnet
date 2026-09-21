"""Tests for the packs derived from PACK_BANDS.

The pack transitions are on the toolchain path, so the sets of target
frameworks and runtime identifiers they resolve must not change.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/sdk:packs.bzl",
    "DEFAULT_SDK",
    "PROJECT_SDKS",
    "WEB_SDK",
    "apphost_pack",
    "runtime_pack_rids",
    "runtime_pack_tfms",
    "runtime_packs",
    "targeting_pack_tfms",
    "targeting_packs",
    "wasm_pack_tfms",
    "wasm_runtime_pack",
)

# Only the sets derived from `pack_bands.bzl` can drift; the netstandard and
# .NET Framework target frameworks are literals in packs.bzl.
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

# Apple silicon packs only exist from .NET 6.
_PRE_NET6_RIDS = [
    "linux-arm64",
    "linux-musl-arm64",
    "linux-musl-x64",
    "linux-x64",
    "osx-x64",
    "win-arm64",
    "win-x64",
]

_BAND_TFMS = {
    "default": [
        "net10.0",
        "net5.0",
        "net6.0",
        "net7.0",
        "net8.0",
        "net9.0",
        "netcoreapp1.0",
        "netcoreapp1.1",
        "netcoreapp2.0",
        "netcoreapp2.1",
        "netcoreapp2.2",
        "netcoreapp3.0",
        "netcoreapp3.1",
    ],
    "web": [
        "net10.0",
        "net5.0",
        "net6.0",
        "net7.0",
        "net8.0",
        "net9.0",
        "netcoreapp2.1",
        "netcoreapp2.2",
        "netcoreapp3.0",
        "netcoreapp3.1",
    ],
}

_RUNTIME_PACK_RIDS = {
    "net10.0": _ALL_RIDS,
    "net5.0": _PRE_NET6_RIDS,
    "net6.0": _ALL_RIDS,
    "net7.0": _ALL_RIDS,
    "net8.0": _ALL_RIDS,
    "net9.0": _ALL_RIDS,
    "netcoreapp3.0": _PRE_NET6_RIDS,
    "netcoreapp3.1": _PRE_NET6_RIDS,
}

# ASP.NET Core did not ship a win-arm64 runtime pack for 3.0.
_WEB_RUNTIME_PACK_RIDS = {
    "netcoreapp3.0": [rid for rid in _PRE_NET6_RIDS if rid != "win-arm64"],
}

def _targeting_table_test_impl(ctx):
    env = unittest.begin(ctx)

    for project_sdk in PROJECT_SDKS:
        bands = _BAND_TFMS[project_sdk]
        asserts.equals(
            env,
            bands,
            sorted([tfm for tfm in targeting_pack_tfms(project_sdk) if tfm in bands]),
            "bands with a targeting pack for the {} SDK".format(project_sdk),
        )

        for tfm in targeting_pack_tfms(project_sdk):
            asserts.true(
                env,
                len(targeting_packs(tfm, project_sdk)) > 0,
                "{}/{} resolves to at least one targeting pack".format(project_sdk, tfm),
            )

    return unittest.end(env)

_targeting_table_test = unittest.make(_targeting_table_test_impl)

def _runtime_table_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, sorted(_RUNTIME_PACK_RIDS.keys()), sorted(runtime_pack_tfms()))

    for project_sdk in PROJECT_SDKS:
        for tfm in runtime_pack_tfms():
            expected = _RUNTIME_PACK_RIDS[tfm]
            if project_sdk == WEB_SDK:
                expected = _WEB_RUNTIME_PACK_RIDS.get(tfm, expected)
            asserts.equals(
                env,
                expected,
                sorted(runtime_pack_rids(tfm, project_sdk)),
                "runtime pack RIDs for {}/{}".format(project_sdk, tfm),
            )

            for rid in expected:
                asserts.true(
                    env,
                    len(runtime_packs(tfm, rid, project_sdk)) > 0,
                    "{}/{}/{} resolves to at least one runtime pack".format(project_sdk, tfm, rid),
                )

    return unittest.end(env)

_runtime_table_test = unittest.make(_runtime_table_test_impl)

def _apphost_table_test_impl(ctx):
    env = unittest.begin(ctx)

    for tfm in runtime_pack_tfms():
        for rid in runtime_pack_rids(tfm):
            asserts.true(env, apphost_pack(tfm, rid) != None, "{}/{} has an apphost pack".format(tfm, rid))

    return unittest.end(env)

_apphost_table_test = unittest.make(_apphost_table_test_impl)

# One case per package id shape.
_TARGETING_PACKS = [
    (("netstandard2.0", DEFAULT_SDK), [("NETStandard.Library", "2.0.3")]),
    (("netstandard2.1", DEFAULT_SDK), [("NETStandard.Library.Ref", "2.1.0")]),
    (("net48", DEFAULT_SDK), [("Microsoft.NETFramework.ReferenceAssemblies.net48", "1.0.3")]),
    (("netcoreapp2.1", DEFAULT_SDK), [("Microsoft.NETCore.App", "2.1.30")]),
    (("net10.0", DEFAULT_SDK), [("Microsoft.NETCore.App.Ref", "10.0.12")]),
    (("netcoreapp2.1", WEB_SDK), [
        ("Microsoft.AspNetCore.App", "2.1.34"),
        ("Microsoft.NETCore.App", "2.1.30"),
    ]),
    (("netcoreapp3.1", WEB_SDK), [
        ("Microsoft.AspNetCore.App.Ref", "3.1.10"),
        ("Microsoft.NETCore.App.Ref", "3.1.0"),
    ]),
    (("net10.0", "nonsense"), []),
]

_RUNTIME_PACKS = [
    (("net5.0", "linux-x64", DEFAULT_SDK), [("Microsoft.NETCore.App.Runtime.linux-x64", "5.0.17")]),
    (("net10.0", "win-arm64", WEB_SDK), [
        ("Microsoft.AspNetCore.App.Runtime.win-arm64", "10.0.12"),
        ("Microsoft.NETCore.App.Runtime.win-arm64", "10.0.12"),
    ]),
]

def _pack_ids_test_impl(ctx):
    env = unittest.begin(ctx)

    for ((tfm, project_sdk), expected) in _TARGETING_PACKS:
        asserts.equals(env, expected, targeting_packs(tfm, project_sdk), "{}/{}".format(project_sdk, tfm))

    for ((tfm, rid, project_sdk), expected) in _RUNTIME_PACKS:
        asserts.equals(
            env,
            expected,
            runtime_packs(tfm, rid, project_sdk),
            "{}/{}/{}".format(project_sdk, tfm, rid),
        )

    asserts.equals(
        env,
        ("Microsoft.NETCore.App.Host.osx-arm64", "10.0.12"),
        apphost_pack("net10.0", "osx-arm64"),
    )
    asserts.equals(
        env,
        None,
        apphost_pack("net5.0", "osx-arm64"),
        "Apple silicon packs only exist from .NET 6 onwards",
    )
    return unittest.end(env)

_pack_ids_test = unittest.make(_pack_ids_test_impl)

def _wasm_test_impl(ctx):
    env = unittest.begin(ctx)

    # A browser runs Mono, so this is the one runtime pack id with an infix.
    asserts.equals(
        env,
        ("Microsoft.NETCore.App.Runtime.Mono.browser-wasm", "10.0.12"),
        wasm_runtime_pack("net10.0"),
    )

    for tfm in ["netcoreapp3.1", "net5.0", "net9.0"]:
        asserts.equals(
            env,
            None,
            wasm_runtime_pack(tfm),
            "{} carries no WebAssembly toolchain".format(tfm),
        )

    for tfm in wasm_pack_tfms():
        asserts.true(
            env,
            wasm_runtime_pack(tfm) != None,
            "{} claims a WebAssembly pack and resolves one".format(tfm),
        )

    return unittest.end(env)

_wasm_test = unittest.make(_wasm_test_impl)

def packs_test_suite(name):
    unittest.suite(
        name,
        _apphost_table_test,
        _pack_ids_test,
        _runtime_table_test,
        _targeting_table_test,
        _wasm_test,
    )
