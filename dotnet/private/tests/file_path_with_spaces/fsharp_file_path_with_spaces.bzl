"F# target with spaces in file path"

load("//dotnet:defs.bzl", "fsharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# Unlike the C# compiler, the F# compiler reads each line of a multiline
# response file as a single literal argument and does not strip surrounding
# double quotes. Paths with spaces are therefore passed unquoted to fsc.
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
            "\'dotnet/private/tests/file_path_with_spaces/api tests/test.fs\'",
        ],
    )

    fsharp_library(
        name = "fsharp_resource_with_spaces",
        srcs = ["api tests/test.fs"],
        resources = ["res dir/data file.txt"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    action_args_test(
        name = "fsharp_resource_with_spaces_test",
        target_under_test = ":fsharp_resource_with_spaces",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = [
            "--resource:\'dotnet/private/tests/file_path_with_spaces/res dir/data file.txt\',\'fsharp_resource_with_spaces.res dir.data file.txt\'",
        ],
    )

    fsharp_library(
        name = "fsharp output with spaces",
        srcs = ["api tests/test.fs"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    action_args_test(
        name = "fsharp_output_with_spaces_test",
        target_under_test = ":fsharp output with spaces",
        action_mnemonic = "FSharpCompile",
        expected_args_containing = [
            "fsharp output with spaces/net10.0/fsharp output with spaces.dll\'",
        ],
    )

    fsharp_library(
        name = "fsharp_reflib with spaces",
        srcs = ["api tests/test.fs"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    fsharp_library(
        name = "fsharp_reference_with_spaces",
        srcs = ["api tests/test.fs"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
        deps = [":fsharp_reflib with spaces"],
    )

    action_args_test(
        name = "fsharp_reference_with_spaces_test",
        target_under_test = ":fsharp_reference_with_spaces",
        action_mnemonic = "FSharpCompile",
        expected_args_containing = [
            "fsharp_reflib with spaces/net10.0/fsharp_reflib with spaces.dll\'",
        ],
    )
