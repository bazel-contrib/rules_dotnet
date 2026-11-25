"""
Rule for assembling the publish output of a .NET binary.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("//dotnet/private:common.bzl", "generate_depsjson", "generate_runtimeconfig", "is_from_nuget_package", "netframework_runtime_identifier", "select_runtime_variants", "tfm_to_semver", "tfm_version", "to_rlocation_path")
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "DotnetBinaryInfo",
    "DotnetNativeToolsInfo",
)
load(
    "//dotnet/private/rules/blazor:blazor_wasm_publish.bzl",
    "blazor_wasm_publish",
)
load(
    "//dotnet/private/rules/blazor:common.bzl",
    "APPLICATION_ENVIRONMENT_DOC",
    "INVARIANT_GLOBALIZATION_DOC",
    "TRIM_MODES",
    "TRIM_MODE_DOC",
)
load(
    "//dotnet/private/rules/common:publish_layout.bzl",
    "collect_assembly_files",
    "publish_content_files",
    "publish_layout",
    "reject_conflicting_paths",
)
load("//dotnet/private/rules/publish_binary:copy_script.bzl", "declare_like", "run_copy_script")
load("//dotnet/private/rules/publish_binary:native_aot.bzl", "NATIVE_AOT_MIN_MAJOR_VERSION", "native_aot_executable")
load(
    "//dotnet/private/rules/ready_to_run:ready_to_run.bzl",
    "compile_ready_to_run",
    "crossgen2_args",
    "native_target",
    "ready_to_run_framework",
    "ready_to_run_references",
)
load("//dotnet/private/sdk:packs.bzl", "WASM_RID", "WINDOWS_ONLY_FRAMEWORKS")
load("//dotnet/private/sdk/runtime_packs:runtime_pack.bzl", "runtime_pack_of_frameworks")
load("//dotnet/private/transitions:tfm_transition.bzl", "publish_binary_transition", "tfm_transition")

def _binary(ctx):
    return ctx.split_attr.binary["binary"]

def _native_tools(ctx):
    """The native compiler the binary resolved for its own framework."""
    return ctx.split_attr.binary["native_tools"][DotnetNativeToolsInfo]

def _publish_binary_impl(ctx):
    # .NET Framework runs the binary from its output directory, on the
    # framework installed in Windows.
    if _binary(ctx)[DotnetBinaryInfo].netfx_layout != None:
        return _netfx_publish(ctx)

    _check_attributes(ctx)
    publish = _publish_inputs(ctx)
    _check_runtime(ctx, publish)

    if ctx.attr.native_aot:
        return _native_aot_publish(ctx, publish)

    managed = _managed_files(ctx, publish)

    if ctx.attr.single_file:
        return _single_file_publish(ctx, publish, managed)

    return _directory_publish(ctx, publish, managed)

def _check_attributes(ctx):
    attr = ctx.attr

    if attr.ready_to_run_composite and not (attr.ready_to_run and attr.self_contained):
        fail("ready_to_run_composite requires ready_to_run and self_contained")

    if attr.native_aot and attr.ready_to_run:
        fail("native_aot cannot be combined with ready_to_run: it compiles ahead of time already")

    # ilc comes from the band of the framework the binary is built for, which
    # can be lower than the one the publish asks for.
    binary_framework = _binary(ctx)[DotnetAssemblyCompileInfo].target_framework
    if attr.native_aot and tfm_version(binary_framework)[0] < NATIVE_AOT_MIN_MAJOR_VERSION:
        fail("{}: native_aot needs .NET {} or later, but {} is built for {}.".format(
            ctx.label,
            NATIVE_AOT_MIN_MAJOR_VERSION,
            _binary(ctx).label,
            binary_framework,
        ))

    if attr.single_file and not attr.self_contained:
        fail("single_file requires self_contained")

    if attr.single_file and attr.native_aot:
        fail("single_file cannot be combined with native_aot: NativeAOT produces a single native binary already")

    if (attr.include_native_libraries_for_self_extract or attr.enable_compression_in_single_file) and not attr.single_file:
        fail("include_native_libraries_for_self_extract and enable_compression_in_single_file require single_file")

    # The SDK refuses to trim Windows Forms and WPF, and NativeAOT trims.
    windows_only = _windows_only_frameworks(_binary(ctx)[DotnetBinaryInfo])
    if attr.native_aot and windows_only:
        fail("{}: native_aot cannot publish {}, which runs on {}: Windows Forms and WPF do not support trimming, which NativeAOT implies.".format(
            ctx.label,
            _binary(ctx).label,
            ", ".join(windows_only),
        ))

def _windows_only_frameworks(binary_info):
    return [framework for framework in binary_info.runtime_frameworks if framework in WINDOWS_ONLY_FRAMEWORKS]

def _publish_inputs(ctx):
    """What every kind of publish starts from."""
    binary = _binary(ctx)
    binary_info = binary[DotnetBinaryInfo]
    compile_info = binary[DotnetAssemblyCompileInfo]

    return struct(
        binary_info = binary_info,
        assembly_info = binary[DotnetAssemblyRuntimeInfo],
        # One configuration of each library, the one the deps.json lists, so
        # that a library built for two frameworks is published once.
        transitive_runtime_deps = select_runtime_variants(binary_info.transitive_runtime_deps),
        # The framework the binary is built for, and so runs on, whatever
        # framework the publish asked for.
        binary_framework = compile_info.target_framework,
        runtime_identifier = ctx.attr.runtime_identifier or binary_info.runtime_pack_info.runtime_identifier,
        # Only a self-contained publish ships the runtime: the shared frameworks
        # the binary and its dependencies reference, as MSBuild publishes them.
        runtime_pack_info = runtime_pack_of_frameworks(binary_info.runtime_pack_info, binary_info.runtime_frameworks) if ctx.attr.self_contained else None,
    )

def _check_runtime(ctx, publish):
    """Checks that the publish can target, and ship, the runtime the binary runs on."""
    binary = _binary(ctx).label

    windows_only = _windows_only_frameworks(publish.binary_info)
    if windows_only and not publish.runtime_identifier.startswith("win"):
        fail("{}: {} runs on {}, which only exists on Windows. Set `runtime_identifier` to a Windows one, such as win-x64.".format(
            ctx.label,
            binary,
            ", ".join(windows_only),
        ))

    if not publish.runtime_identifier or (publish.runtime_pack_info and not publish.runtime_pack_info.assembly_runtime_infos):
        fail("No runtime pack found for target framework {} and runtime identifier {}".format(
            ctx.attr.target_framework,
            ctx.attr.runtime_identifier or "<host>",
        ))


def _native_aot_publish(ctx, publish):
    """One native executable, with what it loads or serves at run time beside it."""
    assembly_info = publish.assembly_info
    parts = [assembly_info] + publish.transitive_runtime_deps

    executable = native_aot_executable(
        ctx,
        _native_tools(ctx),
        publish.binary_info.dll,
        [lib for part in parts for lib in part.libs],
        publish.runtime_identifier,
        ctx.attr.target_framework,
        publish.binary_framework,
        publish.binary_info.winexe,
    )

    # Nothing managed survives the compile: no deps.json, runtimeconfig or
    # apphost. Native libraries are still loaded at run time.
    content_files = publish_content_files(ctx.label, assembly_info, publish.transitive_runtime_deps)
    beside = [(file.basename, file) for part in parts for file in part.native] + [
        (file.basename, file)
        for file in assembly_info.appsetting_files.to_list()
    ] + [
        (entry.dest, entry.file)
        for entry in content_files
    ] + [
        (entry.publish_path, entry.file)
        for entry in publish.binary_info.static_web_files
    ]
    reject_conflicting_paths(beside, ctx.label, content_files = content_files)

    # The runtime is compiled into the executable, so its layer stays empty.
    return _executable_publish(
        ctx,
        executable,
        beside,
        [file for part in parts for file in part.data],
        _dependency_layers(publish.transitive_runtime_deps, None),
    )

def _managed_files(ctx, publish):
    """The files of a publish that runs on the .NET host, and where each goes.

    Returns:
        A struct of the `depsjson` and `runtimeconfig` written for the publish,
        the `assembly_files` and `runtime_pack_files` it ships, their `layout`,
        the `ready_to_run` images replacing assemblies, and the `layers` of the
        dependencies' files.
    """

    # A single-file publish bundles both, so they stay out of its directory.
    meta_dir = "{}/{}/{}".format(ctx.label.name, "bundle" if ctx.attr.single_file else "publish", publish.runtime_identifier)

    depsjson = ctx.actions.declare_file("{}/{}.deps.json".format(meta_dir, publish.assembly_info.name))
    depsjson_struct = generate_depsjson(
        ctx,
        ctx.attr.target_framework,
        ctx.attr.self_contained,
        publish.assembly_info,
        publish.transitive_runtime_deps,
        publish.runtime_pack_info,
    )
    ctx.actions.write(output = depsjson, content = json.encode(depsjson_struct))

    runtimeconfig = ctx.actions.declare_file("{}/{}.runtimeconfig.json".format(meta_dir, publish.assembly_info.name))
    ctx.actions.write(
        output = runtimeconfig,
        content = json.encode(generate_runtimeconfig(
            ctx.attr.target_framework,
            publish.binary_info.runtime_frameworks,
            ctx.attr.self_contained,
            ctx.attr.roll_forward_behavior,
            publish.runtime_pack_info,
            publish.binary_info.framework_version,
        )),
    )

    assembly_files = collect_assembly_files(ctx.label, publish.assembly_info, publish.transitive_runtime_deps, depsjson_struct)
    runtime_pack_files = _runtime_pack_files(publish.runtime_pack_info, depsjson_struct)
    layout = publish_layout(publish.runtime_identifier, publish.binary_info, assembly_files, runtime_pack_files, ctx.attr.self_contained)

    # Before any ReadyToRun or copy action is declared, so that a collision
    # names the targets at fault rather than surfacing as conflicting actions.
    reject_conflicting_paths(layout, ctx.label, content_files = assembly_files.content_files)

    ready_to_run = _NO_READY_TO_RUN
    if ctx.attr.ready_to_run:
        ready_to_run = _ready_to_run_images(ctx, publish, assembly_files, runtime_pack_files)

    return struct(
        depsjson = depsjson,
        runtimeconfig = runtimeconfig,
        assembly_files = assembly_files,
        runtime_pack_files = runtime_pack_files,
        layout = layout,
        ready_to_run = ready_to_run,
        layers = _dependency_layers(publish.transitive_runtime_deps, publish.runtime_pack_info, ready_to_run),
    )

def _directory_publish(ctx, publish, managed):
    """A framework-dependent or self-contained publish: a directory started by an apphost."""
    root = "{}/publish/{}".format(ctx.label.name, publish.runtime_identifier)
    entries = _publish_entries(managed.layout, managed.ready_to_run)

    published = run_copy_script(
        ctx,
        [(file, declare_like(ctx, file, "{}/{}".format(root, path))) for (path, file) in entries.items()],
        "copy",
        "DotnetPublishCopy",
        "Assembling publish output for %{label}",
    )
    main_dll = ctx.actions.declare_file("{}/{}".format(root, publish.binary_info.dll.basename))

    apphost = ctx.actions.declare_file(_executable_name(main_dll, publish.runtime_identifier), sibling = main_dll)
    _stamp_host(
        ctx,
        publish.binary_info.apphost_pack_info.apphost,
        main_dll,
        apphost,
        publish.runtime_identifier,
        publish.binary_info.winexe,
        "DotnetApphostShim",
        "Creating apphost shim for %{label}",
    )

    output_groups = _publish_layers(
        ctx,
        dicts.add(
            entries,
            {file.basename: file for file in [apphost, managed.runtimeconfig, managed.depsjson]},
            _runfiles_entries(ctx, apphost, managed.assembly_files.data),
        ),
        managed.layers,
    )

    return [
        DefaultInfo(
            executable = apphost,
            files = depset([apphost, main_dll, managed.runtimeconfig, managed.depsjson] + published),
            # Data files are runfiles, not files at a relative path: the app
            # resolves them with the runfiles library, and packaging has to
            # carry runfiles along (`include_runfiles` on rules_pkg's
            # `pkg_tar`, for one).
            runfiles = ctx.runfiles(files = managed.assembly_files.data),
        ),
        OutputGroupInfo(**output_groups),
    ]

def _single_file_publish(ctx, publish, managed):
    """A self-contained publish bundled into one executable, as `PublishSingleFile` does."""
    files = managed.assembly_files
    runtime_libs = [lib for pack in managed.runtime_pack_files for lib in pack.libs]
    runtime_native = [file for pack in managed.runtime_pack_files for file in pack.native]

    # The runtime's own native libraries are linked into singlefilehost, as
    # their `DropFromSingleFile` marks in the pack's RuntimeList.xml say.
    dropped = {
        file: None
        for pack in managed.runtime_pack_files
        if pack.name.startswith("Microsoft.NETCore.App.Runtime.")
        for file in pack.native
    }
    native = [file for file in files.native + runtime_native if file not in dropped]

    # As MSBuild does: assemblies are bundled, native libraries only when
    # asked, and everything else stays beside the executable.
    bundled = {
        file: None
        for file in [publish.binary_info.dll] + files.libs + files.resource_assemblies + runtime_libs +
                    (native if ctx.attr.include_native_libraries_for_self_extract else [])
    }

    executable = _bundle(
        ctx,
        publish,
        dicts.add(
            _publish_entries([(path, file) for (path, file) in managed.layout if file in bundled], managed.ready_to_run),
            {file.basename: file for file in [managed.runtimeconfig, managed.depsjson]},
        ),
    )

    return _executable_publish(
        ctx,
        executable,
        [(path, file) for (path, file) in managed.layout if file not in bundled and file not in dropped],
        files.data,
        managed.layers,
    )

# Publish settings that only apply to .NET.
_NOT_FOR_NETFX = [
    "self_contained",
    "ready_to_run",
    "ready_to_run_composite",
    "native_aot",
    "single_file",
    "include_native_libraries_for_self_extract",
    "enable_compression_in_single_file",
]

def _netfx_publish(ctx):
    """A .NET Framework publish: the binary's output directory, without PDBs."""
    binary = _binary(ctx)
    binary_info = binary[DotnetBinaryInfo]
    transitive_runtime_deps = binary_info.transitive_runtime_deps

    for attribute in _NOT_FOR_NETFX:
        if getattr(ctx.attr, attribute):
            fail(("{}: `{}` does not apply to {}, which targets .NET Framework: the framework " +
                  "installed in Windows runs it.").format(ctx.label, attribute, binary.label))

    # The runtime identifier the binary was built for.
    runtime_identifier = ctx.attr.runtime_identifier
    if ctx.attr.runtime_identifier_from_platform:
        runtime_identifier = netframework_runtime_identifier(runtime_identifier)
    if not runtime_identifier.startswith("win"):
        fail(("{}: {} targets .NET Framework, which only runs on Windows, so it cannot be " +
              "published for runtime identifier {}. Set `runtime_identifier` to a Windows " +
              "one, such as win-x64, or leave it unset.").format(ctx.label, binary.label, repr(runtime_identifier)))

    reject_conflicting_paths(binary_info.netfx_layout, ctx.label)
    entries = _publish_entries(binary_info.netfx_layout)

    root = "{}/publish/{}".format(ctx.label.name, runtime_identifier)
    published = run_copy_script(
        ctx,
        [(file, declare_like(ctx, file, "{}/{}".format(root, path))) for (path, file) in entries.items()],
        "copy",
        "DotnetPublishCopy",
        "Assembling publish output for %{label}",
    )
    executable = ctx.actions.declare_file("{}/{}".format(root, binary_info.dll.basename))
    data = binary[DotnetAssemblyRuntimeInfo].data + [file for dep in transitive_runtime_deps for file in dep.data]

    # Run from its runfiles, the executable needs the files beside it there too.
    beside = [(path, file) for (path, file) in entries.items() if path != executable.basename]
    output_groups = _publish_layers(
        ctx,
        dicts.add(entries, _runfiles_entries(ctx, executable, data, beside = beside)),
        _dependency_layers(transitive_runtime_deps, None),
    )

    return [
        DefaultInfo(
            executable = executable,
            files = depset(published),
            runfiles = ctx.runfiles(files = published + data),
        ),
        OutputGroupInfo(**output_groups),
    ]

