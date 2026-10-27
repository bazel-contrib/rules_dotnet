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
      A dict suitable for `select()`, mapping a TFM config setting to labels.
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

    deps = {}
    resolved_any = False

    for tfm in FRAMEWORK_COMPATIBILITY:
        nearest = get_nearest_compatible_target_framework(tfm, frameworks)
        labels = labels_by_group[nearest] if nearest != None else labels_by_group.get(ANY_FRAMEWORK, [])
        if labels:
            resolved_any = True
        deps["@rules_dotnet//dotnet:tfm_{}".format(tfm)] = labels

    if not resolved_any:
        return {"//conditions:default": []}

    # A framework that resolves to no dependencies still needs its own branch:
    # without it a more general framework's branch would match and wrongly
    # apply that framework's dependencies.
    deps["//conditions:default"] = []

    return deps

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
        targeting_pack_overrides = {},
        tools = {},
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
      framework_list: Assembly versions shipped by a targeting pack.
      targeting_pack_overrides: Package versions superseded by a targeting pack.
      tools: Dotnet tool entrypoints, keyed by tool name and target framework.
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
        library_name = library_name,
        libs = ["{}:libs".format(archive)],
        native = ["{}:native".format(archive)],
        nupkg = "{}:{}.{}.nupkg".format(archive, library_name.lower(), version),
        refs = ["{}:refs".format(archive)],
        resource_assemblies = ["{}:resource_assemblies".format(archive)],
        static_web_assets = ["{}:static_web_assets".format(archive)],
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
