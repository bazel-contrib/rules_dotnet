"""The monolithic unpinned hub: downloads every package into the hub itself.

Without a lock file the extension cannot declare spokes (the resolved
versions are only known after `unpinned_<name>` has run), so this hub reads
the freshly resolved lock file, downloads and extracts every package under
`_archives/<id>/<version>/` in its own repository, and generates the same hub
targets the pinned hub does. Sharing and laziness come with pinning.
"""

load(
    "//dotnet/private/rules/nuget:nuget_archive.bzl",
    "fetch_package_into",
    "write_repository_for_testing",
)
load("//dotnet/private/rules/nuget:nuget_repo.bzl", "write_hub_files")
load("//dotnet/private/nuget_resolve:lock.bzl", "parse_lock")

def _in_repo_archive(id, version):
    # Packages are extracted under `_archives/`, not `<id>/<version>/`: the hub
    # generation writes its own package BUILD at `<id>/<version>/BUILD.bazel`
    # and would clobber the archive's BUILD there.
    prefix = "//_archives/{}/{}".format(id.lower(), version.lower())
    return struct(archive = prefix, package_info = prefix + ":package_info.bzl")

def _unpinned_hub_impl(ctx):
    lock = parse_lock(
        ctx.read(ctx.attr.lock),
        "@unpinned_{}//:nuget_resolve.json".format(ctx.attr.resolve_name),
    )

    group = lock.frameworks.get(ctx.attr.framework)
    if group == None:
        fail("@unpinned_{}//:nuget_resolve.json has no framework '{}'. It has: {}.".format(
            ctx.attr.resolve_name,
            ctx.attr.framework,
            ", ".join(lock.frameworks.keys()),
        ))

    packages = []
    for package in group:
        prefix = "_archives/{}/{}/".format(package.id.lower(), package.version.lower())
        extracted = fetch_package_into(ctx, package.id, package.version, package.urls, package.sha512, prefix)
        write_repository_for_testing(ctx, package.id, extracted.nupkg, extracted.files, prefix)
        packages.append({
            "id": package.id,
            "sha512": package.sha512,
            "version": package.version,
        })

    write_hub_files(
        ctx,
        packages,
        _in_repo_archive,
        extra_root_build = "\nalias(name = \"pin\", actual = \"@unpinned_{}//:pin\")\n".format(ctx.attr.resolve_name),
    )

unpinned_hub = repository_rule(
    _unpinned_hub_impl,
    doc = "Generates the hub for one framework of an unpinned resolve tag, downloading every package itself.",
    attrs = {
        "lock": attr.label(
            doc = "The freshly resolved lock file: `@unpinned_<name>//:nuget_resolve.json`.",
            mandatory = True,
        ),
        "framework": attr.string(
            doc = "The target framework this hub serves.",
            mandatory = True,
        ),
        "resolve_name": attr.string(
            doc = "The `name` of the resolve tag, used for the `:pin` alias and error messages.",
            mandatory = True,
        ),
        "netrc": attr.label(
            doc = "A netrc file with the credentials for the feeds.",
        ),
    },
)
