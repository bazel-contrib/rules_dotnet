"""
Rule for assembling the publish output of a .NET binary.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:shell.bzl", "shell")
load("@rules_cc//cc:action_names.bzl", "CPP_LINK_EXECUTABLE_ACTION_NAME")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("//dotnet/private:common.bzl", "generate_depsjson", "generate_runtimeconfig", "get_toolchain", "is_from_nuget_package", "netframework_runtime_identifier", "tfm_to_semver", "tfm_version", "to_rlocation_path")
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
load(
    "//dotnet/private/rules/ready_to_run:ready_to_run.bzl",
    "compile_ready_to_run",
    "crossgen2_args",
    "native_target",
    "ready_to_run_framework",
    "ready_to_run_references",
)
load("//dotnet/private/sdk:packs.bzl", "WASM_RID", "WINDOWS_ONLY_FRAMEWORKS")
load("//dotnet/private/transitions:tfm_transition.bzl", "publish_binary_transition", "tfm_transition")

# How many sources one `cp` invocation takes. A self-contained publish copies
# several hundred files into one directory, and the point of batching is lost if
# the command line grows long enough to risk the execve argument limit.
_COPY_BATCH = 128

def _render_copy_script(copies, is_windows, directories = []):
    """The script that puts every published file in its place.

    A self-contained publish copies the whole runtime pack, so one process per
    file - and a second one to create its directory - dominates the action.
    Each directory is created once instead, and the files that keep their name
    are copied in batches.

    A source that is a directory, a tree artifact, is copied as its contents,
    which are flat.

    Args:
        copies: The (source, destination path) pairs to copy, one pair per destination.
        is_windows: Whether the script is a batch file rather than a shell script.
        directories: Directories to create even when no file lands in them.

    Returns:
        A list of script lines.
    """
    script_body = ["@echo off"] if is_windows else ["#! /usr/bin/env bash", "set -eou pipefail"]

    # Grouped by destination directory, in first-seen order. A file published
    # under a different name cannot join a batch, but its directory is still
    # created along with the rest.
    same_name = {directory: [] for directory in directories}
    renamed = []
    trees = []

    for (src, dst) in copies:
        if src.is_directory:
            trees.append((src, dst))
            continue

        same_name.setdefault(paths.dirname(dst), [])
        if src.basename == paths.basename(dst):
            same_name[paths.dirname(dst)].append(src)
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
                dst = dst.replace("/", "\\"),
            ))
        else:
            script_body.append("cp -f {src} {dst}".format(src = shell.quote(src.path), dst = shell.quote(dst)))

    for (src, dst) in trees:
        if is_windows:
            script_body.append("if not exist \"{dst}\" @mkdir \"{dst}\" >NUL".format(dst = dst.replace("/", "\\")))
            script_body.append("@for %%F in (\"{src}\\*\") do @copy /Y \"%%F\" \"{dst}\" >NUL".format(
                src = src.path.replace("/", "\\"),
                dst = dst.replace("/", "\\"),
            ))
        else:
            script_body.append("mkdir -p {dst}".format(dst = shell.quote(dst)))
            script_body.append("cp -Rf {src}/. {dst}".format(src = shell.quote(src.path), dst = shell.quote(dst)))

    return script_body

_NO_READY_TO_RUN = struct(replace = {}, extra = [])

def _binary(ctx):
    """The binary being published."""
    return ctx.split_attr.binary["binary"]

def _native_tools(ctx):
    """The native compiler the binary resolved for its own framework."""
    return ctx.split_attr.binary["native_tools"][DotnetNativeToolsInfo]

# The framework assemblies ilc has to initialise explicitly, because nothing
# in the managed closure references them.
_AOT_INIT_ASSEMBLIES = [
    "System.Private.CoreLib",
    "System.Private.StackTraceMetadata",
    "System.Private.TypeLoader",
    "System.Private.Reflection.Execution",
]

# The first .NET a NativeAOT publish supports. Earlier compilers take other
# options and bind the framework's native libraries by other names.
_AOT_MIN_MAJOR_VERSION = 10

# The first .NET whose NativeAOT publish is told some things differently. Its
# ilc takes the stack trace data to emit, where earlier ones took a switch.
# And the runtime's contract with debuggers and dump tools, which they look up
# in the executable, is exported under a new name, and has to be pulled into
# the link by name where it is not exported by a list.
_AOT_NET11_MAJOR_VERSION = 11

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

# The order the runtime's static libraries have to reach a Unix linker. Names
# are given without the `lib` prefix or archive extension; entries the pack does
# not ship (the cryptography library differs by platform) are skipped.
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
    # From .NET 11, which compresses with zstd too.
    "zstd",
]

# What the Windows pack contributes to the link, as
# Microsoft.NETCore.Native.Windows.targets lists it. The pack ships every one of
# these, so unlike on Unix a missing file is an error.
_AOT_WINDOWS_LINK_INPUTS = [
    "bootstrapper.obj",
    "Runtime.WorkstationGC.lib",
    "eventpipe-disabled.lib",
    "standalonegc-disabled.lib",
    "aotminipal.lib",
    "zlibstatic.lib",
    "brotlicommon.lib",
    "brotlienc.lib",
    "brotlidec.lib",
    "System.Globalization.Native.Aot.lib",
    "System.IO.Compression.Native.Aot.lib",
]

# What only some Windows packs ship, and the SDK links wherever it is shipped.
_AOT_WINDOWS_OPTIONAL_LINK_INPUTS = [
    # Stubs out the garbage collector's vectorised sort, on the architectures
    # that have one: x64, and arm64 from .NET 11.
    "Runtime.VxsortDisabled.lib",
    # From .NET 11, which compresses with zstd too.
    "zstd_static.lib",
]

# Windows libraries the runtime has needed since .NET 11.
_AOT_WINDOWS_NET11_SYSTEM_LIBS = ["Synchronization"]

# The linkers that take link.exe's command line. A Windows toolchain that
# links through a GNU-style driver would read `/OUT:app.exe` as an input file.
_AOT_MSVC_STYLE_LINKERS = ["link", "lld-link"]

# C runtimes a Bazel toolchain may name as a default library but the NativeAOT
# runtime cannot link against: its objects are built for the static release
# runtime, `libcmt.lib`, which they ask for themselves.
_AOT_WINDOWS_FOREIGN_CRTS = ["msvcrt", "msvcrtd", "libcmtd"]

# Libraries the runtime expects from the platform rather than from its pack,
# keyed by the target operating systems a publish can link for. The C++ runtime
# is absent on Unix because the pack's own libstdc++compat.a covers it.
_AOT_SYSTEM_LIBS = {
    "linux": ["dl", "rt", "m"],
    "osx": ["dl", "objc", "m"],
    "windows": [
        "advapi32",
        "bcrypt",
        "crypt32",
        "iphlpapi",
        "kernel32",
        "mswsock",
        "ncrypt",
        "normaliz",
        "ntdll",
        "ole32",
        "oleaut32",
        "secur32",
        "user32",
        "version",
        "ws2_32",
    ],
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

def _aot_closure(label, assembly_info, transitive_runtime_deps):
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
        content_files = publish_content_files(label, assembly_info, transitive_runtime_deps),
    )

def _aot_link_libraries(aot):
    """The pack's static libraries, in the order the linker needs them."""
    link_inputs = aot.pack.link_inputs

    if aot.os == "windows":
        missing = [basename for basename in _AOT_WINDOWS_LINK_INPUTS if basename not in link_inputs]

        if missing:
            fail("The NativeAOT pack for {} does not ship {}".format(aot.rid, ", ".join(missing)))

        optional = [basename for basename in _AOT_WINDOWS_OPTIONAL_LINK_INPUTS if basename in link_inputs]

        return [link_inputs[basename] for basename in _AOT_WINDOWS_LINK_INPUTS + optional]

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
    ilc = _native_tools(ctx).ilcompiler
    is_windows = aot.os == "windows"

    # The AOT framework replaces the JIT one wholesale: ilc compiles the app
    # and its dependencies against assemblies built for ahead-of-time use. The
    # app's own assembly is the input rather than a reference.
    references = {reference.path: reference for reference in aot.pack.libs + closure.libs}
    references.pop(dll.path, None)

    object_file = ctx.actions.declare_file(aot.prefix + (".obj" if is_windows else ".o"))
    exports_file = ctx.actions.declare_file(aot.prefix + (".def" if is_windows else ".exports"))

    # Every path reaches ilc as a File so that path mapping can rewrite it; a
    # path baked into a string at analysis time would survive unmapped.
    args = ctx.actions.args()
    args.add(dll)
    args.add(object_file, format = "-o:%s")
    args.add("--targetos:" + aot.os)
    args.add("--targetarch:" + aot.arch)
    args.add_all(references.values(), format_each = "-r:%s")
    args.add("-O")

    # Dehydrated data is smaller on disk and slower to start. The SDK only
    # makes that trade by default where relocations are expensive, which on
    # Windows they are not.
    if not is_windows:
        args.add("--dehydrate")
    args.add(exports_file, format = "--exportsfile:%s")

    # A PE export has to say that it is data rather than code.
    args.add("--export-dynamic-symbol:" + aot.debugger_contract + (",DATA" if is_windows else ""))
    args.add_all(_AOT_INIT_ASSEMBLIES, format_each = "--initassembly:%s")

    # The bootstrapper calls into the class library through a fixed set of
    # entry points, which only exist if ilc is asked to emit them.
    args.add("--generateunmanagedentrypoints:System.Private.CoreLib")
    args.add_all(_direct_pinvokes(aot.pack.link_inputs), format_each = "--directpinvoke:%s")
    args.add_all(aot.pack.direct_pinvoke_lists, format_each = "--directpinvokelist:%s")

    switches = dict(_AOT_FEATURE_SWITCHES)
    if is_windows:
        switches["System.Threading.ThreadPool.UseWindowsThreadPool"] = True

    for switch in sorted(switches):
        setting = "{}={}".format(switch, "true" if switches[switch] else "false")
        args.add("--feature:" + setting)

        if switch not in _AOT_SWITCHES_WITHOUT_KNOB:
            args.add("--runtimeknob:" + setting)

    args.add("--runtimeknob:RUNTIME_IDENTIFIER=" + aot.rid)
    args.add(aot.stack_trace_data)
    args.add("--scanreflection")
    args.add("--methodbodyfolding:generic")
    if is_windows:
        args.add("--win32resourcemodule:" + aot.name)

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
            [dll] + references.values() + aot.pack.direct_pinvoke_lists,
            transitive = [ilc.files],
        ),
        outputs = [object_file, exports_file],
        mnemonic = "Ilc",
        progress_message = "Compiling %{label} to native code",
        execution_requirements = {"supports-path-mapping": "1"},
    )

    return struct(object_file = object_file, exports_file = exports_file)

