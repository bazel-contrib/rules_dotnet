"""
Rule for assembling the publish output of a .NET binary.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@rules_cc//cc:action_names.bzl", "CPP_LINK_EXECUTABLE_ACTION_NAME")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("//dotnet/private:common.bzl", "generate_depsjson", "generate_runtimeconfig", "get_toolchain")
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "DotnetBinaryInfo",
    "DotnetNativeAotPackInfo",
    "DotnetToolPackInfo",
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
    "publish_layout",
    "reject_conflicting_paths",
)
load("//dotnet/private/sdk:packs.bzl", "WASM_RID")
load("//dotnet/private/sdk/nativeaot_packs:nativeaot_pack_transition.bzl", "nativeaot_pack_transition")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

# How many sources one `cp` invocation takes. A self-contained publish copies
# several hundred files into one directory, and the point of batching is lost if
# the command line grows long enough to risk the execve argument limit.
_COPY_BATCH = 128

def _render_copy_script(copies, is_windows):
    """The script that puts every published file in its place.

    A self-contained publish copies the whole runtime pack, so one process per
    file - and a second one to create its directory - dominates the action.
    Each directory is created once instead, and the files that keep their name
    are copied in batches.

    Args:
        copies: The (source, destination) pairs to copy, one pair per destination.
        is_windows: Whether the script is a batch file rather than a shell script.

    Returns:
        A list of script lines.
    """
    script_body = ["@echo off"] if is_windows else ["#! /usr/bin/env bash", "set -eou pipefail"]

    # Grouped by destination directory, in first-seen order. A file published
    # under a different name cannot join a batch, but its directory is still
    # created along with the rest.
    same_name = {}
    renamed = []

    for (src, dst) in copies:
        same_name.setdefault(dst.dirname, [])
        if src.basename == dst.basename:
            same_name[dst.dirname].append(src)
        else:
            renamed.append((src, dst))

    for (directory, sources) in same_name.items():
        if is_windows:
            script_body.append("if not exist \"{dir}\" @mkdir \"{dir}\" >NUL".format(dir = directory.replace("/", "\\")))

            # `copy` concatenates when handed several sources, so only the
            # directory creation is shared on Windows.
            for src in sources:
                script_body.append("@copy /Y \"{src}\" \"{dir}\" >NUL".format(
                    src = src.path.replace("/", "\\"),
                    dir = directory.replace("/", "\\"),
                ))
            continue

        script_body.append("mkdir -p {dir}".format(dir = shell.quote(directory)))

        for start in range(0, len(sources), _COPY_BATCH):
            script_body.append("cp -f {srcs} {dir}".format(
                srcs = " ".join([shell.quote(src.path) for src in sources[start:start + _COPY_BATCH]]),
                dir = shell.quote(directory),
            ))

    for (src, dst) in renamed:
        if is_windows:
            script_body.append("@copy /Y \"{src}\" \"{dst}\" >NUL".format(
                src = src.path.replace("/", "\\"),
                dst = dst.path.replace("/", "\\"),
            ))
        else:
            script_body.append("cp -f {src} {dst}".format(src = shell.quote(src.path), dst = shell.quote(dst.path)))

    return script_body

_NO_READY_TO_RUN = struct(replace = {}, extra = [])

def _native_target(runtime_identifier):
    """Splits a runtime identifier into --targetos/--targetarch.

    Both crossgen2 and ilc take the target this way, which is what lets either
    of them cross-compile.
    """
    parts = runtime_identifier.split("-")

    if len(parts) < 2 or parts[0] not in ("linux", "osx", "win"):
        fail("Cannot compile native code for {}".format(runtime_identifier))

    return ("windows" if parts[0] == "win" else parts[0], parts[-1])

# The framework assemblies ilc has to initialise explicitly, because nothing
# in the managed closure references them.
_AOT_INIT_ASSEMBLIES = [
    "System.Private.CoreLib",
    "System.Private.StackTraceMetadata",
    "System.Private.TypeLoader",
    "System.Private.Reflection.Execution",
]

# The trimming switches the SDK turns on for a NativeAOT publish. A switch
# removes the feature's code (`--feature`) and tells the runtime it is gone
# (`--runtimeknob`); the debugger is the one feature the runtime reads from the
# image instead, so it takes no knob.
_AOT_FEATURE_SWITCHES = {
    "System.Diagnostics.Debugger.IsSupported": False,
    "Microsoft.Extensions.DependencyInjection.VerifyOpenGenericServiceTrimmability": True,
    "System.ComponentModel.DefaultValueAttribute.IsSupported": False,
    "System.ComponentModel.Design.IDesignerHost.IsSupported": False,
    "System.ComponentModel.TypeConverter.EnableUnsafeBinaryFormatterInDesigntimeLicenseContextSerialization": False,
    "System.ComponentModel.TypeDescriptor.IsComObjectDescriptorSupported": False,
    "System.Data.DataSet.XmlSerializationIsSupported": False,
    "System.Diagnostics.Tracing.EventSource.IsSupported": False,
    "System.Linq.Enumerable.IsSizeOptimized": True,
    "System.Linq.Expressions.CanEmitObjectArrayDelegate": False,
    "System.Net.SocketsHttpHandler.Http3Support": False,
    "System.Reflection.Metadata.MetadataUpdater.IsSupported": False,
    "System.Resources.ResourceManager.AllowCustomResourceTypes": False,
    "System.Resources.UseSystemResourceKeys": False,
    "System.Runtime.CompilerServices.RuntimeFeature.IsDynamicCodeSupported": False,
    "System.Runtime.InteropServices.BuiltInComInterop.IsSupported": False,
    "System.Runtime.InteropServices.EnableConsumingManagedCodeFromNativeHosting": False,
    "System.Runtime.InteropServices.EnableCppCLIHostActivation": False,
    "System.Runtime.InteropServices.Marshalling.EnableGeneratedComInterfaceComImportInterop": False,
    "System.Runtime.Serialization.EnableUnsafeBinaryFormatterSerialization": False,
    "System.StartupHookProvider.IsSupported": False,
    "System.Text.Encoding.EnableUnsafeUTF7Encoding": False,
    "System.Text.Json.JsonSerializer.IsReflectionEnabledByDefault": False,
    "System.Threading.Thread.EnableAutoreleasePool": False,
}

_AOT_SWITCHES_WITHOUT_KNOB = ["System.Diagnostics.Debugger.IsSupported"]

# The order the runtime's static libraries have to reach the linker. Names are
# given without the platform's `lib` prefix or archive extension; entries the
# pack does not ship (the cryptography library differs by platform) are skipped.
_AOT_LINK_ORDER = [
    "System.Native",
    "System.Globalization.Native",
    "System.IO.Compression.Native",
    "System.Net.Security.Native",
    "System.Security.Cryptography.Native.Apple",
    "System.Security.Cryptography.Native.OpenSsl",
    "bootstrapper",
    "Runtime.WorkstationGC",
    "eventpipe-disabled",
    "Runtime.VxsortDisabled",
    "standalonegc-disabled",
    "aotminipal",
    "stdc++compat",
    "z",
    "brotlienc",
    "brotlidec",
    "brotlicommon",
]

# Libraries the runtime expects from the platform rather than from its pack,
# keyed by the target operating systems a publish can link for. The C++ runtime
# is absent because the pack's own libstdc++compat.a covers it.
_AOT_SYSTEM_LIBS = {
    "linux": ["dl", "rt", "m"],
    "osx": ["dl", "objc", "m"],
}

# Apple frameworks the runtime links against. They come from the macOS SDK, so
# the toolchain's sysroot has to carry them. See docs/README.md.
_AOT_APPLE_FRAMEWORKS = [
    "CoreFoundation",
    "CryptoKit",
    "Foundation",
    "Network",
    "Security",
    "GSS",
]

def _direct_pinvokes(link_inputs):
    """The framework libraries ilc binds directly instead of loading at runtime.

    Read from the static libraries the pack ships, so that a platform's own
    naming -- Apple's cryptography library against OpenSSL's -- falls out on
    its own.
    """
    names = []

    for basename in link_inputs:
        name = basename[3:] if basename.startswith("lib") else basename
        name = name.rsplit(".", 1)[0].removesuffix(".Aot")

        if name.startswith("System."):
            names.append(name)

    return sorted(names)

def _aot_closure(assembly_info, transitive_runtime_deps):
    """Everything a NativeAOT publish has to account for.

    Native libraries are still loaded at runtime, so they travel
    beside the executable.
    """
    parts = [assembly_info] + transitive_runtime_deps

    return struct(
        libs = [file for part in parts for file in part.libs],
        native = [file for part in parts for file in part.native],
        data = [file for part in parts for file in part.data],
        appsetting_files = assembly_info.appsetting_files.to_list(),
    )

def _aot_link_libraries(link_inputs):
    """The pack's static libraries, in the order the linker needs them."""
    libraries = []

    for name in _AOT_LINK_ORDER:
        for basename in ["lib{}.a".format(name), "lib{}.o".format(name)]:
            library = link_inputs.get(basename)

            if library:
                libraries.append(library)

    return libraries

