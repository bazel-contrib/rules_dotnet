"""Tests for the .NET SDK's built-in analyzers (`enable_net_analyzers`,
`enforce_code_style_in_build`, and `analysis_mode`).

The expectations are what MSBuild resolves for the same project (`dotnet msbuild
-getItem:Analyzer`, and `-getItem:EditorConfigFiles` after the
`AddGlobalAnalyzerConfigForPackage_*` targets).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet:defs.bzl", "csharp_library")
load("//dotnet/private/tests:utils.bzl", "only_action")

_NET_ANALYZERS = [
    "Microsoft.CodeAnalysis.NetAnalyzers.dll",
    "Microsoft.CodeAnalysis.CSharp.NetAnalyzers.dll",
]
_CODE_STYLE_ANALYZERS = [
    "Microsoft.CodeAnalysis.CodeStyle.dll",
    "Microsoft.CodeAnalysis.CSharp.CodeStyle.dll",
]
_WEB_ANALYZERS = [
    "Microsoft.AspNetCore.Analyzers.dll",
    "Microsoft.AspNetCore.Mvc.Analyzers.dll",
]

def _basenames(argv, prefix):
    return [arg[len(prefix):].strip("\"").rpartition("/")[2] for arg in argv if arg.startswith(prefix)]

def _sdk_analyzer_args_test_impl(ctx):
    env = analysistest.begin(ctx)
    argv = only_action(env, "CSharpCompile").argv

    for prefix, expected, unexpected in [
        ("/analyzer:", ctx.attr.expected_analyzers, ctx.attr.unexpected_analyzers),
        ("/analyzerconfig:", ctx.attr.expected_configs, ctx.attr.unexpected_configs),
    ]:
        actual = _basenames(argv, prefix)
        for name in expected:
            asserts.true(env, name in actual, "Expected {} in {}".format(name, actual))
        for name in unexpected:
            asserts.false(env, name in actual, "Expected {} not in {}".format(name, actual))

    return analysistest.end(env)

_ATTRS = {
    "expected_analyzers": attr.string_list(),
    "unexpected_analyzers": attr.string_list(),
    "expected_configs": attr.string_list(),
    "unexpected_configs": attr.string_list(),
}

sdk_analyzer_args_test = analysistest.make(_sdk_analyzer_args_test_impl, attrs = _ATTRS)

sdk_analyzer_flag_enabled_test = analysistest.make(
    _sdk_analyzer_args_test_impl,
    attrs = _ATTRS,
    config_settings = {
        str(Label("//dotnet/settings:enable_net_analyzers")): True,
        str(Label("//dotnet/settings:enforce_code_style_in_build")): True,
    },
)

def _library(name, target_framework = "net10.0", **kwargs):
    csharp_library(
        name = name,
        srcs = ["Sample.cs"],
        target_frameworks = [target_framework],
        tags = ["manual"],
        **kwargs
    )

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def sdk_analyzers_tests():
    _library(name = "default_lib")

    sdk_analyzer_args_test(
        name = "disabled_by_default_test",
        target_under_test = ":default_lib",
        unexpected_analyzers = _NET_ANALYZERS + _CODE_STYLE_ANALYZERS,
        unexpected_configs = ["analysislevel_10_default.globalconfig"],
    )

    sdk_analyzer_flag_enabled_test(
        name = "enabled_via_build_settings_test",
        target_under_test = ":default_lib",
        expected_analyzers = _NET_ANALYZERS + _CODE_STYLE_ANALYZERS,
        expected_configs = ["analysislevel_10_default.globalconfig"],
        # MSBuild only adds it when `AnalysisModeStyle` differs from `AnalysisMode`.
        unexpected_configs = ["analysislevelstyle_default.globalconfig"],
    )

    _library(
        name = "explicitly_disabled_lib",
        enable_net_analyzers = "false",
        enforce_code_style_in_build = "false",
    )

    sdk_analyzer_flag_enabled_test(
        name = "target_attribute_overrides_build_settings_test",
        target_under_test = ":explicitly_disabled_lib",
        unexpected_analyzers = _NET_ANALYZERS + _CODE_STYLE_ANALYZERS,
    )

    _library(
        name = "net_analyzers_recommended_lib",
        analysis_mode = "recommended",
        enable_net_analyzers = "true",
        target_framework = "net9.0",
    )

    sdk_analyzer_args_test(
        name = "net_analyzers_recommended_test",
        target_under_test = ":net_analyzers_recommended_lib",
        expected_analyzers = _NET_ANALYZERS,
        unexpected_analyzers = _CODE_STYLE_ANALYZERS + _WEB_ANALYZERS,
        expected_configs = ["analysislevel_9_recommended.globalconfig"],
    )

    _library(
        name = "netstandard_lib",
        enable_net_analyzers = "true",
        target_framework = "netstandard2.0",
    )

    # No analysis level before .NET 5, so no config.
    sdk_analyzer_args_test(
        name = "netstandard_has_no_analysis_level_test",
        target_under_test = ":netstandard_lib",
        expected_analyzers = _NET_ANALYZERS,
        unexpected_configs = ["analysislevel_10_default.globalconfig"],
    )

    _library(
        name = "web_sdk_analyzers_lib",
        enable_net_analyzers = "true",
        enforce_code_style_in_build = "true",
        project_sdk = "web",
    )

    sdk_analyzer_args_test(
        name = "web_sdk_analyzers_test",
        target_under_test = ":web_sdk_analyzers_lib",
        expected_analyzers = _NET_ANALYZERS + _WEB_ANALYZERS + _CODE_STYLE_ANALYZERS,
        expected_configs = ["analysislevel_10_default.globalconfig"],
    )

    # Only `Microsoft.NET.Sdk.Web` adds the ASP.NET Core analyzers.
    for project_sdk in ["razor", "blazorwasm"]:
        _library(
            name = project_sdk + "_sdk_analyzers_lib",
            enable_net_analyzers = "true",
            project_sdk = project_sdk,
        )

        sdk_analyzer_args_test(
            name = project_sdk + "_sdk_analyzers_test",
            target_under_test = ":" + project_sdk + "_sdk_analyzers_lib",
            expected_analyzers = _NET_ANALYZERS,
            unexpected_analyzers = _WEB_ANALYZERS,
        )
