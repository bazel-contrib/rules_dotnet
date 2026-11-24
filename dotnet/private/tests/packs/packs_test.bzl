"""Tests for the packs derived from the pack bands.

The pack transitions are on the toolchain path, so the sets of target
frameworks and runtime identifiers they resolve must not change.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/sdk:pack_bands.bzl", "PACK_BANDS", "SDK_BAND_TFMS", "pack_bands", "sdk_band_tfms")
load(
    "//dotnet/private/sdk:packs.bzl",
    "ASPNETCORE_FRAMEWORK",
    "RUNTIME_FRAMEWORK_SETS",
    "TARGETING_FRAMEWORK_SETS",
    "WINDOWSDESKTOP_FRAMEWORK",
    "apphost_pack",
    "crossgen2_pack",
    "frameworks_key",
    "ilcompiler_build_pack",
    "ilcompiler_pack",
    "nativeaot_pack",
    "resolve_framework_references",
    "runtime_pack_rids",
    "runtime_pack_tfms",
    "runtime_packs",
    "targeting_pack_profiles",
    "targeting_pack_tfms",
    "targeting_packs",
    "wasm_pack_tfms",
    "wasm_runtime_pack",
    "wasm_tool_pack_names",
    "wasm_tool_packs",
)

# The bands as an SDK might resolve them: each at a version of its own, so a
# pack taking the wrong band's version shows.
_BANDS = pack_bands({
    "net6.0": "6.0.36",
    "net7.0": "7.0.20",
    "net8.0": "8.0.33",
    "net9.0": "9.0.22",
    "net10.0": "10.0.14",
})

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

# The releases after the newest these tables spell out, declared ahead of their
# release. Each ships what the newest spelled out does.
_DECLARED_AHEAD = SDK_BAND_TFMS[SDK_BAND_TFMS.index("net10.0") + 1:]

_CORE_TFMS = [
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
]

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

# The .NET Standard versions that have a targeting pack.
_NETSTANDARD_TFMS = ["netstandard1.6", "netstandard2.0", "netstandard2.1"]

# The bands each shared framework has a targeting pack in.
_FRAMEWORK_TFMS = {
    ASPNETCORE_FRAMEWORK: [
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
    # And every .NET Framework, whose own reference assemblies carry Windows
    # Forms and WPF, and .NET Standard, which they leave alone.
    WINDOWSDESKTOP_FRAMEWORK: [
        "net10.0",
        "net5.0",
        "net6.0",
        "net7.0",
        "net8.0",
        "net9.0",
        "netcoreapp3.0",
        "netcoreapp3.1",
    ] + _NETFRAMEWORK_TFMS + _NETSTANDARD_TFMS,
}

def _expected_targeting_tfms(frameworks):
    tfms = _CORE_TFMS + _NETFRAMEWORK_TFMS + _NETSTANDARD_TFMS
    for framework in frameworks:
        tfms = [tfm for tfm in tfms if tfm in _FRAMEWORK_TFMS[framework]]

    return sorted(tfms)

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

# The runtime identifiers each shared framework ships a runtime pack for, where
# they differ from Microsoft.NETCore.App's.
_FRAMEWORK_RIDS = {
    # ASP.NET Core did not ship a win-arm64 runtime pack for 3.0.
    ASPNETCORE_FRAMEWORK: {
        "netcoreapp3.0": [rid for rid in _PRE_NET6_RIDS if rid != "win-arm64"],
    },
    # Windows Forms and WPF ship for Windows alone, and for Arm64 from .NET 5.
    WINDOWSDESKTOP_FRAMEWORK: {
        "netcoreapp3.0": ["win-x64"],
        "netcoreapp3.1": ["win-x64"],
    },
}

def _expected_runtime_rids(tfm, frameworks):
    rids = _RUNTIME_PACK_RIDS.get(tfm, _ALL_RIDS)
    for framework in frameworks:
        shipped = _FRAMEWORK_RIDS[framework].get(tfm)
        if shipped == None:
            shipped = [rid for rid in rids if rid.startswith("win-")] if framework == WINDOWSDESKTOP_FRAMEWORK else rids
        rids = [rid for rid in rids if rid in shipped]

    return rids

def _targeting_table_test_impl(ctx):
    env = unittest.begin(ctx)

    for frameworks in TARGETING_FRAMEWORK_SETS:
        key = frameworks_key(frameworks)
        expected = _expected_targeting_tfms(frameworks)
        asserts.equals(
            env,
            expected,
            sorted([tfm for tfm in targeting_pack_tfms(frameworks) if tfm in _CORE_TFMS + _NETFRAMEWORK_TFMS + _NETSTANDARD_TFMS]),
            "bands with a targeting pack for {}".format(key),
        )
        asserts.equals(
            env,
            _DECLARED_AHEAD,
            targeting_pack_tfms(frameworks)[-len(_DECLARED_AHEAD):],
            "releases declared ahead with a targeting pack for {}".format(key),
        )

        for tfm in targeting_pack_tfms(frameworks):
            asserts.true(
                env,
                len(targeting_packs(tfm, frameworks, bands = PACK_BANDS)) > 0,
                "{}/{} resolves to at least one targeting pack".format(key, tfm),
            )

    return unittest.end(env)

_targeting_table_test = unittest.make(_targeting_table_test_impl)

def _runtime_table_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, sorted(_RUNTIME_PACK_RIDS.keys() + _DECLARED_AHEAD), sorted(runtime_pack_tfms()))

    for frameworks in RUNTIME_FRAMEWORK_SETS:
        key = frameworks_key(frameworks, profiles = False)
        for tfm in runtime_pack_tfms():
            expected = _expected_runtime_rids(tfm, frameworks)
            asserts.equals(
                env,
                expected,
                sorted(runtime_pack_rids(tfm, frameworks)),
                "runtime pack RIDs for {}/{}".format(key, tfm),
            )

            for rid in expected:
                asserts.true(
                    env,
                    len(runtime_packs(tfm, rid, frameworks, bands = PACK_BANDS)) > 0,
                    "{}/{}/{} resolves to at least one runtime pack".format(key, tfm, rid),
                )

    return unittest.end(env)

_runtime_table_test = unittest.make(_runtime_table_test_impl)

def _apphost_table_test_impl(ctx):
    env = unittest.begin(ctx)

    for tfm in runtime_pack_tfms():
        for rid in runtime_pack_rids(tfm):
            asserts.true(env, apphost_pack(tfm, rid, bands = PACK_BANDS) != None, "{}/{} has an apphost pack".format(tfm, rid))

    return unittest.end(env)

_apphost_table_test = unittest.make(_apphost_table_test_impl)

# crossgen2 first shipped as a package in .NET 5, for x64 hosts alone. Every
# later band ships it for every runtime identifier.
_CROSSGEN2_RIDS = {
    "net5.0": ["linux-musl-x64", "linux-x64", "win-x64"],
    "netcoreapp3.0": [],
    "netcoreapp3.1": [],
}

def _crossgen2_table_test_impl(ctx):
    env = unittest.begin(ctx)

    for tfm in runtime_pack_tfms():
        asserts.equals(
            env,
            _CROSSGEN2_RIDS.get(tfm, _RUNTIME_PACK_RIDS.get(tfm, _ALL_RIDS)),
            [rid for rid in _ALL_RIDS if crossgen2_pack(tfm, rid, bands = PACK_BANDS) != None],
            "crossgen2 pack RIDs for {}".format(tfm),
        )

    asserts.equals(
        env,
        ("Microsoft.NETCore.App.Crossgen2.linux-x64", "5.0.17"),
        crossgen2_pack("net5.0", "linux-x64", bands = _BANDS),
    )

    return unittest.end(env)

_crossgen2_table_test = unittest.make(_crossgen2_table_test_impl)

_WEB = {ASPNETCORE_FRAMEWORK: None}
_WPF = {WINDOWSDESKTOP_FRAMEWORK: ["WPF"]}

# One case per package id shape.
_TARGETING_PACKS = [
    (("netstandard2.0", {}), [("NETStandard.Library", "2.0.3")]),
    (("netstandard2.1", {}), [("NETStandard.Library.Ref", "2.1.0")]),
    (("net48", {}), [("Microsoft.NETFramework.ReferenceAssemblies.net48", "1.0.3")]),
    (("netcoreapp2.1", {}), [("Microsoft.NETCore.App", "2.1.30")]),
    (("net10.0", {}), [("Microsoft.NETCore.App.Ref", "10.0.14")]),
    (("net8.0", _WEB), [
        ("Microsoft.AspNetCore.App.Ref", "8.0.33"),
        ("Microsoft.NETCore.App.Ref", "8.0.33"),
    ]),
    (("netcoreapp2.1", _WEB), [
        ("Microsoft.AspNetCore.App", "2.1.34"),
        ("Microsoft.NETCore.App", "2.1.30"),
    ]),
    (("netcoreapp3.1", _WEB), [
        ("Microsoft.AspNetCore.App.Ref", "3.1.10"),
        ("Microsoft.NETCore.App.Ref", "3.1.0"),
    ]),
    # .NET Framework's own reference assemblies carry Windows Forms and WPF.
    (("net48", _WPF), [("Microsoft.NETFramework.ReferenceAssemblies.net48", "1.0.3")]),
    (("net48", _WEB), []),
    (("netstandard2.0", _WPF), [("NETStandard.Library", "2.0.3")]),
    (("netstandard2.0", _WEB), []),
    (("netcoreapp2.1", _WPF), []),
    (("net10.0", _WPF), [
        ("Microsoft.WindowsDesktop.App.Ref", "10.0.14"),
        ("Microsoft.NETCore.App.Ref", "10.0.14"),
    ]),
    (("net10.0", _WEB | _WPF), [
        ("Microsoft.AspNetCore.App.Ref", "10.0.14"),
        ("Microsoft.WindowsDesktop.App.Ref", "10.0.14"),
        ("Microsoft.NETCore.App.Ref", "10.0.14"),
    ]),
]

_RUNTIME_PACKS = [
    (("net5.0", "linux-x64", {}), [("Microsoft.NETCore.App.Runtime.linux-x64", "5.0.17")]),
    (("net10.0", "win-arm64", _WEB), [
        ("Microsoft.AspNetCore.App.Runtime.win-arm64", "10.0.14"),
        ("Microsoft.NETCore.App.Runtime.win-arm64", "10.0.14"),
    ]),
    (("net10.0", "win-x64", _WPF), [
        ("Microsoft.WindowsDesktop.App.Runtime.win-x64", "10.0.14"),
        ("Microsoft.NETCore.App.Runtime.win-x64", "10.0.14"),
    ]),
    (("net10.0", "linux-x64", _WPF), []),
]

def _pack_ids_test_impl(ctx):
    env = unittest.begin(ctx)

    for ((tfm, frameworks), expected) in _TARGETING_PACKS:
        asserts.equals(env, expected, targeting_packs(tfm, frameworks, bands = _BANDS), "{}/{}".format(frameworks_key(frameworks), tfm))

    for ((tfm, rid, frameworks), expected) in _RUNTIME_PACKS:
        asserts.equals(
            env,
            expected,
            runtime_packs(tfm, rid, frameworks, bands = _BANDS),
            "{}/{}/{}".format(frameworks_key(frameworks), tfm, rid),
        )

    asserts.equals(
        env,
        ("Microsoft.NETCore.App.Host.osx-arm64", "10.0.14"),
        apphost_pack("net10.0", "osx-arm64", bands = _BANDS),
    )
    asserts.equals(
        env,
        None,
        apphost_pack("net5.0", "osx-arm64", bands = _BANDS),
        "Apple silicon packs only exist from .NET 6 onwards",
    )

    # ilc and the NativeAOT pack are built together, at the band's version.
    asserts.equals(
        env,
        ("runtime.linux-x64.Microsoft.DotNet.ILCompiler", "9.0.22"),
        ilcompiler_pack("net9.0", "linux-x64", bands = _BANDS),
    )
    asserts.equals(
        env,
        ("Microsoft.NETCore.App.Runtime.NativeAOT.osx-arm64", "9.0.22"),
        nativeaot_pack("net9.0", "osx-arm64", bands = _BANDS),
    )
    asserts.equals(env, None, ilcompiler_pack("net8.0", "linux-x64", bands = _BANDS), "NativeAOT has a pack of its own from .NET 9")

    # What the SDK's own build hands to ilc ships once, and only a Windows
    # publish reads any of it.
    asserts.equals(
        env,
        ("Microsoft.DotNet.ILCompiler", "9.0.22"),
        ilcompiler_build_pack("net9.0", "win-x64", bands = _BANDS),
    )
    asserts.equals(env, None, ilcompiler_build_pack("net9.0", "linux-x64", bands = _BANDS))
    return unittest.end(env)

_pack_ids_test = unittest.make(_pack_ids_test_impl)

def _wasm_test_impl(ctx):
    env = unittest.begin(ctx)

    # A browser runs Mono, so this is the one runtime pack id with an infix.
    asserts.equals(
        env,
        ("Microsoft.NETCore.App.Runtime.Mono.browser-wasm", "10.0.14"),
        wasm_runtime_pack("net10.0", bands = _BANDS),
    )

    # The tools a publish runs are at the band's version too, as the SDK
    # bundles them.
    asserts.equals(
        env,
        [
            ("wasm_sdk", ("Microsoft.NET.Sdk.WebAssembly.Pack", "10.0.14")),
            ("illink", ("Microsoft.NET.ILLink.Tasks", "10.0.14")),
            ("internal_assets", ("Microsoft.AspNetCore.App.Internal.Assets", "10.0.14")),
            ("devserver", ("Microsoft.AspNetCore.Components.WebAssembly.DevServer", "10.0.14")),
        ],
        wasm_tool_packs("net10.0", bands = _BANDS),
    )

    # .NET 11 serves the starter script from the application's own package.
    asserts.equals(env, ["wasm_sdk", "illink", "devserver"], wasm_tool_pack_names("net11.0"))

    for tfm in ["netcoreapp3.1", "net5.0", "net9.0"]:
        asserts.equals(
            env,
            None,
            wasm_runtime_pack(tfm, bands = PACK_BANDS),
            "{} carries no WebAssembly toolchain".format(tfm),
        )

    for tfm in wasm_pack_tfms():
        asserts.true(
            env,
            wasm_runtime_pack(tfm, bands = PACK_BANDS) != None,
            "{} claims a WebAssembly pack and resolves one".format(tfm),
        )

    return unittest.end(env)

_wasm_test = unittest.make(_wasm_test_impl)

def _sdk_bands_test_impl(ctx):
    env = unittest.begin(ctx)

    # The bands whose version the SDK picks are every framework from .NET 6
    # on, those declared ahead included, so a new release needs no band of its
    # own.
    asserts.equals(env, ["net{}.0".format(major) for major in range(6, 21)], SDK_BAND_TFMS)

    # An SDK only knows the releases up to its own.
    asserts.equals(env, ["net6.0", "net7.0", "net8.0", "net9.0", "net10.0"], sdk_band_tfms("net10.0"))
    asserts.equals(env, "net11.0", sdk_band_tfms("net11.0")[-1])
    asserts.equals(env, SDK_BAND_TFMS, sdk_band_tfms(SDK_BAND_TFMS[-1]))

    # A release declared ahead ships the packs the newest spelled out does:
    # .NET 10's, less the internal assets .NET 11 no longer needs.
    for tfm in _DECLARED_AHEAD:
        asserts.equals(
            env,
            sorted([field for field in PACK_BANDS["net10.0"] if field != "internal_assets"]),
            sorted(PACK_BANDS[tfm].keys()),
            tfm,
        )

    bands = pack_bands({tfm: "{}.7".format(tfm[len("net"):]) for tfm in SDK_BAND_TFMS})
    for tfm in SDK_BAND_TFMS:
        versions = {
            field: version
            for (field, version) in bands[tfm].items()
            if not field.endswith("rids")
        }
        asserts.equals(
            env,
            [tfm[len("net"):] + ".7"],
            {version: None for version in versions.values()}.keys(),
            "every pack of {} is at the band's version: {}".format(tfm, versions),
        )

    # The frozen bands keep the versions they were last serviced at.
    asserts.equals(env, "3.1.10", bands["netcoreapp3.1"]["web_ref"])

    return unittest.end(env)

_sdk_bands_test = unittest.make(_sdk_bands_test_impl)

def _framework_references_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, {}, resolve_framework_references("default", []))
    asserts.equals(env, _WEB, resolve_framework_references("web", []))
    asserts.equals(env, _WEB, resolve_framework_references("razor", []))
    asserts.equals(env, _WEB, resolve_framework_references("default", ["Microsoft.AspNetCore.App"]))
    asserts.equals(env, _WPF, resolve_framework_references("default", ["Microsoft.WindowsDesktop.App.WPF"]))

    # References to one framework add up: profiles to the union of them, and
    # one without a profile to the whole framework.
    asserts.equals(
        env,
        {WINDOWSDESKTOP_FRAMEWORK: ["WPF", "WindowsForms"]},
        resolve_framework_references("default", ["Microsoft.WindowsDesktop.App.WindowsForms", "Microsoft.WindowsDesktop.App.WPF"]),
    )
    asserts.equals(
        env,
        {WINDOWSDESKTOP_FRAMEWORK: None},
        resolve_framework_references("default", ["Microsoft.WindowsDesktop.App.WPF", "Microsoft.WindowsDesktop.App"]),
    )

    # Packages are keyed by the frameworks, in a fixed order, profiles only
    # where they narrow the targeting packs.
    asserts.equals(env, "default", frameworks_key({}))
    asserts.equals(env, "aspnetcore_windowsdesktop.wpf.windowsforms", frameworks_key(_WEB | {WINDOWSDESKTOP_FRAMEWORK: ["WPF", "WindowsForms"]}))
    asserts.equals(env, "aspnetcore_windowsdesktop", frameworks_key(_WEB | _WPF, profiles = False))
    asserts.equals(env, 10, len(TARGETING_FRAMEWORK_SETS))
    asserts.equals(env, 4, len(RUNTIME_FRAMEWORK_SETS))
    asserts.equals(
        env,
        len(TARGETING_FRAMEWORK_SETS),
        len({frameworks_key(frameworks): None for frameworks in TARGETING_FRAMEWORK_SETS}),
        "every set of frameworks has a package of its own",
    )

    asserts.equals(env, {"Microsoft.WindowsDesktop.App.Ref": ["WPF"]}, targeting_pack_profiles("net10.0", _WPF))
    asserts.equals(env, {}, targeting_pack_profiles("net10.0", {WINDOWSDESKTOP_FRAMEWORK: None}))
    asserts.equals(env, {}, targeting_pack_profiles("net48", _WPF))

    return unittest.end(env)

_framework_references_test = unittest.make(_framework_references_test_impl)

def packs_test_suite(name):
    unittest.suite(
        name,
        _apphost_table_test,
        _framework_references_test,
        _crossgen2_table_test,
        _pack_ids_test,
        _runtime_table_test,
        _sdk_bands_test,
        _targeting_table_test,
        _wasm_test,
    )
