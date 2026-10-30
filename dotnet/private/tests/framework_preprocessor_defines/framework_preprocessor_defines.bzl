"""Tests that framework preprocessor defines match what the .NET SDK emits.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet:defs.bzl", "csharp_library")
load(
    "//dotnet/private:common.bzl",
    "DEFAULT_TFM",
    "default_csharp_lang_version",
    "framework_preprocessor_symbols",
    "generate_runtimeconfig",
    "get_framework_version_info",
    "get_nearest_compatible_target_framework",
)
load("//dotnet/private/tests:utils.bzl", "action_args_test")

def _net11_framework_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "net10.0", DEFAULT_TFM, "a preview must not become the default")
    asserts.equals(env, None, get_framework_version_info("net11.0"))
    asserts.equals(env, "15.0", default_csharp_lang_version("net11.0", "15.0"))
    asserts.equals(env, "14.0", default_csharp_lang_version("net10.0", "15.0"))
    asserts.equals(env, "14.0", default_csharp_lang_version("net11.0", "14.0"))
    asserts.equals(
        env,
        "net10.0",
        get_nearest_compatible_target_framework("net11.0", ["netstandard2.0", "net8.0", "net10.0"]),
    )
    asserts.equals(env, None, get_nearest_compatible_target_framework("net10.0", ["net11.0"]))

    symbols = framework_preprocessor_symbols("net11.0")
    for symbol in ["NET", "NETCOREAPP", "NET11_0", "NET11_0_OR_GREATER", "NET10_0_OR_GREATER", "NETCOREAPP3_1_OR_GREATER"]:
        asserts.true(env, symbol in symbols, symbol)
    for symbol in ["NET12_0_OR_GREATER", "NET11_OR_GREATER", "NETSTANDARD2_0_OR_GREATER", "NETFRAMEWORK"]:
        asserts.false(env, symbol in symbols, symbol)

    for tfm in ["net10.0", "net8.0", "netstandard2.0", "net48"]:
        asserts.false(env, "NET11_0_OR_GREATER" in framework_preprocessor_symbols(tfm), tfm)

    preview = generate_runtimeconfig(
        "net11.0",
        "web",
        False,
        "Major",
        runtime_version = "11.0.0-rc.3.26522.148",
    )
    asserts.equals(env, [
        {"name": "Microsoft.NETCore.App", "version": "11.0.0-rc.3.26522.148"},
        {"name": "Microsoft.AspNetCore.App", "version": "11.0.0-rc.3.26522.148"},
    ], preview["runtimeOptions"]["frameworks"])
    stable = generate_runtimeconfig("net10.0", "default", False, "Major")
    asserts.equals(env, [
        {"name": "Microsoft.NETCore.App", "version": "10.0.0"},
    ], stable["runtimeOptions"]["frameworks"])

    return unittest.end(env)

_net11_framework_test = unittest.make(_net11_framework_test_impl)

# buildifier: disable=unnamed-macro
# buildifier: disable=function-docstring
def test_framework_preprocessor_defines():
    _net11_framework_test(name = "test_net11_framework")

    csharp_library(
        name = "lib_netstd",
        srcs = ["Hello.cs"],
        target_frameworks = ["netstandard2.0"],
    )

    csharp_library(
        name = "lib_netcore",
        srcs = ["Hello.cs"],
        target_frameworks = ["net8.0"],
    )

    csharp_library(
        name = "lib_netcoreapp",
        srcs = ["Hello.cs"],
        target_frameworks = ["netcoreapp3.1"],
    )

    csharp_library(
        name = "lib_netfx",
        srcs = ["Hello.cs"],
        target_frameworks = ["net48"],
    )

    action_args_test(
        name = "test_netstd",
        target_under_test = ":lib_netstd",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "/d:NETSTANDARD",
            "/d:NETSTANDARD2_0",
            "/d:NETSTANDARD2_0_OR_GREATER",
            "/d:NETSTANDARD1_6_OR_GREATER",
        ],
        expected_nonexistent_partial_args = [
            "/d:NET",
            "/d:NETCOREAPP",
            "/d:NETFRAMEWORK",
            "/d:NET5_0_OR_GREATER",
            "/d:NETCOREAPP3_1_OR_GREATER",
            "/d:NETSTANDARD2_1_OR_GREATER",
            "/d:NET462_OR_GREATER",
            # There is no versionless _OR_GREATER symbol.
            "/d:NETSTANDARD_OR_GREATER",
        ],
    )

    action_args_test(
        name = "test_netcore",
        target_under_test = ":lib_netcore",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "/d:NET",
            "/d:NET8_0",
            "/d:NET8_0_OR_GREATER",
            "/d:NET6_0_OR_GREATER",
            "/d:NETCOREAPP",
            "/d:NETCOREAPP3_1_OR_GREATER",
        ],
        expected_nonexistent_partial_args = [
            "/d:NETSTANDARD",
            "/d:NETFRAMEWORK",
            "/d:NET9_0_OR_GREATER",
            "/d:NET472_OR_GREATER",
            "/d:NETSTANDARD2_0_OR_GREATER",
            "/d:NETSTANDARD2_1_OR_GREATER",
        ],
    )

    action_args_test(
        name = "test_netcoreapp",
        target_under_test = ":lib_netcoreapp",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "/d:NETCOREAPP",
            "/d:NETCOREAPP3_1",
            "/d:NETCOREAPP3_1_OR_GREATER",
            "/d:NETCOREAPP3_0_OR_GREATER",
            "/d:NETCOREAPP2_1_OR_GREATER",
        ],
        expected_nonexistent_partial_args = [
            "/d:NET",
            "/d:NETFRAMEWORK",
            "/d:NETSTANDARD",
            "/d:NETCOREAPP5_0_OR_GREATER",
            "/d:NETCOREAPP6_0_OR_GREATER",
            "/d:NET472_OR_GREATER",
        ],
    )

    action_args_test(
        name = "test_netfx",
        target_under_test = ":lib_netfx",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "/d:NETFRAMEWORK",
            "/d:NET48",
            "/d:NET48_OR_GREATER",
            "/d:NET472_OR_GREATER",
            "/d:NET20_OR_GREATER",
        ],
        expected_nonexistent_partial_args = [
            "/d:NET",
            "/d:NETCOREAPP",
            "/d:NETSTANDARD",
            "/d:NET11_OR_GREATER",
            "/d:NET403_OR_GREATER",
            "/d:NETSTANDARD2_0_OR_GREATER",
            "/d:NET481_OR_GREATER",
        ],
    )
