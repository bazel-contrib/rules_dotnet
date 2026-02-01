"Repository rule for scanning and generating .bzl files from .csproj/.fsproj projects"

load("@bazel_lib//lib:glob_match.bzl", "glob_match")
load(":generator.bzl", "generate_defs_bzl", "generate_project_bzl", "generate_root_build_bazel", "generate_subdir_build_bazel")
load(":nuget_collector.bzl", "create_nuget_collector", "generate_nuget_packages_bzl", "generate_paket_dependencies")
load(":parser.bzl", "parse_project_file")
load(":tfm_utils.bzl", "find_best_toolchain_for_tfms")

def _find_project_files(repository_ctx, workspace_dir, exclude_patterns):
    """Find all .csproj and .fsproj files in the workspace.

    Args:
        repository_ctx: The repository context.
        workspace_dir: Path to the workspace root.
        exclude_patterns: List of glob patterns to exclude.

    Returns:
        List of project file paths relative to workspace root.
    """

    # Detect platform and use appropriate command
    is_windows = repository_ctx.os.name.startswith("windows")

    if is_windows:
        project_files = _find_project_files_windows(repository_ctx, workspace_dir)
    else:
        project_files = _find_project_files_unix(repository_ctx, workspace_dir)

    # Apply exclude patterns (cross-platform filtering)
    filtered = []
    for path in project_files:
        # Normalize to forward slashes for consistent matching
        normalized = path.replace("\\", "/")
        if not _matches_exclude(normalized, exclude_patterns):
            filtered.append(normalized)

    return filtered

def _find_project_files_unix(repository_ctx, workspace_dir):
    """Find project files on Unix systems using find command.

    Args:
        repository_ctx: The repository context.
        workspace_dir: Path to the workspace root.

    Returns:
        List of project file paths relative to workspace root.
    """
    find_args = [
        "find",
        str(workspace_dir),
        "-type",
        "f",
        "(",
        "-name",
        "*.csproj",
        "-o",
        "-name",
        "*.fsproj",
        ")",
        "-not",
        "-path",
        "*/bin/*",
        "-not",
        "-path",
        "*/obj/*",
        "-not",
        "-path",
        "*/.git/*",
        "-not",
        "-path",
        "*/.jj/*",
        "-not",
        "-path",
        "*/bazel-*/*",
    ]

    result = repository_ctx.execute(find_args, timeout = 60)

    if result.return_code != 0:
        return []

    project_files = []
    workspace_str = str(workspace_dir)

    for line in result.stdout.split("\n"):
        line = line.strip()
        if not line:
            continue

        # Make path relative to workspace
        if line.startswith(workspace_str):
            rel_path = line[len(workspace_str):]
            if rel_path.startswith("/"):
                rel_path = rel_path[1:]
        else:
            rel_path = line

        project_files.append(rel_path)

    return project_files

def _find_project_files_windows(repository_ctx, workspace_dir):
    """Find project files on Windows using PowerShell or cmd.

    Args:
        repository_ctx: The repository context.
        workspace_dir: Path to the workspace root.

    Returns:
        List of project file paths relative to workspace root.
    """

    # Try PowerShell first (more reliable, handles exclusions better)
    ps_script = """
$ErrorActionPreference = 'SilentlyContinue'
Get-ChildItem -Path '{}' -Recurse -Include *.csproj,*.fsproj |
    Where-Object {{ $_.FullName -notmatch '\\\\(bin|obj|\\.git|\\.jj|bazel-)\\\\' }} |
    ForEach-Object {{ $_.FullName }}
""".format(str(workspace_dir).replace("'", "''"))

    result = repository_ctx.execute(
        ["powershell", "-NoProfile", "-Command", ps_script],
        timeout = 120,
    )

    if result.return_code == 0 and result.stdout.strip():
        return _parse_windows_paths(result.stdout, str(workspace_dir))

    # Fallback to cmd.exe dir command
    result = repository_ctx.execute(
        ["cmd", "/c", "dir", "/s", "/b", str(workspace_dir) + "\\*.csproj", str(workspace_dir) + "\\*.fsproj"],
        timeout = 120,
    )

    if result.return_code == 0:
        return _parse_windows_paths(result.stdout, str(workspace_dir))

    return []

