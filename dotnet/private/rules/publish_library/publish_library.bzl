"""Rule for assembling the publish output of a .NET library or plugin."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "generate_depsjson",
    "get_portable_assets",
    "is_core_framework",
    "is_from_nuget_package",
    "is_netframework",
    "netframework_runtime_identifier",
    "runtime_frameworks",
    "select_runtime_variants",
)
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
)
load(
    "//dotnet/private/rules/common:publish_layout.bzl",
    "collect_assembly_files",
    "publish_layout",
    "reject_conflicting_paths",
)
load("//dotnet/private/rules/publish_binary:copy_script.bzl", "declare_like", "run_copy_script")
load("//dotnet/private/sdk:packs.bzl", "WINDOWS_ONLY_FRAMEWORKS")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "FRAMEWORK_FROM_CONSUMER",
    "NO_READY_TO_RUN",
    "TFM_RID_TRANSITION_OUTPUTS",
    "platform_to_rid",
    "rid_compatability_transition_outputs",
)

_LAYERS = ["third_party", "first_party", "app"]

def _publish_library_transition_impl(settings, attr):
    tfm = attr.target_framework
    if tfm not in FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS:
        fail("{}: unknown target framework {}. Allowed values are {}".format(
            attr.name,
            tfm,
            ", ".join(FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS.keys()),
        ))

    incoming_rid = settings["//dotnet:rid"]
    if attr.runtime_identifier:
        rid = attr.runtime_identifier
    elif incoming_rid != "base":
        rid = incoming_rid
    else:
        rid = platform_to_rid()
        if is_netframework(tfm):
            rid = netframework_runtime_identifier(rid)

    return dicts.add(
        {"//dotnet:target_framework": tfm, "//dotnet:rid": rid, FRAMEWORK_FROM_CONSUMER: True},
        FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[tfm],
        rid_compatability_transition_outputs(rid),
        NO_READY_TO_RUN,
    )

publish_library_transition = transition(
    implementation = _publish_library_transition_impl,
    inputs = ["//dotnet:rid"],
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)

def _reject_runtime_specific_natives(runtime_info, transitive_runtime_deps, label):
    """Fails when a portable library publish depends on workspace-built native libraries."""
    for info in [runtime_info] + transitive_runtime_deps:
        if not info.native or get_portable_assets(info, True):
            continue

        fail(("{}: {} depends on {}, whose native libraries ({}) exist for the runtime " +
              "being built alone. Set `runtime_identifier` to publish for a single runtime, " +
              "or depend on NuGet packages that carry native libraries for every runtime.").format(
            label,
            runtime_info.name,
            info.name,
            ", ".join(sorted({str(file.owner) if file.owner else file.path: None for file in info.native}.keys())),
        ))

def _excluded_names(ctx, library, runtime_info):
    """The assembly names in the runtime closure of `exclude_deps`."""
    excluded = {}
    for target in ctx.attr.exclude_deps:
        info = target[DotnetAssemblyRuntimeInfo]
        excluded[info.name] = target.label
        for transitive in info.deps.to_list():
            excluded.setdefault(transitive.name, target.label)

    if runtime_info.name in excluded:
        fail("{}: `exclude_deps` excludes {} itself (via {})".format(
            ctx.label,
            library.label,
            excluded[runtime_info.name],
        ))

    return excluded

def _dependency_layers(transitive_runtime_deps):
    """The layer of each dependency's files, keyed by path."""
    layers = {}

    for dep in transitive_runtime_deps:
        layer = "third_party" if is_from_nuget_package(dep) else "first_party"
        files = dep.libs + dep.native + dep.resource_assemblies + dep.data
        portable = get_portable_assets(dep, True)
        if portable:
            files = files + portable.libs + [asset.file for asset in portable.runtime_targets]

        for file in files:
            layers[file.path] = layer

    return layers

