"Generate .bzl files from parsed .csproj/.fsproj projects"

load("@bazel_skylib//lib:paths.bzl", "paths")
load(":parser.bzl", "extract_additional_attrs", "get_bazel_rule_name", "get_project_sdk_attr")

def generate_project_bzl(
        parsed_project,
        project_path,
        project_dir,
        is_fsharp,
        nuget_repo_name = "dotnet_projects.nuget",
        workspace_root = ""):
    """Generate the .bzl file content for a single project.

    Args:
        parsed_project: A struct returned by parse_project_file.
        project_path: Path to the project file relative to workspace.
        project_dir: Directory containing the project file relative to workspace.
        is_fsharp: Whether this is an F# project.
        nuget_repo_name: Name of the NuGet repository.
        workspace_root: The workspace root for label resolution.

    Returns:
        String content of the .bzl file.
    """
    rule_name = get_bazel_rule_name(parsed_project, is_fsharp)
    project_sdk = get_project_sdk_attr(parsed_project)
    additional_attrs = extract_additional_attrs(parsed_project)

    # Generate source file list or glob
    srcs = _generate_srcs(parsed_project, is_fsharp)

    # Generate dependencies
    deps = _generate_deps(parsed_project, project_dir, nuget_repo_name, workspace_root)

    # Build the .bzl file content
    lines = []
    lines.append('"Generated from {}"'.format(project_path))
    lines.append("")
    lines.append('load("@rules_dotnet//dotnet:defs.bzl", "{}")'.format(rule_name))
    lines.append("")
    lines.append("def auto_dotnet_targets(name, **kwargs):")
    lines.append('    """Auto-generated targets from {}.'.format(project_path.split("/")[-1]))
    lines.append("")
    lines.append("    Args:")
    lines.append("        name: The target name.")
    lines.append("        **kwargs: Additional arguments passed to the underlying rule.")
    lines.append('    """')

    # Start rule invocation
    lines.append("    {}(".format(rule_name))
    lines.append("        name = name,")

    # Source files
    lines.append("        srcs = {},".format(srcs))

    # Target frameworks (required)
    if parsed_project.target_frameworks:
        frameworks = ['"{}"'.format(f) for f in parsed_project.target_frameworks]
        lines.append("        target_frameworks = [{}],".format(", ".join(frameworks)))
    else:
        # Default to a reasonable framework if none specified
        lines.append('        target_frameworks = ["net8.0"],  # Default, update as needed')

    # Dependencies
    if deps:
        lines.append("        deps = [")
        for dep in deps:
            lines.append('            "{}",'.format(dep))
        lines.append("        ],")

    # Project SDK
    if project_sdk:
        lines.append('        project_sdk = "{}",'.format(project_sdk))

    # Additional attributes from properties
    for attr_name, attr_value in additional_attrs.items():
        if type(attr_value) == "bool":
            lines.append("        {} = {},".format(attr_name, "True" if attr_value else "False"))
        elif type(attr_value) == "int":
            lines.append("        {} = {},".format(attr_name, attr_value))
        else:
            lines.append('        {} = "{}",'.format(attr_name, attr_value))

    # Allow kwargs override
    lines.append("        **kwargs")
    lines.append("    )")
    lines.append("")

    return "\n".join(lines)

def _generate_srcs(parsed_project, is_fsharp):
    """Generate the srcs attribute value.

    Args:
        parsed_project: A struct returned by parse_project_file.
        is_fsharp: Whether this is an F# project.

    Returns:
        String representation of the srcs list or glob.
    """
    ext = ".fs" if is_fsharp else ".cs"

    if parsed_project.sources:
        # Explicit sources - use them directly
        # For F#, order matters, so we preserve the order from the .fsproj
        sources = ['"{}"'.format(s) for s in parsed_project.sources]
        return "[{}]".format(", ".join(sources))

    if parsed_project.enable_default_items:
        # Use glob for default item behavior (SDK-style projects include subdirectories)
        return 'kwargs.get("srcs", native.glob(["**/*{}"], exclude = ["obj/**", "bin/**"]))'.format(ext)

    # No sources and default items disabled - return empty or kwargs
    return 'kwargs.get("srcs", [])'