def _ilc_compile(ctx, dll, closure, aot):
    """Compiles the whole managed closure to one native object file.

    Returns that object and the list of symbols to export from the executable
    linked from it.
    """
    ilc = ctx.attr._ilcompiler_pack[DotnetToolPackInfo]

    # The AOT framework replaces the JIT one wholesale: ilc compiles the app
    # and its dependencies against assemblies built for ahead-of-time use. The
    # app's own assembly is the input rather than a reference.
    references = {reference.path: reference for reference in aot.pack.libs + closure.libs}
    references.pop(dll.path, None)

    object_file = ctx.actions.declare_file(aot.prefix + ".o")
    exports_file = ctx.actions.declare_file(aot.prefix + ".exports")

    # Every path reaches ilc as a File so that path mapping can rewrite it; a
    # path baked into a string at analysis time would survive unmapped.
    args = ctx.actions.args()
    args.add(dll)
    args.add(object_file, format = "-o:%s")
    args.add("--targetos:" + aot.os)
    args.add("--targetarch:" + aot.arch)
    args.add_all(references.values(), format_each = "-r:%s")
    args.add("-O")
    args.add("--dehydrate")
    args.add(exports_file, format = "--exportsfile:%s")
    args.add("--export-dynamic-symbol:DotNetRuntimeDebugHeader")
    args.add_all(_AOT_INIT_ASSEMBLIES, format_each = "--initassembly:%s")

    # The bootstrapper calls into the class library through a fixed set of
    # entry points, which only exist if ilc is asked to emit them.
    args.add("--generateunmanagedentrypoints:System.Private.CoreLib")
    args.add_all(_direct_pinvokes(aot.pack.link_inputs), format_each = "--directpinvoke:%s")

    for switch in sorted(_AOT_FEATURE_SWITCHES):
        setting = "{}={}".format(switch, "true" if _AOT_FEATURE_SWITCHES[switch] else "false")
        args.add("--feature:" + setting)

        if switch not in _AOT_SWITCHES_WITHOUT_KNOB:
            args.add("--runtimeknob:" + setting)

    args.add("--runtimeknob:RUNTIME_IDENTIFIER=" + aot.rid)
    args.add("--stacktracedata")
    args.add("--scanreflection")
    args.add("--methodbodyfolding:generic")

    # A warning from framework code is not the user's to fix, and one bad
    # method should not fail the whole publish.
    args.add("--singlewarn")
    args.add("--nosinglewarnassembly:" + aot.name)
    args.add("--resilient")
    args.set_param_file_format("multiline")
    args.use_param_file("@%s", use_always = True)

    ctx.actions.run(
        executable = ilc.tool,
        arguments = [args],
        inputs = depset(
            [dll] + references.values(),
            transitive = [ilc.files],
        ),
        outputs = [object_file, exports_file],
        mnemonic = "Ilc",
        progress_message = "Compiling %{label} to native code",
        execution_requirements = {"supports-path-mapping": "1"},
    )

    return struct(object_file = object_file, exports_file = exports_file)