def _executable_publish(ctx, executable, beside, data, dependency_layers):
    """A publish that is one executable with files copied beside it.

    Args:
        ctx: The rule context.
        executable: The executable.
        beside: The (path, File) pairs to copy beside it. Where two take the
            same path the last wins, as in a publish directory.
        data: The data files, which travel as runfiles.
        dependency_layers: The layer of each dependency's files, from `_dependency_layers`.

    Returns:
        The DefaultInfo and OutputGroupInfo of the publish.
    """
    beside = _publish_entries(beside).items()

    sidecars = []
    if beside:
        sidecars = run_copy_script(
            ctx,
            [(file, declare_like(ctx, file, path, sibling = executable)) for (path, file) in beside],
            "sidecars",
            "DotnetCopySidecars",
            "Copying sidecars for %{label}",
        )

    # The sidecars are runfiles too. The layers copy them from their sources
    # rather than from beside the executable.
    output_groups = _publish_layers(
        ctx,
        dicts.add(
            _publish_entries(beside),
            {executable.basename: executable},
            _runfiles_entries(ctx, executable, data, beside = beside),
        ),
        dependency_layers,
    )

    return [
        DefaultInfo(
            executable = executable,
            files = depset([executable] + sidecars),
            runfiles = ctx.runfiles(files = sidecars + data),
        ),
        OutputGroupInfo(**output_groups),
    ]

