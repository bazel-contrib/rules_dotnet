"""Helper for running Roslyn analyzers and producing SARIF reports.

Designed for aspect-based static analysis and linters such as `rules_lint`, so
that external aspects can analyze any `csharp_library`, `csharp_binary`, or
`csharp_test` target and obtain a SARIF v2.1 report without coupling to
`rules_dotnet`'s compilation internals (targeting packs, response files,
Razor/scoped CSS generation, or persistent compiler workers).
"""

load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetCSharpAnalyzerInfo")

def _collect_extra_analyzers(targets):
    files = []
    for entry in targets:
        if type(entry) == "File":
            files.append(entry)
        elif DotnetAssemblyCompileInfo in entry:
            info = entry[DotnetAssemblyCompileInfo]
            files.extend(info.analyzers)
            files.extend(info.analyzers_csharp)
            files.extend(info.transitive_analyzers.to_list())
            files.extend(info.transitive_analyzers_csharp.to_list())
        elif DefaultInfo in entry:
            files.extend(entry[DefaultInfo].files.to_list())
    return files

def _collect_files(entries):
    files = []
    for entry in entries:
        if type(entry) == "File":
            files.append(entry)
        elif DefaultInfo in entry:
            files.extend(entry[DefaultInfo].files.to_list())
    return files

def analyze_csharp_target(
        actions,
        target,
        output_sarif,
        *,
        enable_net_analyzers = True,
        enforce_code_style = True,
        analysis_mode = "default",
        extra_analyzers = [],
        extra_analyzer_configs = [],
        extra_additionalfiles = [],
        treat_warnings_as_errors = False):
    """Registers a C# Roslyn analyzer action on `target` that writes a SARIF v2.1 report.

    Runs `csc` with `/errorlog:<output_sarif>,version=2.1` using the target's
    own resolved references, framework targeting pack, Razor/scoped CSS inputs,
    and analyzers, plus the .NET SDK's built-in analyzers (`CAxxxx` and
    `IDExxxx`) and any `extra_analyzers` (such as Roslynator or StyleCop) or
    `.editorconfig` / `.globalconfig` files passed by the aspect.

    Args:
        actions: `ctx.actions` from the calling aspect or rule.
        target: The `Target` being visited. If it is not a C# target carrying
            `DotnetCSharpAnalyzerInfo`, this function returns `False` and
            registers no action.
        output_sarif: The declared output `File` where the SARIF v2.1 report
            will be written.
        enable_net_analyzers: Include the .NET SDK's `CAxxxx` analyzers (and
            Web SDK analyzers for `project_sdk = "web"`). Defaults to `True`.
        enforce_code_style: Include the .NET SDK's `IDExxxx` C# code style
            analyzers (including `IDE0055` formatting diagnostics). Defaults to
            `True`.
        analysis_mode: The SDK analyzer preset (`default`, `none`, `minimum`,
            `recommended`, or `all`). Defaults to `"default"`.
        extra_analyzers: Additional analyzer `File`s or analyzer `Target`s
            (such as `@paket.nuget//roslynator.analyzers`) to run alongside the
            target's and SDK's analyzers.
        extra_analyzer_configs: Additional `.editorconfig` or `.globalconfig`
            `File`s or `Target`s passed via `/analyzerconfig:`. Placed after the
            SDK's preset configs so workspace settings take precedence.
        extra_additionalfiles: Additional `File`s or `Target`s passed via
            `/additionalfile:`.
        treat_warnings_as_errors: If `False` (the default), warnings are
            recorded in `output_sarif` without failing the action, matching how
            `rules_lint` collects SARIF reports. Set to `True` to fail the
            action when analyzer warnings are emitted.

    Returns:
        `True` if `target` is a C# target and an analysis action was registered,
        or `False` otherwise.
    """
    if DotnetCSharpAnalyzerInfo not in target:
        return False

    target[DotnetCSharpAnalyzerInfo].compile(
        actions,
        output_sarif,
        enable_net_analyzers = enable_net_analyzers,
        enforce_code_style = enforce_code_style,
        analysis_mode = analysis_mode,
        extra_analyzers = _collect_extra_analyzers(extra_analyzers),
        extra_analyzer_configs = _collect_files(extra_analyzer_configs),
        extra_additionalfiles = _collect_files(extra_additionalfiles),
        treat_warnings_as_errors = treat_warnings_as_errors,
    )
    return True
