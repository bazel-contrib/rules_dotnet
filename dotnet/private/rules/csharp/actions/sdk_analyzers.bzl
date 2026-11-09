"Resolves the .NET SDK's built-in analyzers and global analyzer configs."

load("//dotnet/private:common.bzl", "is_core_framework", "tfm_to_semver")
load("//dotnet/private/sdk:packs.bzl", "WEB_SDK", "normalize_project_sdk")

def _effective_analysis_level_major(target_framework, toolchain):
    """The major version of the SDK's `analysislevel_<major>_<mode>.globalconfig`.

    `Microsoft.NET.Sdk.Analyzers.targets` uses the target framework's major
    version for `.NET 5+` and falls back to the SDK's own major version when
    `EnableNETAnalyzers` is explicitly enabled on an older framework.
    """
    if is_core_framework(target_framework) and not target_framework.startswith("netcoreapp"):
        return int(tfm_to_semver(target_framework).split(".")[0])
    return int(toolchain.dotnetinfo.sdk_version.split(".")[0])

def _select_config(configs, basename):
    for config in configs:
        if config.basename == basename:
            return config
    return None

def sdk_analyzer_compile_inputs(
        *,
        toolchain,
        target_framework,
        project_sdk,
        enable_net_analyzers,
        enforce_code_style_in_build,
        analysis_mode = "default"):
    """Selects the .NET SDK's built-in analyzers and `.globalconfig` files.

    Matches `Microsoft.NET.Sdk.Analyzers.targets` and `Sdk.Server.props` in
    `Microsoft.NET.Sdk.Web`.

    Args:
        toolchain: The `dotnet_toolchain` `ToolchainInfo`.
        target_framework: The target's TFM (`net10.0`, `netstandard2.0`, ...).
        project_sdk: The target's `project_sdk` attribute.
        enable_net_analyzers: Whether to include the SDK's `CAxxxx` analyzers
            (and ASP.NET Core analyzers when `project_sdk == "web"`).
        enforce_code_style_in_build: Whether to include the SDK's `IDExxxx`
            C# code style analyzers.
        analysis_mode: The preset mode (`default`, `none`, `minimum`,
            `recommended`, or `all`).

    Returns:
        `struct(analyzers = [...], analyzer_configs = [...])`.
    """
    analyzers = []
    analyzer_configs = []
    mode = analysis_mode.lower()

    if enable_net_analyzers:
        if toolchain.csharp_net_analyzers != None:
            analyzers.extend(toolchain.csharp_net_analyzers.files.to_list())

        if normalize_project_sdk(project_sdk) == WEB_SDK and is_core_framework(target_framework):
            if toolchain.web_sdk_analyzers != None:
                analyzers.extend(toolchain.web_sdk_analyzers.files.to_list())

        if toolchain.net_analyzer_configs != None:
            major = _effective_analysis_level_major(target_framework, toolchain)
            config = _select_config(
                toolchain.net_analyzer_configs.files.to_list(),
                "analysislevel_{}_{}.globalconfig".format(major, mode),
            )
            if config != None:
                analyzer_configs.append(config)

    if enforce_code_style_in_build:
        if toolchain.csharp_codestyle_analyzers != None:
            analyzers.extend(toolchain.csharp_codestyle_analyzers.files.to_list())

        if toolchain.csharp_codestyle_configs != None:
            config = _select_config(
                toolchain.csharp_codestyle_configs.files.to_list(),
                "analysislevelstyle_{}.globalconfig".format(mode),
            )
            if config != None:
                analyzer_configs.append(config)

    return struct(
        analyzers = analyzers,
        analyzer_configs = analyzer_configs,
    )
