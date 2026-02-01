"Utilities for collecting and resolving NuGet package references across projects"

def create_nuget_collector():
    """Create a new NuGet package collector.

    Returns:
        A struct with methods to add packages and get the resolved list.
    """
    packages = {}

    def add_package(package_id, version, source_project = None):
        """Add a package reference to the collector.

        Args:
            package_id: The NuGet package ID.
            version: The version string.
            source_project: Optional path to the project that requires this package.
        """
        if not package_id:
            return

        normalized_id = package_id.lower()

        if normalized_id not in packages:
            packages[normalized_id] = struct(
                id = package_id,  # Keep original casing
                versions = {},
                sources = [],
            )

        pkg = packages[normalized_id]

        # Track version usage
        if version:
            if version not in pkg.versions:
                pkg.versions[version] = []
            if source_project:
                pkg.versions[version].append(source_project)

        if source_project and source_project not in pkg.sources:
            pkg.sources.append(source_project)

    def add_packages_from_project(package_refs, source_project):
        """Add multiple package references from a project.

        Args:
            package_refs: List of structs with id and version.
            source_project: Path to the project file.
        """
        for pkg in package_refs:
            add_package(pkg.id, pkg.version, source_project)

    def resolve_packages():
        """Resolve all collected packages to a single version each.

        Uses highest version strategy (similar to MSBuild behavior).

        Returns:
            List of structs with id and version, sorted by id.
        """
        resolved = []

        for normalized_id in sorted(packages.keys()):
            pkg = packages[normalized_id]
            versions = pkg.versions.keys()

            if not versions:
                # No version specified, will need to be resolved at runtime
                resolved.append(struct(
                    id = pkg.id,
                    version = "",
                    sources = pkg.sources,
                ))
                continue

            # Pick the highest version
            best_version = _select_highest_version(list(versions))
            resolved.append(struct(
                id = pkg.id,
                version = best_version,
                sources = pkg.sources,
            ))

        return resolved

    def get_version_conflicts():
        """Get packages with multiple versions requested.

        Returns:
            List of structs describing conflicts.
        """
        conflicts = []

        for normalized_id in sorted(packages.keys()):
            pkg = packages[normalized_id]
            versions = list(pkg.versions.keys())

            if len(versions) > 1:
                conflicts.append(struct(
                    id = pkg.id,
                    versions = versions,
                    sources = pkg.versions,
                ))

        return conflicts

    return struct(
        add_package = add_package,
        add_packages_from_project = add_packages_from_project,
        resolve_packages = resolve_packages,
        get_version_conflicts = get_version_conflicts,
    )

def _select_highest_version(versions):
    """Select the highest version from a list of version strings.

    Uses semantic versioning comparison when possible.

    Args:
        versions: List of version strings.

    Returns:
        The highest version string.
    """
    if not versions:
        return ""

    if len(versions) == 1:
        return versions[0]

    # Parse and compare versions
    parsed = []
    for v in versions:
        parsed.append((v, _parse_version(v)))

    # Sort by parsed version (descending)
    # Since Starlark doesn't have a key function, we do manual comparison
    sorted_versions = _sort_versions(parsed)

    return sorted_versions[0][0]

def _parse_version(version_str):
    """Parse a version string into comparable components.

    Args:
        version_str: A version string like "1.2.3" or "1.2.3-beta.1".

    Returns:
        A tuple of (major, minor, patch, prerelease_parts, original).
    """
    if not version_str:
        return (0, 0, 0, [], "")

    # Split off prerelease suffix
    main_part = version_str
    prerelease = ""

    if "-" in version_str:
        parts = version_str.split("-", 1)
        main_part = parts[0]
        prerelease = parts[1] if len(parts) > 1 else ""

    # Parse main version numbers
    version_parts = main_part.split(".")
    major = _safe_int(version_parts[0]) if len(version_parts) > 0 else 0
    minor = _safe_int(version_parts[1]) if len(version_parts) > 1 else 0
    patch = _safe_int(version_parts[2]) if len(version_parts) > 2 else 0

    # Parse prerelease parts for comparison
    prerelease_parts = prerelease.split(".") if prerelease else []

    return (major, minor, patch, prerelease_parts, version_str)

def _safe_int(s):
    """Safely convert string to int, returning 0 on failure."""
    if not s:
        return 0

    # Remove any non-numeric suffix (e.g., "1a" -> 1)
    num_str = ""
    for c in s.elems():
        if c.isdigit():
            num_str += c
        else:
            break

    return int(num_str) if num_str else 0

def _sort_versions(parsed_versions):
    """Sort parsed versions in descending order.

    Args:
        parsed_versions: List of (original_str, parsed_tuple) pairs.

    Returns:
        Sorted list with highest version first.
    """

    # Simple bubble sort since Starlark doesn't have sorted() with key
    result = list(parsed_versions)

    for i in range(len(result)):
        for j in range(i + 1, len(result)):
            if _compare_versions(result[i][1], result[j][1]) < 0:
                # Swap if result[i] < result[j]
                result[i], result[j] = result[j], result[i]

    return result

