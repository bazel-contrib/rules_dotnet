"""Implicit and explicit global `using` directives for C# compilations.

Mirrors the .NET SDK's `GenerateGlobalUsings` target and task:
  * `Microsoft.NET.Sdk.CSharp.props`
  * `Microsoft.NET.Sdk.Web` (`Targets/Sdk.Server.props`)
  * `Microsoft.NET.Sdk.BlazorWebAssembly` (`Sdk/Sdk.props`)
  * `Microsoft.NET.Sdk.WindowsDesktop.WindowsForms.props`
  * `Microsoft.NET.Sdk.WindowsDesktop.WPF.props`
  * `Microsoft.NET.GenerateGlobalUsings.targets`
"""

load("//dotnet/private:common.bzl", "is_netframework")
load("//dotnet/private/sdk:packs.bzl", "BLAZORWASM_SDK", "WEB_SDK", "WINDOWSDESKTOP_FRAMEWORK")

# Always included by Microsoft.NET.Sdk.CSharp.props when ImplicitUsings is on.
# System.Net.Http is gated on `'$(TargetFrameworkIdentifier)' != '.NETFramework'`.
_BASE_SDK_IMPLICIT_USINGS = [
    "System",
    "System.Collections.Generic",
    "System.IO",
    "System.Linq",
    "System.Threading",
    "System.Threading.Tasks",
]

_EXTRA_SDK_IMPLICIT_USINGS = {
    BLAZORWASM_SDK: [
        "Microsoft.Extensions.Configuration",
        "Microsoft.Extensions.DependencyInjection",
        "Microsoft.Extensions.Logging",
    ],
    WEB_SDK: [
        "System.Net.Http.Json",
        "Microsoft.AspNetCore.Builder",
        "Microsoft.AspNetCore.Hosting",
        "Microsoft.AspNetCore.Http",
        "Microsoft.AspNetCore.Routing",
        "Microsoft.Extensions.Configuration",
        "Microsoft.Extensions.DependencyInjection",
        "Microsoft.Extensions.Hosting",
        "Microsoft.Extensions.Logging",
    ],
}

_WINFORMS_IMPLICIT_USINGS = [
    "System.Drawing",
    "System.Windows.Forms",
]

# Microsoft.NET.Sdk.WindowsDesktop.WPF.props removes System.IO (conflicts with
# System.Windows.Shapes.Path) and System.Net.Http when UseWPF is enabled.
_WPF_REMOVED_IMPLICIT_USINGS = {
    "System.IO": None,
    "System.Net.Http": None,
}

def _uses_windows_forms(frameworks):
    if WINDOWSDESKTOP_FRAMEWORK not in frameworks:
        return False
    profiles = frameworks[WINDOWSDESKTOP_FRAMEWORK]
    return profiles == None or "WindowsForms" in profiles

def _uses_wpf(frameworks):
    if WINDOWSDESKTOP_FRAMEWORK not in frameworks:
        return False
    profiles = frameworks[WINDOWSDESKTOP_FRAMEWORK]
    return profiles == None or "WPF" in profiles

def _supports_global_usings(langversion):
    normalized = langversion.lower()
    if normalized in ("latest", "latestmajor", "preview", "default"):
        return True
    if normalized in ("iso-1", "iso-2"):
        return False
    major_str = normalized.partition(".")[0]
    if major_str.isdigit():
        return int(major_str) >= 10
    return True

def _validate_global_usings(label, attr_name, entries):
    for ns in entries:
        if not ns or ns != ns.strip() or ns.startswith("global using ") or any([ch in ns for ch in (";", "\n", "\r")]):
            fail("{}: invalid namespace {} in `{}`; pass bare namespace names such as \"System.Text.Json\".".format(
                label,
                repr(ns),
                attr_name,
            ))

def resolve_global_usings(
        *,
        label = None,
        project_sdk,
        target_framework,
        implicit_usings,
        frameworks = {},
        global_usings = [],
        excluded_global_usings = []):
    """Resolves the ordered, deduplicated global `using` namespaces for a C# target.

    Args:
        label: The target's `Label`, used in validation error messages.
        project_sdk: The target's `project_sdk` attribute.
        target_framework: The target's TFM.
        implicit_usings: Whether to include the .NET SDK's implicit usings.
        frameworks: Shared frameworks applicable to `target_framework`.
        global_usings: Additional namespaces to import globally (`<Using Include="..." />`).
        excluded_global_usings: Namespaces to drop (`<Using Remove="..." />`).

    Returns:
        A sorted list of unique global `using` entries.
    """
    _validate_global_usings(label, "global_usings", global_usings)
    _validate_global_usings(label, "excluded_global_usings", excluded_global_usings)

    candidates = []
    if implicit_usings:
        candidates.extend(_BASE_SDK_IMPLICIT_USINGS)
        if not is_netframework(target_framework):
            candidates.append("System.Net.Http")
        candidates.extend(_EXTRA_SDK_IMPLICIT_USINGS.get(project_sdk, []))
        if _uses_windows_forms(frameworks):
            candidates.extend(_WINFORMS_IMPLICIT_USINGS)
        if _uses_wpf(frameworks):
            candidates = [ns for ns in candidates if ns not in _WPF_REMOVED_IMPLICIT_USINGS]

    candidates.extend(global_usings)
    if not candidates:
        return []

    excluded = {ns: None for ns in excluded_global_usings}
    kept = {ns: None for ns in candidates if ns and ns not in excluded}
    return sorted(kept.keys())

def write_global_usings_csharp(
        actions,
        *,
        label,
        out_dir,
        assembly_name,
        langversion,
        project_sdk,
        target_framework,
        implicit_usings,
        frameworks = {},
        global_usings = [],
        excluded_global_usings = []):
    """Writes `<assembly>.GlobalUsings.g.cs` when global usings are present.

    Matches `GenerateGlobalUsings` in `Microsoft.NET.Build.Tasks`: emits
    `// <auto-generated/>` followed by sorted `global using <ns>;` lines so code
    style analyzers (`IDE0005`) ignore unused implicit imports.

    Args:
        actions: `ctx.actions`.
        label: The target's `Label`.
        out_dir: The target's per-TFM output directory.
        assembly_name: The assembly name without extension.
        langversion: The resolved C# language version for `target_framework`.
        project_sdk: The target's `project_sdk` attribute.
        target_framework: The target's TFM.
        implicit_usings: Whether to include the .NET SDK's implicit usings.
        frameworks: Shared frameworks applicable to `target_framework`.
        global_usings: Additional namespaces to import globally.
        excluded_global_usings: Namespaces to exclude from global imports.

    Returns:
        The generated `.GlobalUsings.g.cs` `File`, or `None` if there are no global usings.
    """
    usings = resolve_global_usings(
        label = label,
        project_sdk = project_sdk,
        target_framework = target_framework,
        implicit_usings = implicit_usings,
        frameworks = frameworks,
        global_usings = global_usings,
        excluded_global_usings = excluded_global_usings,
    )
    if not usings:
        return None

    if not _supports_global_usings(langversion):
        fail("{}: `implicit_usings` and `global_usings` require C# 10 or later, but {} compiles with C# {}. Set `langversion = \"10.0\"` or later.".format(
            label,
            target_framework,
            langversion,
        ))

    output = actions.declare_file("%s/%s.GlobalUsings.g.cs" % (out_dir, assembly_name))
    lines = ["// <auto-generated/>"] + ["global using %s;" % ns for ns in usings] + [""]
    actions.write(output, "\n".join(lines))
    return output