def _runtime_pack_files(runtime_pack_info, deps_json_struct):
    """The files each runtime pack contributes to the publish, one struct per pack.

    A pack's file is left out when a user dependency overrides it, which drops
    it from the pack's deps.json target.
    """
    if not runtime_pack_info:
        return []

    targets = deps_json_struct["targets"].values()[0]
    packs = []

    for pack in runtime_pack_info.assembly_runtime_infos:
        target = targets.get("runtimepack.{}/{}".format(pack.name, pack.version)) or {}

        packs.append(struct(
            name = pack.name,
            libs = [file for file in pack.libs if file.basename in target.get("runtime", {})],
            native = [file for file in pack.native if file.basename in target.get("native", {})],
            data = pack.data,
        ))

    return packs

_NO_READY_TO_RUN = struct(replace = {}, extra = [])

def _publish_entries(layout, ready_to_run = _NO_READY_TO_RUN):
    """The file each publish path holds, with ReadyToRun images in place of their assemblies.

    Keyed by path, the last pair winning: the binary's own assembly arrives
    twice, and two packages may ship a file of the same name.
    """
    entries = {path: ready_to_run.replace.get(file.path, file) for (path, file) in layout}

    for file in ready_to_run.extra:
        entries[file.basename] = file

    return entries

def _executable_name(dll, runtime_identifier):
    """The name of the executable that starts `dll` on `runtime_identifier`."""
    return paths.replace_extension(dll.basename, ".exe" if runtime_identifier.startswith("win") else "")