def _ilc_link(ctx, compiled, aot):
    """Links the compiled object into a native executable."""
    toolchain = ctx.toolchains["@bazel_tools//tools/cpp:toolchain_type"]

    if toolchain == None:
        fail("NativeAOT needs a C/C++ toolchain to link with, but none is registered")

    cc_toolchain = toolchain.cc
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
        unsupported_features = ctx.disabled_features,
    )
    linker = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_EXECUTABLE_ACTION_NAME,
    )
    link_variables = cc_common.create_link_variables(
        feature_configuration = feature_configuration,
        cc_toolchain = cc_toolchain,
    )

    is_apple = aot.os == "osx"
    libraries = _aot_link_libraries(aot.pack.link_inputs)
    executable = ctx.actions.declare_file(aot.prefix)

    # Ordered the way a Unix linker reads its command line: the object first,
    # then the archives that satisfy it, then the system libraries.
    args = ctx.actions.args()

    # Whatever the toolchain itself needs to target this platform: the sysroot
    # on a hermetic toolchain, the SDK path on Apple. These arrive as plain
    # strings, some of them output paths, which is why this action cannot opt
    # in to path mapping the way `Ilc` does.
    args.add_all(cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_EXECUTABLE_ACTION_NAME,
        variables = link_variables,
    ))
    args.add(compiled.object_file)
    args.add("-o", executable)

    if is_apple:
        # Exports only what ilc listed and drops the rest. There is no Linux
        # counterpart: the runtime relies on sections a GC-ing linker cannot
        # prove are reachable.
        args.add("-exported_symbols_list", compiled.exports_file)

    args.add_all(libraries)

    if not is_apple:
        args.add("-Wl,--build-id=sha1")
        args.add("-Wl,--as-needed")
        args.add("-pthread")

    args.add_all(_AOT_SYSTEM_LIBS[aot.os], format_each = "-l%s")

    if is_apple:
        args.add_all(_AOT_APPLE_FRAMEWORKS, before_each = "-framework")
    else:
        # The hardening the runtime ships with: read-only relocations,
        # immediate binding, and a position-independent executable.
        args.add("-Wl,-z,relro")
        args.add("-Wl,-z,now")
        args.add("-pie")
        args.add("-Wl,-pie")

    ctx.actions.run(
        executable = linker,
        arguments = [args],
        inputs = depset(
            [compiled.object_file, compiled.exports_file] + libraries,
            transitive = [cc_toolchain.all_files],
        ),
        outputs = [executable],
        env = cc_common.get_environment_variables(
            feature_configuration = feature_configuration,
            action_name = CPP_LINK_EXECUTABLE_ACTION_NAME,
            variables = link_variables,
        ),
        mnemonic = "IlcLink",
        progress_message = "Linking native executable for %{label}",
    )

    return executable

