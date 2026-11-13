"Excluded analyzers tests"

load("//dotnet:defs.bzl", "csharp_binary", "csharp_library", "csharp_test")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

_REQUEST_DELEGATE_GENERATOR = "Microsoft.AspNetCore.Http.RequestDelegateGenerator.dll"
_CONFIGURATION_BINDING_GENERATOR = "Microsoft.Extensions.Configuration.Binder.SourceGeneration.dll"
_LOGGING_GENERATOR = "Microsoft.Extensions.Logging.Generators.dll"

_EXCLUDED = [_REQUEST_DELEGATE_GENERATOR, _CONFIGURATION_BINDING_GENERATOR]

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
        expected_args_containing = _EXCLUDED + [_LOGGING_GENERATOR],
    )

    csharp_library(
        name = "library_with_excluded_analyzers",
        srcs = ["excluded_analyzers.cs"],
        project_sdk = "web",
        target_frameworks = ["net10.0"],
        excluded_analyzers = _EXCLUDED,
        tags = ["manual"],
    )

    action_args_test(
        name = "library_with_excluded_analyzers_test",
        target_under_test = ":library_with_excluded_analyzers",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [_LOGGING_GENERATOR],
        expected_args_not_containing = _EXCLUDED,
    )

    csharp_binary(
        name = "binary_with_excluded_analyzers",
        srcs = ["excluded_analyzers.cs"],
        project_sdk = "web",
        target_frameworks = ["net10.0"],
        excluded_analyzers = _EXCLUDED,
        tags = ["manual"],
    )

    action_args_test(
        name = "binary_with_excluded_analyzers_test",
        target_under_test = ":binary_with_excluded_analyzers",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [_LOGGING_GENERATOR],
        expected_args_not_containing = _EXCLUDED,
    )

    csharp_test(
        name = "test_with_excluded_analyzers",
        srcs = ["excluded_analyzers.cs"],
        project_sdk = "web",
        target_frameworks = ["net10.0"],
        excluded_analyzers = _EXCLUDED,
        tags = ["manual"],
    )

    action_args_test(
        name = "test_with_excluded_analyzers_test",
        target_under_test = ":test_with_excluded_analyzers",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [_LOGGING_GENERATOR],
        expected_args_not_containing = _EXCLUDED,
    )