def _stamp_host(ctx, host, dll, output, runtime_identifier, winexe, mnemonic, progress_message):
    """Copies a host (apphost or singlefilehost) to `output`, set to start `dll` from beside it.

    `winexe` gives it the Windows GUI subsystem, so that it starts without a console window.
    """
    ctx.actions.run(
        mnemonic = mnemonic,
        progress_message = progress_message,
        executable = ctx.attr._apphost_shimmer.files_to_run,
        arguments = [host.path, dll.basename, output.path, runtime_identifier, "true" if winexe else "false"],
        # Not the assembly, whose name is all the host records: depending on it
        # would tie the host, and so the app layer, to the whole publish copy.
        inputs = depset([host], transitive = [ctx.attr._apphost_shimmer.default_runfiles.files]),
        tools = [ctx.attr._apphost_shimmer.files, ctx.attr._apphost_shimmer.default_runfiles.files],
        outputs = [output],
    )

def _bundle_spec(entry):
    (path, file) = entry
    return "{}={}".format(path, file.path)

def _bundle(ctx, publish, bundle):
    """Appends files to a copy of singlefilehost that starts the binary.

    Args:
        ctx: The rule context.
        publish: The struct from `_publish_inputs`.
        bundle: The File to bundle at each path.

    Returns:
        The executable.
    """
    singlefilehost = publish.binary_info.apphost_pack_info.singlefilehost

    if singlefilehost == None:
        fail("The apphost pack for {} has no singlefilehost".format(publish.runtime_identifier))

    dll = publish.binary_info.dll
    name = _executable_name(dll, publish.runtime_identifier)

    # Stamped where the bundler does not write: it copies the host to the
    # executable's path before appending the bundle.
    host = ctx.actions.declare_file("{}/bundle/{}/{}".format(ctx.label.name, publish.runtime_identifier, name))
    _stamp_host(
        ctx,
        singlefilehost,
        dll,
        host,
        publish.runtime_identifier,
        publish.binary_info.winexe,
        "DotnetSingleFileHost",
        "Creating single-file host for %{label}",
    )

    executable = ctx.actions.declare_file("{}/publish/{}/{}".format(ctx.label.name, publish.runtime_identifier, name))

    # The runtime pack's identifier is portable, so it names the operating
    # system plainly where the publish's may name a distribution.
    (target_os, target_arch) = native_target(publish.runtime_pack_info.runtime_identifier)
    options = [
        option
        for (option, enabled) in [
            ("BundleNativeBinaries", ctx.attr.include_native_libraries_for_self_extract),
            ("EnableCompression", ctx.attr.enable_compression_in_single_file),
        ]
        if enabled
    ]

    args = ctx.actions.args()
    args.add("--bundle")
    args.add(host)
    args.add(executable)
    args.add(target_os)
    args.add(target_arch)

    # The bundle format is the binary's runtime's, which is what reads it.
    args.add(tfm_to_semver(publish.binary_framework))
    args.add(dll.basename.removesuffix(".dll"))
    args.add(", ".join(options) or "None")
    args.add_all(sorted(bundle.items()), map_each = _bundle_spec)
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run(
        mnemonic = "DotnetSingleFileBundle",
        progress_message = "Bundling %{label} into a single file",
        executable = ctx.attr._apphost_shimmer.files_to_run,
        arguments = [args],
        inputs = depset([host] + bundle.values(), transitive = [ctx.attr._apphost_shimmer.default_runfiles.files]),
        tools = [ctx.attr._apphost_shimmer.files, ctx.attr._apphost_shimmer.default_runfiles.files],
        outputs = [executable],
    )

    return executable

