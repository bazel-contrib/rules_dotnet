"""Implementation of the `nuget` module extension. See //dotnet:nuget.bzl."""

load(
    "//dotnet/private/nuget_resolve:input_hash.bzl",
    "compute_input_hash",
)
load("//dotnet/private/nuget_resolve:lock.bzl", "parse_lock")
load("//dotnet/private/nuget_resolve:pinned_hub.bzl", "pinned_hub")
load("//dotnet/private/nuget_resolve:resolve.bzl", "nuget_resolve")
load(
    "//dotnet/private/nuget_resolve:tool.bzl",
    "bootstrap_sdk_dotnet_label",
    "nuget_resolver_tool",
)
load("//dotnet/private/nuget_resolve:unpinned_hub.bzl", "unpinned_hub")
load(
    "//dotnet/private/rules/nuget:nuget_repo.bzl",
    "nuget_archives",
)

_DEFAULT_SOURCES = ["https://api.nuget.org/v3/index.json"]

_resolve = tag_class(
    doc = "Resolves a set of NuGet packages transitively, once per target framework.",
    attrs = {
        "name": attr.string(
            doc = "Prefix for the repositories: a hub per framework as `<name>.<tfm>`, the resolve repository as `unpinned_<name>`.",
            mandatory = True,
        ),
        "packages": attr.string_dict(
            doc = """Package id to version range, in NuGet's PackageReference syntax: `13.0.3` (minimum version, resolves to the lowest applicable), `[13.0.3]` (exact), `4.0.*` (floating). Semantics identical to `dotnet restore`.""",
            mandatory = True,
            allow_empty = False,
        ),
        "frameworks": attr.string_list(
            doc = "The target frameworks to resolve for. Each becomes its own hub repository, addressed as `@<name>.<tfm>//<package>`.",
            mandatory = True,
            allow_empty = False,
        ),
        "sources": attr.string_list(
            doc = "The NuGet feeds, in lookup order. V3 (`index.json`) and V2 are both supported.",
            default = _DEFAULT_SOURCES,
        ),
        "lock_file": attr.label(
            doc = "The checked-in `nuget_resolve.json`. Without it every fetch resolves fresh (unpinned mode).",
        ),
        "fail_if_repin_required": attr.bool(
            doc = """Fail the build when the inputs no longer match the lock file. Only meaningful with `lock_file`; without one it is inert. With `REPIN=1` in the environment a mismatch warns instead of failing, so the `:pin` target itself always builds.""",
            default = True,
        ),
        "netrc": attr.label(
            doc = "A netrc file with the credentials for the feeds. Defaults to the user's.",
        ),
    },
)

def resolve_repositories(tag):
    """The repository names one resolve tag claims.

    Args:
      tag: A struct or tag with `name` and `frameworks` fields.

    Returns:
      The resolve repository name followed by the hub names, one per
      framework.
    """
    return ["unpinned_" + tag.name] + [
        "{}.{}".format(tag.name, tfm)
        for tfm in tag.frameworks
    ]

def claim(claimed, repo, owner):
    """Records repo as claimed by owner.

    Args:
      claimed: The claim map, repository name to owner description.
      repo: The repository name being claimed.
      owner: A description of the claimant, for error messages.

    Returns:
      An error message when the repository was already claimed, else None.
    """
    existing = claimed.get(repo)
    if existing != None:
        return "The repository @{} is already provided by {}. Pick a different `name` for one of the resolve tags.".format(repo, existing)
    claimed[repo] = owner
    return None

def _collect(module_ctx):
    """Gathers every resolve tag across all modules, checking name collisions."""
    entries = []

    # Repository name to the module that claimed it, so that a collision
    # between two tags (also across modules) is reported rather than silently
    # resolved.
    claimed = {}

    for module in module_ctx.modules:
        for tag in module.tags.resolve:
            owner = "the resolve tag '{}' of module '{}'".format(tag.name, module.name)
            for repo in resolve_repositories(tag):
                error = claim(claimed, repo, owner)
                if error:
                    fail(error)

            entries.append(struct(
                tag = tag,
                is_dev = module_ctx.is_dev_dependency(tag),
                is_root = module.is_root,
            ))

    return entries

