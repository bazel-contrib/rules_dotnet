"F# Warning settings"

load("//dotnet:defs.bzl", "fsharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def fsharp_additional_compiler_options():
    fsharp_library(
        name = "fsharp_all_additional_compiler_options",
        srcs = ["additional_compiler_options.fs"],
        target_frameworks = ["net8.0"],
        compiler_options = ["/warnnotaserror:CS1234", "/warnnotaserror:CS0000"],
        tags = ["manual"],
    )

    action_args_test(
        name = "fsharp_all_additional_compiler_options_test",
        target_under_test = ":fsharp_all_additional_compiler_options",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = ["/warnnotaserror:CS1234", "/warnnotaserror:CS0000"],
    )