def _generate_deps(parsed_project, project_dir, nuget_repo_name, _workspace_root):  # buildifier: disable=unused-variable
    """Generate the deps list.

    Args:
        parsed_project: A struct returned by parse_project_file.
        project_dir: Directory containing the project file.
        nuget_repo_name: Name of the NuGet repository.
        _workspace_root: The workspace root for label resolution (unused, kept for API compatibility).

    Returns:
        List of Bazel label strings.
    """
    deps = []

    # Add project references
    for proj_ref in parsed_project.project_references:
        label = _project_reference_to_label(proj_ref.path, project_dir)
        if label:
            deps.append(label)

    # Add package references
    for pkg_ref in parsed_project.package_references:
        label = "@{}//{}".format(nuget_repo_name, pkg_ref.id.lower())
        deps.append(label)

    return deps

def _project_reference_to_label(ref_path, project_dir):
    """Convert a ProjectReference path to a Bazel label.

    Uses paths utilities from bazel_skylib for path manipulation.

    Args:
        ref_path: Relative path from the current project to the referenced project.
        project_dir: Directory containing the current project file.

    Returns:
        Bazel label string, or None if conversion fails.
    """
    if not ref_path:
        return None

    # Normalize the path (handle Windows backslashes)
    ref_path = ref_path.replace("\\", "/")

    # Resolve relative path components
    resolved = _resolve_relative_path(project_dir, ref_path)
    if resolved == None:
        return None

    # Use paths utilities to extract directory and filename
    dir_path = paths.dirname(resolved)
    filename = paths.basename(resolved)

    # Remove file extension to get target name using paths.split_extension
    target_name, _ext = paths.split_extension(filename)

    # Build the label
    if dir_path:
        return "//{}:{}".format(dir_path, target_name)
    else:
        return ":{}".format(target_name)

def _resolve_relative_path(base_dir, rel_path):
    """Resolve a relative path against a base directory.

    Uses paths.normalize from bazel_skylib to handle path normalization.

    Args:
        base_dir: The base directory path.
        rel_path: The relative path to resolve.

    Returns:
        The resolved path, or None if it goes above workspace root.
    """

    # Join the paths and normalize
    joined = paths.join(base_dir, rel_path) if base_dir else rel_path
    normalized = paths.normalize(joined)

    # Check if the path goes above workspace root (starts with ..)
    if normalized.startswith(".."):
        return None

    # Handle the case where normalize returns "." for empty paths
    if normalized == ".":
        return ""

    return normalized

def generate_defs_bzl():
    """Generate the root defs.bzl file for the @dotnet_projects repository.

    Returns:
        String content of the defs.bzl file.
    """
    return '''"Common utilities for @dotnet_projects repository"

# This file provides common utilities that can be used across generated .bzl files.
# Currently empty but can be extended with shared functionality.
'''

def generate_root_build_bazel():
    """Generate the root BUILD.bazel file for the @dotnet_projects repository.

    Returns:
        String content of the BUILD.bazel file.
    """
    return '''# Generated BUILD.bazel for @dotnet_projects repository
# This file exports the generated .bzl files.

exports_files(glob(["**/*.bzl"]))
'''

def generate_subdir_build_bazel(bzl_files):
    """Generate a BUILD.bazel file for a subdirectory.

    Args:
        bzl_files: List of .bzl filenames in this directory.

    Returns:
        String content of the BUILD.bazel file.
    """
    lines = [
        "# Generated BUILD.bazel",
        "",
    ]

    if bzl_files:
        exports = ['"{}"'.format(f) for f in bzl_files]
        lines.append("exports_files([{}])".format(", ".join(exports)))
    else:
        lines.append("# No .bzl files in this directory")

    lines.append("")
    return "\n".join(lines)
