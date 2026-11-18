"The .NET SDK's built-in analyzers and the global configs that set their severities."

load("//dotnet/private:common.bzl", "is_core_framework", "is_greater_or_equal_framework", "tfm_version")
load("//dotnet/private/sdk:packs.bzl", "WEB_SDK")

def _files(target):
    return target.files.to_list() if target else []

def _analysis_level(target_framework):
    """MSBuild's `EffectiveAnalysisLevel`: the framework's major version from .NET 5 on, and None before."""
    if is_core_framework(target_framework) and is_greater_or_equal_framework(target_framework, "net5.0"):
        return tfm_version(target_framework)[0]
    return None

def sdk_analyzer_compile_inputs(
        *,
        toolchain,
        target_framework,
        project_sdk,
        enable_net_analyzers,
        enforce_code_style_in_build,
        analysis_mode):
    """Selects the analyzers and `.globalconfig` files the .NET SDK adds to a C# compilation.

    See `Microsoft.NET.Sdk.Analyzers.targets`, and `Sdk.Server.props` in `Microsoft.NET.Sdk.Web`.

    Args:
        toolchain: The `dotnet_toolchain` `ToolchainInfo`.
        target_framework: The target's TFM.
        project_sdk: The target's `project_sdk` attribute.
        enable_net_analyzers: Whether to add the `CAxxxx` analyzers, and the
            ASP.NET Core analyzers for `project_sdk = "web"`.
        enforce_code_style_in_build: Whether to add the `IDExxxx` analyzers.
        analysis_mode: The `analysis_mode` attribute.

    Returns:
        `struct(analyzers = [...], analyzer_configs = [...])`.
    """
    analyzers = []
    analyzer_configs = []

    if enable_net_analyzers:
        analyzers += _files(toolchain.csharp_net_analyzers)

        # MSBuild adds these to a web project even without `EnableNETAnalyzers`.
        if project_sdk == WEB_SDK and is_core_framework(target_framework):
            analyzers += _files(toolchain.web_sdk_analyzers)

        level = _analysis_level(target_framework)
        if level:
            config = "analysislevel_{}_{}.globalconfig".format(level, analysis_mode)
            analyzer_configs += [f for f in _files(toolchain.net_analyzer_configs) if f.basename == config]

    if enforce_code_style_in_build:
        analyzers += _files(toolchain.csharp_codestyle_analyzers)

    return struct(
        analyzers = analyzers,
        analyzer_configs = analyzer_configs,
    )
