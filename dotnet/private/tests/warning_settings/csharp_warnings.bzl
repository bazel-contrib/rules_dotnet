"C# Warning settings"

load("//dotnet:defs.bzl", "csharp_library")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def csharp_warnings():
    csharp_library(
        name = "csharp_all_warnings",
        srcs = ["warnings.cs"],
        target_frameworks = ["net8.0"],
        treat_warnings_as_errors = True,
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_all_warnings_test",
        target_under_test = ":csharp_all_warnings",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/warnaserror+"],
    )

    csharp_library(
        name = "csharp_all_warnings_except_some",
        srcs = ["warnings.cs"],
        target_frameworks = ["net8.0"],
        treat_warnings_as_errors = True,
        warnings_not_as_errors = ["CS1591"],
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_all_warnings_except_some_test",
        target_under_test = ":csharp_all_warnings_except_some",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/warnaserror+", "/warnaserror-:CS1591"],
    )

    csharp_library(
        name = "csharp_warnings_as_errors",
        srcs = ["warnings.cs"],
        target_frameworks = ["net8.0"],
        warnings_as_errors = ["CS0025", "CS0026"],
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_warnings_as_errors_test",
        target_under_test = ":csharp_warnings_as_errors",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/warnaserror+:CS0025", "/warnaserror+:CS0026"],
    )

    csharp_library(
        name = "csharp_warnings_not_as_errors",
        srcs = ["warnings.cs"],
        target_frameworks = ["net8.0"],
        treat_warnings_as_errors = True,
        warnings_not_as_errors = ["CS0025", "CS0026"],
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_warnings_not_as_errors_test",
        target_under_test = ":csharp_warnings_not_as_errors",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/warnaserror-:CS0025", "/warnaserror-:CS0026"],
    )

    csharp_library(
        name = "csharp_warning_level",
        srcs = ["warnings.cs"],
        target_frameworks = ["net8.0"],
        warning_level = 5,
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_warning_level_test",
        target_under_test = ":csharp_warning_level",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/warn:5"],
    )

    csharp_library(
        name = "csharp_nowarn",
        srcs = ["warnings.cs"],
        target_frameworks = ["net8.0"],
        nowarn = ["CS1234", "CS0000"],
        tags = ["manual"],
    )

    action_args_test(
        name = "csharp_nowarn_test",
        target_under_test = ":csharp_nowarn",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/nowarn:CS1234,CS0000"],
    )