def _linker_name(linker):
    """A linker's name, without its directory or the Windows `.exe` suffix."""
    return linker.replace("\\", "/").rsplit("/", 1)[-1].lower().removesuffix(".exe")

def _ilc_link(ctx, compiled, aot):
    """Links the compiled object into a native executable."""
    toolchain = _native_tools(ctx).cc_link_toolchain

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
    is_windows = aot.os == "windows"
    libraries = _aot_link_libraries(aot)

    if is_windows and _linker_name(linker) not in _AOT_MSVC_STYLE_LINKERS:
        fail("NativeAOT links for Windows with link.exe or lld-link, but the C/C++ toolchain links with {}".format(linker))

    executable = ctx.actions.declare_file(aot.prefix + (".exe" if is_windows else ""))

    # Ordered the way a Unix linker reads its command line: the object first,
    # then the archives that satisfy it, then the system libraries.
    args = ctx.actions.args()

    # Whatever the toolchain itself needs to target this platform: the sysroot
    # on a hermetic toolchain, the SDK path on Apple. These arrive as plain
    # strings, some of them output paths, which is why this action cannot opt
    # in to path mapping the way `Ilc` does.
    toolchain_args = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_EXECUTABLE_ACTION_NAME,
        variables = link_variables,
    )

    # Bazel's MSVC toolchain adds `/SUBSYSTEM:CONSOLE` to every executable;
    # the subsystem is set below.
    if is_windows:
        toolchain_args = [arg for arg in toolchain_args if not arg.upper().lstrip("/-").startswith("SUBSYSTEM:")]

    args.add_all(toolchain_args)
    args.add(compiled.object_file)

    extra_inputs = []

    if is_windows:
        args.add(executable, format = "/OUT:%s")
        args.add(compiled.exports_file, format = "/DEF:%s")
        args.add_all(libraries)
        args.add_all(_AOT_SYSTEM_LIBS[aot.os] + aot.windows_system_libs, format_each = "%s.lib")
        args.add("/NOLOGO")
        args.add("/MANIFEST:NO")
        args.add("/MERGE:.managedcode=.text")
        args.add("/MERGE:hydrated=.bss")
        args.add("/INCREMENTAL:NO")

        # As in the SDK, a WinExe keeps the console entry point.
        args.add("/SUBSYSTEM:WINDOWS" if aot.windows_gui else "/SUBSYSTEM:CONSOLE")
        args.add("/ENTRY:wmainCRTStartup")
        args.add("/NOEXP")
        args.add("/NOIMPLIB")
        args.add("/STACK:1572864")
        args.add("/IGNORE:4104")
        if aot.arch == "x64":
            args.add("/CETCOMPAT")
        args.add("/NODEFAULTLIB:libucrt.lib")
        args.add("/DEFAULTLIB:ucrt.lib")

        # The SDK takes a linker and its library paths from the toolchain and
        # nothing else. Bazel's toolchain also picks a C runtime and a debug
        # format for the compilation mode, which would link the debug runtime
        # under `-c dbg` and leave the executable needing vcruntime140.dll
        # otherwise, so both choices are undone here.
        args.add_all(_AOT_WINDOWS_FOREIGN_CRTS, format_each = "/NODEFAULTLIB:%s.lib")
        args.add("/DEBUG:NONE")
        args.add("/OPT:REF")
        args.add("/OPT:ICF")
    else:
        args.add("-o", executable)

        # Exports the runtime's contract with debuggers and dump tools, which look
        # it up among the executable's exports, as the SDK does. On Apple that is
        # the list ilc wrote, which also keeps everything else unexported.
        if is_apple:
            args.add("-exported_symbols_list", compiled.exports_file)
        else:
            # The SDK hands GNU ld ilc's version script, but lld refuses one: it
            # hides symbols a shared library refers to, such as glibc's
            # _IO_stdin_used. A dynamic list exports the contract alone and hides
            # nothing, with GNU ld, gold and lld alike.
            dynamic_list = ctx.actions.declare_file(aot.prefix + ".dynamic-list")
            ctx.actions.write(dynamic_list, "{\n    %s;\n};\n" % aot.debugger_contract)
            args.add(dynamic_list, format = "-Wl,--dynamic-list=%s")
            extra_inputs.append(dynamic_list)

        args.add_all(libraries)

        if not is_apple:
            if aot.pull_debugger_contract:
                args.add("-Wl,-u," + aot.debugger_contract)
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
            [compiled.object_file, compiled.exports_file] + libraries + extra_inputs,
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

