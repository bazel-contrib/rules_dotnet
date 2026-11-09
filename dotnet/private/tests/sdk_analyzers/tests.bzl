"""Tests for the .NET SDK's built-in analyzers (`enable_net_analyzers`,
`enforce_code_style_in_build`, and `analysis_mode`)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet:defs.bzl", "csharp_library")
load("//dotnet/private/tests:utils.bzl", "only_action")

_ANALYZER_PREFIX = "/analyzer:"
_CONFIG_PREFIX = "/analyzerconfig:"

def _extract_basenames(argv, prefix):
    return [
        arg[len(prefix):].strip("\"").rpartition("/")[-1]
        for arg in argv
        if arg.startswith(prefix)
    ]

def _sdk_analyzer_args_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = only_action(env, "CSharpCompile")

    analyzers = _extract_basenames(action.argv, _ANALYZER_PREFIX)
    configs = _extract_basenames(action.argv, _CONFIG_PREFIX)

    for expected in ctx.attr.expected_analyzers:
        asserts.true(
            env,
            expected in analyzers,
            "Expected analyzer {} in {}".format(expected, analyzers),
        )

    for unexpected in ctx.attr.unexpected_analyzers:
        asserts.false(
            env,
            unexpected in analyzers,
            "Expected analyzer {} not to be in {}".format(unexpected, analyzers),
        )

    for expected in ctx.attr.expected_configs:
        asserts.true(
            env,
            expected in configs,
            "Expected analyzerconfig {} in {}".format(expected, configs),
        )

    for unexpected in ctx.attr.unexpected_configs:
        asserts.false(
            env,
            unexpected in configs,
            "Expected analyzerconfig {} not to be in {}".format(unexpected, configs),
        )

    return analysistest.end(env)

sdk_analyzer_args_test = analysistest.make(
    _sdk_analyzer_args_test_impl,
    attrs = {
        "expected_analyzers": attr.string_list(),
        "unexpected_analyzers": attr.string_list(),
        "expected_configs": attr.string_list(),
        "unexpected_configs": attr.string_list(),
    },
)

sdk_analyzer_flag_enabled_test = analysistest.make(
    _sdk_analyzer_args_test_impl,
    attrs = {
        "expected_analyzers": attr.string_list(),
        "unexpected_analyzers": attr.string_list(),
        "expected_configs": attr.string_list(),
        "unexpected_configs": attr.string_list(),
    },
    config_settings = {
        str(Label("//dotnet/settings:enable_net_analyzers")): True,
        str(Label("//dotnet/settings:enforce_code_style_in_build")): True,
    },
)

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def sdk_analyzers_tests():
    csharp_library(
        name = "default_lib",
        srcs = ["Sample.cs"],
        target_frameworks = ["net10.0"],
    )

    sdk_analyzer_args_test(
        name = "disabled_by_default_test",
        target_under_test = ":default_lib",
        unexpected_analyzers = [
            "Microsoft.CodeAnalysis.NetAnalyzers.dll",
            "Microsoft.CodeAnalysis.CSharp.NetAnalyzers.dll",
            "Microsoft.CodeAnalysis.CodeStyle.dll",
            "Microsoft.CodeAnalysis.CSharp.CodeStyle.dll",
            "Microsoft.AspNetCore.Analyzers.dll",
        ],
        unexpected_configs = [
            "analysislevel_10_default.globalconfig",
            "analysislevelstyle_default.globalconfig",
        ],
    )

    sdk_analyzer_flag_enabled_test(
        name = "enabled_via_build_settings_test",
        target_under_test = ":default_lib",
        expected_analyzers = [
            "Microsoft.CodeAnalysis.NetAnalyzers.dll",
            "Microsoft.CodeAnalysis.CSharp.NetAnalyzers.dll",
            "Microsoft.CodeAnalysis.CodeStyle.dll",
            "Microsoft.CodeAnalysis.CSharp.CodeStyle.dll",
        ],
        expected_configs = [
            "analysislevel_10_default.globalconfig",
            "analysislevelstyle_default.globalconfig",
        ],
    )

    csharp_library(
        name = "net_analyzers_recommended_lib",
        srcs = ["Sample.cs"],
        analysis_mode = "recommended",
        enable_net_analyzers = 1,
        target_frameworks = ["net9.0"],
    )

    sdk_analyzer_args_test(
        name = "net_analyzers_recommended_test",
        target_under_test = ":net_analyzers_recommended_lib",
        expected_analyzers = [
            "Microsoft.CodeAnalysis.NetAnalyzers.dll",
            "Microsoft.CodeAnalysis.CSharp.NetAnalyzers.dll",
        ],
        unexpected_analyzers = [
            "Microsoft.CodeAnalysis.CodeStyle.dll",
            "Microsoft.AspNetCore.Analyzers.dll",
        ],
        expected_configs = [
            "analysislevel_9_recommended.globalconfig",
        ],
    )

    csharp_library(
        name = "web_sdk_analyzers_lib",
        srcs = ["Sample.cs"],
        enable_net_analyzers = 1,
        enforce_code_style_in_build = 1,
        project_sdk = "web",
        target_frameworks = ["net10.0"],
    )

    sdk_analyzer_args_test(
        name = "web_sdk_analyzers_test",
        target_under_test = ":web_sdk_analyzers_lib",
        expected_analyzers = [
            "Microsoft.CodeAnalysis.NetAnalyzers.dll",
            "Microsoft.CodeAnalysis.CSharp.NetAnalyzers.dll",
            "Microsoft.AspNetCore.Analyzers.dll",
            "Microsoft.AspNetCore.Mvc.Analyzers.dll",
            "Microsoft.CodeAnalysis.CodeStyle.dll",
            "Microsoft.CodeAnalysis.CSharp.CodeStyle.dll",
        ],
        expected_configs = [
            "analysislevel_10_default.globalconfig",
            "analysislevelstyle_default.globalconfig",
        ],
    )

    csharp_library(
        name = "explicitly_disabled_lib",
        srcs = ["Sample.cs"],
        enable_net_analyzers = 0,
        enforce_code_style_in_build = 0,
        target_frameworks = ["net10.0"],
    )

    sdk_analyzer_flag_enabled_test(
        name = "target_attribute_overrides_build_settings_test",
        target_under_test = ":explicitly_disabled_lib",
        unexpected_analyzers = [
            "Microsoft.CodeAnalysis.NetAnalyzers.dll",
            "Microsoft.CodeAnalysis.CodeStyle.dll",
        ],
    )
