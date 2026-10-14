"""Implementation of the `packages_lock` module extension.

A `packages.lock.json` written by `dotnet restore` pins an exact version for
every package a project resolved, per target framework. The file does not
record the feeds the packages came from, so they are passed with the `sources`
attribute.
"""

load("//dotnet/private/packages_lock:lock.bzl", "parse_lock")
load(
    "//dotnet/private/rules/nuget:nuget_repo.bzl",
    "nuget_archives",
    "nuget_hub_repo",
)
load(
    "@bazel_tools//tools/build_defs/repo:utils.bzl",
    "read_netrc",
    "read_user_netrc",
    "use_netrc",
)

_DEFAULT_REPO_PREFIX = "nuget."

_DEFAULT_SOURCES = ["https://api.nuget.org/v3/index.json"]

# Bump this when the shape or meaning of a computed package integrity changes.
_FACT_VERSION = "v1"

_parse = tag_class(
    doc = "Makes the packages of a `packages.lock.json` file available to Bazel.",
    attrs = {
        "lock": attr.label(
            doc = "The `packages.lock.json` file to read the resolved packages from.",
            mandatory = True,
        ),
        "sources": attr.string_list(
            doc = """The NuGet feeds to download the packages from.

The lock file does not record them. V3 (`index.json`) and V2 feeds are both
supported; every package is tried against each feed in order.""",
            default = _DEFAULT_SOURCES,
        ),
        "frameworks": attr.string_list(
            doc = """The target frameworks to make available.

Defaults to every framework in the lock file. Each becomes its own
repository, so a package in the `net10.0` framework of a lock parsed with the
default prefix is addressed as `@nuget.net10.0//<package>`.""",
        ),
        "repo_prefix": attr.string(
            doc = """Prepended to the lower cased framework name to name its repository.

Change it when two lock files in the same build have a framework in common.""",
            default = _DEFAULT_REPO_PREFIX,
        ),
        "netrc": attr.label(
            doc = "A netrc file with the credentials for the feeds. Defaults to the user's.",
        ),
    },
)

def packages_from_lock(content, sources):
    """Translates a `packages.lock.json` into the NuGet repository format.

    Args:
      content: The lock file contents.
      sources: The feeds to download the packages from; the file does not
        record them.

    Returns:
      A list of structs, one per target framework, each with `name` and
      `packages` fields. Each package is a dict with `id`, `version` and
      `sources` keys.
    """
    return [
        struct(
            name = group.name,
            packages = [
                {
                    "id": package.id,
                    "sources": sources,
                    "version": package.version,
                }
                for package in group.packages
            ],
        )
        for group in parse_lock(content)
    ]

def _auth(netrc_entries, urls):
    return use_netrc(netrc_entries, urls, {
        "type": "basic",
        "login": "<login>",
        "password": "<password>",
    })

def _integrity_fact_key(id, version):
    return "package_integrity/{}:{}/{}".format(_FACT_VERSION, id.lower(), version.lower())

def _package_urls(module_ctx, package, netrc_entries, base_addresses):
    urls = []

    for source in package["sources"]:
        if source.endswith("index.json"):
            base_address = base_addresses.get(source)
            if base_address == None:
                output = "packages_lock_feed_index_{}.json".format(len(base_addresses))
                result = module_ctx.download(
                    url = source,
                    output = output,
                    auth = _auth(netrc_entries, [source]),
                    allow_fail = True,
                )
                if not result.success:
                    fail("Could not read NuGet feed index {}: {}".format(source, result.error))

                index = json.decode(module_ctx.read(output))
                for resource in index.get("resources", []):
                    if resource.get("@type") == "PackageBaseAddress/3.0.0":
                        base_address = resource.get("@id", "")
                        break

                if not base_address:
                    fail("{} has no PackageBaseAddress/3.0.0 resource.".format(source))

                base_addresses[source] = base_address

            if not base_address.endswith("/"):
                base_address += "/"
            id = package["id"].lower()
            version = package["version"].lower()
            urls.append(
                "{base}{id}/{version}/{id}.{version}.nupkg".format(
                    base = base_address,
                    id = id,
                    version = version,
                ),
            )
        else:
            urls.append("{}/package/{}/{}".format(
                source.rstrip("/"),
                package["id"].lower(),
                package["version"].lower(),
            ))

    if not urls:
        fail("No NuGet feeds are configured for package {} {}.".format(
            package["id"],
            package["version"],
        ))

    return urls