def _native_aot_executable(ctx, dll, closure, runtime_identifier, target_framework, compiler_framework, winexe):
    """Compiles the managed closure to native code and links it into one executable.

    `compiler_framework` is the framework the binary is built for, whose band
    ilc comes from. It can be lower than the `target_framework` published for.
    `winexe` gives a Windows executable the Windows GUI subsystem.
    """
    pack = _native_tools(ctx).nativeaot_pack

    if not pack.libs:
        fail("NativeAOT is not available for {} on {}".format(target_framework, runtime_identifier))

    (target_os, target_arch) = native_target(runtime_identifier)
    net11 = tfm_version(compiler_framework)[0] >= _AOT_NET11_MAJOR_VERSION

    if target_os not in _AOT_SYSTEM_LIBS:
        fail("NativeAOT cannot target {} yet".format(target_os))

    name = dll.basename.removesuffix(".dll")
    aot = struct(
        pack = pack,
        rid = runtime_identifier,
        os = target_os,
        arch = target_arch,
        name = name,
        # `frames`, the method names, is what the switch emitted, and what the
        # SDK asks for unless line numbers are asked for as well.
        stack_trace_data = "--stacktracedata:frames" if net11 else "--stacktracedata",
        debugger_contract = "DotNetRuntimeContractDescriptor" if net11 else "DotNetRuntimeDebugHeader",
        pull_debugger_contract = net11,
        windows_system_libs = _AOT_WINDOWS_NET11_SYSTEM_LIBS if net11 else [],
        windows_gui = winexe and target_os == "windows",
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
            name = pack.name,
            libs = [file for file in pack.libs if file.basename in target.get("runtime", {})],
            native = [file for file in pack.native if file.basename in target.get("native", {})],
            data = pack.data,
        ))

    return packs

# The layers of a publish, from the one that changes least to the one that
# changes with every build. Stacked in this order they give the publish
# directory.
_LAYERS = ["runtime", "third_party", "first_party", "app"]