def _publish_output_groups(ctx, subdir, entries, dependency_layers):
    """Declares the `publish_dir` directory and `<layer>_layer` directories."""
    layers = {layer: [] for layer in _LAYERS}
    all_copies = []

    for path in sorted(entries):
        file = entries[path]
        all_copies.append((file, path))
        layers[dependency_layers.get(file.path, "app")].append((file, path))

    publish_dir = ctx.actions.declare_directory("{}/publish_dir/{}".format(ctx.label.name, subdir))
    run_copy_script(
        ctx,
        all_copies,
        "publish_dir",
        "DotnetPublishDirectory",
        "Assembling publish directory for %{label}",
        directory = publish_dir,
    )

    output_groups = {"publish_dir": depset([publish_dir])}

    for (layer, copies) in layers.items():
        directory = ctx.actions.declare_directory("{}/layers/{}".format(ctx.label.name, layer))
        run_copy_script(
            ctx,
            copies,
            "layer_" + layer,
            "DotnetPublishLayer",
            "Assembling the {} layer of %{{label}}".format(layer),
            directory = directory,
        )
        output_groups[layer + "_layer"] = depset([directory])

    return output_groups

def _publish_library_impl(ctx):
    library = ctx.attr.library[0]
    compile_info = library[DotnetAssemblyCompileInfo]
    runtime_info = library[DotnetAssemblyRuntimeInfo]
    target_framework = ctx.attr.target_framework
    runtime_identifier = ctx.attr.runtime_identifier or None
    portable = runtime_identifier == None

    if compile_info.target_framework == None:
        fail("{}: {} is an imported assembly. `publish_library` publishes a csharp_library or fsharp_library.".format(
            ctx.label,
            library.label,
        ))

    if compile_info.target_framework != target_framework:
        fail(("{}: asks {} for {}, but that target builds {}: the highest of its target_frameworks " +
              "that {} can use. Add {} to its target_frameworks, or change target_framework.").format(
            ctx.label,
            library.label,
            target_framework,
            compile_info.target_framework,
            target_framework,
            target_framework,
        ))

    if not runtime_info.libs:
        fail("{}: {} builds no assembly to publish".format(ctx.label, library.label))

    if is_netframework(target_framework) and runtime_identifier and not runtime_identifier.startswith("win"):
        fail(("{}: {} targets .NET Framework, which only runs on Windows, so it cannot be " +
              "published for runtime identifier {}. Set `runtime_identifier` to a Windows " +
              "one, such as win-x64, or leave it unset.").format(ctx.label, library.label, repr(runtime_identifier)))

    excluded_names = _excluded_names(ctx, library, runtime_info)
    transitive_runtime_deps = select_runtime_variants([
        dep
        for dep in runtime_info.deps.to_list()
        if dep.name not in excluded_names
    ])

    windows_only = [framework for framework in runtime_frameworks(runtime_info, transitive_runtime_deps) if framework in WINDOWS_ONLY_FRAMEWORKS]
    if windows_only and runtime_identifier and not runtime_identifier.startswith("win"):
        fail("{}: {} runs on {}, which only exists on Windows. Set `runtime_identifier` to a Windows one, such as win-x64, or leave it unset.".format(
            ctx.label,
            library.label,
            ", ".join(windows_only),
        ))

    if portable:
        _reject_runtime_specific_natives(runtime_info, transitive_runtime_deps, ctx.label)

    depsjson_struct = generate_depsjson(
        ctx,
        target_framework = target_framework,
        is_self_contained = False,
        target_assembly_runtime_info = runtime_info,
        transitive_runtime_deps = transitive_runtime_deps,
        portable = portable,
    )

    if excluded_names:
        for target_fragment in depsjson_struct["targets"].values()[0].values():
            target_fragment["dependencies"] = {
                name: version
                for (name, version) in target_fragment.get("dependencies", {}).items()
                if name not in excluded_names
            }

    assembly_files = collect_assembly_files(
        ctx.label,
        runtime_info,
        transitive_runtime_deps,
        depsjson_struct,
        portable = portable,
    )
    layout = publish_layout(None, assembly_files, [])
    reject_conflicting_paths(layout, ctx.label, content_files = assembly_files.content_files)

    subdir = runtime_identifier if runtime_identifier else target_framework
    root = "{}/publish/{}".format(ctx.label.name, subdir)
    entries = {path: file for (path, file) in layout}

    copies = [
        (file, declare_like(ctx, file, "{}/{}".format(root, path)))
        for (path, file) in entries.items()
    ]
    outputs = run_copy_script(
        ctx,
        copies,
        "copy",
        "DotnetPublishCopy",
        "Assembling publish output for %{label}",
    )

    depsjson_files = []
    if ctx.attr.include_deps_json and is_core_framework(target_framework):
        depsjson = ctx.actions.declare_file("{}/{}.deps.json".format(root, runtime_info.name))
        ctx.actions.write(
            output = depsjson,
            content = json.encode(depsjson_struct),
        )
        depsjson_files.append(depsjson)
        entries[depsjson.basename] = depsjson

    output_groups = _publish_output_groups(
        ctx,
        subdir,
        entries,
        _dependency_layers(transitive_runtime_deps),
    )

    return [
        DefaultInfo(
            files = depset(depsjson_files + outputs),
            runfiles = ctx.runfiles(files = assembly_files.data),
        ),
        OutputGroupInfo(**output_groups),
    ]

