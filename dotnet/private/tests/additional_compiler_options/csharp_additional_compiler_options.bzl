"C# Warning settings"

load("//dotnet:defs.bzl", "csharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def csharp_additional_compiler_options():
    csharp_library(
        name = "csharp_all_additional_compiler_options",
        srcs = ["additional_compiler_options.cs"],
        target_frameworks = ["net8.0"],
        compiler_options = ["/warnnotaserror:CS1234", "/warnnotaserror:CS0000"],
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_all_additional_compiler_options_test",
        target_under_test = ":csharp_all_additional_compiler_options",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/warnnotaserror:CS1234", "/warnnotaserror:CS0000"],
    )
