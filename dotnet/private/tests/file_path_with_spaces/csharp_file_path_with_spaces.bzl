"C# target with spaces in file path"

load("//dotnet:defs.bzl", "csharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def csharp_file_path_args_with_spaces():
    csharp_library(
        name = "csharp_file_path_api_tests_with_spaces",
        srcs = ["api tests/test.cs"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_file_path_with_spaces_test",
        target_under_test = ":csharp_file_path_api_tests_with_spaces",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "\"dotnet/private/tests/file_path_with_spaces/api tests/test.cs\"",
        ],
    )