def _native_aot_executable(ctx, dll, closure, runtime_identifier, target_framework):
    """Compiles the managed closure to native code and links it into one executable."""
    pack = ctx.attr._nativeaot_pack[0][DotnetNativeAotPackInfo]

    if not pack.libs:
        fail("NativeAOT is not available for {} on {}".format(target_framework, runtime_identifier))

    (target_os, target_arch) = _native_target(runtime_identifier)

    if target_os not in _AOT_SYSTEM_LIBS:
        fail("NativeAOT cannot target {} yet: only Linux and macOS are supported".format(target_os))

    name = dll.basename.removesuffix(".dll")
    aot = struct(
        pack = pack,
        rid = runtime_identifier,
        os = target_os,
        arch = target_arch,
        name = name,
        # The executable's path; the object and the export list sit beside it
        # under their own extensions.
        prefix = "{}/aot/{}/{}".format(ctx.label.name, runtime_identifier, name),
    )

    return _ilc_link(ctx, _ilc_compile(ctx, dll, closure, aot), aot)

def _runtime_pack_files(runtime_pack_info, deps_json_struct):
    """The files each runtime pack contributes to the publish, one struct per pack.

    A user dependency that overrides a runtime pack DLL drops it from the
    pack's deps.json target, and then the pack's copy is not published.
    """
    if not runtime_pack_info:
        return []

    targets = deps_json_struct["targets"].values()[0]
    packs = []

    for pack in runtime_pack_info.assembly_runtime_infos:
        target = targets.get("runtimepack.{}/{}".format(pack.name, pack.version)) or {}

        packs.append(struct(
            libs = [file for file in pack.libs if file.basename in target.get("runtime", {})],
            native = [file for file in pack.native if file.basename in target.get("native", {})],
            data = pack.data,
        ))

    return packs