def _dependency_layers(transitive_runtime_deps, runtime_pack_info, ready_to_run = _NO_READY_TO_RUN):
    """The layer of each dependency's files, keyed by path.

    A ReadyToRun image takes the layer of the assembly it replaces. A file
    missing from it, such as the binary's own assembly, a composite image or
    one generated for the publish, belongs to `app`.
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

def _publish_entries(layout, ready_to_run = _NO_READY_TO_RUN):
    """The file each publish path holds.

    Keyed by path because the binary's own assembly arrives twice, as the main
    DLL and again among the assemblies to publish. A ReadyToRun image takes the
    place of its assembly.
    """
    entries = {path: ready_to_run.replace.get(file.path, file) for (path, file) in layout}

    for file in ready_to_run.extra:
        entries[file.basename] = file

    return entries

def _runfiles_entries(ctx, executable, data, beside = []):
    """The runfiles tree beside a publish's executable, as Bazel lays it out.

    The runfiles library looks for `<executable>.runfiles` beside the running
    executable, and resolves repository names through the `_repo_mapping` at
    its top. Bazel lays out that tree for the publish itself, but a layer has
    to carry its own, so it holds what Bazel's does: every runfile at its
    rlocation path, the executable included, and a repository mapping both
    there and beside the executable. The mapping is the binary's, as a rule
    cannot reach its own; its extra rows only name repositories the tree does
    not hold.

    Args:
        ctx: The rule context.
        executable: The published executable the library starts from.
        data: The data files the publish carries as runfiles.
        beside: The (path, file) pairs the publish also carries as runfiles
            beside the executable, each file the source of the copy there.

    Returns:
        The runfiles paths, each with the file it holds.
    """
    root = executable.basename + ".runfiles"
    here = paths.dirname(to_rlocation_path(ctx, executable))

    entries = {"{}/{}".format(root, to_rlocation_path(ctx, file)): file for file in data + [executable]}

    for (path, file) in beside:
        entries["{}/{}/{}".format(root, here, path)] = file

    repo_mapping = _binary(ctx)[DefaultInfo].files_to_run.repo_mapping_manifest
    if repo_mapping:
        entries[root + "/_repo_mapping"] = repo_mapping
        entries[executable.basename + ".repo_mapping"] = repo_mapping

    return entries

def _publish_layers(ctx, entries, dependency_layers):
    """Lays out each layer of a publish as a directory of its own.

    A directory lands wherever a packaging rule puts it, while files under
    `<name>/publish/<rid>` keep that prefix unless every rule strips it.

    A layer is copied from the files the publish copies rather than from the
    publish directory, so that it depends only on its own files. Its script
    lists them sorted by path, so that it changes only when they do, not when
    a dependency elsewhere in the graph reorders them.

    Args:
        ctx: The rule context.
        entries: The file each path in the layers holds.
        dependency_layers: The layer of each dependency's files, by path.

    Returns:
        The directory of each layer, as its `<layer>_layer` output group.
    """
    layers = {layer: [] for layer in _LAYERS}

    for path in sorted(entries):
        file = entries[path]
        layers[dependency_layers.get(file.path, "app")].append((file, path))

    output_groups = {}

    # One action per layer, which runs only when its output group is asked for.
    for (layer, copies) in layers.items():
        directory = ctx.actions.declare_directory("{}/layers/{}".format(ctx.label.name, layer))

        _run_copy_script(
            ctx,
            copies,
            "layer_" + layer,
            "DotnetPublishLayer",
            "Assembling the {} layer of %{{label}}".format(layer),
            directory = directory,
        )

        output_groups[layer + "_layer"] = depset([directory])

    return output_groups

def _shipped_images(runtime_infos, framework, published):
    """The images the targets below the binary compiled for the published assemblies.

    A package reached in several configurations compiles its assembly in each,
    possibly against different files. The image compiled against published
    files is shipped, else the first by path, so that the order of the
    dependency graph cannot decide.

    Args:
        runtime_infos: The DotnetAssemblyRuntimeInfo of the binary and of
            everything it depends on.
        framework: The publish's framework, from `ready_to_run_framework`.
        published: The paths of the published assemblies, as dict keys.

    Returns:
        The image of each assembly a target compiled, keyed by its path.
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

def _ready_to_run_images(ctx, binary_info, assembly_files, runtime_pack_files, runtime_identifier):
    """The ReadyToRun images of the published assemblies.

    A composite image is compiled here. Otherwise the targets below the binary
    compiled their own assemblies, and the publish compiles only the rest.

    crossgen2 cross-compiles, so the tool comes from the pack for the execution
    platform while the target platform and the references come from the target.
    """
    crossgen2 = _native_tools(ctx).crossgen2
    framework = ready_to_run_framework(binary_info.runtime_pack_info)

    # Runtime pack assemblies already ship as ReadyToRun images, so only a
    # composite image, which has to cover the framework, recompiles them.
    # Either way the framework is there for crossgen2 to resolve against.
    compiled = [binary_info.dll] + assembly_files.libs
    if ctx.attr.ready_to_run_composite:
        for pack in runtime_pack_files:
            compiled.extend(pack.libs)

    assemblies = {assembly.path: assembly for assembly in compiled}.values()
    root = "{}/r2r/{}".format(ctx.label.name, runtime_identifier)

    if ctx.attr.ready_to_run_composite:
        image = ctx.actions.declare_file("{}/composite/{}.r2r.dll".format(
            root,
            _binary(ctx)[DotnetAssemblyRuntimeInfo].name,
        ))

        components = {}
        outputs = [image]

        for assembly in assemblies:
            component = ctx.actions.declare_file("{}/composite/{}".format(root, assembly.basename))
            components[assembly.path] = component
            outputs.append(component)

        # One image covers every assembly, so it depends on all of them anyway.
        framework_paths = {lib.path: None for lib in framework.libs}
        args = crossgen2_args(ctx.actions, framework, [assembly for assembly in assemblies if assembly.path not in framework_paths])
        args.add("--composite")
        args.add(image, format = "--out:%s")
        args.add_all(assemblies)

        ctx.actions.run(
            executable = crossgen2.tool,
            arguments = [args],
            inputs = depset(assemblies, transitive = [framework.files, crossgen2.files]),
            outputs = outputs,
            mnemonic = "Crossgen2Composite",
            progress_message = "Compiling composite ReadyToRun image for %{label}",
            execution_requirements = {"supports-path-mapping": "1"},
        )

        return struct(replace = components, extra = [image])

    runtime_infos = [_binary(ctx)[DotnetAssemblyRuntimeInfo]] + binary_info.transitive_runtime_deps
    images = _shipped_images(runtime_infos, framework, {assembly.path: None for assembly in assemblies})

    # An imported DLL compiles nothing, and a target pinning its own runtime
    # identifier compiled against another runtime pack.
    remaining = [assembly for assembly in assemblies if assembly.path not in images]
    if remaining:
        owners = {lib.path: info for info in runtime_infos for lib in info.libs}

        for assembly in remaining:
            image = ctx.actions.declare_file("{}/{}".format(root, assembly.basename))
            owner = owners[assembly.path]
            references = ready_to_run_references(owner.libs, owner.deps)
            compile_ready_to_run(ctx.actions, crossgen2, framework, references, assembly, image)
            images[assembly.path] = image

    return struct(replace = images, extra = [])

