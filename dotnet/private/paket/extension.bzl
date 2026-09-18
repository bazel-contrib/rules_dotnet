"""Implementation of the `paket` module extension. See //dotnet:paket.bzl."""

load("//dotnet/private/paket:dependencies.bzl", "parse_dependencies")
load(
    "//dotnet/private/paket:feed.bzl",
    "integrity_fact_key",
    "read_netrc_entries",
    "resolve_integrity_cached",
)
load("//dotnet/private/paket:lock.bzl", "parse_lock")
load(
    "//dotnet/private/rules/nuget:nuget_repo.bzl",
    "nuget_archives",
    "nuget_hub_repo",
)

_DEFAULT_REPO_PREFIX = "paket."

_parse = tag_class(
    doc = "Makes the dependency groups of a `paket.lock` file available to Bazel.",
    attrs = {
        "lock": attr.label(
            doc = "The `paket.lock` file to read the resolved packages from.",
            mandatory = True,
        ),
        "dependencies": attr.label(
            doc = """The `paket.dependencies` the lock file was resolved from.

Optional. When given, the extension checks the lock file still covers what
this file asks for, so that editing it without re-running Paket fails the
build with the command that fixes it rather than a confusing missing package
much later.""",
        ),
        "groups": attr.string_list(
            doc = """The dependency groups to make available.

Defaults to every group in the lock file. Listing groups explicitly is useful
to keep test-only groups out of a module's public dependencies, by declaring
them on a second, `dev_dependency = True` usage of this extension.""",
        ),
        "repo_prefix": attr.string(
            doc = """Prepended to the lower cased group name to name its repository.

The `Build` group of a lock file parsed with the default prefix is addressed
as `@paket.build//<package>`. Change it when two lock files in the same build
have a group in common.""",
            default = _DEFAULT_REPO_PREFIX,
        ),
        "netrc": attr.label(
            doc = "A netrc file with the credentials for the feeds. Defaults to the user's.",
        ),
        "verify_integrity": attr.bool(
            doc = """Whether to pin packages to the hash their feed publishes.

Paket does not record hashes, so they are looked up from the feed's
registration metadata and remembered in `MODULE.bazel.lock`. Feeds that do not
serve that metadata yield no hash and their packages are pinned by version
alone.""",
            default = True,
        ),
    },
)

_INSTALL_COMMAND = "bazel run @rules_dotnet//tools/paket -- install"

def _check_lock_is_current(tag, declared, groups):
    """Fails if the lock file does not cover what the dependencies file asks for.

    Only exact versions are compared; a constraint such as `~> 6.2` can
    legitimately resolve to anything, so for those only the package's presence
    is checked.
    """
    stale = []

    for (group_name, packages) in declared.items():
        group = groups.get(group_name.lower())
        if group == None:
            stale.append("the '{}' group is missing".format(group_name))
            continue

        locked = {package.id.lower(): package.version for package in group.packages}

        for (id, version) in packages.items():
            if id.lower() not in locked:
                stale.append("{} is missing from the '{}' group".format(id, group_name))
            elif version and version != locked[id.lower()]:
                stale.append("{} is pinned at {} but the '{}' group resolves {}".format(
                    id,
                    version,
                    group_name,
                    locked[id.lower()],
                ))

    if stale:
        # buildifier: disable=print
        print("Warning: {} is out of date with {}:\n  {}\n\nRun `{}` to regenerate it.".format(
            tag.lock,
            tag.dependencies,
            "\n  ".join(stale),
            _INSTALL_COMMAND,
        ))

def _select_groups(tag, groups):
    """Returns the groups the tag asked for, defaulting to all of them."""
    if not tag.groups:
        return groups.values()

    selected = []

    for name in tag.groups:
        group = groups.get(name.lower())
        if group == None:
            fail("{} has no group named '{}'. It has: {}.".format(
                tag.lock,
                name,
                ", ".join([group.name for group in groups.values()]),
            ))
        selected.append(group)

    return selected

def _collect(module_ctx):
    """Reads every lock file the build refers to.

    Returns:
      A list of structs, one per dependency group that has been asked for.
    """
    requests = []

    # Repository name to the lock file that claimed it, so that a collision
    # between two modules is reported rather than silently resolved.
    claimed = {}

    for module in module_ctx.modules:
        for tag in module.tags.parse:
            groups = {
                group.name.lower(): group
                for group in parse_lock(module_ctx.read(tag.lock), str(tag.lock))
            }

            if tag.dependencies:
                _check_lock_is_current(
                    tag,
                    parse_dependencies(module_ctx.read(tag.dependencies)),
                    groups,
                )

            for group in _select_groups(tag, groups):
                repo = tag.repo_prefix + group.name.lower()

                if repo in claimed:
                    fail(
                        "The '{}' group is already provided by {} as @{}.".format(
                            group.name,
                            claimed[repo],
                            repo,
                        ) + " Declare it once, or set a different `repo_prefix`.",
                    )
                claimed[repo] = str(tag.lock)

                requests.append(struct(
                    group = group,
                    is_dev = module_ctx.is_dev_dependency(tag),
                    is_root = module.is_root,
                    netrc = tag.netrc,
                    repo = repo,
                    verify_integrity = tag.verify_integrity,
                ))

    return requests

def _resolve_integrity(module_ctx, requests):
    """Returns the hash of every resolved package, keyed for `facts`."""
    resolved = {}
    indexes = {}

    for request in requests:
        if not request.verify_integrity:
            continue

        resolve_integrity_cached(
            module_ctx,
            request.group.sources,
            request.group.packages,
            read_netrc_entries(module_ctx, request.netrc),
            resolved,
            indexes,
        )

    return resolved

def _paket_impl(module_ctx):
    requests = _collect(module_ctx)
    facts = _resolve_integrity(module_ctx, requests)

    archives = {}
    direct_deps = []
    direct_dev_deps = []

    for request in requests:
        packages = [
            {
                "id": package.id,
                "netrc": request.netrc,
                "sha512": facts.get(integrity_fact_key(package.id, package.version), ""),
                "sources": request.group.sources,
                "version": package.version,
            }
            for package in request.group.packages
        ]

        nuget_archives(packages, archives)
        nuget_hub_repo(request.repo, packages)

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

paket = module_extension(
    implementation = _paket_impl,
    doc = "Resolves NuGet packages from a Paket lock file.",
    tag_classes = {"parse": _parse},
)
