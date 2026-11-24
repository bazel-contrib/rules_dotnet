"""Tests for the framework tables derived from the framework lists.

Frameworks are declared ahead of their release, so the derivations have to give
each what the SDK will.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private:common.bzl",
    "framework_preprocessor_symbols",
    "get_highest_compatible_target_framework",
    "get_nearest_compatible_target_framework",
    "nuget_framework_to_tfm",
    "shared_framework_version",
    "target_platform",
    "tfm_to_nuget_framework",
    "tfm_version",
)
load(
    "//dotnet/private/sdk:frameworks.bzl",
    "DEFAULT_TARGET_FRAMEWORK",
    "FRAMEWORK_COMPATIBILITY",
    "SDK_LANG_VERSIONS",
    "SDK_NETCOREAPP_FRAMEWORKS",
    "SDK_NETFRAMEWORK_FRAMEWORKS",
    "SDK_NETSTANDARD_FRAMEWORKS",
    "SDK_WINDOWS_FRAMEWORKS",
    "base_framework",
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
        # Declared ahead of their release.
        "net11.0": "15.0",
        "net20.0": "24.0",
        "netstandard2.0": "7.3",
        "netstandard2.1": "8.0",
        # A Windows specific framework takes its release's.
        "net8.0-windows": "12.0",
    }.items():
        asserts.equals(env, expected, SDK_LANG_VERSIONS[tfm], tfm)

    asserts.equals(
        env,
        sorted(SDK_NETSTANDARD_FRAMEWORKS + SDK_NETFRAMEWORK_FRAMEWORKS + SDK_NETCOREAPP_FRAMEWORKS + SDK_WINDOWS_FRAMEWORKS),
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
    asserts.equals(env, SDK_NETCOREAPP_FRAMEWORKS[-1] + "-windows", keys[-1])

    # A Windows specific framework sits right after the one it is specific to,
    # so that the table ranks a package's assets as NuGet does.
    for tfm in SDK_WINDOWS_FRAMEWORKS:
        asserts.equals(env, keys.index(base_framework(tfm)) + 1, keys.index(tfm), tfm)
    asserts.equals(env, ["net5.0"], FRAMEWORK_COMPATIBILITY["net5.0-windows"])
    asserts.equals(env, ["net8.0", "net7.0-windows"], FRAMEWORK_COMPATIBILITY["net8.0-windows"])
    asserts.equals(env, ["net8.0"], FRAMEWORK_COMPATIBILITY["net9.0"], "a plain framework consumes no Windows specific one")
    asserts.equals(env, "net5.0-windows", SDK_WINDOWS_FRAMEWORKS[0], "platform specific frameworks start with .NET 5")

    # Releases are declared ahead, a decade on, and nothing but the SDK limits
    # which of them a target builds for.
    asserts.equals(env, "net20.0", SDK_NETCOREAPP_FRAMEWORKS[-1])
    asserts.equals(env, ["net10.0"], FRAMEWORK_COMPATIBILITY["net11.0"])
    asserts.equals(env, SDK_NETCOREAPP_FRAMEWORKS[-1], DEFAULT_TARGET_FRAMEWORK)

    return unittest.end(env)

_compatibility_test = unittest.make(_compatibility_test_impl)

def _shared_framework_version_test_impl(ctx):
    env = unittest.begin(ctx)

    # The release's first, which the host rolls forward from.
    asserts.equals(env, "10.0.0", shared_framework_version("net10.0", "10.0.12"))
    asserts.equals(env, "8.0.0", shared_framework_version("net8.0", "11.0.0-rc.3.26522.148"))

    # A preview sorts before the release, so an app for the release a preview
    # SDK ships asks for the preview.
    asserts.equals(env, "11.0.0-rc.3.26522.148", shared_framework_version("net11.0", "11.0.0-rc.3.26522.148"))
    asserts.equals(env, "11.0.0", shared_framework_version("net11.0", "11.0.0"))
    asserts.equals(env, "11.0.0", shared_framework_version("net11.0", "12.0.0-preview.1.27101.1"))

    return unittest.end(env)

_shared_framework_version_test = unittest.make(_shared_framework_version_test_impl)

def _windows_frameworks_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, [8, 0], tfm_version("net8.0-windows"))

    # As the SDK spells it in package metadata and folders, and back.
    asserts.equals(env, "net8.0-windows7.0", tfm_to_nuget_framework("net8.0-windows"))
    for (framework, expected) in {
        "net8.0-windows": "net8.0-windows",
        "net8.0-windows7.0": "net8.0-windows",
        "NET8.0-Windows7.0": "net8.0-windows",
        ".NETCoreApp8.0-windows7.0": "net8.0-windows",
        "netcoreapp3.1-windows": None,
        # A later version of Windows needs the Windows SDK projections.
        "net8.0-windows10.0.19041.0": None,
        "net8.0-android": None,
    }.items():
        asserts.equals(env, expected, nuget_framework_to_tfm(framework), framework)

    # GenerateTargetPlatformDefineConstants and GeneratePlatformCompatibleDefineConstants.
    symbols = framework_preprocessor_symbols("net8.0-windows")
    for symbol in ["NET", "NET8_0", "NET8_0_OR_GREATER", "NETCOREAPP", "WINDOWS", "WINDOWS7_0", "WINDOWS7_0_OR_GREATER"]:
        asserts.true(env, symbol in symbols, "net8.0-windows defines {}".format(symbol))
    asserts.false(env, "WINDOWS" in framework_preprocessor_symbols("net8.0"))

    asserts.equals(env, "Windows7.0", target_platform("net8.0-windows"))
    asserts.equals(env, None, target_platform("net8.0"))

    # NuGet's nearest framework: the release first, then the platform.
    asserts.equals(env, "net8.0-windows", get_nearest_compatible_target_framework("net8.0-windows", ["net8.0", "net8.0-windows"]))
    asserts.equals(env, "net8.0", get_nearest_compatible_target_framework("net8.0-windows", ["net8.0", "net7.0-windows"]))
    asserts.equals(env, "net7.0-windows", get_nearest_compatible_target_framework("net8.0-windows", ["net7.0", "net7.0-windows"]))
    asserts.equals(env, "net7.0", get_nearest_compatible_target_framework("net8.0", ["net7.0", "net7.0-windows"]))

    # What a dependency builds for.
    asserts.equals(env, "net8.0", get_highest_compatible_target_framework("net8.0-windows", ["net8.0", "net9.0"]))
    asserts.equals(env, "net8.0-windows", get_highest_compatible_target_framework("net9.0-windows", ["net8.0-windows", "net8.0"]))
    asserts.equals(env, None, get_highest_compatible_target_framework("net9.0", ["net8.0-windows"]))
    asserts.equals(env, "net8.0", get_highest_compatible_target_framework("net9.0", ["net8.0-windows", "net8.0"]))

    # Built directly, a target builds for the newest it lists.
    asserts.equals(env, "net8.0-windows", get_highest_compatible_target_framework(DEFAULT_TARGET_FRAMEWORK, ["net8.0-windows"]))

    return unittest.end(env)

_windows_frameworks_test = unittest.make(_windows_frameworks_test_impl)

def frameworks_test_suite(name):
    unittest.suite(
        name,
        _compatibility_test,
        _windows_frameworks_test,
        _lang_versions_test,
        _shared_framework_version_test,
    )
