"""Repository rule for a group of NuGet packages.

A group becomes one "hub" repository holding a `BUILD.bazel` per package, plus
one "spoke" `nuget_archive` per unique package version holding the extracted
`.nupkg`. The hub's BUILD files load the metadata the spoke extracted, so a
package that nothing depends on is never downloaded.
"""

load("//dotnet/private/rules/nuget:nuget_archive.bzl", "nuget_archive")

_GLOBAL_NUGET_PREFIX = "nuget"

_PACKAGES_TEMPLATE = """\
"GENERATED"

# The packages in this repository: lower cased package id to the package the
# label `//<name>` resolves to.
PACKAGES = {packages}
"""

_PACKAGE_TEMPLATE = """\
"GENERATED"

load("@rules_dotnet//dotnet/private/rules/nuget:package.bzl", "nuget_package")
load(
    "{package_info}",
    "DEPENDENCY_GROUPS",
    "FRAMEWORK_LIST",
    "TARGETING_PACK_OVERRIDES",
    "TOOLS",
)
load("//:packages.bzl", "PACKAGES")

package(default_visibility = ["//visibility:public"])

nuget_package(
    version = "{version}",
    library_name = "{library_name}",
    archive = "{archive}",
    packages = PACKAGES,
    sha512 = "{sha512}",
    dependency_groups = DEPENDENCY_GROUPS,
    framework_list = FRAMEWORK_LIST,
    targeting_pack_overrides = TARGETING_PACK_OVERRIDES,
    tools = TOOLS,
)
"""

_ALIAS_TEMPLATE = """\
"GENERATED"

package(default_visibility = ["//visibility:public"])

alias(name = "{name}", actual = "{package}")

alias(name = "content_files", actual = "{archive}:content_files")

alias(name = "files", actual = "{archive}:files")
"""

_TOOLS_TEMPLATE = """\
"GENERATED"

load("@rules_dotnet//dotnet/private/rules/nuget:package.bzl", "nuget_package_tools")
load("{package_info}", "TOOLS")

package(default_visibility = ["//visibility:public"])

nuget_package_tools(
    package = "{package}",
    tools = TOOLS,
)
"""

def nuget_package_label(id, version):
    """Returns the label a package version is addressed by inside a hub.

    Args:
      id: The package id.
      version: The normalized package version.

    Returns:
      A repository relative label.
    """
    return "//{}/{}".format(id.lower(), version)

def nuget_archive_name(id, version):
    """Returns the repository name of the archive holding a package version.

    Archives are shared: the same package version referenced from two
    dependency groups is downloaded and extracted once.

    Args:
      id: The package id.
      version: The normalized package version.

    Returns:
      The repository name.
    """
    return "{}.{}.v{}".format(_GLOBAL_NUGET_PREFIX, id.lower(), version.lower())

def _spoke_archive(id, version):
    """The archive of a package version as its own `nuget_archive` repository."""
    archive = "@{}//".format(nuget_archive_name(id, version))
    return struct(archive = archive, package_info = archive + ":package_info.bzl")