def _parse_windows_paths(output, workspace_dir):
    """Parse Windows command output and convert to relative paths.

    Args:
        output: Command output with full paths.
        workspace_dir: Workspace directory path.

    Returns:
        List of relative paths with forward slashes.
    """
    project_files = []
    workspace_str = workspace_dir.replace("/", "\\")

    # Also handle forward-slash version
    workspace_str_fwd = workspace_dir.replace("\\", "/")

    for line in output.split("\n"):
        line = line.strip()
        if not line:
            continue

        # Skip common exclusion directories
        line_lower = line.lower()
        if "\\bin\\" in line_lower or "\\obj\\" in line_lower or "\\.git\\" in line_lower or "\\.jj\\" in line_lower or "\\bazel-" in line_lower:
            continue

        # Make path relative
        if line.startswith(workspace_str):
            rel_path = line[len(workspace_str):]
        elif line.startswith(workspace_str_fwd):
            rel_path = line[len(workspace_str_fwd):]
        else:
            rel_path = line

        # Remove leading path separator
        if rel_path.startswith("\\") or rel_path.startswith("/"):
            rel_path = rel_path[1:]

        # Normalize to forward slashes
        rel_path = rel_path.replace("\\", "/")

        if rel_path:
            project_files.append(rel_path)

    return project_files

def _matches_exclude(path, patterns):
    """Check if a path matches any exclude pattern.

    Uses glob_match from bazel_lib for proper glob pattern matching.

    Args:
        path: The path to check.
        patterns: List of glob patterns.

    Returns:
        True if the path should be excluded.
    """
    for pattern in patterns:
        if glob_match(pattern, path):
            return True
    return False

