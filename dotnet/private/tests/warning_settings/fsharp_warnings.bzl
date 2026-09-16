"F# Warning settings"

load("//dotnet:defs.bzl", "fsharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def fsharp_warnings():
    fsharp_library(
        name = "fsharp_all_warnings",
        srcs = ["warnings.fs"],
        target_frameworks = ["net8.0"],
        treat_warnings_as_errors = True,
        tags = ["manual"],
    )

    action_args_test(
        name = "fsharp_all_warnings_test",
        target_under_test = ":fsharp_all_warnings",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = ["/warnaserror+"],
    )

    fsharp_library(
        name = "fsharp_warnings_as_errors",
        srcs = ["warnings.fs"],
        target_frameworks = ["net8.0"],
        warnings_as_errors = ["FS0025", "FS0026"],
        tags = ["manual"],
    )

    action_args_test(
        name = "fsharp_warnings_as_errors_test",
        target_under_test = ":fsharp_warnings_as_errors",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = ["/warnaserror+:FS0025", "/warnaserror+:FS0026"],
    )

    fsharp_library(
        name = "fsharp_warnings_not_as_errors",
        srcs = ["warnings.fs"],
        target_frameworks = ["net8.0"],
        treat_warnings_as_errors = True,
        warnings_not_as_errors = ["FS0025", "FS0026"],
        tags = ["manual"],
    )

    action_args_test(
        name = "fsharp_warnings_not_as_errors_test",
        target_under_test = ":fsharp_warnings_not_as_errors",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = ["/warnaserror-:FS0025", "/warnaserror-:FS0026"],
    )

    fsharp_library(
        name = "fsharp_warning_level",
        srcs = ["warnings.fs"],
        target_frameworks = ["net8.0"],
        warning_level = 5,
        tags = ["manual"],
    )

    action_args_test(
        name = "fsharp_warning_level_test",
        target_under_test = ":fsharp_warning_level",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = ["/warn:5"],
    )

    fsharp_library(
        name = "fsharp_nowarn",
        srcs = ["warnings.fs"],
        target_frameworks = ["net8.0"],
        nowarn = ["FS0000", "FS1234"],
        tags = ["manual"],
    )

    action_args_test(
        name = "fsharp_nowarn_test",
        target_under_test = ":fsharp_nowarn",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = ["/nowarn:FS0000,FS1234"],
    )
