"""Declares the repositories that hold the SDK's packs and native tools.

Each repository groups its packages behind targets named for what they provide
(`@dotnet.targeting_packs//user/default:net10.0`), so labels do not move when
the SDK in use moves the bands to other versions.

The tables built while loading name a target for every release rules_dotnet
declares. Those of releases newer than the SDK fail when built, saying which
SDK they need: see `sdk_too_old.bzl`.
"""

load("@bazel_skylib//lib:collections.bzl", "collections")
load(
    "//dotnet/private/paket:feed.bzl",
    "integrity_fact_key",
    "package_versions",
    "read_netrc_entries",
    "resolve_integrity_cached",
)
load(
    "//dotnet/private/rules/nuget:nuget_repo.bzl",
    "nuget_archive_name",
    "nuget_archives",
    "nuget_hub_repo",
    "nuget_package_label",
)
load("//dotnet/private/sdk:pack_bands.bzl", "PACK_BANDS", "pack_bands", "sdk_band_tfms")
load(
    "//dotnet/private/sdk:packs.bzl",
    "APPHOST_PACK_REPO",
    "ASPNETCORE_FRAMEWORK",
    "BOOTSTRAP_PACKS",
    "CROSSGEN2_PACK_REPO",
    "HOST_RIDS",
    "ILCOMPILER_PACK_REPO",
    "NATIVEAOT_PACK_REPO",
    "NEWEST_BAND",
    "RUNTIME_FRAMEWORK_SETS",
    "RUNTIME_PACK_REPO",
    "TARGETING_FRAMEWORK_SETS",
    "TARGETING_PACK_REPO",
    "USER_PACKS",
    "WASM_PACK_REPO",
    "WASM_RID",
    "aot_pack_rids",
    "aot_pack_tfms",
    "apphost_pack",
    "crossgen2_pack",
    "frameworks_key",
    "host_platform_setting",
    "host_tool_tfms",
    "ilcompiler_build_pack",
    "ilcompiler_pack",
    "nativeaot_pack",
    "runtime_pack_rids",
    "runtime_pack_tfms",
    "runtime_packs",
    "targeting_pack_profiles",
    "targeting_pack_tfms",
    "targeting_packs",
    "wasm_pack_tfms",
    "wasm_runtime_pack",
    "wasm_tool_packs",
)
load(
    "//dotnet/private/sdk:releases.bzl",
    "is_superseded",
    "newest_shared_release",
    "runtimes_shipped_by",
    "tfm_channel",
)

_NUGET_ORG = "https://api.nuget.org/v3/index.json"

# Bump when the shape of a fact changes so that stale entries are ignored
# rather than misread.
_FACT_VERSION = "v1"

# How many packs a failure names before it only counts the rest.
_LISTED_PACKS = 5

# A running server keeps a failed evaluation and repeats it without asking the
# feed again, so retrying takes a restart.
_RETRY = (
    "This is usually a network problem or a nuget.org outage. Once nuget.org answers again, " +
    "run `bazel shutdown` and retry: the running Bazel server repeats this failure until it restarts."
)

# Where the rules the generated packages use are loaded from, other than the
# `<kind>_pack` rules, which live in `<kind>_packs/<kind>_pack.bzl`.
_RULE_FILES = {
    "sdk_too_old": "@rules_dotnet//dotnet/private/sdk:sdk_too_old.bzl",
}

def _render(value):
    """Renders an attribute value, keeping `select` dicts as selects."""
    if type(value) == "dict":
        return "select({})".format(json.encode(value))

    return json.encode(value)

def _target(rule, attrs):
    return "{}(\n{}\n)".format(rule, "\n".join([
        "    {} = {},".format(key, _render(attrs[key]))
        for key in sorted(attrs)
    ]))

def _alias(name, actual):
    return "alias(\n    name = {},\n    actual = {},\n)".format(json.encode(name), _render(actual))