publish_library = rule(
    _publish_library_impl,
    doc = """Publish a .NET library and its runtime dependencies to a directory layout.

Produces the flat publish layout of `dotnet publish` on a class library (and
`<EnableDynamicLoading>true</EnableDynamicLoading>` on .NET Core / .NET 5+):
the library's assembly and its transitive runtime dependencies at the root,
satellite resource assemblies under `<locale>/`, and native libraries under
`runtimes/<rid>/native/` (plus `runtimes/<rid>/lib/<tfm>/` when portable).
Unlike `publish_binary`, `publish_library` is not executable and emits no
apphost shim or `runtimeconfig.json`, as a library runs inside an existing host
process.

When `runtime_identifier` is omitted, the publish is portable and carries every
runtime identifier's assets from NuGet packages under `runtimes/<rid>/`. When
`runtime_identifier` is set, only that runtime's assets (including
workspace-built native libraries) are included.

For plugins and add-ins that load into a host application (`AssemblyLoadContext`
on .NET Core, `AppDomain` on .NET Framework, VSIX extensions, MSBuild tasks),
`exclude_deps` excludes the runtime closures of assemblies the host already
provides, matching MSBuild's `<ProjectReference Private="false" ExcludeAssets="runtime" />`.

### Output groups

| Name | Contents |
| --- | --- |
| `publish_dir` | The complete published layout as a single directory artifact. |
| `third_party_layer` | Directory containing NuGet package runtime assets. |
| `first_party_layer` | Directory containing workspace dependency runtime assets. |
| `app_layer` | Directory containing the library's own assembly, content files, and `.deps.json`. |""",
    attrs = {
        "library": attr.label(
            doc = "The .NET library (`csharp_library` or `fsharp_library`) to publish.",
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
            cfg = publish_library_transition,
            mandatory = True,
        ),
        "target_framework": attr.string(
            doc = "The target framework moniker that should be published.",
            mandatory = True,
        ),
        "runtime_identifier": attr.string(
            doc = """The runtime identifier to publish for. When unset, the publish is
            portable and carries every runtime identifier's assets from NuGet packages
            under `runtimes/<rid>/`.""",
            default = "",
        ),
        "exclude_deps": attr.label_list(
            doc = """Dependencies whose runtime closures are already provided by the host
            process and should be excluded from the published output and `deps.json`,
            matching MSBuild's `<ProjectReference Private="false" ExcludeAssets="runtime" />`
            or `<PackageReference ExcludeAssets="runtime" />`.""",
            providers = [DotnetAssemblyRuntimeInfo],
            cfg = publish_library_transition,
        ),
        "include_deps_json": attr.bool(
            doc = """Whether to emit `<library>.deps.json` when publishing for .NET Core /
            .NET 5+ (mirroring MSBuild's `<EnableDynamicLoading>true</EnableDynamicLoading>`
            for `AssemblyDependencyResolver`). Ignored on .NET Framework and .NET Standard,
            which do not use `deps.json`.""",
            default = True,
        ),
    },
    toolchains = ["//dotnet/toolchain:toolchain_type"],
    executable = False,
)
