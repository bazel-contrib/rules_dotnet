"Excluded analyzers tests"

load("//dotnet:defs.bzl", "csharp_binary", "csharp_library", "csharp_test")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# Both come from the ASP.NET Core targeting pack.
_LOGGING_GENERATOR = "Microsoft.Extensions.Logging.Generators.dll"
_OPTIONS_GENERATOR = "Microsoft.Extensions.Options.SourceGeneration.dll"

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def csharp_excluded_analyzers():
    csharp_library(
        name = "library_without_excluded_analyzers",
        srcs = ["excluded_analyzers.cs"],
        project_sdk = "web",
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    action_args_test(
        name = "library_without_excluded_analyzers_test",
        target_under_test = ":library_without_excluded_analyzers",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [_LOGGING_GENERATOR, _OPTIONS_GENERATOR],
    )

    for kind, rule in [("library", csharp_library), ("binary", csharp_binary), ("test", csharp_test)]:
        rule(
            name = kind + "_with_excluded_analyzers",
            srcs = ["excluded_analyzers.cs"],
            project_sdk = "web",
            target_frameworks = ["net10.0"],
            excluded_analyzers = [_LOGGING_GENERATOR],
            tags = ["manual"],
        )

        action_args_test(
            name = kind + "_with_excluded_analyzers_test",
            target_under_test = ":" + kind + "_with_excluded_analyzers",
            action_mnemonic = "CSharpCompile",
            expected_args_containing = [_OPTIONS_GENERATOR],
            expected_args_not_containing = [_LOGGING_GENERATOR],
        )