def write_hub_files(ctx, packages, archive_and_info, extra_build_files = {}, extra_root_build = ""):
    """Writes the hub repository files for one dependency group.

    Used by every hub-shaped repository rule: the classic `_nuget_repo` and
    the pinned hub (archives as cross-repository `@<spoke>//` labels) and the
    unpinned monolithic hub (archives extracted into the hub repository
    itself, addressed as `//<id>/<version>`).

    Args:
      ctx: The repository context.
      packages: Dicts with `id`, `version` and optionally `name` and `sha512`
        keys. `name` is the label the package is addressed by and defaults to
        its id.
      archive_and_info: A function `(id, version) -> struct(archive,
        package_info)`, where `archive` is the label prefix of the package's
        archive (`"@<spoke>//"` or `"//<id>/<version>"`) and `package_info`
        the label the generated package BUILD loads `package_info.bzl` from.
      extra_build_files: Additional BUILD files to write into the repository,
        keyed by path.
      extra_root_build: Extra content appended to the root BUILD.bazel (the
        `:pin` alias).
    """
    for (path, content) in extra_build_files.items():
        ctx.file(path, content)

    ctx.file("BUILD.bazel", """\
"GENERATED"

package(default_visibility = ["//visibility:public"])
""" + extra_root_build)

    # A dependency group resolves one version per id, so `name` is just the id.
    # The SDK's pack repositories hold several versions of an id and tell them
    # apart with `<id>.v<version>`; there a dependency edge naming that id is
    # ambiguous, so it resolves to nothing rather than to an arbitrary version.
    names = {}
    for package in packages:
        id = package["id"].lower()
        names[id] = None if id in names else package.get("name", package["id"]).lower()

    ctx.file("packages.bzl", _PACKAGES_TEMPLATE.format(
        packages = json.encode({id: name for (id, name) in names.items() if name}),
    ))

    for package in packages:
        id = package["id"].lower()
        name = package.get("name", package["id"]).lower()
        version = package["version"]
        archive = archive_and_info(package["id"], version)

        ctx.file("{}/{}/BUILD.bazel".format(id, version), _PACKAGE_TEMPLATE.format(
            archive = archive.archive,
            package_info = archive.package_info,
            library_name = package["id"],
            sha512 = package.get("sha512", ""),
            version = version,
        ))

        ctx.file("{}/BUILD.bazel".format(name), _ALIAS_TEMPLATE.format(
            archive = archive.archive,
            name = name,
            package = nuget_package_label(id, version),
        ))

        ctx.file("{}/tools/BUILD.bazel".format(name), _TOOLS_TEMPLATE.format(
            package_info = archive.package_info,
            package = nuget_package_label(id, version),
        ))

def _nuget_repo_impl(ctx):
    packages = [json.decode(package) for package in ctx.attr.packages]

    write_hub_files(
        ctx,
        packages,
        _spoke_archive,
        extra_build_files = ctx.attr.extra_build_files,
    )

_nuget_repo = repository_rule(
    _nuget_repo_impl,
    doc = "Generates the BUILD files for a group of resolved NuGet packages.",
    attrs = {
        "packages": attr.string_list(
            doc = "The resolved packages, each a JSON object with `name`, `id`, `version` and `sha512` keys.",
            mandatory = True,
            allow_empty = False,
        ),
        "extra_build_files": attr.string_dict(
            doc = "Additional BUILD files to write, keyed by their path in the repository.",
        ),
    },
)

def nuget_archives(packages, declared):
    """Declares a `nuget_archive` for each package that does not have one yet.

    Args:
      packages: Dicts with `id`, `version` and `sources` keys, and optionally
        `sha512`, `netrc` and `urls`. When `urls` is given the archive
        downloads those directly and never reads a feed index.
      declared: The names of the archives declared so far, which this call
        adds to. Pass the same dict across groups so that a package version
        shared between them is only declared once.
    """
    for package in packages:
        name = nuget_archive_name(package["id"], package["version"])
        if name in declared:
            continue

        declared[name] = True
        nuget_archive(
            name = name,
            id = package["id"].lower(),
            netrc = package.get("netrc", None),
            sha512 = package.get("sha512", ""),
            sources = package["sources"],
            urls = package.get("urls", []),
            version = package["version"].lower(),
        )

def nuget_hub_repo(name, packages, extra_build_files = {}):
    """Declares the hub repository for one dependency group.

    The `nuget_archive` repositories the hub points at have to be declared
    separately with `nuget_archives`, so that groups can share them.

    Args:
      name: The repository name, which is how users address the group.
      packages: Dicts with `id`, `version` and optionally `name` and `sha512`
        keys. `name` is the label the package is addressed by and defaults to
        its id.
      extra_build_files: Additional BUILD files to write into the repository,
        keyed by path.
    """
    _nuget_repo(
        name = name,
        extra_build_files = extra_build_files,
        packages = [
            json.encode({
                "id": package["id"],
                "name": package.get("name", package["id"]),
                "sha512": package.get("sha512", ""),
                "version": package["version"],
            })
            for package in packages
        ],
    )

def nuget_repo(name, packages):
    """Declares a repository for a set of resolved NuGet packages.

    Prefer pointing the `paket` module extension at a `paket.lock` file. This
    is the lower level entry point, for resolvers that produce the package
    list some other way.

    Args:
      name: The repository name, which is how users address the packages.
      packages: Dicts describing each resolved package, with `id`, `version`
        and `sources` keys, and optionally `sha512` and `netrc`.
    """
    nuget_archives(packages, {})
    nuget_hub_repo(name, packages)