def _build_file(targets, aliases = {}):
    """A package of targets.

    Args:
      targets: Each target as a (rule, attributes) pair.
      aliases: Aliases to add, by name.

    Returns:
      The BUILD file's content.
    """
    loads = [
        "load({}, {})".format(
            json.encode(_RULE_FILES.get(rule) or "@rules_dotnet//dotnet/private/sdk/{0}s:{0}.bzl".format(rule)),
            json.encode(rule),
        )
        for rule in sorted(collections.uniq([rule for (rule, _) in targets]))
    ]
    return "\n\n".join(
        ['"GENERATED"'] +
        (["\n".join(loads)] if loads else []) +
        ['package(default_visibility = ["//visibility:public"])'] +
        [_target(rule, attrs) for (rule, attrs) in targets] +
        [_alias(name, actual) for (name, actual) in aliases.items()],
    ) + "\n"

def _too_new(name, tfm, sdk_version):
    """A target standing in for a pack of a release newer than the SDK."""
    return ("sdk_too_old", {
        "name": name,
        "sdk_version": sdk_version,
        "target_framework": tfm,
    })

def _unknown(packs):
    """Whether any (id, version) pair is from a band the SDK does not know."""
    return any([version == None for (_, version) in packs])

def _targeting(pack_sets):
    """One package per (pack set, set of shared frameworks), each at its own SDK's bands.

    Args:
      pack_sets: The SDK behind each pack set, as a struct of its `version`
        and its `bands`.

    Returns:
      A struct of build files and the packages they reference.
    """
    packages = []
    build_files = {}

    for (pack_set, sdk) in pack_sets.items():
        for frameworks in TARGETING_FRAMEWORK_SETS:
            targets = []

            for tfm in targeting_pack_tfms(frameworks):
                packs = targeting_packs(tfm, frameworks, bands = sdk.bands)
                if _unknown(packs):
                    targets.append(_too_new(tfm, tfm, sdk.version))
                    continue

                packages += packs
                targets.append(("targeting_pack", {
                    "name": tfm,
                    "packs": [nuget_package_label(id, version) for (id, version) in packs],
                    # As strings: a dict would render as a select.
                    "profiles": [
                        "{}:{}".format(id, profile)
                        for (id, profiles) in targeting_pack_profiles(tfm, frameworks).items()
                        for profile in profiles
                    ],
                    "target_framework": tfm,
                }))

            build_files["{}/{}/BUILD.bazel".format(pack_set, frameworks_key(frameworks))] = _build_file(targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _runtime(sdk):
    packages = []
    build_files = {}

    for frameworks in RUNTIME_FRAMEWORK_SETS:
        for tfm in runtime_pack_tfms():
            targets = []

            for rid in runtime_pack_rids(tfm, frameworks):
                packs = runtime_packs(tfm, rid, frameworks, bands = sdk.bands)
                if _unknown(packs):
                    targets.append(_too_new(rid, tfm, sdk.version))
                    continue

                packages += packs
                targets.append(("runtime_pack", {
                    "name": rid,
                    "packs": [nuget_package_label(id, version) for (id, version) in packs],
                    "runtime_identifier": rid,
                    "target_framework": tfm,
                }))

            build_files["{}/{}/BUILD.bazel".format(frameworks_key(frameworks, profiles = False), tfm)] = _build_file(targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _wasm(sdk):
    """What a Blazor WebAssembly publish needs, per target framework.

    One target per framework rather than per runtime identifier, as a browser
    is the only target. The tools are at the band's version, as the SDK bundles
    them: `illink` will not start on a runtime older than the one it was built
    for. The `newest` package names the SDK's own band's tools, which run on
    its runtime whatever the framework.
    """
    packages = []
    build_files = {}
    newest = None

    for tfm in wasm_pack_tfms():
        runtime = wasm_runtime_pack(tfm, bands = sdk.bands)
        tools = wasm_tool_packs(tfm, bands = sdk.bands)

        if _unknown([runtime] + [pack for (_, pack) in tools]):
            build_files["{}/BUILD.bazel".format(tfm)] = _build_file([
                _too_new(name, tfm, sdk.version)
                for name in [WASM_RID] + [name for (name, _) in tools]
            ])
            continue

        newest = (tfm, [name for (name, _) in tools])
        packages += [runtime] + [pack for (_, pack) in tools]
        build_files["{}/BUILD.bazel".format(tfm)] = _build_file(
            [("runtime_pack", {
                "name": WASM_RID,
                "packs": [nuget_package_label(*runtime)],
                "runtime_identifier": WASM_RID,
                "target_framework": tfm,
            })],
            aliases = {
                name: "@{}//:files".format(nuget_archive_name(id, version))
                for (name, (id, version)) in tools
            },
        )

    if newest:
        (tfm, names) = newest
        build_files["{}/BUILD.bazel".format(NEWEST_BAND)] = _build_file([], aliases = {
            name: "//{}:{}".format(tfm, name)
            for name in names
        })
    else:
        # An SDK older than every band, which only the first band would do for.
        first = wasm_pack_tfms()[0]
        build_files["{}/BUILD.bazel".format(NEWEST_BAND)] = _build_file([
            _too_new(name, first, sdk.version)
            for (name, _) in wasm_tool_packs(first, bands = PACK_BANDS)
        ])

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _apphost(sdk):
    packages = []
    build_files = {}

    for tfm in runtime_pack_tfms():
        targets = []

        for rid in runtime_pack_rids(tfm):
            pack = apphost_pack(tfm, rid, bands = sdk.bands)
            if _unknown([pack]):
                targets.append(_too_new(rid, tfm, sdk.version))
                continue

            packages.append(pack)
            targets.append(("apphost_pack", {
                "name": rid,
                "pack": nuget_package_label(*pack),
                "runtime_identifier": rid,
                "target_framework": tfm,
            }))

        build_files["{}/BUILD.bazel".format(tfm)] = _build_file(targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _host_tool(kind, pack, sdk):
    """One package per band, each holding the band's pack for every host.

    `host_tool_pack` selects the band in the target configuration, and the
    band's `host` alias, reached through the exec transition, selects the pack
    for the execution platform.

    Args:
      kind: The pack rule's name, which also names the `.bzl` file it lives in.
      pack: Returns the (id, version) of the tool's pack for a tfm, host rid
        and bands, or None where the tool did not ship for that combination.
      sdk: The SDK, as a struct of its `version` and its `bands`.

    Returns:
      A struct of build files and the packages they reference.
    """
    packages = []
    targets_by_band = {}
    build_files = {}

    for tfm in host_tool_tfms(pack):
        found = [(rid, pack(tfm, rid, bands = sdk.bands)) for rid in HOST_RIDS]
        found = [(rid, tool) for (rid, tool) in found if tool != None]

        if _unknown([tool for (_, tool) in found]):
            build_files["{}/BUILD.bazel".format(tfm)] = _build_file([_too_new("host", tfm, sdk.version)])
            continue

        packages += [tool for (_, tool) in found]

        # The tool is a native executable with its JIT libraries beside it,
        # none of which the package rules classify, so the pack reads the
        # archive's file list directly.
        targets_by_band[tfm] = [
            ("{}_pack".format(kind), {
                "name": rid,
                "pack_files": "@{}//:files".format(nuget_archive_name(id, version)),
            })
            for (rid, (id, version)) in found
        ]

    # Bands come oldest first. A host that an older band did not ship the tool
    # for gets the newest band's.
    newest = targets_by_band.keys()[-1] if targets_by_band else None

    for (tfm, targets) in targets_by_band.items():
        hosts = {host_platform_setting(attrs["name"]): ":" + attrs["name"] for (_, attrs) in targets}

        if tfm != newest:
            hosts["//conditions:default"] = "//{}:host".format(newest)

        build_files["{}/BUILD.bazel".format(tfm)] = _build_file(targets, aliases = {"host": hosts})

    if newest:
        build_files["{}/BUILD.bazel".format(NEWEST_BAND)] = _build_file([], aliases = {
            "host": "//{}:host".format(newest),
        })
    else:
        # An SDK older than every band, which only the first band would do for.
        build_files["{}/BUILD.bazel".format(NEWEST_BAND)] = _build_file([
            _too_new("host", host_tool_tfms(pack)[0], sdk.version),
        ])

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _nativeaot(sdk):
    """One target per runtime identifier a framework can publish AOT for.

    Carries both halves of what a NativeAOT publish needs: the framework
    assemblies ilc compiles against, and the static libraries the native link
    consumes. Neither is a classified asset kind, so the pack reads the
    archive's file list directly.
    """
    packages = []
    build_files = {}

    for tfm in aot_pack_tfms():
        targets = []

        for rid in aot_pack_rids(tfm):
            pack = nativeaot_pack(tfm, rid, bands = sdk.bands)
            if _unknown([pack]):
                targets.append(_too_new(rid, tfm, sdk.version))
                continue

            packages.append(pack)
            attrs = {
                "name": rid,
                "pack_files": "@{}//:files".format(nuget_archive_name(*pack)),
            }

            # The SDK reads the list from beside its own targets, so that it
            # always matches the ilc it is handed to.
            build_pack = ilcompiler_build_pack(tfm, rid, bands = sdk.bands)
            if build_pack != None:
                packages.append(build_pack)
                attrs["direct_pinvoke_lists"] = [
                    "@{}//:build/WindowsAPIs.txt".format(nuget_archive_name(*build_pack)),
                ]

            targets.append(("nativeaot_pack", attrs))

        build_files["{}/BUILD.bazel".format(tfm)] = _build_file(targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _band_fact_key(sdk_version, tfm):
    return "pack-band/{}:{}/{}".format(_FACT_VERSION, sdk_version, tfm)

def _reference_packs(tfm):
    """The packs whose publication decides a band's version.

    A patch that never published its reference packs published none of the
    band's other packs either, and the reference packs are the first to stop
    being serviced. ilc ships from a build of its own, so it is checked too.
    """
    packs = [id for (id, _) in targeting_packs(tfm, {ASPNETCORE_FRAMEWORK: None}, bands = PACK_BANDS)]

    ilcompiler = ilcompiler_pack(tfm, "linux-x64", bands = PACK_BANDS)
    if ilcompiler != None:
        packs.append(ilcompiler[0])

    return packs

def _published_versions(module_ctx, ids, netrc_entries, indexes, cache):
    """The versions nuget.org publishes of each package, None where it gave none.

    Args:
      module_ctx: The module extension context.
      ids: The package ids.
      netrc_entries: Credentials for the package feed.
      indexes: Feed index cache, shared across calls.
      cache: Version lists by lower case id, which this call adds to.

    Returns:
      A list of each package's versions, in the order of `ids`.
    """
    missing = [id for id in ids if id.lower() not in cache]
    if missing:
        answered = package_versions(module_ctx, _NUGET_ORG, missing, netrc_entries, indexes) or {}
        for id in missing:
            cache[id.lower()] = answered.get(id.lower())

    return [cache[id.lower()] for id in ids]

def _band_targets(module_ctx, sdk, tfms, releases):
    """The runtime of each band that had shipped by the day the SDK did.

    Args:
      module_ctx: The module extension context.
      sdk: The SDK, from `resolve_sdk`.
      tfms: The bands' target frameworks.
      releases: Release metadata cache, shared across calls.

    Returns:
      A dict of target framework to runtime version: the SDK's own for its own
      band, and the band's first release where it had none yet.
    """
    channels = {tfm: tfm_channel(tfm) for tfm in tfms}
    shipped = runtimes_shipped_by(
        module_ctx,
        releases,
        [channel for channel in channels.values() if channel != sdk.channel],
        sdk.release_date,
    )
    shipped[sdk.channel] = sdk.runtime_version

    return {tfm: shipped.get(channel) or channel + ".0" for (tfm, channel) in channels.items()}

def _band_version(sdk, tfm, target, references, published):
    """The newest release of a band, up to `target`, that published every reference pack.

    Args:
      sdk: The SDK, from `resolve_sdk`.
      tfm: The band's target framework.
      target: The runtime version from `_band_targets`.
      references: The band's reference pack ids, from `_reference_packs`.
      published: The versions nuget.org publishes of each of `references`.

    Returns:
      The version.
    """
    if None in published:
        # Guessing would decide the packs a build compiles against from
        # whether the feed was reachable, so the evaluation fails instead.
        fail(("nuget.org did not list the versions of {}, which .NET SDK {} needs to pick the " +
              "packs it compiles against for {}. " + _RETRY).format(
            ", ".join([id for (id, versions) in zip(references, published) if versions == None]),
            sdk.version,
            tfm,
        ))

    # A preview SDK of a released channel falls back to the release where
    # the preview's packs do not share a version.
    channel = tfm_channel(tfm)
    version = newest_shared_release(channel, target, published) or newest_shared_release(channel, channel + ".0", published)
    if version == None:
        fail("NuGet has no version of {} at or before {} that is in all of {}, which .NET SDK {} needs.".format(
            tfm,
            target,
            ", ".join(references),
            sdk.version,
        ))

    return version

def _band_versions(module_ctx, sdk, netrc_entries, indexes, releases, published, facts):
    """Returns the version each band from .NET 6 onwards is at for an SDK.

    An SDK compiles against the packs of what had shipped by the day it did,
    which is what it bundles, give or take a release the metadata dates late.
    A patch whose packs were never published gives way to the newest one
    before it that was. Bands newer than the SDK's own are left out: it cannot
    build for them.

    Args:
      module_ctx: The module extension context.
      sdk: The SDK, from `resolve_sdk`.
      netrc_entries: Credentials for the package feed.
      indexes: Feed index cache, shared across calls.
      releases: Release metadata cache, shared across calls.
      published: Version lists cache, shared across calls.
      facts: The facts to hand back to Bazel, which this call adds to.

    Returns:
      The version of each band the SDK knows, by target framework.
    """
    remembered = getattr(module_ctx, "facts", {})
    versions = {}
    pending = []

    for tfm in sdk_band_tfms(sdk.tfm):
        version = remembered.get(_band_fact_key(sdk.version, tfm))
        if type(version) == "string" and version:
            versions[tfm] = version
            facts[_band_fact_key(sdk.version, tfm)] = version
        else:
            pending.append(tfm)

    if not pending:
        return versions

    targets = _band_targets(module_ctx, sdk, pending, releases)

    # Looked up together, so that the feed is asked once.
    references = {tfm: _reference_packs(tfm) for tfm in pending}
    _published_versions(
        module_ctx,
        collections.uniq([id for ids in references.values() for id in ids]),
        netrc_entries,
        indexes,
        published,
    )

    for tfm in pending:
        lists = _published_versions(module_ctx, references[tfm], netrc_entries, indexes, published)
        versions[tfm] = _band_version(sdk, tfm, targets[tfm], references[tfm], lists)

        # The SDK version alone decides a band, except for a step back past a
        # patch that a later one has yet to show is for good: the packs of a
        # patch can reach the feed after the release metadata does.
        if versions[tfm] == targets[tfm] or is_superseded(tfm_channel(tfm), targets[tfm], lists):
            facts[_band_fact_key(sdk.version, tfm)] = versions[tfm]

    return versions

def _resolve_hashes(module_ctx, packages, netrc_entries, indexes):
    """Looks up the SHA-512 nuget.org publishes for each pack.

    Args:
      module_ctx: The module extension context.
      packages: The packs, as (id, version) pairs.
      netrc_entries: Credentials for the package feed.
      indexes: Feed index cache, shared across calls.

    Returns:
      The integrity of each pack, by `integrity_fact_key`.
    """
    resolved = {}
    resolve_integrity_cached(
        module_ctx,
        [_NUGET_ORG],
        [struct(id = id, version = version) for (id, version) in packages],
        netrc_entries,
        resolved,
        indexes,
    )

    # nuget.org publishes a hash for every package, so a missing one means a
    # lookup that failed. Declaring the pack without one would download it
    # unverified, and every later build would reuse that unverified pin.
    unverified = sorted([
        "{} {}".format(id, version)
        for (id, version) in packages
        if not resolved.get(integrity_fact_key(id, version))
    ])
    if unverified:
        fail(("Could not look up the SHA-512 of {} of the .NET SDK's packs on nuget.org, so they " +
              "cannot be downloaded verified: {}{}. " + _RETRY).format(
            len(unverified),
            ", ".join(unverified[:_LISTED_PACKS]),
            " and {} more".format(len(unverified) - _LISTED_PACKS) if len(unverified) > _LISTED_PACKS else "",
        ))

    return resolved

def declare_pack_repos(module_ctx, sdk, bootstrap, releases):
    """Declares the repositories holding the SDK's packs.

    Each SDK resolves its own targeting pack set, so neither decides what the
    other compiles against. Only the registered SDK has runtime, apphost and
    tool packs: rules_dotnet's own tools are never published.

    Args:
      module_ctx: The module extension context.
      sdk: The registered .NET SDK, from `resolve_sdk`.
      bootstrap: The SDK that builds rules_dotnet's own tools, from
        `resolve_sdk`.
      releases: Release metadata cache, shared with `resolve_sdk`.

    Returns:
      The facts to hand back to Bazel, so that the versions and hashes looked
      up here are reused by later evaluations.
    """
    netrc_entries = read_netrc_entries(module_ctx, None)
    indexes = {}
    published = {}
    facts = {}

    def with_bands(resolved_sdk):
        versions = _band_versions(module_ctx, resolved_sdk, netrc_entries, indexes, releases, published, facts)
        return struct(version = resolved_sdk.version, bands = pack_bands(versions))

    user = with_bands(sdk)
    tools = user if bootstrap.version == sdk.version else with_bands(bootstrap)

    kinds = [
        (TARGETING_PACK_REPO, _targeting({
            USER_PACKS: user,
            BOOTSTRAP_PACKS: tools,
        })),
        (RUNTIME_PACK_REPO, _runtime(user)),
        (APPHOST_PACK_REPO, _apphost(user)),
        (CROSSGEN2_PACK_REPO, _host_tool("crossgen2", crossgen2_pack, user)),
        # ilc and the NativeAOT pack ship together at the band's version, as
        # the SDK bundles them.
        (ILCOMPILER_PACK_REPO, _host_tool("ilcompiler", ilcompiler_pack, user)),
        (NATIVEAOT_PACK_REPO, _nativeaot(user)),
        (WASM_PACK_REPO, _wasm(user)),
    ]

    resolved = _resolve_hashes(
        module_ctx,
        collections.uniq([pack for (_, kind) in kinds for pack in kind.packages]),
        netrc_entries,
        indexes,
    )

    declared = {}
    for (repo, kind) in kinds:
        hub = [
            {
                "id": id,
                "name": "{}.v{}".format(id.lower(), version),
                "sha512": resolved[integrity_fact_key(id, version)],
                "sources": [_NUGET_ORG],
                "version": version,
            }
            for (id, version) in kind.packages
        ]
        nuget_archives(hub, declared)
        nuget_hub_repo(repo, hub, extra_build_files = kind.build_files)

    return facts | resolved