def _ready_to_run_images(ctx, publish, assembly_files, runtime_pack_files):
    """The ReadyToRun images of the published assemblies.

    Returns:
        A struct of `replace`, the image of each assembly keyed by the
        assembly's path, and `extra`, images published besides.
    """
    framework = ready_to_run_framework(publish.binary_info.runtime_pack_info)

    # Runtime pack assemblies already ship as ReadyToRun images; only a
    # composite image, which has to cover the framework, recompiles them.
    compiled = [publish.binary_info.dll] + assembly_files.libs
    if ctx.attr.ready_to_run_composite:
        compiled += [lib for pack in runtime_pack_files for lib in pack.libs]

    # By name, the last winning, as the layout does with two packages shipping
    # the same assembly.
    assemblies = {assembly.basename: assembly for assembly in compiled}.values()
    root = "{}/r2r/{}".format(ctx.label.name, publish.runtime_identifier)

    if ctx.attr.ready_to_run_composite:
        return _composite_image(ctx, publish, framework, assemblies, root + "/composite")

    return _per_assembly_images(ctx, publish, framework, assemblies, root)

def _composite_image(ctx, publish, framework, assemblies, directory):
    """Compiles one image covering every assembly, which each is rewritten to refer to."""
    crossgen2 = _native_tools(ctx).crossgen2
    image = ctx.actions.declare_file("{}/{}.r2r.dll".format(directory, publish.assembly_info.name))
    components = {
        assembly.path: ctx.actions.declare_file("{}/{}".format(directory, assembly.basename))
        for assembly in assemblies
    }

    # The image covers the framework, and depends on every assembly anyway, so
    # everything else is a reference.
    framework_paths = {lib.path: None for lib in framework.libs}
    args = crossgen2_args(ctx.actions, framework, [assembly for assembly in assemblies if assembly.path not in framework_paths])
    args.add("--composite")
    args.add(image, format = "--out:%s")
    args.add_all(assemblies)

    ctx.actions.run(
        executable = crossgen2.tool,
        arguments = [args],
        inputs = depset(assemblies, transitive = [framework.files, crossgen2.files]),
        outputs = [image] + components.values(),
        mnemonic = "Crossgen2Composite",
        progress_message = "Compiling composite ReadyToRun image for %{label}",
        execution_requirements = {"supports-path-mapping": "1"},
    )

    return struct(replace = components, extra = [image])