def _compare_versions(v1, v2):
    """Compare two parsed versions.

    Args:
        v1: Parsed version tuple.
        v2: Parsed version tuple.

    Returns:
        Negative if v1 < v2, positive if v1 > v2, 0 if equal.
    """

    # Compare major.minor.patch
    if v1[0] != v2[0]:
        return v1[0] - v2[0]
    if v1[1] != v2[1]:
        return v1[1] - v2[1]
    if v1[2] != v2[2]:
        return v1[2] - v2[2]

    # Prerelease versions are lower than release versions
    pre1 = v1[3]
    pre2 = v2[3]

    if not pre1 and pre2:
        return 1  # v1 is release, v2 is prerelease
    if pre1 and not pre2:
        return -1  # v1 is prerelease, v2 is release

    # Both are prerelease or both are release
    # Compare prerelease parts
    for i in range(min(len(pre1), len(pre2))):
        p1 = pre1[i]
        p2 = pre2[i]

        # Try numeric comparison first
        n1 = _safe_int(p1)
        n2 = _safe_int(p2)

        if p1.isdigit() and p2.isdigit():
            if n1 != n2:
                return n1 - n2
        else:
            # String comparison
            if p1 < p2:
                return -1
            if p1 > p2:
                return 1

    # More prerelease parts = lower version? Actually more specific prerelease
    # This is simplified - full semver is more complex
    return len(pre1) - len(pre2)

def generate_nuget_packages_bzl(packages, repo_name = "dotnet_projects.nuget"):
    """Generate the content of a packages.bzl file.

    Note: The generated file creates placeholder entries. For full NuGet support,
    users should use paket2bazel to generate complete package definitions with
    SHA512 hashes, sources, and dependency information.

    Args:
        packages: List of resolved package structs with id and version.
        repo_name: Name of the NuGet repository to create.

    Returns:
        String content of the .bzl file.
    """
    lines = [
        '"Generated NuGet packages for csproj integration"',
        "",
        "# NOTE: This file contains package references extracted from .csproj files.",
        "# For full NuGet support with SHA512 verification and dependency resolution,",
        "# consider using Paket and paket2bazel instead.",
        "#",
        "# To use Paket:",
        "# 1. Create a paket.dependencies file with the packages below",
        "# 2. Run: dotnet tool run paket install",
        "# 3. Run: bazel run @rules_dotnet//tools/paket2bazel -- \\\\",
        "#          --dependencies-file $(pwd)/paket.dependencies \\\\",
        "#          --output-folder $(pwd)",
        "",
        'load("@rules_dotnet//dotnet:defs.bzl", "nuget_repo")',
        "",
        "# Default NuGet source URL template",
        '_NUGET_SOURCE = "https://api.nuget.org/v3-flatcontainer/{{id}}/{{version}}/{{id}}.{{version}}.nupkg"',
        "",
        "def dotnet_nuget_packages():",
        '    """Create NuGet repository with packages from all .csproj files.',
        "",
        "    WARNING: This generated file uses placeholder SHA512 values.",
        "    The first build will fail with hash mismatch errors.",
        "    Update the sha512 values with the correct hashes from the error messages,",
        "    or use paket2bazel for proper package resolution.",
        '    """',
        "    nuget_repo(",
        '        name = "{}",'.format(repo_name),
        "        packages = [",
    ]

    for pkg in packages:
        if pkg.version:
            lines.append("            {{")
            lines.append('                "id": "{}",'.format(pkg.id))
            lines.append('                "version": "{}",'.format(pkg.version))
            lines.append('                "sha512": "",  # TODO: Add correct SHA512 hash')
            lines.append('                "sources": [_NUGET_SOURCE.format(id = "{}", version = "{}")],'.format(
                pkg.id.lower(),
                pkg.version,
            ))
            lines.append('                "dependencies": {{}},')
            lines.append('                "targeting_pack_overrides": [],')
            lines.append('                "framework_list": [],')
            lines.append("            }},")
        else:
            lines.append("            # WARNING: Version not specified for {}".format(pkg.id))

    lines.extend([
        "        ],",
        "    )",
        "",
    ])

    return "\n".join(lines)

def generate_paket_dependencies(packages):
    """Generate a paket.dependencies file from collected packages.

    This can be used to bootstrap Paket integration.

    Args:
        packages: List of resolved package structs with id and version.

    Returns:
        String content of a paket.dependencies file.
    """
    lines = [
        "# Generated paket.dependencies from .csproj files",
        "# Run 'dotnet tool run paket install' to resolve dependencies",
        "",
        "source https://api.nuget.org/v3/index.json",
        "storage: none",
        "framework: auto-detect",
        "",
    ]

    for pkg in packages:
        if pkg.version:
            lines.append("nuget {} == {}".format(pkg.id, pkg.version))
        else:
            lines.append("nuget {}".format(pkg.id))

    lines.append("")
    return "\n".join(lines)
