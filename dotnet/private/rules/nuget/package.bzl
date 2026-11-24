"""Turns the metadata of a single NuGet package into Bazel targets.

`nuget_repo` writes one `BUILD.bazel` per package version that loads the
metadata the package's `nuget_archive` extracted and hands it to the macro
below. Keeping the logic here rather than in generated text means the
generated files stay small and the behaviour is testable.
"""

load(
    "//dotnet/private:common.bzl",
    "FRAMEWORK_COMPATIBILITY",
    "get_nearest_compatible_target_framework",
)
load("//dotnet/private/rules/nuget:dotnet_tool.bzl", "dotnet_tool")
load("//dotnet/private/rules/nuget:imports.bzl", "import_library")
load("//dotnet/private/rules/nuget:package_metadata.bzl", "ANY_FRAMEWORK")
load("//dotnet/private/sdk:frameworks.bzl", "framework_platform")

# By canonical label, so that the hub repository resolves them whatever name it
# sees rules_dotnet under.
_TFM_SETTINGS = {tfm: str(Label("//dotnet:tfm_" + tfm)) for tfm in FRAMEWORK_COMPATIBILITY}

def _branches(values_by_tfm, groups):
    """The `tfm_*` branches a select needs to give every framework its value.

    A configuration matches the branch of every framework it is compatible
    with, and select takes the most specific. So a framework needs a branch
    unless its only predecessor resolves the same.

    `net8.0-windows` has two predecessors, `net8.0` and `net7.0-windows`, that
    select cannot rank. So either every Windows specific framework gets a
    branch, if the package has a Windows specific group, or none does.

    Args:
      values_by_tfm: What every framework resolves to.
      groups: The frameworks the package declares groups for.

    Returns:
      A dict of `tfm_*` condition to value.
    """
    windows_groups = any([framework_platform(group) for group in groups])

    branches = {}
    for (tfm, value) in values_by_tfm.items():
        if framework_platform(tfm):
            if windows_groups:
                branches[tfm] = value
            continue

        if len(FRAMEWORK_COMPATIBILITY[tfm]) != 1 or value != values_by_tfm[FRAMEWORK_COMPATIBILITY[tfm][0]]:
            branches[tfm] = value

    return {_TFM_SETTINGS[tfm]: value for (tfm, value) in branches.items()}

def deps_by_tfm(dependency_groups, packages):
    """Maps every supported TFM onto the labels of the deps it should use.

    A NuGet package declares its dependencies per framework and the consumer
    picks the closest one it is compatible with. Dependencies that the
    dependency group did not resolve are dropped: they are either provided by
    the framework itself or pulled in through a different group.

    Args:
      dependency_groups: Dependency package ids keyed by target framework.
      packages: Every package in the repository, as a dict of lower cased id
        to the label it is addressed by.

    Returns:
      A dict suitable for `select()`, mapping a TFM config setting to labels,
      with no branch for a framework that resolves as its only predecessor
      does.
    """
    frameworks = [
        framework
        for framework in dependency_groups
        if framework != ANY_FRAMEWORK
    ]

    # Resolving a dependency group to labels only depends on which group is
    # nearest, and most of the ~40 frameworks share one, so do it per group.
    labels_by_group = {
        framework: [
            "//{}".format(packages[id])
            for id in [id.lower() for id in ids]
            if id in packages
        ]
        for (framework, ids) in dependency_groups.items()
    }

    labels_by_tfm = {}
    for tfm in FRAMEWORK_COMPATIBILITY:
        nearest = get_nearest_compatible_target_framework(tfm, frameworks)
        labels_by_tfm[tfm] = labels_by_group[nearest] if nearest != None else labels_by_group.get(ANY_FRAMEWORK, [])

    if not any(labels_by_tfm.values()):
        return {"//conditions:default": []}

    deps = _branches(labels_by_tfm, frameworks)
    deps["//conditions:default"] = []

    return deps

def framework_references_by_tfm(framework_reference_groups):
    """Maps every supported TFM onto the shared frameworks a package needs for it.

    As for dependencies, a consumer takes the nearest compatible group.

    Args:
      framework_reference_groups: Framework reference names keyed by target
        framework, from the package's `.nuspec`.

    Returns:
      A dict suitable for `select()`, mapping a TFM config setting to names.
    """
    if not framework_reference_groups:
        return {"//conditions:default": []}

    by_tfm = {}
    for tfm in FRAMEWORK_COMPATIBILITY:
        nearest = get_nearest_compatible_target_framework(tfm, framework_reference_groups.keys())
        by_tfm[tfm] = framework_reference_groups[nearest] if nearest != None else []

    references = _branches(by_tfm, framework_reference_groups.keys())
    references["//conditions:default"] = []

    return references