def _ready_to_run_images(ctx, binary_info, assembly_files, runtime_pack_files, runtime_identifier):
    """Compiles the published assemblies to ReadyToRun.

    crossgen2 cross-compiles, so the tool comes from the pack for the execution
    platform while the target platform and the references come from the target.
    """
    crossgen2 = ctx.attr._crossgen2_pack[DotnetToolPackInfo]
    (target_os, target_arch) = _native_target(runtime_identifier)

    framework = [
        lib
        for runtime_pack in binary_info.runtime_pack_info.assembly_runtime_infos
        for lib in runtime_pack.libs
    ]

    # Runtime pack assemblies already ship as ReadyToRun images, so only a
    # composite image, which has to cover the framework, recompiles them.
    # Either way the framework is there for crossgen2 to resolve against.
    compiled = [binary_info.dll] + assembly_files.libs
    if ctx.attr.ready_to_run_composite:
        for pack in runtime_pack_files:
            compiled.extend(pack.libs)

    assemblies = {assembly.path: assembly for assembly in compiled}.values()
    references = {reference.path: reference for reference in framework + assemblies}.values()
    inputs = depset(references, transitive = [crossgen2.files])
    root = "{}/r2r/{}".format(ctx.label.name, runtime_identifier)

    def common_args():
        """The arguments every crossgen2 action here starts with.

        The references alone run past any OS command line limit, so they always
        go into a parameter file. Each action builds its own rather than sharing
        one written ahead of time, because Bazel rewrites the paths inside a
        parameter file it writes for a path-mapped action and cannot rewrite
        those in a file that already exists.
        """
        args = ctx.actions.args()
        args.add("--targetos:" + target_os)
        args.add("--targetarch:" + target_arch)
        args.add("-O")
        args.add_all(references, format_each = "-r:%s")
        args.set_param_file_format("multiline")
        args.use_param_file("@%s", use_always = True)

        return args

    if ctx.attr.ready_to_run_composite:
        image = ctx.actions.declare_file("{}/composite/{}.r2r.dll".format(
            root,
            ctx.attr.binary[0][DotnetAssemblyRuntimeInfo].name,
        ))

        components = {}
        outputs = [image]

        for assembly in assemblies:
            component = ctx.actions.declare_file("{}/composite/{}".format(root, assembly.basename))
            components[assembly.path] = component
            outputs.append(component)

        args = common_args()
        args.add("--composite")
        args.add(image, format = "--out:%s")
        args.add_all(assemblies)

        ctx.actions.run(
            executable = crossgen2.tool,
            arguments = [args],
            inputs = inputs,
            outputs = outputs,
            mnemonic = "Crossgen2Composite",
            progress_message = "Compiling composite ReadyToRun image for %{label}",
            execution_requirements = {"supports-path-mapping": "1"},
        )

        return struct(replace = components, extra = [image])

    images = {}

    for assembly in assemblies:
        image = ctx.actions.declare_file("{}/{}".format(root, assembly.basename))
        args = common_args()
        args.add(image, format = "--out:%s")
        args.add(assembly)

        ctx.actions.run(
            executable = crossgen2.tool,
            arguments = [args],
            inputs = inputs,
            outputs = [image],
            mnemonic = "Crossgen2",
            progress_message = "Compiling %{input} to ReadyToRun",
            execution_requirements = {"supports-path-mapping": "1"},
        )

        images[assembly.path] = image

    return struct(replace = images, extra = [])

def _run_copy_script(ctx, copies, suffix, mnemonic, progress_message):
    """Runs one action that puts every (source, destination) pair in place.

    The pairs are also the action's inputs and outputs.

    Args:
        ctx: The rule context.
        copies: The (source, destination) pairs to copy.
        suffix: Distinguishes this script from the target's other copy scripts.
        mnemonic: The action's mnemonic.
        progress_message: The action's progress message.

    Returns:
        The destination files.
    """

    # The script runs on the machine building the publish, not the one the
    # publish is for. Those differ whenever a publish cross-compiles, and a
    # Windows machine cannot run the shell script a Linux target would pick.
    # The toolchain is resolved for the execution platform, so it is what knows
    # which machine that is.
    is_windows = get_toolchain(ctx).dotnetinfo.os == "windows"
    outputs = [dst for (_, dst) in copies]
    script = ctx.actions.declare_file("{}.{}.{}".format(ctx.label.name, suffix, "bat" if is_windows else "sh"))

    ctx.actions.write(
        output = script,
        content = ("\r\n" if is_windows else "\n").join(_render_copy_script(copies, is_windows)),
        is_executable = True,
    )
    ctx.actions.run(
        executable = script,
        inputs = depset([src for (src, _) in copies]),
        outputs = outputs,
        tools = [script],
        mnemonic = mnemonic,
        progress_message = progress_message,
    )

    return outputs

def _copy_beside(ctx, executable, files, static_web_files = []):
    """Copies files into the directory holding `executable`.

    Args:
        ctx: The rule context.
        executable: The published executable they sit beside.
        files: Files that land directly beside it.
        static_web_files: The servable tree, which keeps the structure the
            binary gave it.

    Returns:
        The copied files.
    """
    copies = [
        (file, ctx.actions.declare_file(file.basename, sibling = executable))
        for file in files
    ] + [
        (entry.file, ctx.actions.declare_file(entry.publish_path, sibling = executable))
        for entry in static_web_files
    ]
    if not copies:
        return []

    return _run_copy_script(
        ctx,
        copies,
        "sidecars",
        "DotnetCopySidecars",
        "Copying sidecars for %{label}",
    )

