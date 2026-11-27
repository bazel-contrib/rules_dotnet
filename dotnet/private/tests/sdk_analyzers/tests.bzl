"""Tests for the .NET SDK's built-in analyzers (`enable_net_analyzers`,
`enforce_code_style_in_build`, and `analysis_mode`).

The expectations are what MSBuild resolves for the same project (`dotnet msbuild
-getItem:Analyzer`, and `-getItem:EditorConfigFiles` after the
`AddGlobalAnalyzerConfigForPackage_*` targets).
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load(
    "//dotnet:defs.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetCSharpAnalyzerInfo",
    "csharp_binary",
    "csharp_library",
    "sdk_analyzer_compile_inputs",
)
load("//dotnet/private/tests:utils.bzl", "only_action")

def _csharp_analyzer_info_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.true(env, DotnetAssemblyCompileInfo in target, "Expected DotnetAssemblyCompileInfo provider on C# target")
    asserts.true(env, DotnetCSharpAnalyzerInfo in target, "Expected DotnetCSharpAnalyzerInfo provider on C# target")
    info = target[DotnetCSharpAnalyzerInfo]
    asserts.equals(env, ctx.attr.expected_assembly_name, info.assembly_name)
    asserts.equals(env, ctx.attr.expected_assembly_name + ".dll", info.out_dll_name)
    asserts.equals(env, ctx.attr.expected_target, info.target)
    asserts.equals(env, "net10.0", info.target_framework)
    asserts.equals(env, ctx.attr.expected_project_sdk, info.project_sdk)

    src_basenames = [f.basename for f in info.srcs.to_list()]
    asserts.true(env, ctx.attr.expected_src in src_basenames, "Expected {} in info.srcs: {}".format(ctx.attr.expected_src, src_basenames))
    asserts.true(env, len(info.framework_files.to_list()) > 0, "Expected non-empty framework_files")

    # DotnetCSharpAnalyzerInfo excludes the SDK's built-in analyzers and globalconfigs so
    # external lint aspects can layer `sdk_analyzer_compile_inputs` with their own settings,
    # while still keeping targeting-pack and dependency source generators/analyzers.
    analyzer_basenames = [f.basename for f in info.analyzers_csharp.to_list()]
    for sdk_analyzer in _NET_ANALYZERS + _CODE_STYLE_ANALYZERS + _WEB_ANALYZERS:
        asserts.false(env, sdk_analyzer in analyzer_basenames, "Expected SDK analyzer {} not in info.analyzers_csharp: {}".format(sdk_analyzer, analyzer_basenames))
    asserts.true(env, "System.Text.Json.SourceGeneration.dll" in analyzer_basenames, "Expected System.Text.Json generator in info.analyzers_csharp: {}".format(analyzer_basenames))
    if ctx.attr.expected_project_sdk == "web":
        asserts.true(env, "Microsoft.AspNetCore.App.SourceGenerators.dll" in analyzer_basenames, "Expected ASP.NET Core generator in info.analyzers_csharp: {}".format(analyzer_basenames))

    config_basenames = [f.basename for f in info.analyzer_configs.to_list()]
    asserts.false(env, "analysislevel_10_default.globalconfig" in config_basenames, "Expected SDK globalconfig not in info.analyzer_configs: {}".format(config_basenames))

    for symbol in ctx.attr.expected_defines:
        asserts.true(env, symbol in info.defines, "Expected {} in info.defines: {}".format(symbol, info.defines))
    for symbol in ctx.attr.unexpected_defines:
        asserts.false(env, symbol in info.defines, "Expected {} not in info.defines: {}".format(symbol, info.defines))

    empty_sdk_inputs = sdk_analyzer_compile_inputs(
        toolchain = None,
        target_framework = info.target_framework,
        project_sdk = info.project_sdk,
        enable_net_analyzers = False,
        enforce_code_style_in_build = False,
        analysis_mode = "default",
    )
    asserts.equals(env, [], empty_sdk_inputs.analyzers)
    asserts.equals(env, [], empty_sdk_inputs.analyzer_configs)

    return analysistest.end(env)

_ANALYZER_INFO_ATTRS = {
    "expected_assembly_name": attr.string(mandatory = True),
    "expected_target": attr.string(mandatory = True),
    "expected_project_sdk": attr.string(mandatory = True),
    "expected_src": attr.string(mandatory = True),
    "expected_defines": attr.string_list(),
    "unexpected_defines": attr.string_list(),
}

csharp_analyzer_info_dbg_test = analysistest.make(
    _csharp_analyzer_info_test_impl,
    attrs = _ANALYZER_INFO_ATTRS,
    config_settings = {
        "//command_line_option:compilation_mode": "dbg",
    },
)

csharp_analyzer_info_opt_test = analysistest.make(
    _csharp_analyzer_info_test_impl,
    attrs = _ANALYZER_INFO_ATTRS,
    config_settings = {
        "//command_line_option:compilation_mode": "opt",
    },
)

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

    csharp_analyzer_info_dbg_test(
        name = "csharp_analyzer_info_lib_test",
        target_under_test = ":web_sdk_analyzers_lib",
        expected_assembly_name = "web_sdk_analyzers_lib",
        expected_target = "library",
        expected_project_sdk = "web",
        expected_src = "Sample.cs",
        expected_defines = ["TRACE", "DEBUG", "NET10_0"],
        unexpected_defines = ["RELEASE"],
    )

    csharp_binary(
        name = "sdk_analyzers_bin",
        srcs = ["Program.cs"],
        defines = ["CUSTOM_SYM"],
        enable_net_analyzers = "true",
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )

    csharp_analyzer_info_dbg_test(
        name = "csharp_analyzer_info_bin_dbg_test",
        target_under_test = ":sdk_analyzers_bin",
        expected_assembly_name = "sdk_analyzers_bin",
        expected_target = "exe",
        expected_project_sdk = "default",
        expected_src = "Program.cs",
        expected_defines = ["TRACE", "DEBUG", "NET10_0", "CUSTOM_SYM"],
        unexpected_defines = ["RELEASE"],
    )

    csharp_analyzer_info_opt_test(
        name = "csharp_analyzer_info_bin_opt_test",
        target_under_test = ":sdk_analyzers_bin",
        expected_assembly_name = "sdk_analyzers_bin",
        expected_target = "exe",
        expected_project_sdk = "default",
        expected_src = "Program.cs",
        expected_defines = ["TRACE", "RELEASE", "NET10_0", "CUSTOM_SYM"],
        unexpected_defines = ["DEBUG"],
    )
