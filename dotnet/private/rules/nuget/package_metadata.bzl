"""Readers for the metadata files that ship inside a `.nupkg`.

These run against the archive `nuget_archive` has already downloaded and
extracted.
"""

load("//dotnet/private:common.bzl", "nuget_framework_to_tfm")
load("//dotnet/private:xml.bzl", "xml")

# The key used for dependencies that are not tied to a target framework.
ANY_FRAMEWORK = ""

# https://github.com/dotnet/sdk/blob/main/documentation/general/tool-nuget-package-format.md
_DOTNET_TOOL_PACKAGE_TYPE = "DotnetTool"

def _add_dependencies(dependency_groups, framework, element):
    """Adds the <dependency> children of `element` to `framework`'s group."""
    ids = dependency_groups.setdefault(framework, [])

    for dependency in xml.children(element, "dependency"):
        id = xml.attr(dependency, "id")
        if id and id not in ids:
            ids.append(id)

def parse_nuspec(content):
    """Reads the parts of a `.nuspec` manifest that rules_dotnet cares about.

    Args:
      content: The contents of the `.nuspec` file.

    Returns:
      A struct with:
        is_dotnet_tool: Whether the package declares the DotnetTool package type.
        dependency_groups: Package ids keyed by target framework. Frameworks
          rules_dotnet does not support are dropped, and dependencies that are
          not tied to a framework are keyed by ANY_FRAMEWORK.
        framework_reference_groups: The shared frameworks the package needs,
          as framework reference names keyed by target framework. Frameworks
          rules_dotnet does not support are dropped.
    """
    package = xml.parse(content)
    if package == None:
        fail("The .nuspec manifest is empty")

    metadata = xml.child(package, "metadata")
    if metadata == None:
        fail("The .nuspec manifest has no <metadata> element")

    package_types = [
        xml.attr(package_type, "name")
        for package_type in xml.children(xml.child(metadata, "packageTypes"), "packageType")
    ]

    dependency_groups = {}
    dependencies = xml.child(metadata, "dependencies")

    if dependencies != None:
        # Packages that predate dependency groups list their dependencies
        # directly, which means they apply to every framework.
        if xml.children(dependencies, "dependency"):
            _add_dependencies(dependency_groups, ANY_FRAMEWORK, dependencies)

        for group in xml.children(dependencies, "group"):
            framework = xml.attr(group, "targetFramework")

            if not framework:
                _add_dependencies(dependency_groups, ANY_FRAMEWORK, group)
                continue

            tfm = nuget_framework_to_tfm(framework)

            # An empty group is meaningful: it says the package has no
            # dependencies for that framework, so it still gets an entry.
            if tfm != None:
                _add_dependencies(dependency_groups, tfm, group)

    # Framework references flow to every direct and transitive consumer.
    framework_reference_groups = {}
    for group in xml.children(xml.child(metadata, "frameworkReferences"), "group"):
        tfm = nuget_framework_to_tfm(xml.attr(group, "targetFramework") or "")
        if tfm == None:
            continue

        names = framework_reference_groups.setdefault(tfm, [])
        for reference in xml.children(group, "frameworkReference"):
            name = xml.attr(reference, "name")
            if name and name not in names:
                names.append(name)

    return struct(
        dependency_groups = dependency_groups,
        framework_reference_groups = framework_reference_groups,
        is_dotnet_tool = _DOTNET_TOOL_PACKAGE_TYPE in package_types,
    )

def parse_framework_list(content):
    """Reads `data/FrameworkList.xml` from a targeting pack.

    A runtime pack's `data/RuntimeList.xml` has the same shape.

    Args:
      content: The contents of the `FrameworkList.xml` file.

    Returns:
      A dict of lower cased assembly name to assembly version.
    """
    return parse_framework_list_metadata(content).assemblies

def parse_framework_list_metadata(content):
    """Reads everything rules_dotnet uses from a `FrameworkList.xml` or `RuntimeList.xml`.

    Args:
      content: The contents of the file.

    Returns:
      A struct with, each a dict keyed by lower cased assembly name unless
      said otherwise:
        assemblies: The assembly version of each managed assembly.
        file_versions: The file version of each managed assembly, for
          breaking ties in assembly version.
        profiles: The `;` separated profiles of each managed assembly that is
          in any. One in none is only part of the whole framework.
        analyzer_profiles: The `;` separated profiles of each analyzer, keyed
          by its path inside the package, empty for one in no profile.
    """
    file_list = xml.parse(content)
    assemblies = {}
    file_versions = {}
    profiles = {}
    analyzer_profiles = {}

    for file in xml.children(file_list, "File"):
        kind = xml.attr(file, "Type")
        profile = xml.attr(file, "Profile") or ""

        if kind == "Analyzer":
            path = xml.attr(file, "Path")
            if path:
                analyzer_profiles[path] = profile
            continue

        if kind != "Managed":
            continue

        name = xml.attr(file, "AssemblyName")
        version = xml.attr(file, "AssemblyVersion")
        if not name or not version:
            continue

        name = name.lower()
        assemblies[name] = version.lower()
        file_version = xml.attr(file, "FileVersion")
        if file_version:
            file_versions[name] = file_version
        if profile:
            profiles[name] = profile

    return struct(
        assemblies = assemblies,
        file_versions = file_versions,
        profiles = profiles,
        analyzer_profiles = analyzer_profiles,
    )

def parse_package_overrides(content):
    """Reads `data/PackageOverrides.txt` from a targeting pack.

    Args:
      content: The contents of the `PackageOverrides.txt` file.

    Returns:
      A dict of lower cased package id to the minimum version the targeting
      pack supersedes.
    """
    overrides = {}

    for line in content.splitlines():
        parts = line.strip().split("|")
        if len(parts) != 2 or not parts[0] or not parts[1]:
            continue

        overrides[parts[0].lower()] = parts[1].lower()

    return overrides

def parse_dotnet_tool_settings(content, path):
    """Reads a `DotnetToolSettings.xml` file from a tool package.

    Args:
      content: The contents of the `DotnetToolSettings.xml` file.
      path: The path of the file, used in error messages.

    Returns:
      A list of dicts with `name`, `entrypoint` and `runner` keys.
    """
    settings = xml.parse(content)
    if settings == None:
        fail("{} is empty".format(path))

    version = xml.attr(settings, "Version")
    if version != "1":
        fail("{} has unsupported version '{}' (expected '1')".format(path, version))

    commands = xml.child(settings, "Commands")
    if commands == None:
        fail("{} has no <Commands> element".format(path))

    return [
        {
            "entrypoint": xml.attr(command, "EntryPoint"),
            "name": xml.attr(command, "Name"),
            "runner": xml.attr(command, "Runner"),
        }
        for command in xml.children(commands, "Command")
    ]
