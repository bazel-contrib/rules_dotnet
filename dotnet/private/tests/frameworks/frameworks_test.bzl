"""Tests for the framework tables derived from the hand-maintained lists.

Adding a .NET release is meant to be a one-line change to the lists, so the
derivations have to give a new framework what the SDK would.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/sdk:frameworks.bzl",
    "DEFAULT_TARGET_FRAMEWORK",
    "FRAMEWORK_COMPATIBILITY",
    "SDK_LANG_VERSIONS",
    "SDK_NETCOREAPP_FRAMEWORKS",
    "SDK_NETFRAMEWORK_FRAMEWORKS",
    "SDK_NETSTANDARD_FRAMEWORKS",
)

def _lang_versions_test_impl(ctx):
    env = unittest.begin(ctx)

    # Microsoft.CSharp.Core.targets: 7.3 below .NET Core 3.0 and .NET Standard
    # 2.1, 8.0 up to .NET 5, and from .NET 5 on, C# 9 plus each release since.
    for (tfm, expected) in {
        "net48": "7.3",
        "netcoreapp2.2": "7.3",
        "netcoreapp3.0": "8.0",
        "netcoreapp3.1": "8.0",
        "net5.0": "9.0",
        "net8.0": "12.0",
        "net10.0": "14.0",
        "netstandard2.0": "7.3",
        "netstandard2.1": "8.0",
    }.items():
        asserts.equals(env, expected, SDK_LANG_VERSIONS[tfm], tfm)

    asserts.equals(
        env,
        sorted(SDK_NETSTANDARD_FRAMEWORKS + SDK_NETFRAMEWORK_FRAMEWORKS + SDK_NETCOREAPP_FRAMEWORKS),
        sorted(SDK_LANG_VERSIONS.keys()),
        "every framework the SDK lists has a language version, and nothing else does",
    )

    return unittest.end(env)

_lang_versions_test = unittest.make(_lang_versions_test_impl)

def _compatibility_test_impl(ctx):
    env = unittest.begin(ctx)

    for (tfm, expected) in {
        # The first of each family.
        "netstandard": [],
        "net11": [],
        "netcoreapp1.0": ["netstandard1.6"],
        # The legacy monikers the SDK does not list.
        "netstandard1.0": ["netstandard"],
        "net20": ["net11"],
        "net403": ["net40"],
        "net45": ["net403", "netstandard1.1"],
        # A bridge to .NET Standard.
        "net461": ["net46", "netstandard2.0"],
        "netcoreapp3.0": ["netcoreapp2.2", "netstandard2.1"],
        # Just the previous release.
        "net5.0": ["netcoreapp3.1"],
        "net10.0": ["net9.0"],
    }.items():
        asserts.equals(env, expected, FRAMEWORK_COMPATIBILITY[tfm], tfm)

    # Families in order, each oldest first: other tables slice it by position.
    keys = FRAMEWORK_COMPATIBILITY.keys()
    asserts.equals(env, "netstandard", keys[0])
    asserts.equals(env, keys.index("netstandard2.1") + 1, keys.index("net11"))
    asserts.equals(env, keys.index("net481") + 1, keys.index("netcoreapp1.0"))
    asserts.equals(env, SDK_NETCOREAPP_FRAMEWORKS[-1], keys[-1])

    asserts.true(env, DEFAULT_TARGET_FRAMEWORK in SDK_NETCOREAPP_FRAMEWORKS)

    return unittest.end(env)

_compatibility_test = unittest.make(_compatibility_test_impl)

def frameworks_test_suite(name):
    unittest.suite(
        name,
        _compatibility_test,
        _lang_versions_test,
    )
