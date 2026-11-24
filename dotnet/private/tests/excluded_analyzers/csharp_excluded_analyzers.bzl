"Excluded analyzers tests"

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet:defs.bzl", "csharp_binary", "csharp_library", "csharp_test")
load("//dotnet/private/tests:utils.bzl", "action_args_test", "only_action")

# Both come from the ASP.NET Core targeting pack.
_LOGGING_GENERATOR = "Microsoft.Extensions.Logging.Generators.dll"
_OPTIONS_GENERATOR = "Microsoft.Extensions.Options.SourceGeneration.dll"

def _no_analyzer_inputs_test_impl(ctx):
    env = analysistest.begin(ctx)
    inputs = [f.basename for f in only_action(env, "CSharpCompile").inputs.to_list()]
    asserts.false(env, _LOGGING_GENERATOR in inputs, "Expected no analyzers among the inputs: {}".format(inputs))
    return analysistest.end(env)

_no_analyzer_inputs_test = analysistest.make(_no_analyzer_inputs_test_impl)

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

    # With analyzers off, the compile runs none, so it does not read them either.
    csharp_library(
        name = "library_without_analyzers",
        srcs = ["excluded_analyzers.cs"],
        project_sdk = "web",
        run_analyzers = False,
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    _no_analyzer_inputs_test(
        name = "library_without_analyzers_test",
        target_under_test = ":library_without_analyzers",
    )