def _copy_to_publish(ctx, runtime_identifier, layout, binary_info, ready_to_run = _NO_READY_TO_RUN):
    root = "{}/publish/{}".format(ctx.label.name, runtime_identifier)

    # Keyed by destination because the binary's own assembly arrives twice, as
    # the main DLL and again in the list of assemblies to publish.
    copies = {
        path: (
            ready_to_run.replace.get(file.path, file),
            ctx.actions.declare_file("{}/{}".format(root, path)),
        )
        for (path, file) in layout
    }

    for file in ready_to_run.extra:
        copies[file.basename] = (file, ctx.actions.declare_file("{}/{}".format(root, file.basename)))

    outputs = _run_copy_script(
        ctx,
        copies.values(),
        "copy",
        "DotnetPublishCopy",
        "Assembling publish output for %{label}",
    )

    return (ctx.actions.declare_file("{}/{}".format(root, binary_info.dll.basename)), outputs)

def _create_shim_exe(ctx, apphost_pack_info, dll, runtime_identifier):
    windows_constraint = ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]

    apphost = apphost_pack_info.apphost
    output = ctx.actions.declare_file(paths.replace_extension(dll.basename, ".exe" if ctx.target_platform_has_constraint(windows_constraint) else ""), sibling = dll)

    ctx.actions.run(
        mnemonic = "DotnetApphostShim",
        progress_message = "Creating apphost shim for %{label}",
        executable = ctx.attr._apphost_shimmer.files_to_run,
        arguments = [apphost.path, dll.path, output.path, runtime_identifier],
        inputs = depset([apphost, dll], transitive = [ctx.attr._apphost_shimmer.default_runfiles.files]),
        tools = [ctx.attr._apphost_shimmer.files, ctx.attr._apphost_shimmer.default_runfiles.files],
        outputs = [output],
    )

    return output

def _generate_runtimeconfig(ctx, output, target_framework, project_sdk, is_self_contained, roll_forward_behavior, runtime_pack_info):
    runtimeconfig_struct = generate_runtimeconfig(target_framework, project_sdk, is_self_contained, roll_forward_behavior, runtime_pack_info)

    ctx.actions.write(
        output = output,
        content = json.encode(runtimeconfig_struct),
    )

def _generate_depsjson(
        ctx,
        output,
        target_framework,
        is_self_contained,
        assembly_info,
        transitive_runtime_deps,
        runtime_pack_info):
    depsjson_struct = generate_depsjson(ctx, target_framework, is_self_contained, assembly_info, transitive_runtime_deps, runtime_pack_info)

    ctx.actions.write(
        output = output,
        content = json.encode(depsjson_struct),
    )

    return depsjson_struct

def _publish_binary_impl(ctx):
    assembly_compile_info = ctx.attr.binary[0][DotnetAssemblyCompileInfo]
    assembly_runtime_info = ctx.attr.binary[0][DotnetAssemblyRuntimeInfo]
    binary_info = ctx.attr.binary[0][DotnetBinaryInfo]
    transitive_runtime_deps = binary_info.transitive_runtime_deps
    target_framework = ctx.attr.target_framework
    is_self_contained = ctx.attr.self_contained

    if ctx.attr.ready_to_run_composite and not (ctx.attr.ready_to_run and is_self_contained):
        fail("ready_to_run_composite requires ready_to_run and self_contained")

    if ctx.attr.native_aot and ctx.attr.ready_to_run:
        fail("native_aot cannot be combined with ready_to_run: it compiles ahead of time already")

    assembly_name = assembly_runtime_info.name
    runtime_pack_info = binary_info.runtime_pack_info if is_self_contained else None
    runtime_identifier = ctx.attr.runtime_identifier if ctx.attr.runtime_identifier else binary_info.runtime_pack_info.runtime_identifier
    roll_forward_behavior = ctx.attr.roll_forward_behavior

    if ctx.attr.native_aot:
        # Nothing managed survives into the output, so none of the publish
        # layout below applies: no deps.json, no runtimeconfig, no apphost.
        closure = _aot_closure(assembly_runtime_info, transitive_runtime_deps)
        executable = _native_aot_executable(
            ctx,
            binary_info.dll,
            closure,
            runtime_identifier,
            target_framework,
        )

        # A NativeAOT publish keeps nothing managed, but it still serves the
        # same files, so the tree travels with the executable.
        sidecars = _copy_beside(
            ctx,
            executable,
            closure.native + closure.appsetting_files,
            binary_info.static_web_files,
        )

        return [DefaultInfo(
            executable = executable,
            files = depset([executable] + sidecars),
            runfiles = ctx.runfiles(files = sidecars + closure.data),
        )]

    depsjson = ctx.actions.declare_file("{}/publish/{}/{}.deps.json".format(ctx.label.name, runtime_identifier, assembly_name))
    depsjson_struct = _generate_depsjson(
        ctx,
        depsjson,
        target_framework,
        is_self_contained,
        assembly_runtime_info,
        transitive_runtime_deps,
        runtime_pack_info,
    )

    runtimeconfig = ctx.actions.declare_file("{}/publish/{}/{}.runtimeconfig.json".format(
        ctx.label.name,
        runtime_identifier,
        assembly_name,
    ))

    _generate_runtimeconfig(
        ctx,
        runtimeconfig,
        target_framework,
        assembly_compile_info.project_sdk,
        is_self_contained,
        roll_forward_behavior,
        runtime_pack_info,
    )

    assembly_files = collect_assembly_files(assembly_runtime_info, transitive_runtime_deps, depsjson_struct)
    runtime_pack_files = _runtime_pack_files(runtime_pack_info, depsjson_struct)

    layout = publish_layout(runtime_identifier, binary_info, assembly_files, runtime_pack_files, is_self_contained)

    # Checked before the ReadyToRun and copy actions are declared, so a
    # collision names the targets at fault instead of surfacing as conflicting
    # actions on a path nobody wrote.
    reject_conflicting_paths(layout, ctx.label)

    ready_to_run = _NO_READY_TO_RUN

    if ctx.attr.ready_to_run:
        ready_to_run = _ready_to_run_images(
            ctx,
            binary_info,
            assembly_files,
            runtime_pack_files,
            runtime_identifier,
        )

    (main_dll, outputs) = _copy_to_publish(ctx, runtime_identifier, layout, binary_info, ready_to_run)

    apphost_shim = _create_shim_exe(ctx, binary_info.apphost_pack_info, main_dll, runtime_identifier)

    return [
        DefaultInfo(
            executable = apphost_shim,
            files = depset([apphost_shim, main_dll, runtimeconfig, depsjson] + outputs),
            # Data files reach the publish as runfiles, not as files at a
            # relative path: end users have to resolve them with the runfiles
            # library, and package them with a rule that carries runfiles along
            # (`include_runfiles` on rules_pkg's `pkg_tar`, for one).
            runfiles = ctx.runfiles(files = assembly_files.data),
        ),
    ]