def _per_assembly_images(ctx, publish, framework, assemblies, directory):
    """The images the targets below the binary compiled, and the rest compiled here.

    An imported DLL compiles nothing, and a target pinning its own runtime
    identifier compiled against another runtime pack.
    """
    runtime_infos = [publish.assembly_info] + publish.transitive_runtime_deps
    images = _shipped_images(runtime_infos, framework, {assembly.path: None for assembly in assemblies})
    remaining = [assembly for assembly in assemblies if assembly.path not in images]

    if remaining:
        crossgen2 = _native_tools(ctx).crossgen2
        owners = {lib.path: info for info in runtime_infos for lib in info.libs}

        for assembly in remaining:
            image = ctx.actions.declare_file("{}/{}".format(directory, assembly.basename))
            owner = owners[assembly.path]
            compile_ready_to_run(ctx.actions, crossgen2, framework, ready_to_run_references(owner.libs, owner.deps), assembly, image)
            images[assembly.path] = image

    return struct(replace = images, extra = [])

def _shipped_images(runtime_infos, framework, published):
    """The images the targets below the binary compiled for the published assemblies.

    A package reached in several configurations compiles its assembly in each,
    possibly against different files. The image compiled against published
    files wins, else the first by path, so that graph order cannot decide.

    Args:
        runtime_infos: The DotnetAssemblyRuntimeInfo of the binary and everything it depends on.
        framework: The publish's framework, from `ready_to_run_framework`.
        published: The paths of the published assemblies, as dict keys.

    Returns:
        The image of each assembly a target compiled, keyed by the assembly's path.
    """
    candidates = {}
    for info in runtime_infos:
        for entry in getattr(info, "ready_to_run", None) or []:
            if entry.framework == framework.key and entry.assembly.path in published:
                candidates.setdefault(entry.assembly.path, []).append(entry)

    shipped = {}
    for (path, entries) in candidates.items():
        if len(entries) > 1:
            entries = sorted(entries, key = lambda entry: entry.image.path)
            entries = [entry for entry in entries if all([file.path in published for file in entry.references])] or entries

        shipped[path] = entries[0].image

    return shipped

# The layers of a publish, from the one that changes least to the one that
# changes with every build. Stacked in this order they give the publish.
_LAYERS = ["runtime", "third_party", "first_party", "app"]

def _dependency_layers(transitive_runtime_deps, runtime_pack_info, ready_to_run = _NO_READY_TO_RUN):
    """The layer of each dependency's files, keyed by path.

    An image takes the layer of the assembly it replaces. Anything missing,
    such as the binary's own assembly or a composite image, belongs to `app`.
    """
    layers = {}

    for dep in transitive_runtime_deps:
        layer = "third_party" if is_from_nuget_package(dep) else "first_party"

        for file in dep.libs + dep.native + dep.resource_assemblies + dep.data:
            layers[file.path] = layer

    if runtime_pack_info:
        for pack in runtime_pack_info.assembly_runtime_infos:
            for file in pack.libs + pack.native + pack.data:
                layers[file.path] = "runtime"

    for (assembly, image) in ready_to_run.replace.items():
        layers[image.path] = layers.get(assembly, "app")

    return layers

def _runfiles_entries(ctx, executable, data, beside = []):
    """The runfiles tree a layer carries for the publish's executable.

    Laid out as Bazel lays it out beside an executable: every runfile at its
    rlocation path, the executable included, and the binary's repository
    mapping both at the top of the tree and beside the executable.

    Args:
        ctx: The rule context.
        executable: The published executable.
        data: The data files the publish carries as runfiles.
        beside: The (path, File) pairs also carried as runfiles beside the executable.

    Returns:
        The File at each path of the tree.
    """
    root = executable.basename + ".runfiles"
    here = paths.dirname(to_rlocation_path(ctx, executable))

    entries = {"{}/{}".format(root, to_rlocation_path(ctx, file)): file for file in data + [executable]}

    for (path, file) in beside:
        entries["{}/{}/{}".format(root, here, path)] = file

    # A rule cannot reach its own repository mapping; the binary's only adds
    # rows for repositories the tree does not hold.
    repo_mapping = _binary(ctx)[DefaultInfo].files_to_run.repo_mapping_manifest
    if repo_mapping:
        entries[root + "/_repo_mapping"] = repo_mapping
        entries[executable.basename + ".repo_mapping"] = repo_mapping

    return entries