def _add_download_integrities(module_ctx, requests):
    integrities = {}
    remembered = getattr(module_ctx, "facts", {})
    netrc_entries_by_label = {}
    base_addresses = {}

    for request in requests:
        for package in request.packages:
            fact_key = _integrity_fact_key(package["id"], package["version"])
            if fact_key not in integrities:
                if fact_key in remembered:
                    integrities[fact_key] = remembered[fact_key]
                else:
                    netrc = package.get("netrc")
                    if netrc not in netrc_entries_by_label:
                        netrc_entries_by_label[netrc] = (
                            read_netrc(module_ctx, netrc)
                            if netrc
                            else read_user_netrc(module_ctx)
                        )
                    netrc_entries = netrc_entries_by_label[netrc]
                    urls = _package_urls(module_ctx, package, netrc_entries, base_addresses)
                    result = module_ctx.download(
                        url = urls,
                        output = "packages_lock_package_{}.nupkg".format(len(integrities)),
                        auth = _auth(netrc_entries, urls),
                        allow_fail = True,
                    )
                    if not result.success:
                        fail("Could not download NuGet package {} {}: {}".format(
                            package["id"],
                            package["version"],
                            result.error,
                        ))
                    if not result.integrity:
                        fail("Bazel did not calculate an integrity hash for NuGet package {} {}.".format(
                            package["id"],
                            package["version"],
                        ))

                    integrities[fact_key] = result.integrity

            package["sha512"] = integrities[fact_key]

    return integrities

def _select_frameworks(tag, groups):
    """Returns the frameworks the tag asked for, defaulting to all of them."""
    if not tag.frameworks:
        return groups

    by_name = {group.name.lower(): group for group in groups}
    selected = []

    for name in tag.frameworks:
        group = by_name.get(name.lower())
        if group == None:
            fail("{} has no framework named '{}'. It has: {}.".format(
                tag.lock,
                name,
                ", ".join([group.name for group in groups]),
            ))
        selected.append(group)

    return selected

def _collect(module_ctx):
    """Reads every lock file the build refers to.

    Returns:
      A list of structs, one per framework that has been asked for.
    """
    requests = []

    # Repository name to the lock file that claimed it, so that a collision
    # between two modules is reported rather than silently resolved.
    claimed = {}

    for module in module_ctx.modules:
        for tag in module.tags.parse:
            groups = packages_from_lock(module_ctx.read(tag.lock), tag.sources)

            for group in _select_frameworks(tag, groups):
                repo = tag.repo_prefix + group.name.lower()

                if repo in claimed:
                    fail(
                        "The '{}' framework is already provided by {} as @{}.".format(
                            group.name,
                            claimed[repo],
                            repo,
                        ) + " Declare it once, or set a different `repo_prefix`.",
                    )
                claimed[repo] = str(tag.lock)

                requests.append(struct(
                    is_dev = module_ctx.is_dev_dependency(tag),
                    is_root = module.is_root,
                    packages = [
                        dict(package, netrc = tag.netrc)
                        for package in group.packages
                    ],
                    repo = repo,
                ))

    return requests

def _packages_lock_impl(module_ctx):
    requests = _collect(module_ctx)
    facts = _add_download_integrities(module_ctx, requests)

    archives = {}
    direct_deps = []
    direct_dev_deps = []

    for request in requests:
        nuget_archives(request.packages, archives)
        nuget_hub_repo(request.repo, request.packages)

        if request.is_root:
            if request.is_dev:
                direct_dev_deps.append(request.repo)
            else:
                direct_deps.append(request.repo)

    metadata = {}
    if hasattr(module_ctx, "facts"):
        metadata["facts"] = facts

    return module_ctx.extension_metadata(
        root_module_direct_deps = direct_deps,
        root_module_direct_dev_deps = direct_dev_deps,
        reproducible = True,
        **metadata
    )

packages_lock = module_extension(
    implementation = _packages_lock_impl,
    doc = "Resolves NuGet packages from a `packages.lock.json` file.",
    tag_classes = {"parse": _parse},
)