# buildifier: disable=function-docstring-args
# buildifier: disable=unnamed-macro
def nuget_package(
        *,
        version,
        library_name,
        archive,
        packages,
        sha512 = "",
        dependency_groups = {},
        framework_list = {},
        framework_list_metadata = {},
        framework_reference_groups = {},
        targeting_pack_overrides = {},
        tools = {},
        static_web_assets_base_path = "",
        tags = []):
    """Declares the targets for one version of one NuGet package.

    Args:
      version: The normalized package version. Also the target name, so that
        the package is addressable as `//<id>/<version>`.
      library_name: The package id with its original casing.
      archive: The package the extracted `nuget_archive` targets live in,
        e.g. `@nuget.argu.v6.1.1//`.
      packages: Every package in the repository, as a dict of lower cased id
        to the label it is addressed by. Dependencies that are not in it were
        not resolved into this group and are dropped.
      sha512: The subresource integrity of the `.nupkg`, or "" if the feed did
        not publish one.
      dependency_groups: Dependency package ids keyed by target framework.
      framework_list: Assembly versions shipped by a targeting or runtime pack.
      framework_list_metadata: The rest of what a pack's FrameworkList.xml or
        RuntimeList.xml says: `file_versions`, `profiles` and
        `analyzer_profiles`.
      framework_reference_groups: The shared frameworks the package needs,
        keyed by target framework.
      targeting_pack_overrides: Package versions superseded by a targeting pack.
      tools: Dotnet tool entrypoints, keyed by tool name and target framework.
      static_web_assets_base_path: Where the package's manifest says its static
        web assets are served from, or empty for MSBuild's default.
      tags: Tags for the package target.
    """
    import_library(
        name = version,
        analyzers = ["{}:analyzers".format(archive)],
        analyzers_csharp = ["{}:analyzers_csharp".format(archive)],
        analyzers_fsharp = ["{}:analyzers_fsharp".format(archive)],
        analyzers_vb = ["{}:analyzers_vb".format(archive)],
        data = ["{}:data".format(archive)],
        framework_list = framework_list,
        framework_list_analyzer_profiles = framework_list_metadata.get("analyzer_profiles", {}),
        framework_list_file_versions = framework_list_metadata.get("file_versions", {}),
        framework_list_profiles = framework_list_metadata.get("profiles", {}),
        framework_references = select(framework_references_by_tfm(framework_reference_groups)),
        library_name = library_name,
        libs = ["{}:libs".format(archive)],
        native = ["{}:native".format(archive)],
        # `nuget_archive` names the download after the lower cased id and
        # version; a pre-release label can carry upper case letters.
        nupkg = "{}:{}.{}.nupkg".format(archive, library_name.lower(), version.lower()),
        portable_assets = "{}:portable_assets".format(archive),
        refs = ["{}:refs".format(archive)],
        resource_assemblies = ["{}:resource_assemblies".format(archive)],
        static_web_assets = ["{}:static_web_assets".format(archive)],
        static_web_assets_base_path = static_web_assets_base_path,
        typeproviders = ["{}:typeproviders".format(archive)],
        sha512 = sha512,
        targeting_pack_overrides = targeting_pack_overrides,
        version = version,
        deps = select(deps_by_tfm(dependency_groups, packages)),
        tags = tags,
    )

    for (tool_name, by_tfm) in tools.items():
        dotnet_tool(
            name = "tool_{}".format(tool_name),
            entrypoint = {tfm: tool["entrypoint"] for (tfm, tool) in by_tfm.items()},
            runner = {tfm: tool["runner"] for (tfm, tool) in by_tfm.items()},
            target_frameworks = by_tfm.keys(),
            deps = "{}:tools".format(archive),
        )

# buildifier: disable=unnamed-macro
def nuget_package_tools(*, package, tools):
    """Declares an alias per dotnet tool a package provides.

    The tool targets themselves live next to the package so that they can
    reach its files; these aliases give them the shorter, version independent
    labels that users depend on.

    Args:
      package: The label of the package, e.g. `//csharpier/1.0.3`.
      tools: Dotnet tool entrypoints, keyed by tool name and target framework.
    """
    for tool_name in tools:
        native.alias(
            name = tool_name,
            actual = "{}:tool_{}".format(package, tool_name),
        )