def _publish_layers(ctx, entries, dependency_layers):
    """Lays out each layer of a publish as a directory of its own.

    A layer is copied from the publish's sources rather than from the publish
    directory, so that it depends only on its own files, and its script lists
    them sorted by path, so that it changes only when they do.

    Args:
        ctx: The rule context.
        entries: The File at each path of the layers.
        dependency_layers: The layer of each dependency's files, by path.

    Returns:
        The directory of each layer, keyed by its `<layer>_layer` output group.
    """
    layers = {layer: [] for layer in _LAYERS}

    for path in sorted(entries):
        file = entries[path]
        layers[dependency_layers.get(file.path, "app")].append((file, path))

    output_groups = {}

    # One action per layer, which only runs when its output group is asked for.
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

# A rule rather than only the macro: the incoming transition on `binary`
# becomes an outgoing one here, which lets `runtime_identifier` be selected on,
# and an executable cannot be forwarded, so the rule has to create it.
_publish_binary = rule(
    _publish_binary_impl,
    doc = "Publishes a .NET binary. See `publish_binary`.",
    # Read by the C/C++ toolchain a NativeAOT publish links with.
    fragments = ["cpp"],
    attrs = {
        "binary": attr.label(
            doc = "The .NET binary to publish.",
            # The `native_tools` branch carries only the compiler.
            providers = [[DotnetBinaryInfo], [DotnetNativeToolsInfo]],
            cfg = publish_binary_transition,
            mandatory = True,
        ),
        "self_contained": attr.bool(
            doc = """Ship the .NET runtime with the application.

A framework-dependent publish, the default, needs a matching .NET runtime
installed on the machine it runs on. A self-contained one carries the runtime
for `runtime_identifier` and runs without one.""",
            default = False,
        ),
        "target_framework": attr.string(
            doc = "The target framework to publish for, such as `net10.0`.",
            mandatory = True,
        ),
        "runtime_identifier": attr.string(
            doc = "The runtime identifier to publish for, such as `linux-x64`. Defaults to the platform " +
                  "being built for. See https://learn.microsoft.com/en-us/dotnet/core/rid-catalog",
            mandatory = False,
        ),
        "runtime_identifier_from_platform": attr.bool(
            doc = "Set by the `publish_binary` macro when it fills in `runtime_identifier` from the target platform.",
            default = False,
        ),
        "roll_forward_behavior": attr.string(
            doc = "Which installed runtime a framework-dependent publish may run on: " +
                  "https://learn.microsoft.com/en-us/dotnet/core/versions/selection#control-roll-forward-behavior",
            default = "Minor",
            values = ["Minor", "Major", "LatestPatch", "LatestMinor", "LatestMajor", "Disable"],
        ),
        "ready_to_run": attr.bool(
            doc = """Compile the published assemblies to ReadyToRun.

ReadyToRun adds native code alongside the IL so the JIT has less to do at
startup. The published files keep their names; each assembly is replaced by
its compiled image.""",
            default = False,
        ),
        "ready_to_run_composite": attr.bool(
            doc = """Compile a single composite ReadyToRun image.

One image covers every assembly, framework included, which lets code be
inlined across assembly boundaries. Requires `ready_to_run` and
`self_contained`.""",
            default = False,
        ),
        "native_aot": attr.bool(
            doc = """Compile the publish ahead of time to a native executable.

The output is one self-contained executable with no IL and no JIT, so there is
no `deps.json`, `runtimeconfig.json` or apphost; native libraries, app
settings, content files and static web assets still sit beside it. Implies
trimming. Needs a C/C++ toolchain registered for the target platform, and a
binary built for .NET 10 or later. Cannot be combined with `ready_to_run` or
`single_file`.""",
            default = False,
        ),
        "single_file": attr.bool(
            doc = """Bundle the application, its managed dependencies and the runtime into a single executable.

Mirrors MSBuild's `<PublishSingleFile>true</PublishSingleFile>`. Requires
`self_contained`. App settings, content files, static web assets and (unless
`include_native_libraries_for_self_extract` is set) native libraries stay
beside the executable.""",
            default = False,
        ),
        "include_native_libraries_for_self_extract": attr.bool(
            doc = """Bundle native libraries too, extracted to disk at startup.

Mirrors MSBuild's `<IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>`.
Requires `single_file`.""",
            default = False,
        ),
        "enable_compression_in_single_file": attr.bool(
            doc = """Compress the files bundled into a single-file executable.

Mirrors MSBuild's `<EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>`.
Requires `single_file`.""",
            default = False,
        ),
        "_apphost_shimmer": attr.label(
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
            executable = True,
            default = "//dotnet/private/tools/apphost_shimmer:apphost_shimmer",
            cfg = "exec",
        ),
    },
    toolchains = ["//dotnet/toolchain:toolchain_type"],
    executable = True,
    cfg = tfm_transition,
)

