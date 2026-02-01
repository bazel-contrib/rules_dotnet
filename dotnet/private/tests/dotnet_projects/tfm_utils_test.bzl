"Tests for TFM utilities"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/rules/dotnet_projects:tfm_utils.bzl", "find_best_toolchain_for_tfms", "get_min_sdk_major_for_tfm", "get_sdk_major_version", "get_suggested_sdk_for_tfm", "sdk_supports_tfm")

def _get_min_sdk_major_test_impl(ctx):
    env = unittest.begin(ctx)

    # Modern .NET versions
    asserts.equals(env, 10, get_min_sdk_major_for_tfm("net10.0"))
    asserts.equals(env, 9, get_min_sdk_major_for_tfm("net9.0"))
    asserts.equals(env, 8, get_min_sdk_major_for_tfm("net8.0"))
    asserts.equals(env, 7, get_min_sdk_major_for_tfm("net7.0"))
    asserts.equals(env, 6, get_min_sdk_major_for_tfm("net6.0"))

    # .NET Standard
    asserts.equals(env, 3, get_min_sdk_major_for_tfm("netstandard2.1"))
    asserts.equals(env, 2, get_min_sdk_major_for_tfm("netstandard2.0"))

    # Case insensitive
    asserts.equals(env, 9, get_min_sdk_major_for_tfm("NET9.0"))

    # Unknown TFM
    asserts.equals(env, None, get_min_sdk_major_for_tfm("unknown"))

    return unittest.end(env)

get_min_sdk_major_test = unittest.make(_get_min_sdk_major_test_impl)

def _get_sdk_major_version_test_impl(ctx):
    env = unittest.begin(ctx)

    # Standard versions
    asserts.equals(env, 10, get_sdk_major_version("10.0.100"))
    asserts.equals(env, 9, get_sdk_major_version("9.0.300"))
    asserts.equals(env, 8, get_sdk_major_version("8.0.410"))

    # Preview/RC versions
    asserts.equals(env, 10, get_sdk_major_version("10.0.100-preview.1"))
    asserts.equals(env, 10, get_sdk_major_version("10.0.100-rc.2.25502.107"))

    # Edge cases
    asserts.equals(env, 0, get_sdk_major_version(""))
    asserts.equals(env, 5, get_sdk_major_version("5"))

    return unittest.end(env)

get_sdk_major_version_test = unittest.make(_get_sdk_major_version_test_impl)

def _sdk_supports_tfm_test_impl(ctx):
    env = unittest.begin(ctx)

    # .NET 10 SDK supports all TFMs
    asserts.true(env, sdk_supports_tfm("10.0.100", "net10.0"))
    asserts.true(env, sdk_supports_tfm("10.0.100", "net9.0"))
    asserts.true(env, sdk_supports_tfm("10.0.100", "net8.0"))
    asserts.true(env, sdk_supports_tfm("10.0.100", "netstandard2.0"))

    # .NET 9 SDK cannot build net10.0
    asserts.false(env, sdk_supports_tfm("9.0.300", "net10.0"))
    asserts.true(env, sdk_supports_tfm("9.0.300", "net9.0"))
    asserts.true(env, sdk_supports_tfm("9.0.300", "net8.0"))

    # .NET 8 SDK cannot build net9.0 or net10.0
    asserts.false(env, sdk_supports_tfm("8.0.410", "net10.0"))
    asserts.false(env, sdk_supports_tfm("8.0.410", "net9.0"))
    asserts.true(env, sdk_supports_tfm("8.0.410", "net8.0"))

    # Unknown TFM should be assumed supported
    asserts.true(env, sdk_supports_tfm("10.0.100", "custom-tfm"))

    return unittest.end(env)

sdk_supports_tfm_test = unittest.make(_sdk_supports_tfm_test_impl)

def _get_suggested_sdk_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "10.0.100", get_suggested_sdk_for_tfm("net10.0"))
    asserts.equals(env, "9.0.300", get_suggested_sdk_for_tfm("net9.0"))
    asserts.equals(env, "8.0.410", get_suggested_sdk_for_tfm("net8.0"))
    asserts.equals(env, None, get_suggested_sdk_for_tfm("unknown"))

    return unittest.end(env)

get_suggested_sdk_test = unittest.make(_get_suggested_sdk_test_impl)

def _find_best_toolchain_test_impl(ctx):
    env = unittest.begin(ctx)

    # Test with single toolchain covering all TFMs
    registered = {"dotnet": "10.0.100"}
    tfms = ["net10.0", "net9.0", "net8.0"]

    coverage = find_best_toolchain_for_tfms(registered, tfms)
    asserts.equals(env, 3, len(coverage.covered))
    asserts.equals(env, 0, len(coverage.uncovered))

    # Test with toolchain not covering all TFMs
    registered2 = {"dotnet": "8.0.410"}
    tfms2 = ["net10.0", "net9.0", "net8.0"]

    coverage2 = find_best_toolchain_for_tfms(registered2, tfms2)
    asserts.equals(env, 1, len(coverage2.covered))
    asserts.equals(env, 2, len(coverage2.uncovered))
    asserts.true(env, "net10.0" in coverage2.uncovered)
    asserts.true(env, "net9.0" in coverage2.uncovered)
    asserts.true(env, "net8.0" in coverage2.covered)

    # Test suggestions
    asserts.equals(env, "10.0.100", coverage2.suggestions.get("net10.0"))
    asserts.equals(env, "9.0.300", coverage2.suggestions.get("net9.0"))

    return unittest.end(env)

find_best_toolchain_test = unittest.make(_find_best_toolchain_test_impl)

def _multiple_toolchains_test_impl(ctx):
    env = unittest.begin(ctx)

    # Multiple toolchains - each TFM covered by at least one
    registered = {
        "dotnet": "9.0.300",
        "dotnet_10": "10.0.100",
    }
    tfms = ["net10.0", "net9.0", "net8.0"]

    coverage = find_best_toolchain_for_tfms(registered, tfms)

    # All should be covered
    asserts.equals(env, 3, len(coverage.covered))
    asserts.equals(env, 0, len(coverage.uncovered))

    # net10.0 should only be covered by dotnet_10
    asserts.equals(env, 1, len(coverage.covered["net10.0"]))
    asserts.true(env, "dotnet_10" in coverage.covered["net10.0"])

    # net9.0 should be covered by both
    asserts.equals(env, 2, len(coverage.covered["net9.0"]))

    return unittest.end(env)

multiple_toolchains_test = unittest.make(_multiple_toolchains_test_impl)

def tfm_utils_test_suite(name):
    unittest.suite(
        name,
        get_min_sdk_major_test,
        get_sdk_major_version_test,
        sdk_supports_tfm_test,
        get_suggested_sdk_test,
        find_best_toolchain_test,
        multiple_toolchains_test,
    )