def _dotnet_projects_repo_impl(repository_ctx):
    """Implementation of the dotnet_projects_repo repository rule."""
    exclude_patterns = repository_ctx.attr.exclude_patterns
    nuget_repo_name = repository_ctx.attr.nuget_repo_name
    registered_toolchains_json = repository_ctx.attr.registered_toolchains
    fail_on_missing = repository_ctx.attr.fail_on_missing_toolchain

    # Parse registered toolchains from JSON
    registered_toolchains = {}
    if registered_toolchains_json:
        registered_toolchains = json.decode(registered_toolchains_json)

    # Get workspace root directory
    # Use workspace_root if available (Bazel 7.1+), otherwise fail with a helpful message
    if hasattr(repository_ctx, "workspace_root"):
        workspace_dir = repository_ctx.workspace_root
    else:
        fail("The scan_projects feature requires Bazel 7.1 or later which provides repository_ctx.workspace_root")

    # Find all project files
    project_files = _find_project_files(
        repository_ctx,
        workspace_dir,
        exclude_patterns,
    )

    # Watch directories containing project files for changes
    # This helps Bazel detect when new files are added to existing project directories
    # Note: New top-level directories with projects won't be detected automatically
    # - users should run `bazel sync --only=@dotnet_projects` after adding new project directories
    if hasattr(repository_ctx, "watch_tree"):
        watched_dirs = {}
        has_root_project = False
        for project_path in project_files:
            project_dir = "/".join(project_path.split("/")[:-1]) if "/" in project_path else ""
            if not project_dir:
                # Project at workspace root
                has_root_project = True
                continue
            if project_dir not in watched_dirs:
                watched_dirs[project_dir] = True
                dir_path = repository_ctx.path(workspace_dir).get_child(project_dir)
                repository_ctx.watch_tree(dir_path)

        # Note: We intentionally don't watch the workspace root even if there are
        # root-level projects, as this would cause excessive re-evaluation.
        # Users should run `bazel sync` if they add new root-level project files.
        if has_root_project:
            # Watch individual project files at root instead of the whole directory
            for project_path in project_files:
                if "/" not in project_path:
                    repository_ctx.watch(repository_ctx.path(workspace_dir).get_child(project_path))

    # Collect NuGet packages
    nuget_collector = create_nuget_collector()

    # Track generated files by directory
    generated_dirs = {}

    # Collect all TFMs for validation
    all_tfms = {}  # TFM -> list of projects using it
    parsed_projects = []  # Store parsed projects for later processing

    # First pass: parse all projects and collect TFMs
    for project_path in project_files:
        # Read project file content
        full_path = repository_ctx.path(workspace_dir).get_child(project_path)

        # Check if file exists and is readable
        content = repository_ctx.read(full_path)
        if not content:
            continue

        # Determine if F# or C#
        is_fsharp = project_path.endswith(".fsproj")

        # Parse the project
        parsed = parse_project_file(content)

        if parsed.errors:
            # Log errors but continue
            # buildifier: disable=print
            print("Warning: Errors parsing {}: {}".format(project_path, ", ".join(parsed.errors)))

        # Collect TFMs
        for tfm in parsed.target_frameworks:
            if tfm not in all_tfms:
                all_tfms[tfm] = []
            all_tfms[tfm].append(project_path)

        # Store for later
        parsed_projects.append(struct(
            path = project_path,
            parsed = parsed,
            is_fsharp = is_fsharp,
        ))

    # Validate toolchain coverage
    if registered_toolchains and all_tfms:
        coverage = find_best_toolchain_for_tfms(registered_toolchains, all_tfms.keys())

        if coverage.uncovered:
            message_lines = [
                "The following target frameworks are not covered by any registered toolchain:",
            ]
            for tfm in coverage.uncovered:
                projects = all_tfms.get(tfm, [])
                message_lines.append("  {} (used by {} project(s)):".format(tfm, len(projects)))
                for proj in projects[:3]:  # Show first 3 projects
                    message_lines.append("    - {}".format(proj))
                if len(projects) > 3:
                    message_lines.append("    - ... and {} more".format(len(projects) - 3))

                suggested = coverage.suggestions.get(tfm)
                if suggested:
                    message_lines.append("    Suggested: dotnet.toolchain(dotnet_version = \"{}\")".format(suggested))

            message = "\n".join(message_lines)

            if fail_on_missing:
                fail(message)
            else:
                # buildifier: disable=print
                print("WARNING: " + message)

        # Write a summary file
        summary_lines = ["# Toolchain Coverage Summary", ""]
        summary_lines.append("## Registered Toolchains")
        for name, version in registered_toolchains.items():
            summary_lines.append("- {}: {}".format(name, version))
        summary_lines.append("")
        summary_lines.append("## Discovered Target Frameworks")
        for tfm, projects in all_tfms.items():
            status = "COVERED" if tfm in coverage.covered else "NOT COVERED"
            summary_lines.append("- {} ({}) - {} project(s)".format(tfm, status, len(projects)))
        summary_lines.append("")

        if coverage.uncovered:
            summary_lines.append("## Missing Toolchains")
            for tfm in coverage.uncovered:
                suggested = coverage.suggestions.get(tfm, "unknown")
                summary_lines.append("- {}: dotnet.toolchain(dotnet_version = \"{}\")".format(tfm, suggested))

        repository_ctx.file("TOOLCHAIN_COVERAGE.md", "\n".join(summary_lines))

    # Second pass: generate .bzl files
    for proj in parsed_projects:
        project_path = proj.path
        parsed = proj.parsed
        is_fsharp = proj.is_fsharp

        # Collect NuGet packages
        nuget_collector.add_packages_from_project(parsed.package_references, project_path)

        # Generate .bzl content
        project_dir = "/".join(project_path.split("/")[:-1]) if "/" in project_path else ""
        bzl_content = generate_project_bzl(
            parsed,
            project_path,
            project_dir,
            is_fsharp,
            nuget_repo_name,
            str(workspace_dir),
        )

        # Determine output path
        # Project at my/path/foo.csproj -> my/path/foo.csproj.bzl
        bzl_path = project_path + ".bzl"

        # Create directory structure
        output_dir = "/".join(bzl_path.split("/")[:-1]) if "/" in bzl_path else ""
        if output_dir:
            repository_ctx.file(output_dir + "/.gitkeep", "")

        # Track this file in its directory
        if output_dir not in generated_dirs:
            generated_dirs[output_dir] = []
        generated_dirs[output_dir].append(bzl_path.split("/")[-1])

        # Write the .bzl file
        repository_ctx.file(bzl_path, bzl_content)

    # Generate nuget packages.bzl
    resolved_packages = nuget_collector.resolve_packages()
    if resolved_packages:
        nuget_bzl = generate_nuget_packages_bzl(resolved_packages, nuget_repo_name)
        repository_ctx.file("nuget/packages.bzl", nuget_bzl)

        # Also generate an extension file for the NuGet packages
        nuget_extension_bzl = _generate_nuget_extension_bzl(nuget_repo_name)
        repository_ctx.file("nuget/packages_extension.bzl", nuget_extension_bzl)

        # Generate a paket.dependencies file to help users set up Paket
        paket_deps = generate_paket_dependencies(resolved_packages)
        repository_ctx.file("nuget/paket.dependencies.generated", paket_deps)

        if "nuget" not in generated_dirs:
            generated_dirs["nuget"] = []
        generated_dirs["nuget"].extend(["packages.bzl", "packages_extension.bzl"])

    # Generate root files
    repository_ctx.file("defs.bzl", generate_defs_bzl())
    repository_ctx.file("BUILD.bazel", generate_root_build_bazel())

    # Generate BUILD.bazel for each directory
    for dir_path, bzl_files in generated_dirs.items():
        if dir_path:
            build_content = generate_subdir_build_bazel(bzl_files)
            repository_ctx.file(dir_path + "/BUILD.bazel", build_content)

    # Report any version conflicts
    conflicts = nuget_collector.get_version_conflicts()
    if conflicts:
        conflict_lines = ["# NuGet version conflicts detected:"]
        for conflict in conflicts:
            conflict_lines.append("#   {}: versions {} requested from:".format(
                conflict.id,
                ", ".join(conflict.versions),
            ))
            for version, sources in conflict.sources.items():
                for source in sources:
                    conflict_lines.append("#     - {} (version {})".format(source, version))
        conflict_lines.append("")
        repository_ctx.file("CONFLICTS.md", "\n".join(conflict_lines))