# The incoming transition on `binary` becomes an outgoing one here, which is
# what lets the rule select on `runtime_identifier`. The file copying lives
# here too: Bazel cannot forward an executable, so this rule has to create it.
_publish_binary = rule(
    _publish_binary_impl,
    doc = """Publish a .Net binary""",
    # Read by the C/C++ toolchain a NativeAOT publish links with.
    fragments = ["cpp"],
    attrs = {
        "binary": attr.label(
            doc = "The .Net binary that is being published",
            providers = [DotnetBinaryInfo],
            cfg = tfm_transition,
            mandatory = True,
        ),
        "self_contained": attr.bool(
            doc = """
            Whether the binary should be self-contained.
            
            If true, the binary will be published as a self-contained but you need to provide
            a runtime pack in the `runtime_packs` attribute. At some point the rules might
            resolve the runtime pack automatically.

            If false, the binary will be published as a non-self-contained. That means that to be
            able to run the binary you need to have a .Net runtime installed on the host system.
            """,
            default = False,
        ),
        "target_framework": attr.string(
            doc = "The target framework that should be published",
            mandatory = True,
        ),
        "runtime_identifier": attr.string(
            doc = "The runtime identifier that is being targeted. " +
                  "See https://docs.microsoft.com/en-us/dotnet/core/rid-catalog",
            mandatory = False,
        ),
        "roll_forward_behavior": attr.string(
            doc = "The roll forward behavior that should be used: https://learn.microsoft.com/en-us/dotnet/core/versions/selection#control-roll-forward-behavior",
            default = "Minor",
            values = ["Minor", "Major", "LatestPatch", "LatestMinor", "LatestMajor", "Disable"],
        ),
        "ready_to_run": attr.bool(
            doc = """Compile the published assemblies to ReadyToRun.

ReadyToRun embeds native code alongside the IL so the JIT has less to do at
startup. The published file set is unchanged: each assembly is replaced by its
compiled image.""",
            default = False,
        ),
        "ready_to_run_composite": attr.bool(
            doc = """Compile a single composite ReadyToRun image.

One image covers every assembly, which lets crossgen2 inline across assembly
boundaries. Requires `ready_to_run` and `self_contained`, because the framework
has to be part of the image.""",
            default = False,
        ),
        "native_aot": attr.bool(
            doc = """Compile the publish ahead of time to a native executable.

The output is a single self-contained binary with no IL and no JIT, so the
managed publish layout does not apply: `deps.json`, `runtimeconfig.json` and
the apphost shim are all absent. Implies trimming, and needs a registered
C/C++ toolchain to link with.""",
            default = False,
        ),
        "_ilcompiler_pack": attr.label(
            doc = """The ILCompiler pack to compile native code with.

Selected by the execution platform rather than the target: ilc
cross-compiles, so what matters is the machine it runs on.""",
            cfg = "exec",
            default = Label("//dotnet/private:ilcompiler_pack"),
        ),
        "_nativeaot_pack": attr.label(
            doc = "The framework a NativeAOT publish compiles and links against.",
            cfg = nativeaot_pack_transition,
            default = Label("//dotnet/private/sdk/nativeaot_packs:nativeaot_pack"),
        ),
        "_crossgen2_pack": attr.label(
            doc = """The crossgen2 pack to compile ReadyToRun images with.

Selected by the execution platform rather than the target: crossgen2
cross-compiles, so what matters is the machine it runs on.""",
            cfg = "exec",
            default = Label("//dotnet/private:crossgen2_pack"),
        ),
        "_apphost_shimmer": attr.label(
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
            executable = True,
            default = "//dotnet/private/tools/apphost_shimmer:apphost_shimmer",
            cfg = "exec",
        ),
        "_windows_constraint": attr.label(default = "@platforms//os:windows"),
    },
    toolchains = [
        "//dotnet:toolchain_type",
        # Only a NativeAOT publish links native code, so a build that never
        # asks for one does not need a C/C++ toolchain registered.
        config_common.toolchain_type("@bazel_tools//tools/cpp:toolchain_type", mandatory = False),
    ],
    executable = True,
    cfg = tfm_transition,
)

