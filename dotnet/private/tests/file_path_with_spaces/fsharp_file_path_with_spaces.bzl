"F# target with spaces in file path"

load("//dotnet:defs.bzl", "fsharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def fsharp_file_path_args_with_spaces():
    fsharp_library(
        name = "fsharp_file_path_api_tests_with_spaces",
        srcs = ["api tests/test.fs"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    action_args_test(
        name = "fsharp_file_path_with_spaces_test",
        target_under_test = ":fsharp_file_path_api_tests_with_spaces",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = [
            "dotnet/private/tests/file_path_with_spaces/api tests/test.fs",
        ],
    )


