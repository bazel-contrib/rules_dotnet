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

    csharp_library(
        name = "csharp_resource_with_spaces",
        srcs = ["api tests/test.cs"],
        resources = ["res dir/data file.txt"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_resource_with_spaces_test",
        target_under_test = ":csharp_resource_with_spaces",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = [
            "/resource:\"dotnet/private/tests/file_path_with_spaces/res dir/data file.txt\",\"csharp_resource_with_spaces.res dir.data file.txt\"",
        ],
    )

    csharp_library(
        name = "csharp output with spaces",
        srcs = ["api tests/test.cs"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_output_with_spaces_test",
        target_under_test = ":csharp output with spaces",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [
            "/out:\"",
            "/refout:\"",
            "/pdb:\"",
            "csharp output with spaces.dll\"",
        ],
    )

    csharp_library(
        name = "reflib with spaces",
        srcs = ["api tests/test.cs"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    csharp_library(
        name = "csharp_reference_with_spaces",
        srcs = ["api tests/test.cs"],
        deps = [":reflib with spaces"],
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_reference_with_spaces_test",
        target_under_test = ":csharp_reference_with_spaces",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [
            "-r:\"",
            "reflib with spaces.dll\"",
        ],
    )
