"""Implicit and explicit global `using` directives for C# compilations.

Mirrors the .NET SDK's `GenerateGlobalUsings` target. The implicit usings are
the `Using` items of the SDK's own props files, which the toolchain reads out of
the SDK (see `//dotnet/private/sdk:implicit_usings.bzl`), evaluated here against
the properties MSBuild would give the target.
"""

load("//dotnet/private:common.bzl", "is_core_framework", "is_netframework", "is_standard_framework", "tfm_version")
load("//dotnet/private:msbuild_condition.bzl", "evaluate_condition")
load("//dotnet/private/sdk:implicit_usings.bzl", "SDK_IMPLICIT_USINGS_BASE_PROPS", "SDK_IMPLICIT_USINGS_PROPS")
load("//dotnet/private/sdk:packs.bzl", "WINDOWSDESKTOP_FRAMEWORK")

def _uses_profile(frameworks, profile):
    if WINDOWSDESKTOP_FRAMEWORK not in frameworks:
        return False
    profiles = frameworks[WINDOWSDESKTOP_FRAMEWORK]
    return profiles == None or profile in profiles

def _target_framework_identifier(target_framework):
    if is_core_framework(target_framework):
        return ".NETCoreApp"
    if is_netframework(target_framework):
        return ".NETFramework"
    if is_standard_framework(target_framework):
        return ".NETStandard"
    return ""

def _properties(target_framework, frameworks):
    """The MSBuild properties the SDK's `Using` conditions read, lower cased."""
    return {
        "implicitusings": "enable",
        "language": "C#",
        "targetframeworkidentifier": _target_framework_identifier(target_framework),
        "targetframeworkversion": "v" + ".".join([str(part) for part in tfm_version(target_framework)]),
        "usewindowsforms": "true" if _uses_profile(frameworks, "WindowsForms") else "",
        "usewpf": "true" if _uses_profile(frameworks, "WPF") else "",
    }

def _sdk_implicit_usings(label, toolchain, project_sdk, target_framework, frameworks):
    """Evaluates the SDK's `Using` items in import order, applying each `Remove` to what came before."""
    sdk_props = toolchain.implicit_usings
    sdk_version = toolchain.dotnetinfo.sdk_version
    if sdk_props == None:
        fail("{}: `implicit_usings` needs a toolchain that reads them from the SDK, and the .NET SDK {} toolchain does not.".format(label, sdk_version))
    if SDK_IMPLICIT_USINGS_BASE_PROPS not in sdk_props:
        fail("{}: `implicit_usings` reads the SDK's Sdks/{}, which .NET SDK {} does not have.".format(label, SDK_IMPLICIT_USINGS_BASE_PROPS, sdk_version))

    properties = _properties(target_framework, frameworks)
    usings = {}
    for path in SDK_IMPLICIT_USINGS_PROPS[project_sdk]:
        props = sdk_props.get(path)
        if not props:
            continue
        if props["unsupported"]:
            fail("{}: `implicit_usings` cannot read Sdks/{} of .NET SDK {}: {}".format(label, path, sdk_version, props["unsupported"]))

        for item in props["items"]:
            applies = True
            for condition in item["conditions"]:
                result, error = evaluate_condition(condition, properties)
                if error:
                    fail("{}: `implicit_usings` cannot evaluate the condition {} in Sdks/{} of .NET SDK {}: {}".format(
                        label,
                        repr(condition),
                        path,
                        sdk_version,
                        error,
                    ))
                if not result:
                    applies = False
                    break

            if not applies:
                continue
            if item["op"] == "include":
                usings[item["namespace"]] = None
            else:
                usings.pop(item["namespace"], None)

    return usings.keys()

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

# What cannot appear in a namespace name. Identifiers may use any Unicode
# letter, so this rejects rather than allows. It rules out `static X`,
# `Alias = X` and `X;`, which would otherwise end up in the directive.
_NOT_IN_NAMESPACE = " \t\r\n;=,:<>()[]{}\"'`/\\!#$%^&*+-?|~"

def _is_namespace(name):
    """Whether `name` is a dotted name such as `System.Text.Json`."""
    for part in name.split("."):
        if not part or part[0].isdigit():
            return False
        for char in part.elems():
            if char in _NOT_IN_NAMESPACE:
                return False
    return True

def _validate_global_usings(label, attr_name, entries):
    for ns in entries:
        if not _is_namespace(ns):
            fail("{}: invalid namespace {} in `{}`; pass bare namespace names such as \"System.Text.Json\".".format(
                label,
                repr(ns),
                attr_name,
            ))

def resolve_global_usings(
        *,
        label,
        toolchain,
        project_sdk,
        target_framework,
        implicit_usings,
        frameworks = {},
        global_usings = [],
        excluded_global_usings = []):
    """Resolves the sorted, deduplicated global `using` namespaces for a C# target.

    The SDK's items come first, then `global_usings`, so that a namespace an SDK
    props file removes can be added back, as `<Using Include>` in a project file
    can. `excluded_global_usings` removes from both, as `<Using Remove>` does.

    Args:
        label: The target's `Label`, used in error messages.
        toolchain: The `dotnet_toolchain` `ToolchainInfo`.
        project_sdk: The target's `project_sdk` attribute.
        target_framework: The target's TFM.
        implicit_usings: Whether to include the .NET SDK's implicit usings.
        frameworks: Shared frameworks applicable to `target_framework`.
        global_usings: Additional namespaces to import globally (`<Using Include="..." />`).
        excluded_global_usings: Namespaces to drop (`<Using Remove="..." />`).

    Returns:
        A sorted list of unique namespaces.
    """
    _validate_global_usings(label, "global_usings", global_usings)
    _validate_global_usings(label, "excluded_global_usings", excluded_global_usings)

    candidates = []
    if implicit_usings:
        candidates.extend(_sdk_implicit_usings(label, toolchain, project_sdk, target_framework, frameworks))
    candidates.extend(global_usings)

    excluded = {ns: None for ns in excluded_global_usings}
    return sorted({ns: None for ns in candidates if ns not in excluded}.keys())

def write_global_usings_csharp(
        actions,
        *,
        label,
        toolchain,
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
    `// <auto-generated/>` followed by sorted `global using <ns>;` lines,
    so code style analyzers (`IDE0005`) ignore unused implicit imports.

    Args:
        actions: `ctx.actions`.
        label: The target's `Label`.
        toolchain: The `dotnet_toolchain` `ToolchainInfo`.
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
        toolchain = toolchain,
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