# Settings that mean nothing for an application running in a browser.
_NOT_FOR_WASM = [
    "self_contained",
    "ready_to_run",
    "ready_to_run_composite",
    "native_aot",
    "single_file",
    "include_native_libraries_for_self_extract",
    "enable_compression_in_single_file",
    "roll_forward_behavior",
]

# Settings only a WebAssembly publish has, declared on the macro itself.
_WASM_ONLY_ATTRS = {
    "trim_mode": attr.string(
        doc = TRIM_MODE_DOC,
        configurable = False,
        values = [""] + TRIM_MODES,
    ),
    "application_environment": attr.string(
        doc = APPLICATION_ENVIRONMENT_DOC,
        configurable = False,
    ),
    "invariant_globalization": attr.bool(
        doc = INVARIANT_GLOBALIZATION_DOC,
        configurable = False,
    ),
}

# Resolved here because the TFM/RID transition cannot see the target platform.
_TARGET_RID = select({
    "@rules_dotnet//dotnet/private:linux-arm64": "linux-arm64",
    "@rules_dotnet//dotnet/private:linux-x64": "linux-x64",
    "@rules_dotnet//dotnet/private:osx-arm64": "osx-arm64",
    "@rules_dotnet//dotnet/private:osx-x64": "osx-x64",
    "@rules_dotnet//dotnet/private:windows-arm64": "win-arm64",
    "@rules_dotnet//dotnet/private:windows-x64": "win-x64",
})

def _publish_binary_macro_impl(name, **kwargs):
    if kwargs.pop("wasm", False):
        _publish_wasm(name, kwargs)
        return

    rid = kwargs.get("runtime_identifier", None)

    # `runtime_identifier` stays configurable so that cross-compiling can pick
    # it per platform, so it cannot also pick the kind of publish. A `select`
    # can only be inspected through its rendering.
    if rid != None and WASM_RID in str(rid):
        fail(
            "{}: a browser publish is selected with `wasm = True`, not with ".format(name) +
            "`runtime_identifier = \"{}\"`.".format(WASM_RID),
        )

    # By truthiness: an attribute the macro declares itself arrives as its
    # type's zero value when unset, not as None.
    for attribute in _WASM_ONLY_ATTRS:
        if kwargs.pop(attribute, None):
            fail(
                "{}: `{}` only applies to a WebAssembly publish.\n".format(name, attribute) +
                "Set `wasm = True` to publish for a browser.",
            )

    if rid == None:
        kwargs["runtime_identifier"] = _TARGET_RID
        kwargs["runtime_identifier_from_platform"] = True

    _publish_binary(name = name, **kwargs)

def _publish_wasm(name, kwargs):
    """Hands a browser publish to the rule that builds a static site."""
    for attribute in _NOT_FOR_WASM:
        # Against None: an inherited attribute the user did not set arrives as
        # None, and False is a value they did set.
        if kwargs.pop(attribute, None) != None:
            fail(
                "{}: `{}` does not apply to a WebAssembly publish.\n".format(name, attribute) +
                "A browser has no .NET host to be self-contained from, nothing to compile " +
                "ahead of time for, and no runtime to roll forward onto.",
            )

    kwargs.pop("runtime_identifier", None)

    # Unset attributes are dropped so that the rule's own defaults apply.
    blazor_wasm_publish(name = name, **{
        key: value
        for (key, value) in kwargs.items()
        if value != None and value != ""
    })

publish_binary = macro(
    doc = """Publishes a .NET binary for deployment, as `dotnet publish` does.

By default the publish is framework-dependent: a directory holding the
application, its dependencies and an executable that starts it on an installed
.NET runtime. `self_contained` ships the runtime too, `single_file` bundles
everything into one executable, `native_aot` compiles it ahead of time to
native code, `ready_to_run` precompiles the assemblies to shorten startup, and
`wasm` publishes a Blazor WebAssembly application as a static site.

Data files are carried as runfiles; resolve them with the runfiles library.

Except for `wasm`, the publish is also split into the layers of a container
image, each a directory in its `<layer>_layer` output group. Stacked in this
order they give the publish directory:

* `runtime`: the runtime of a self-contained publish, empty otherwise.
* `third_party`: what the application's NuGet packages contribute.
* `first_party`: the libraries built in this repository.
* `app`: the application's assembly, executable, `deps.json`,
  `runtimeconfig.json`, app settings and static web assets.

Together they also hold the runfiles tree beside the executable, each data
file in the layer of the target it belongs to.

A .NET Framework binary is published as its output directory, without PDBs.""",
    inherit_attrs = _publish_binary,
    attrs = dicts.add(_WASM_ONLY_ATTRS, {
        # Set by the macro itself.
        "runtime_identifier_from_platform": None,
        "wasm": attr.bool(
            doc = """Publish a Blazor WebAssembly application as a static site.

The output is a `wwwroot` directory rather than something to run, so it carries
no apphost and no runtime configuration.""",
            configurable = False,
        ),
    }),
    implementation = _publish_binary_macro_impl,
)