def _run_copy_script(ctx, copies, suffix, mnemonic, progress_message, directory = None):
    """Runs one action that puts every (source, destination) pair in place.

    Args:
        ctx: The rule context.
        copies: The (source, destination) pairs to copy. A destination is a
            File, or a path inside `directory` when one is given.
        suffix: Distinguishes this script from the target's other copy scripts.
        mnemonic: The action's mnemonic.
        progress_message: The action's progress message.
        directory: The directory to copy into, which is then the only output.

    Returns:
        The action's outputs.
    """

    # The script runs on the machine building the publish, not the one the
    # publish is for. Those differ whenever a publish cross-compiles, and a
    # Windows machine cannot run the shell script a Linux target would pick.
    # The toolchain is resolved for the execution platform, so it is what knows
    # which machine that is.
    is_windows = get_toolchain(ctx).dotnetinfo.os == "windows"

    if directory:
        # Created even when nothing lands in it, because a remote worker does
        # not create a declared directory.
        outputs = [directory]
        directories = [directory.path]
        pairs = [(src, "{}/{}".format(directory.path, dst)) for (src, dst) in copies]
    else:
        outputs = [dst for (_, dst) in copies]
        directories = []
        pairs = [(src, dst.path) for (src, dst) in copies]

    script = ctx.actions.declare_file("{}.{}.{}".format(ctx.label.name, suffix, "bat" if is_windows else "sh"))

    ctx.actions.write(
        output = script,
        content = ("\r\n" if is_windows else "\n").join(_render_copy_script(pairs, is_windows, directories)),
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

def _declare_like(ctx, source, path, sibling = None):
    """Declares the copy of `source` at `path`: a directory for a tree artifact."""
    if source.is_directory:
        return ctx.actions.declare_directory(path, sibling = sibling)
    return ctx.actions.declare_file(path, sibling = sibling)

def _copy_beside(ctx, executable, layout):
    """Copies files into the directory holding `executable`.

    Args:
        ctx: The rule context.
        executable: The published executable they sit beside.
        layout: The (path, file) pairs to copy, each path relative to that
            directory.

    Returns:
        The copied files.
    """
    copies = [
        (file, _declare_like(ctx, file, path, sibling = executable))
        for (path, file) in layout
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

def _copy_to_publish(ctx, runtime_identifier, entries, binary_info):
    root = "{}/publish/{}".format(ctx.label.name, runtime_identifier)

    copies = [
        (file, _declare_like(ctx, file, "{}/{}".format(root, path)))
        for (path, file) in entries.items()
    ]

    outputs = _run_copy_script(
        ctx,
        copies,
        "copy",
        "DotnetPublishCopy",
        "Assembling publish output for %{label}",
    )

    return (ctx.actions.declare_file("{}/{}".format(root, binary_info.dll.basename)), outputs)

def _executable_name(dll, runtime_identifier):
    """The name of the executable that starts `dll` on `runtime_identifier`."""
    return paths.replace_extension(dll.basename, ".exe" if runtime_identifier.startswith("win") else "")

def _stamp_host(ctx, host, dll, output, runtime_identifier, winexe, mnemonic, progress_message):
    """Copies a host from its pack to `output`, set to start `dll` from beside it.

    Args:
        ctx: The rule context.
        host: The host to copy: `apphost` or `singlefilehost`.
        dll: The assembly the host starts.
        output: The File to write the host to.
        runtime_identifier: The runtime identifier published for.
        winexe: True if the host should receive the Windows GUI PE subsystem.
        mnemonic: The action's mnemonic.
        progress_message: The action's progress message.
    """
    ctx.actions.run(
        mnemonic = mnemonic,
        progress_message = progress_message,
        executable = ctx.attr._apphost_shimmer.files_to_run,
        arguments = [host.path, dll.basename, output.path, runtime_identifier, "true" if winexe else "false"],
        # The host only records the assembly's name, as it sits beside it.
        # Depending on the assembly would tie the host, and so the app layer,
        # to the action copying the whole publish.
        inputs = depset([host], transitive = [ctx.attr._apphost_shimmer.default_runfiles.files]),
        tools = [ctx.attr._apphost_shimmer.files, ctx.attr._apphost_shimmer.default_runfiles.files],
        outputs = [output],
    )

def _create_shim_exe(ctx, apphost_pack_info, dll, runtime_identifier, winexe = False):
    output = ctx.actions.declare_file(_executable_name(dll, runtime_identifier), sibling = dll)

    _stamp_host(
        ctx,
        apphost_pack_info.apphost,
        dll,
        output,
        runtime_identifier,
        winexe,
        "DotnetApphostShim",
        "Creating apphost shim for %{label}",
    )

    return output

def _bundle_spec(entry):
    (path, file) = entry
    return "{}={}".format(path, file.path)

def _create_single_file(ctx, apphost_pack_info, dll, runtime_identifier, runtime_pack_info, target_framework, bundle, winexe = False):
    """Bundles files into a copy of `singlefilehost` that starts `dll`.

    Args:
        ctx: The rule context.
        apphost_pack_info: The DotnetApphostPackInfo holding `singlefilehost`.
        dll: The assembly the executable starts.
        runtime_identifier: The runtime identifier published for.
        runtime_pack_info: The DotnetRuntimePackInfo of the runtime the
            executable carries.
        target_framework: The framework the binary runs on, which decides the
            bundle's format.
        bundle: The File to bundle at each path.
        winexe: True if the host should receive the Windows GUI PE subsystem.

    Returns:
        The executable.
    """
    singlefilehost = apphost_pack_info.singlefilehost

    if singlefilehost == None:
        fail("The apphost pack for {} has no singlefilehost".format(runtime_identifier))

    name = _executable_name(dll, runtime_identifier)

    # Stamped where the bundler does not write, since it copies the host to
    # the executable's path before appending the bundle.
    host = ctx.actions.declare_file("{}/bundle/{}/{}".format(ctx.label.name, runtime_identifier, name))
    _stamp_host(
        ctx,
        singlefilehost,
        dll,
        host,
        runtime_identifier,
        winexe,
        "DotnetSingleFileHost",
        "Creating single-file host for %{label}",
    )

    executable = ctx.actions.declare_file("{}/publish/{}/{}".format(ctx.label.name, runtime_identifier, name))

    # The runtime pack's identifier is portable, so it names the operating
    # system plainly where the publish's may name a distribution.
    (target_os, target_arch) = native_target(runtime_pack_info.runtime_identifier)

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
    args.add(tfm_to_semver(target_framework))
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

def _executable_publish(ctx, executable, beside, data, dependency_layers):
    """A publish that is one executable with files copied beside it.

    NativeAOT and single-file publishes, whose assemblies are compiled or
    bundled into the executable.

    Args:
        ctx: The rule context.
        executable: The executable.
        beside: The (path, file) pairs to copy beside it.
        data: The data files, which travel as runfiles.
        dependency_layers: The layer of each dependency, from `_dependency_layers`.

    Returns:
        The DefaultInfo and OutputGroupInfo of the publish.
    """
    sidecars = _copy_beside(ctx, executable, beside)

    # The sidecars are runfiles too, and the layers copy them from their
    # sources rather than from beside the executable.
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

def _generate_runtimeconfig(ctx, output, target_framework, frameworks, is_self_contained, roll_forward_behavior, runtime_pack_info, framework_version):
    runtimeconfig_struct = generate_runtimeconfig(target_framework, frameworks, is_self_contained, roll_forward_behavior, runtime_pack_info, framework_version)

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

# What says how a .NET application is hosted, which a .NET Framework one is
# not: the framework installed in Windows runs it.
_NOT_FOR_NETFX = [
    "self_contained",
    "ready_to_run",
    "ready_to_run_composite",
    "native_aot",
    "single_file",
    "include_native_libraries_for_self_extract",
    "enable_compression_in_single_file",
]

def _netfx_publish(ctx, binary_info, assembly_runtime_info, transitive_runtime_deps):
    """Publishes a .NET Framework binary.

    As `dotnet publish` does for .NET Framework, the publish is the binary's
    output directory as it is, less the PDBs: the executable, its
    `<exe>.config`, and the assemblies and native libraries beside it. There
    is no deps.json, runtimeconfig.json or apphost.

    Args:
        ctx: The rule context.
        binary_info: The binary's DotnetBinaryInfo.
        assembly_runtime_info: The binary's DotnetAssemblyRuntimeInfo.
        transitive_runtime_deps: The DotnetAssemblyRuntimeInfo of everything it depends on.

    Returns:
        The DefaultInfo and OutputGroupInfo of the publish.
    """
    for attribute in _NOT_FOR_NETFX:
        if getattr(ctx.attr, attribute):
            fail(("{}: `{}` does not apply to {}, which targets .NET Framework: the framework " +
                  "installed in Windows runs it.").format(ctx.label, attribute, _binary(ctx).label))

    # As the transition does for the binary: the target platform's runtime
    # identifier, which the macro fills in, gives way to Windows.
    runtime_identifier = ctx.attr.runtime_identifier
    if ctx.attr.runtime_identifier_from_platform:
        runtime_identifier = netframework_runtime_identifier(runtime_identifier)
    if not runtime_identifier.startswith("win"):
        fail(("{}: {} targets .NET Framework, which only runs on Windows, so it cannot be " +
              "published for runtime identifier {}. Set `runtime_identifier` to a Windows " +
              "one, such as win-x64, or leave it unset.").format(ctx.label, _binary(ctx).label, repr(runtime_identifier)))

    layout = binary_info.netfx_layout
    reject_conflicting_paths(layout, ctx.label)

    entries = _publish_entries(layout)
    (executable, outputs) = _copy_to_publish(ctx, runtime_identifier, entries, binary_info)
    data = assembly_runtime_info.data + [file for dep in transitive_runtime_deps for file in dep.data]

    # The executable loads what is beside it, so that is in its runfiles too,
    # as with a single-file or NativeAOT publish: a target that runs the
    # publish from its own runfiles tree finds the whole application there.
    beside = [(path, file) for (path, file) in entries.items() if path != executable.basename]

    output_groups = _publish_layers(
        ctx,
        dicts.add(entries, _runfiles_entries(ctx, executable, data, beside = beside)),
        _dependency_layers(transitive_runtime_deps, None),
    )

    return [
        DefaultInfo(
            executable = executable,
            files = depset(outputs),
            runfiles = ctx.runfiles(files = outputs + data),
        ),
        OutputGroupInfo(**output_groups),
    ]

def _publish_binary_impl(ctx):
    assembly_compile_info = _binary(ctx)[DotnetAssemblyCompileInfo]
    assembly_runtime_info = _binary(ctx)[DotnetAssemblyRuntimeInfo]
    binary_info = _binary(ctx)[DotnetBinaryInfo]
    transitive_runtime_deps = binary_info.transitive_runtime_deps
    target_framework = ctx.attr.target_framework
    is_self_contained = ctx.attr.self_contained

    if binary_info.netfx_layout != None:
        return _netfx_publish(ctx, binary_info, assembly_runtime_info, transitive_runtime_deps)

    if ctx.attr.ready_to_run_composite and not (ctx.attr.ready_to_run and is_self_contained):
        fail("ready_to_run_composite requires ready_to_run and self_contained")

    if ctx.attr.native_aot and ctx.attr.ready_to_run:
        fail("native_aot cannot be combined with ready_to_run: it compiles ahead of time already")

    # The compiler comes from the band of the framework the binary is built
    # for, which can be lower than the one the publish asks for.
    if ctx.attr.native_aot and tfm_version(assembly_compile_info.target_framework)[0] < _AOT_MIN_MAJOR_VERSION:
        fail("{}: native_aot needs .NET {} or later, but {} is built for {}.".format(
            ctx.label,
            _AOT_MIN_MAJOR_VERSION,
            _binary(ctx).label,
            assembly_compile_info.target_framework,
        ))

    if ctx.attr.single_file and not is_self_contained:
        fail("single_file requires self_contained")

    if ctx.attr.single_file and ctx.attr.native_aot:
        fail("single_file cannot be combined with native_aot: NativeAOT produces a single native binary already")

    if (ctx.attr.include_native_libraries_for_self_extract or ctx.attr.enable_compression_in_single_file) and not ctx.attr.single_file:
        fail("include_native_libraries_for_self_extract and enable_compression_in_single_file require single_file")

    windows_only = [framework for framework in binary_info.runtime_frameworks if framework in WINDOWS_ONLY_FRAMEWORKS]

    # The SDK refuses to trim Windows Forms and WPF, and NativeAOT trims.
    if ctx.attr.native_aot and windows_only:
        fail("{}: native_aot cannot publish {}, which runs on {}: Windows Forms and WPF do not support trimming, which NativeAOT implies.".format(
            ctx.label,
            _binary(ctx).label,
            ", ".join(windows_only),
        ))

    assembly_name = assembly_runtime_info.name
    runtime_pack_info = binary_info.runtime_pack_info if is_self_contained else None
    runtime_identifier = ctx.attr.runtime_identifier if ctx.attr.runtime_identifier else binary_info.runtime_pack_info.runtime_identifier

    if windows_only and not (runtime_identifier or "").startswith("win"):
        fail("{}: {} runs on {}, which only exists on Windows. Set `runtime_identifier` to a Windows one, such as win-x64.".format(
            ctx.label,
            _binary(ctx).label,
            ", ".join(windows_only),
        ))

    if not runtime_identifier or (is_self_contained and not runtime_pack_info.assembly_runtime_infos):
        fail("No runtime pack found for target framework {} and runtime identifier {}".format(
            target_framework,
            ctx.attr.runtime_identifier or "<host>",
        ))

    # The runtime pack only carries the shared frameworks the binary
    # references itself.
    missing = [framework for framework in binary_info.runtime_frameworks if framework not in binary_info.packed_frameworks]
    if (is_self_contained or ctx.attr.ready_to_run) and missing:
        fail("{}: {} runs on {}, which one of its dependencies references, but a {} publish only takes the runtime packs of the shared frameworks the binary references itself. Add {} to the `framework_references` of {}.".format(
            ctx.label,
            _binary(ctx).label,
            ", ".join(missing),
            "self-contained" if is_self_contained else "ReadyToRun",
            " and ".join(["\"{}\"".format(framework) for framework in missing]),
            _binary(ctx).label,
        ))
    roll_forward_behavior = ctx.attr.roll_forward_behavior

    if ctx.attr.native_aot:
        # Nothing managed survives into the output, so none of the publish
        # layout below applies: no deps.json, no runtimeconfig, no apphost.
        closure = _aot_closure(ctx.label, assembly_runtime_info, transitive_runtime_deps)
        executable = _native_aot_executable(
            ctx,
            binary_info.dll,
            closure,
            runtime_identifier,
            target_framework,
            assembly_compile_info.target_framework,
            binary_info.winexe,
        )

        # A NativeAOT publish keeps nothing managed, but it still serves the
        # same files, so the tree travels with the executable.
        beside = [(file.basename, file) for file in closure.native + closure.appsetting_files] + [
            (entry.dest, entry.file)
            for entry in closure.content_files
        ] + [
            (entry.publish_path, entry.file)
            for entry in binary_info.static_web_files
        ]

        # The runtime is compiled into the executable, so that layer is empty.
        return _executable_publish(
            ctx,
            executable,
            beside,
            closure.data,
            _dependency_layers(transitive_runtime_deps, None),
        )

    publish_meta_dir = "bundle" if ctx.attr.single_file else "publish"
    depsjson = ctx.actions.declare_file("{}/{}/{}/{}.deps.json".format(ctx.label.name, publish_meta_dir, runtime_identifier, assembly_name))
    depsjson_struct = _generate_depsjson(
        ctx,
        depsjson,
        target_framework,
        is_self_contained,
        assembly_runtime_info,
        transitive_runtime_deps,
        runtime_pack_info,
    )

    runtimeconfig = ctx.actions.declare_file("{}/{}/{}/{}.runtimeconfig.json".format(
        ctx.label.name,
        publish_meta_dir,
        runtime_identifier,
        assembly_name,
    ))

    _generate_runtimeconfig(
        ctx,
        runtimeconfig,
        target_framework,
        binary_info.runtime_frameworks,
        is_self_contained,
        roll_forward_behavior,
        runtime_pack_info,
        binary_info.framework_version,
    )

    assembly_files = collect_assembly_files(ctx.label, assembly_runtime_info, transitive_runtime_deps, depsjson_struct)
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

    if ctx.attr.single_file:
        # The runtime's own native libraries are linked into singlefilehost,
        # which their `DropFromSingleFile` marks in the runtime pack's
        # RuntimeList.xml say, so they are neither bundled nor published.
        dropped = {
            file: None
            for pack in runtime_pack_files
            if pack.name.startswith("Microsoft.NETCore.App.Runtime.")
            for file in pack.native
        }
        managed = [binary_info.dll] + assembly_files.libs + assembly_files.resource_assemblies + [
            lib
            for pack in runtime_pack_files
            for lib in pack.libs
        ]
        native = [
            lib
            for lib in assembly_files.native + [lib for pack in runtime_pack_files for lib in pack.native]
            if lib not in dropped
        ]

        # As MSBuild does: the managed assemblies go into the bundle, and the
        # native libraries when asked. Everything else stays beside the
        # executable, at the path the publish gives it.
        bundled = {
            file: None
            for file in managed + (native if ctx.attr.include_native_libraries_for_self_extract else [])
        }

        executable = _create_single_file(
            ctx,
            binary_info.apphost_pack_info,
            binary_info.dll,
            runtime_identifier,
            runtime_pack_info,
            # The binary's, as the runtime reading the bundle is the one it
            # picked, whatever framework the publish asked for.
            assembly_compile_info.target_framework,
            dicts.add(
                _publish_entries([(path, file) for (path, file) in layout if file in bundled], ready_to_run),
                {file.basename: file for file in [runtimeconfig, depsjson]},
            ),
            binary_info.winexe,
        )

        return _executable_publish(
            ctx,
            executable,
            [(path, file) for (path, file) in layout if file not in bundled and file not in dropped],
            assembly_files.data,
            _dependency_layers(transitive_runtime_deps, runtime_pack_info, ready_to_run),
        )

    entries = _publish_entries(layout, ready_to_run)
    (main_dll, outputs) = _copy_to_publish(ctx, runtime_identifier, entries, binary_info)

    apphost_shim = _create_shim_exe(ctx, binary_info.apphost_pack_info, main_dll, runtime_identifier, binary_info.winexe)

    output_groups = _publish_layers(
        ctx,
        dicts.add(
            entries,
            {file.basename: file for file in [apphost_shim, runtimeconfig, depsjson]},
            _runfiles_entries(ctx, apphost_shim, assembly_files.data),
        ),
        _dependency_layers(transitive_runtime_deps, runtime_pack_info, ready_to_run),
    )

    return [
        DefaultInfo(
            executable = apphost_shim,
            files = depset([apphost_shim, main_dll, runtimeconfig, depsjson] + outputs),
            # Data files reach the publish as runfiles, not as files at a
            # relative path: end users have to resolve them with the runfiles
            # library, and package them with a rule that carries runfiles along
            # (`include_runfiles` on rules_pkg's `pkg_tar`, for one). The
            # layers carry the runfiles tree themselves.
            runfiles = ctx.runfiles(files = assembly_files.data),
        ),
        OutputGroupInfo(**output_groups),
    ]

# The incoming transition on `binary` becomes an outgoing one here, which is
# what lets the rule select on `runtime_identifier`. The file copying lives
# here too: Bazel cannot forward an executable, so this rule has to create it.
_publish_binary = rule(
    _publish_binary_impl,
    doc = """Publish a .Net binary.

The publish is also split into the layers of a container image, each a
directory in its `<layer>_layer` output group. Stacked in this order they give
the publish directory:

* `runtime`: the runtime pack of a self-contained publish, empty otherwise.
* `third_party`: what the application's NuGet packages contribute.
* `first_party`: the libraries built in this repository.
* `app`: the application's assembly, apphost, `deps.json`,
  `runtimeconfig.json`, app settings and static web assets.

Together they also hold the runfiles tree Bazel lays out beside the
executable, each data file in the layer of the target it belongs to.

A .NET Framework binary is published as its output directory, less the PDBs:
the executable, its `<exe>.config` and the files beside it, with no
`deps.json`, `runtimeconfig.json` or apphost.""",
    # Read by the C/C++ toolchain a NativeAOT publish links with.
    fragments = ["cpp"],
    attrs = {
        "binary": attr.label(
            doc = "The .Net binary that is being published",
            # The `native_tools` branch carries only the compiler.
            providers = [[DotnetBinaryInfo], [DotnetNativeToolsInfo]],
            cfg = publish_binary_transition,
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
        "runtime_identifier_from_platform": attr.bool(
            doc = """Set by the `publish_binary` macro when `runtime_identifier` is the
target platform's because none was given. A .NET Framework binary, which only runs
on Windows, is then published for Windows on the same architecture.""",
            default = False,
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
C/C++ toolchain to link with. The binary has to be built for .NET 10 or later.""",
            default = False,
        ),
        "single_file": attr.bool(
            doc = """Bundle the application, its managed dependencies, and the runtime into a single executable.

Mirrors MSBuild's `<PublishSingleFile>true</PublishSingleFile>`. Requires
`self_contained = True`. Managed assemblies, `deps.json`, and
`runtimeconfig.json` are embedded into the `singlefilehost` binary;
appsettings, static web assets, and (unless
`include_native_libraries_for_self_extract = True`) non-runtime native
libraries remain beside the executable.""",
            default = False,
        ),
        "include_native_libraries_for_self_extract": attr.bool(
            doc = """Embed native libraries into the single-file bundle for self-extraction at startup.

Mirrors MSBuild's `<IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>`.
Requires `single_file = True`.""",
            default = False,
        ),
        "enable_compression_in_single_file": attr.bool(
            doc = """Compress embedded files inside the single-file bundle.

Mirrors MSBuild's `<EnableCompressionInSingleFile>true</EnableCompressionInSingleFile>`.
Requires `single_file = True`.""",
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

# Settings that only describe a .NET application running on a .NET host, and so
# mean nothing once the target is a browser.
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
        kwargs["runtime_identifier_from_platform"] = True

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
