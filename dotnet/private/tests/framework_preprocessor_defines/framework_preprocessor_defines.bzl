"Tests for ensuring that NET*_OR_GREATER defines are properly set when targeting a given TFM."

load("//dotnet:defs.bzl", "csharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=unnamed-macro
# buildifier: disable=function-docstring
def test_framework_preprocessor_defines():
    # TODO: Also test .NET Framework. Currently blocked by https://github.com/bazel-contrib/rules_dotnet/issues/477

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

    action_args_test(
        name = "test_netstd",
        target_under_test = ":lib_netstd",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "/d:NETSTANDARD2_0",
            "/d:NETSTANDARD2_0_OR_GREATER",
            "/d:NETSTANDARD1_6_OR_GREATER",
        ],
        expected_nonexistent_partial_args = [
            "/d:NET5_0_OR_GREATER",
            "/d:NETCOREAPP3_1_OR_GREATER",
            "/d:NETSTANDARD2_1_OR_GREATER",
            "/d:NET462_OR_GREATER",
        ],
    )

    action_args_test(
        name = "test_netcore",
        target_under_test = ":lib_netcore",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "/d:NET8_0",
            "/d:NET8_0_OR_GREATER",
            "/d:NET6_0_OR_GREATER",
            "/d:NETSTANDARD2_1_OR_GREATER",
        ],
        expected_nonexistent_partial_args = [
            "/d:NET9_0_OR_GREATER",
            "/d:NET472_OR_GREATER",
        ],
    )
