"""Declares the repositories that hold the SDK's packs and native tools.

Each repository groups its packages behind targets named for what they provide
(`@dotnet.targeting_packs//user/default:net10.0`), so labels do not move when
the SDK in use moves the bands to other versions.
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
load("//dotnet/private/sdk:pack_bands.bzl", "PACK_BANDS", "SDK_BAND_TFMS", "pack_bands")
load(
    "//dotnet/private/sdk:packs.bzl",
    "APPHOST_PACK_REPO",
    "BOOTSTRAP_PACKS",
    "CROSSGEN2_PACK_REPO",
    "ILCOMPILER_PACK_REPO",
    "NATIVEAOT_PACK_REPO",
    "PROJECT_SDKS",
    "RUNTIME_PACK_REPO",
    "TARGETING_PACK_REPO",
    "USER_PACKS",
    "WASM_PACK_REPO",
    "WASM_RID",
    "WEB_SDK",
    "aot_pack_rids",
    "aot_pack_tfms",
    "apphost_pack",
    "crossgen2_pack",
    "host_platform_setting",
    "host_rids",
    "host_tool_tfms",
    "ilcompiler_pack",
    "nativeaot_pack",
    "runtime_pack_rids",
    "runtime_pack_tfms",
    "runtime_packs",
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

NUGET_ORG = "https://api.nuget.org/v3/index.json"

# Bump when the shape of a fact changes so that stale entries are ignored
# rather than misread.
_FACT_VERSION = "v1"

def _reference_packs(tfm):
    """The packs whose publication decides a band's version.

    A patch that never published its reference packs published none of the
    band's other packs either, and the reference packs are the first to stop
    being serviced. ilc ships from a build of its own, so it is checked too.
    """
    packs = [id for (id, _) in targeting_packs(tfm, WEB_SDK, bands = PACK_BANDS)]

    ilcompiler = ilcompiler_pack(tfm, "linux-x64", bands = PACK_BANDS)
    if ilcompiler != None:
        packs.append(ilcompiler[0])

    return packs

_HEADER = """\
"GENERATED"

load("@rules_dotnet//dotnet/private/sdk/{kind}_packs:{kind}_pack.bzl", "{kind}_pack")