def _nuget_impl(module_ctx):
    entries = _collect(module_ctx)

    if not entries:
        return module_ctx.extension_metadata(reproducible = True)

    # One tool repository per extension instance, shared by every resolve tag.
    # The SDK label resolves through rules_dotnet's own repo mapping: its
    # MODULE.bazel lists the per-platform bootstrap SDKs in use_repo(dotnet).
    dotnet = bootstrap_sdk_dotnet_label(module_ctx.os.name, module_ctx.os.arch)
    nuget_resolver_tool(
        name = "nuget_resolver_tool",
        dotnet = dotnet,
    )

    archives = {}
    direct_deps = []
    direct_dev_deps = []
    all_pinned = True

    for entry in entries:
        tag = entry.tag
        input_hash = compute_input_hash(tag.packages, tag.frameworks, tag.sources)

        nuget_resolve(
            name = "unpinned_" + tag.name,
            packages = tag.packages,
            frameworks = tag.frameworks,
            sources = tag.sources,
            input_hash = input_hash,
            lock_file = tag.lock_file,
            netrc = tag.netrc,
            dotnet = dotnet,
            tool = "@nuget_resolver_tool//:publish/NuGetResolver.dll",
        )

        if tag.lock_file:
            lock = parse_lock(module_ctx.read(tag.lock_file), str(tag.lock_file))
            missing = [tfm for tfm in tag.frameworks if lock.frameworks.get(tfm) == None]
            if missing:
                # buildifier: disable=print
                print("{} has no framework(s) {}. It has: {}. Falling back to resolving them fresh; regenerate the lock file with `REPIN=1 bazel run @{}.{}//:pin`.".format(
                    tag.lock_file,
                    ", ".join(missing),
                    ", ".join(lock.frameworks.keys()),
                    tag.name,
                    tag.frameworks[0],
                ))

            for tfm in tag.frameworks:
                group = lock.frameworks.get(tfm)
                if group == None:
                    all_pinned = False

                    # The unpinned hub reads the freshly resolved lock from
                    # @unpinned_<name>, so this repo exists, its `:pin` alias
                    # works, and the refetch after repin flips it to the
                    # pinned hub.
                    unpinned_hub(
                        name = "{}.{}".format(tag.name, tfm),
                        lock = "@unpinned_{}//:nuget_resolve.json".format(tag.name),
                        framework = tfm,
                        resolve_name = tag.name,
                        netrc = tag.netrc,
                    )
                    continue

                packages = [
                    {
                        "id": package.id,
                        "netrc": tag.netrc,
                        "sha512": package.sha512,
                        "sources": tag.sources,
                        "urls": package.urls,
                        "version": package.version,
                    }
                    for package in group
                ]

                # Spokes are shared across tags first-wins: the same id+version
                # from a later tag reuses the first tag's archive (integrity is
                # still bounded by the lock file's sha512).
                nuget_archives(packages, archives)
                pinned_hub(
                    name = "{}.{}".format(tag.name, tfm),
                    lock_file = tag.lock_file,
                    input_hash = input_hash,
                    fail_if_repin_required = tag.fail_if_repin_required,
                    framework = tfm,
                    resolve_name = tag.name,
                )
        else:
            all_pinned = False
            for tfm in tag.frameworks:
                unpinned_hub(
                    name = "{}.{}".format(tag.name, tfm),
                    lock = "@unpinned_{}//:nuget_resolve.json".format(tag.name),
                    framework = tfm,
                    resolve_name = tag.name,
                    netrc = tag.netrc,
                )

        if entry.is_root:
            for tfm in tag.frameworks:
                if entry.is_dev:
                    direct_dev_deps.append("{}.{}".format(tag.name, tfm))
                else:
                    direct_deps.append("{}.{}".format(tag.name, tfm))

    return module_ctx.extension_metadata(
        root_module_direct_deps = direct_deps,
        root_module_direct_dev_deps = direct_dev_deps,
        reproducible = all_pinned,
    )

nuget = module_extension(
    implementation = _nuget_impl,
    doc = "Resolves NuGet packages transitively, with optional pinning.",
    tag_classes = {"resolve": _resolve},
    # The tool build and its SDK label depend on the host platform.
    os_dependent = True,
    arch_dependent = True,
)
