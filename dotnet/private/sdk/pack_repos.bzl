"""Declares the repositories that hold the SDK's packs and native tools.

Each repository groups its packages behind targets named for what they provide
(`@dotnet.targeting_packs//user/default:net10.0`), so labels do not move when
the versions in `PACK_BANDS` change.
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
    "aot_pack_rids",
    "aot_pack_tfms",
    "apphost_pack",
    "band_is_movable",
    "crossgen2_pack",
    "host_rids",
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
load("//dotnet/private/sdk:versions.bzl", "TOOL_VERSIONS")

NUGET_ORG = "https://api.nuget.org/v3/index.json"

_HEADER = """\
"GENERATED"

load("@rules_dotnet//dotnet/private/sdk/{kind}_packs:{kind}_pack.bzl", "{kind}_pack")

package(default_visibility = ["//visibility:public"])\
"""

def _retarget(packs, version):
    """Moves a band's packs onto `version`, or leaves them alone if None."""
    if version == None:
        return packs

    return [(id, version) for (id, _) in packs]

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

def _targeting(versions_by_pack_set):
    """One package per (pack set, project SDK), each at its own band.

    Args:
      versions_by_pack_set: The version each band moves to, by target framework,
        for each pack set.

    Returns:
      A struct of build files and the packages they reference.
    """
    packages = []
    build_files = {}

    for (pack_set, versions) in versions_by_pack_set.items():
        for project_sdk in PROJECT_SDKS:
            targets = []

            for tfm in targeting_pack_tfms(project_sdk):
                packs = _retarget(targeting_packs(tfm, project_sdk), versions.get(tfm))
                packages += packs
                targets.append({
                    "name": tfm,
                    "packs": [nuget_package_label(id, version) for (id, version) in packs],
                    "target_framework": tfm,
                })

            build_files["{}/{}/BUILD.bazel".format(pack_set, project_sdk)] = _build_file("targeting", targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _runtime(versions):
    packages = []
    build_files = {}

    for project_sdk in PROJECT_SDKS:
        for tfm in runtime_pack_tfms():
            targets = []

            for rid in runtime_pack_rids(tfm, project_sdk):
                packs = _retarget(runtime_packs(tfm, rid, project_sdk), versions.get(tfm))
                packages += packs
                targets.append({
                    "name": rid,
                    "packs": [nuget_package_label(id, version) for (id, version) in packs],
                    "runtime_identifier": rid,
                    "target_framework": tfm,
                })

            build_files["{}/{}/BUILD.bazel".format(project_sdk, tfm)] = _build_file("runtime", targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _wasm(versions):
    """What a Blazor WebAssembly publish needs, per target framework.

    There is one target per framework rather than per runtime identifier,
    because a browser is the only target. The runtime pack reuses the
    `runtime_pack` rule, since it carries the same mix of managed assemblies and
    native files as any other; the tools are just their archives' file lists.
    """
    packages = []
    build_files = {}

    for tfm in wasm_pack_tfms():
        (id, version) = _retarget([wasm_runtime_pack(tfm)], versions.get(tfm))[0]
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

        for (name, (tool_id, tool_version)) in wasm_tool_packs(tfm):
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

def _apphost(versions):
    packages = []
    build_files = {}

    for tfm in runtime_pack_tfms():
        targets = []

        for rid in runtime_pack_rids(tfm):
            (id, version) = _retarget([apphost_pack(tfm, rid)], versions.get(tfm))[0]
            packages.append((id, version))
            targets.append({
                "name": rid,
                "pack": nuget_package_label(id, version),
                "runtime_identifier": rid,
                "target_framework": tfm,
            })

        build_files["{}/BUILD.bazel".format(tfm)] = _build_file("apphost", targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _host_tool(kind, pack, versions):
    """One target per host runtime identifier, selecting its pack by framework.

    The tool is picked by the machine the build runs on while the framework
    comes from the configuration, and a rule attribute cannot select on both.

    Args:
      kind: The pack rule's name, which also names the `.bzl` file it lives in.
      pack: Returns the (id, version) of the tool's pack for a tfm and host rid,
        or None where the tool did not ship for that combination.
      versions: The version to move each band's packs to, by target framework.

    Returns:
      A struct of build files and the packages they reference.
    """
    packages = []
    targets = []

    for rid in host_rids():
        by_tfm = {}

        for tfm in runtime_pack_tfms():
            found = pack(tfm, rid)

            if found == None:
                continue

            (id, version) = found
            version = versions.get(tfm) or version
            packages.append((id, version))

            # The tool is a native executable with its JIT libraries beside it,
            # none of which the package rules classify, so the pack reads the
            # archive's file list directly.
            by_tfm["@rules_dotnet//dotnet:tfm_{}".format(tfm)] = "@{}//:files".format(nuget_archive_name(id, version))

        if by_tfm:
            # Nothing sets a target framework outside a tfm transition, so the
            # target still has to resolve without one. Bands come oldest first,
            # so this is the newest the tool shipped for.
            by_tfm["//conditions:default"] = by_tfm.values()[-1]

        targets.append({
            "name": rid,
            "pack_files": by_tfm,
        })

    return struct(
        # Not the root BUILD: the hub writes its own there.
        build_files = {"tool/BUILD.bazel": _build_file(kind, targets)},
        packages = collections.uniq(packages),
    )

def _nativeaot():
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
            (id, version) = nativeaot_pack(tfm, rid)
            packages.append((id, version))
            targets.append({
                "name": rid,
                "pack_files": "@{}//:files".format(nuget_archive_name(id, version)),
            })

        build_files["{}/BUILD.bazel".format(tfm)] = _build_file("nativeaot", targets)

    return struct(build_files = build_files, packages = collections.uniq(packages))

def _band_versions(module_ctx, sdk_version, netrc_entries, indexes):
    """Returns the version an SDK moves its band's packs to, by target framework.

    Compiling against the reference pack that ships with the SDK in use is what
    MSBuild does, and one SDK is registered per toolchain type, so an SDK moves
    exactly one band. Every other band is left where the table puts it, as is
    one whose reference pack was never published for that patch.

    Args:
      module_ctx: The module extension context.
      sdk_version: The SDK version whose band to move, or None.
      netrc_entries: Credentials for the package feed.
      indexes: Feed index cache, shared across calls.

    Returns:
      A struct of the facts looked up and the version to move to, by framework.
    """
    sdk = TOOL_VERSIONS.get(sdk_version) if sdk_version else None

    if sdk == None or not band_is_movable(sdk["runtimeTfm"]):
        return struct(facts = {}, versions = {})

    tfm = sdk["runtimeTfm"]
    runtime_version = sdk["runtimeVersion"]
    (ref_id, _) = targeting_packs(tfm)[0]
    key = "pack/v1:{}/{}".format(ref_id.lower(), runtime_version)
    published = getattr(module_ctx, "facts", {}).get(key)

    if published == None:
        # The reference pack stops being serviced first, so it stands in for
        # the whole band.
        published = runtime_version in package_versions(
            module_ctx,
            NUGET_ORG,
            ref_id,
            netrc_entries,
            indexes,
        )

    return struct(
        facts = {key: published},
        versions = {tfm: runtime_version} if published else {},
    )

def declare_pack_repos(module_ctx, sdk_version, bootstrap_version):
    """Declares the repositories holding the SDK's packs.

    The two SDKs move their own targeting pack set and nothing else, so neither
    decides what the other compiles against. Only the registered SDK has runtime,
    apphost and crossgen2 packs: rules_dotnet's own tools are never published.

    Args:
      module_ctx: The module extension context.
      sdk_version: The registered .NET SDK version, or None.
      bootstrap_version: The SDK version that builds rules_dotnet's own tools,
        or None.

    Returns:
      The facts to hand back to Bazel, so that the versions and hashes looked
      up here are reused by later evaluations.
    """
    netrc_entries = read_netrc_entries(module_ctx, None)
    indexes = {}

    bands = _band_versions(module_ctx, sdk_version, netrc_entries, indexes)
    bootstrap = _band_versions(module_ctx, bootstrap_version, netrc_entries, indexes)
    kinds = [
        (TARGETING_PACK_REPO, _targeting({
            USER_PACKS: bands.versions,
            BOOTSTRAP_PACKS: bootstrap.versions,
        })),
        (RUNTIME_PACK_REPO, _runtime(bands.versions)),
        (APPHOST_PACK_REPO, _apphost(bands.versions)),
        (CROSSGEN2_PACK_REPO, _host_tool("crossgen2", crossgen2_pack, bands.versions)),
        # ilc and the NativeAOT pack are versioned together and never mixed
        # with the JIT packs, so a registered SDK does not move them.
        (ILCOMPILER_PACK_REPO, _host_tool("ilcompiler", ilcompiler_pack, {})),
        (NATIVEAOT_PACK_REPO, _nativeaot()),
        (WASM_PACK_REPO, _wasm(bands.versions)),
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

    return bands.facts | bootstrap.facts | resolved