# Settings that only describe a .NET application running on a .NET host, and so
# mean nothing once the target is a browser.
_NOT_FOR_WASM = [
    "self_contained",
    "ready_to_run",
    "ready_to_run_composite",
    "native_aot",
    "roll_forward_behavior",
]

# The reverse: settings only a WebAssembly publish has. Naming them once means
# the rejection below and the macro's own attributes cannot disagree.
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

# The runtime identifier of the platform being built for. Resolved here because
# the TFM/RID transition cannot see the target platform.
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

    # `runtime_identifier` stays configurable so that cross-compiling can
    # resolve it per platform, which means it cannot also choose the kind of
    # publish. Only the rendering of the value can be inspected here, because a
    # configurable attribute arrives as a `select`.
    if rid != None and WASM_RID in str(rid):
        fail(
            "{}: a browser publish is selected with `wasm = True`, not with ".format(name) +
            "`runtime_identifier = \"{}\"`.".format(WASM_RID),
        )

    # By truthiness, unlike the inherited attributes below: an attribute the
    # macro declares itself arrives as its type's zero value when unset, not as
    # None.
    for attribute in _WASM_ONLY_ATTRS:
        if kwargs.pop(attribute, None):
            fail(
                "{}: `{}` only applies to a WebAssembly publish.\n".format(name, attribute) +
                "Set `wasm = True` to publish for a browser.",
            )

    if rid == None:
        kwargs["runtime_identifier"] = _TARGET_RID

    _publish_binary(name = name, **kwargs)

def _publish_wasm(name, kwargs):
    """Hands a browser publish to the rule that builds a static site."""
    for attribute in _NOT_FOR_WASM:
        # Against None rather than by truthiness: an inherited attribute the
        # user did not set arrives as None, and False is a value they did set.
        if kwargs.pop(attribute, None) != None:
            fail(
                "{}: `{}` does not apply to a WebAssembly publish.\n".format(name, attribute) +
                "A browser has no .NET host to be self-contained from, nothing to compile " +
                "ahead of time for, and no runtime to roll forward onto.",
            )

    kwargs.pop("runtime_identifier", None)

    # Unset attributes are dropped so that the rule's own defaults apply: an
    # inherited one arrives as None and a declared one as its type's zero value.
    blazor_wasm_publish(name = name, **{
        key: value
        for (key, value) in kwargs.items()
        if value != None and value != ""
    })

publish_binary = macro(
    inherit_attrs = _publish_binary,
    attrs = dicts.add(_WASM_ONLY_ATTRS, {
        "wasm": attr.bool(
            doc = """Publish a Blazor WebAssembly application as a static site.

The output is a `wwwroot` directory rather than something to run, so it carries
no apphost and no runtime configuration.""",
            configurable = False,
        ),
    }),
    implementation = _publish_binary_macro_impl,
)