package(default_visibility = ["//visibility:public"])\
"""

def _render(value):
    """Renders an attribute value, keeping `select` dicts as selects."""
    if type(value) == "dict":
        return "select({})".format(json.encode(value))

    return json.encode(value)

def _target(kind, attrs):
    return "{}_pack(\n{}\n)".format(kind, "\n".join([
        "    {} = {},".format(key, _render(attrs[key]))
        for key in sorted(attrs)
    ]))

def _build_file(kind, targets):
    return "\n\n".join([_HEADER.format(kind = kind)] + [_target(kind, a) for a in targets]) + "\n"

def _targeting(bands_by_pack_set):
    """One package per (pack set, project SDK), each at its own SDK's bands.

    Args:
      bands_by_pack_set: The bands of the SDK behind each pack set.

    Returns:
      A struct of build files and the packages they reference.
    """
    packages = []
    build_files = {}

    for (pack_set, bands) in bands_by_pack_set.items():
        for project_sdk in PROJECT_SDKS:
            targets = []

            for tfm in targeting_pack_tfms(project_sdk):
                packs = targeting_packs(tfm, project_sdk, bands = bands)
                packages += packs
                targets.append({
                    "name": tfm,
                    "packs": [nuget_package_label(id, version) for (id, version) in packs],
                    "target_framework": tfm,
                })

            build_files["{}/{}/BUILD.bazel".format(pack_set, project_sdk)] = _build_file("targeting", targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _runtime(bands):
    packages = []
    build_files = {}

    for project_sdk in PROJECT_SDKS:
        for tfm in runtime_pack_tfms():
            targets = []

            for rid in runtime_pack_rids(tfm, project_sdk):
                packs = runtime_packs(tfm, rid, project_sdk, bands = bands)
                packages += packs
                targets.append({
                    "name": rid,
                    "packs": [nuget_package_label(id, version) for (id, version) in packs],
                    "runtime_identifier": rid,
                    "target_framework": tfm,
                })

            build_files["{}/{}/BUILD.bazel".format(project_sdk, tfm)] = _build_file("runtime", targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _wasm(bands):
    """What a Blazor WebAssembly publish needs, per target framework.

    There is one target per framework rather than per runtime identifier,
    because a browser is the only target. The runtime pack reuses the
    `runtime_pack` rule, since it carries the same mix of managed assemblies and
    native files as any other; the tools are just their archives' file lists.

    The tools are at the band's version too, as the SDK bundles them at its
    own: `illink` will not start on a runtime older than the one it was built
    for, so tools newer than the SDK in use cannot trim.
    """
    packages = []
    build_files = {}

    for tfm in wasm_pack_tfms():
        (id, version) = wasm_runtime_pack(tfm, bands = bands)
        packages.append((id, version))

        lines = [
            "\"GENERATED\"",
            "",
            "load(\"@rules_dotnet//dotnet/private/sdk/runtime_packs:runtime_pack.bzl\", \"runtime_pack\")",
            "",
            "package(default_visibility = [\"//visibility:public\"])",
            "",
            _target("runtime", {
                "name": WASM_RID,
                "packs": [nuget_package_label(id, version)],
                "runtime_identifier": WASM_RID,
                "target_framework": tfm,
            }),
        ]

        for (name, (tool_id, tool_version)) in wasm_tool_packs(tfm, bands = bands):
            packages.append((tool_id, tool_version))
            lines += [
                "",
                "alias(\n    name = \"{}\",\n    actual = \"@{}//:files\",\n)".format(
                    name,
                    nuget_archive_name(tool_id, tool_version),
                ),
            ]

        build_files["{}/BUILD.bazel".format(tfm)] = "\n".join(lines) + "\n"

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _apphost(bands):
    packages = []
    build_files = {}

    for tfm in runtime_pack_tfms():
        targets = []

        for rid in runtime_pack_rids(tfm):
            (id, version) = apphost_pack(tfm, rid, bands = bands)
            packages.append((id, version))
            targets.append({
                "name": rid,
                "pack": nuget_package_label(id, version),
                "runtime_identifier": rid,
                "target_framework": tfm,
            })

        build_files["{}/BUILD.bazel".format(tfm)] = _build_file("apphost", targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _host_tool(kind, pack, bands):
    """One package per band, each holding the band's pack for every host.

    `host_tool_pack` selects the band in the target configuration, and the
    band's `host` alias, reached through the exec transition, selects the pack
    for the execution platform.

    Args:
      kind: The pack rule's name, which also names the `.bzl` file it lives in.
      pack: Returns the (id, version) of the tool's pack for a tfm, host rid
        and bands, or None where the tool did not ship for that combination.
      bands: The bands to take versions from.

    Returns:
      A struct of build files and the packages they reference.
    """
    packages = []
    targets_by_band = {}

    for tfm in host_tool_tfms(pack):
        targets = []

        for rid in host_rids():
            found = pack(tfm, rid, bands = bands)

            if found == None:
                continue

            (id, version) = found
            packages.append((id, version))

            # The tool is a native executable with its JIT libraries beside it,
            # none of which the package rules classify, so the pack reads the
            # archive's file list directly.
            targets.append({
                "name": rid,
                "pack_files": "@{}//:files".format(nuget_archive_name(id, version)),
            })

        targets_by_band[tfm] = targets

    # Bands come oldest first. A host that an older band did not ship the tool
    # for gets the newest band's.
    newest = targets_by_band.keys()[-1] if targets_by_band else None
    build_files = {}

    for (tfm, targets) in targets_by_band.items():
        hosts = {host_platform_setting(target["name"]): ":" + target["name"] for target in targets}

        if tfm != newest:
            hosts["//conditions:default"] = "//{}:host".format(newest)

        build_files["{}/BUILD.bazel".format(tfm)] = "{}\nalias(\n    name = \"host\",\n    actual = {},\n)\n".format(
            _build_file(kind, targets),
            _render(hosts),
        )

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _nativeaot(bands):
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
            (id, version) = nativeaot_pack(tfm, rid, bands = bands)
            packages.append((id, version))
            targets.append({
                "name": rid,
                "pack_files": "@{}//:files".format(nuget_archive_name(id, version)),
            })

        build_files["{}/BUILD.bazel".format(tfm)] = _build_file("nativeaot", targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def band_fact_key(sdk_version, tfm):
    """Returns the key the version of a band for an SDK is remembered under.

    Args:
      sdk_version: The SDK version.
      tfm: The band's target framework.

    Returns:
      The fact key.
    """
    return "pack-band/{}:{}/{}".format(_FACT_VERSION, sdk_version, tfm)

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
        answered = package_versions(module_ctx, NUGET_ORG, missing, netrc_entries, indexes) or {}
        for id in missing:
            cache[id.lower()] = answered.get(id.lower())

    return [cache[id.lower()] for id in ids]

def _band_versions(module_ctx, sdk, netrc_entries, indexes, releases, published, facts):
    """Returns the version each band from .NET 6 onwards is at for an SDK.

    An SDK compiles against the packs of what had shipped by the day it did:
    its own band at its own runtime, and every other band at the newest patch
    out by then, which is what the SDK itself bundles, give or take a release
    the metadata dates late. A band that had not shipped yet gets its first
    release. A patch whose packs were never published gives way to the newest
    one before it that was.

    The SDK version alone decides each band, so each is remembered as a fact,
    except a step back that a later patch has yet to show is for good: the
    packs of a patch can reach the feed after the release metadata does.

    Args:
      module_ctx: The module extension context.
      sdk: The SDK, from `resolve_sdk`.
      netrc_entries: Credentials for the package feed.
      indexes: Feed index cache, shared across calls.
      releases: Release metadata cache, shared across calls.
      published: Version lists cache, shared across calls.
      facts: The facts to hand back to Bazel, which this call adds to.

    Returns:
      The version of each band in `SDK_BAND_TFMS`, by target framework.
    """
    remembered = getattr(module_ctx, "facts", {})
    versions = {}

    for tfm in SDK_BAND_TFMS:
        version = remembered.get(band_fact_key(sdk.version, tfm))
        if type(version) == "string" and version:
            versions[tfm] = version
            facts[band_fact_key(sdk.version, tfm)] = version

    pending = [tfm for tfm in SDK_BAND_TFMS if tfm not in versions]
    if not pending:
        return versions

    channels = {tfm: tfm_channel(tfm) for tfm in pending}
    shipped = runtimes_shipped_by(
        module_ctx,
        releases,
        [channel for channel in channels.values() if channel != sdk.channel],
        sdk.release_date,
    )
    shipped[sdk.channel] = sdk.runtime_version

    # Looked up together, so that the feed is asked once.
    _published_versions(
        module_ctx,
        collections.uniq([id for tfm in pending for id in _reference_packs(tfm)]),
        netrc_entries,
        indexes,
        published,
    )

    for tfm in pending:
        channel = channels[tfm]
        first = channel + ".0"
        target = shipped.get(channel) or first
        lists = _published_versions(module_ctx, _reference_packs(tfm), netrc_entries, indexes, published)

        if None in lists:
            # No fact, so that a feed that did not answer does not pin the
            # band for every later evaluation.
            versions[tfm] = target
            continue

        # A preview SDK of a released channel falls back to the release where
        # the preview's packs do not share a version.
        version = newest_shared_release(channel, target, lists) or newest_shared_release(channel, first, lists)
        if version == None:
            fail("NuGet has no version of {} at or before {} that is in all of {}, which .NET SDK {} needs.".format(
                tfm,
                target,
                ", ".join(_reference_packs(tfm)),
                sdk.version,
            ))

        versions[tfm] = version
        if version == target or is_superseded(channel, target, lists):
            facts[band_fact_key(sdk.version, tfm)] = version

    return versions

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

    bands = pack_bands(_band_versions(module_ctx, sdk, netrc_entries, indexes, releases, published, facts))
    bootstrap_bands = bands
    if bootstrap.version != sdk.version:
        bootstrap_bands = pack_bands(_band_versions(module_ctx, bootstrap, netrc_entries, indexes, releases, published, facts))

    kinds = [
        (TARGETING_PACK_REPO, _targeting({
            USER_PACKS: bands,
            BOOTSTRAP_PACKS: bootstrap_bands,
        })),
        (RUNTIME_PACK_REPO, _runtime(bands)),
        (APPHOST_PACK_REPO, _apphost(bands)),
        (CROSSGEN2_PACK_REPO, _host_tool("crossgen2", crossgen2_pack, bands)),
        # ilc and the NativeAOT pack ship together at the band's version, as
        # the SDK bundles them.
        (ILCOMPILER_PACK_REPO, _host_tool("ilcompiler", ilcompiler_pack, bands)),
        (NATIVEAOT_PACK_REPO, _nativeaot(bands)),
        (WASM_PACK_REPO, _wasm(bands)),
    ]

    # The kinds cannot share a package: their ids end in `.Ref`,
    # `.Runtime.<rid>`, `.Host.<rid>`, `.Crossgen2.<rid>` and
    # `.Runtime.NativeAOT.<rid>`, and ILCompiler packs are `runtime.<rid>.*`.
    packages = [pack for (_, kind) in kinds for pack in kind.packages]

    resolved = {}
    resolve_integrity_cached(
        module_ctx,
        [NUGET_ORG],
        [struct(id = id, version = version) for (id, version) in packages],
        netrc_entries,
        resolved,
        indexes,
    )

    declared = {}
    for (repo, kind) in kinds:
        hub = [
            {
                "id": id,
                "name": "{}.v{}".format(id.lower(), version),
                "sha512": resolved.get(integrity_fact_key(id, version), ""),
                "sources": [NUGET_ORG],
                "version": version,
            }
            for (id, version) in kind.packages
        ]
        nuget_archives(hub, declared)
        nuget_hub_repo(repo, hub, extra_build_files = kind.build_files)

    return facts | resolved