def _generate_nuget_extension_bzl(_nuget_repo_name):  # buildifier: disable=unused-variable
    """Generate module extension for NuGet packages.

    Args:
        _nuget_repo_name: Name of the NuGet repository (unused, kept for API compatibility).

    Returns:
        String content of the extension .bzl file.
    """
    return '''"Generated module extension for NuGet packages"

load(":packages.bzl", _dotnet_nuget_packages = "dotnet_nuget_packages")

def _dotnet_nuget_impl(module_ctx):
    """Implementation of the dotnet_projects NuGet extension."""
    _dotnet_nuget_packages()
    return module_ctx.extension_metadata(reproducible = True)

dotnet_nuget_extension = module_extension(
    implementation = _dotnet_nuget_impl,
)
'''

dotnet_projects_repo = repository_rule(
    implementation = _dotnet_projects_repo_impl,
    # buildifier: disable=unsorted-dict-items
    attrs = {
        "root_module_name": attr.string(
            default = "",
            doc = "Name of the root module to scan (deprecated, not used).",
        ),
        "exclude_patterns": attr.string_list(
            default = ["**/bin/**", "**/obj/**", "**/.git/**", "**/.jj/**"],
            doc = "Glob patterns for paths to exclude from scanning.",
        ),
        "nuget_repo_name": attr.string(
            default = "dotnet_projects.nuget",
            doc = "Name of the NuGet repository to generate.",
        ),
        "registered_toolchains": attr.string(
            default = "",
            doc = "JSON-encoded dict of registered toolchain names to SDK versions.",
        ),
        "auto_register_toolchains": attr.bool(
            default = False,
            doc = "If true, auto-register toolchains for discovered TFMs (not yet implemented).",
        ),
        "fail_on_missing_toolchain": attr.bool(
            default = True,
            doc = "If true, fail when a TFM is not covered by any registered toolchain.",
        ),
    },
    doc = """Scans a workspace for .csproj and .fsproj files and generates .bzl files.

This repository rule:
1. Finds all .csproj and .fsproj files in the workspace
2. Parses each project file to extract properties, sources, and dependencies
3. Generates a .bzl file for each project with an auto_dotnet_targets() macro
4. Collects all NuGet package references and generates a nuget_repo() call
5. Validates that registered toolchains cover all discovered target frameworks

Usage in MODULE.bazel:
    dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
    dotnet.toolchain(dotnet_version = "10.0.100")
    dotnet.scan_projects()
    use_repo(dotnet, "dotnet_toolchains", "dotnet_projects")

Usage in BUILD files:
    load("@dotnet_projects//path/to:project.csproj.bzl", "auto_dotnet_targets")
    auto_dotnet_targets(name = "project")

File Change Detection:
    Bazel will automatically re-run this repository rule when:
    - Any existing .csproj or .fsproj file is modified
    - New project files are added to directories that already contain project files

    Bazel will NOT automatically detect:
    - New project files added to entirely new directories
    - New top-level project directories

    To pick up new project directories, run:
        bazel sync --only=@dotnet_projects

Requirements:
    - Bazel 7.1 or later (for repository_ctx.workspace_root support)
""",
)
