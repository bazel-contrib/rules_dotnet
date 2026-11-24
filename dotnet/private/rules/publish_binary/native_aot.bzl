"""Compiles a .NET binary ahead of time into a native executable, as `PublishAot` does."""

load("@rules_cc//cc:action_names.bzl", "CPP_LINK_EXECUTABLE_ACTION_NAME")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("//dotnet/private:common.bzl", "tfm_version")
load("//dotnet/private/rules/ready_to_run:ready_to_run.bzl", "native_target")

# Earlier compilers take other options and bind the framework's native
# libraries by other names.
NATIVE_AOT_MIN_MAJOR_VERSION = 10

# From .NET 11 ilc takes the kind of stack trace data to emit, and the
# runtime's contract with debuggers and dump tools is exported under a new
# name, which a Unix link has to pull in explicitly.
_NET11_MAJOR_VERSION = 11

# Framework assemblies nothing in the app references, so ilc has to be told
# to initialise them.
_INIT_ASSEMBLIES = [
    "System.Private.CoreLib",
    "System.Private.StackTraceMetadata",
    "System.Private.TypeLoader",
    "System.Private.Reflection.Execution",
]

# The feature switches the SDK sets for a NativeAOT publish. Each removes the
# feature's code (`--feature`) and tells the runtime it is gone
# (`--runtimeknob`), except the debugger, which the runtime reads from the image.
_FEATURE_SWITCHES = {
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

_WINDOWS_FEATURE_SWITCHES = {"System.Threading.ThreadPool.UseWindowsThreadPool": True}

_SWITCHES_WITHOUT_KNOB = ["System.Diagnostics.Debugger.IsSupported"]

# The pack's static libraries in the order a Unix linker needs them, without
# the `lib` prefix or extension. Those a pack does not ship (the cryptography
# library differs by platform) are skipped.
_UNIX_LINK_ORDER = [
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
# Microsoft.NETCore.Native.Windows.targets lists it. Every pack ships these.
_WINDOWS_LINK_INPUTS = [
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

# Linked wherever a Windows pack ships them.
_WINDOWS_OPTIONAL_LINK_INPUTS = [
    # The garbage collector's vectorised sort stub: x64, and arm64 from .NET 11.
    "Runtime.VxsortDisabled.lib",
    # From .NET 11, which compresses with zstd too.
    "zstd_static.lib",
]

_WINDOWS_NET11_SYSTEM_LIBS = ["Synchronization"]

# Linkers that take link.exe's command line. A GNU-style driver would read
# `/OUT:app.exe` as an input file.
_MSVC_STYLE_LINKERS = ["link", "lld-link"]

# C runtimes a Bazel toolchain may pick that the NativeAOT runtime cannot link
# with: it is built for the static release runtime, `libcmt.lib`.
_WINDOWS_FOREIGN_CRTS = ["msvcrt", "msvcrtd", "libcmtd"]

# Libraries the runtime takes from the platform. Unix needs no C++ runtime: the
# pack's libstdc++compat.a covers it.
_SYSTEM_LIBS = {
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

# These come from the macOS SDK, so the toolchain's sysroot has to carry them.
# See docs/README.md.
_APPLE_FRAMEWORKS = [
    "CoreFoundation",
    "CryptoKit",
    "Foundation",
    "Network",
    "Security",
    "GSS",
]

def native_aot_executable(ctx, native_tools, dll, libs, runtime_identifier, target_framework, compiler_framework, winexe):
    """Compiles an application and its managed dependencies into one native executable.

    Args:
        ctx: The rule context.
        native_tools: The DotnetNativeToolsInfo the binary resolved for its framework.
        dll: The application's assembly.
        libs: The assemblies of the application and everything it depends on.
        runtime_identifier: The runtime identifier to compile for.
        target_framework: The framework the publish asked for, for messages.
        compiler_framework: The framework the binary is built for, whose band
            ilc comes from. It can be lower than `target_framework`.
        winexe: Whether a Windows executable is a GUI one, without a console window.

    Returns:
        The executable.
    """
    pack = native_tools.nativeaot_pack

    if not pack.libs:
        fail("NativeAOT is not available for {} on {}".format(target_framework, runtime_identifier))

    (target_os, target_arch) = native_target(runtime_identifier)
    net11 = tfm_version(compiler_framework)[0] >= _NET11_MAJOR_VERSION
    name = dll.basename.removesuffix(".dll")

    aot = struct(
        pack = pack,
        rid = runtime_identifier,
        os = target_os,
        arch = target_arch,
        name = name,
        # `frames` (method names) is what the earlier switch emitted, and what
        # the SDK asks for unless line numbers are asked for too.
        stack_trace_data = "--stacktracedata:frames" if net11 else "--stacktracedata",
        debugger_contract = "DotNetRuntimeContractDescriptor" if net11 else "DotNetRuntimeDebugHeader",
        pull_debugger_contract = net11,
        windows_system_libs = _WINDOWS_NET11_SYSTEM_LIBS if net11 else [],
        windows_gui = winexe and target_os == "windows",
        # The executable's path; the object and export list sit beside it.
        prefix = "{}/aot/{}/{}".format(ctx.label.name, runtime_identifier, name),
    )

    compiled = _ilc_compile(ctx, native_tools.ilcompiler, dll, libs, aot)

    return _link(ctx, native_tools.cc_link_toolchain, compiled, aot)

def _direct_pinvokes(link_inputs):
    """The framework libraries ilc binds directly instead of loading at run time.

    Read off the static libraries the pack ships, so that each platform's own
    set (Apple's cryptography library rather than OpenSSL's) falls out.
    """
    names = []

    for basename in link_inputs:
        name = basename[3:] if basename.startswith("lib") else basename
        name = name.rsplit(".", 1)[0].removesuffix(".Aot")

        if name.startswith("System."):
            names.append(name)

    return sorted(names)

def _feature_switch_args(is_windows):
    switches = dict(_FEATURE_SWITCHES)
    if is_windows:
        switches.update(_WINDOWS_FEATURE_SWITCHES)

    args = []

    for switch in sorted(switches):
        setting = "{}={}".format(switch, "true" if switches[switch] else "false")
        args.append("--feature:" + setting)

        if switch not in _SWITCHES_WITHOUT_KNOB:
            args.append("--runtimeknob:" + setting)

    return args

def _ilc_compile(ctx, ilc, dll, libs, aot):
    """Compiles the managed closure to one native object file.

    Returns:
        A struct of the `object_file` and the `exports_file` listing the
        symbols the executable exports.
    """
    is_windows = aot.os == "windows"

    # The pack's framework, built for ahead-of-time use, replaces the JIT one.
    # The app's own assembly is the input rather than a reference.
    references = {reference.path: reference for reference in aot.pack.libs + libs}
    references.pop(dll.path, None)

    object_file = ctx.actions.declare_file(aot.prefix + (".obj" if is_windows else ".o"))
    exports_file = ctx.actions.declare_file(aot.prefix + (".def" if is_windows else ".exports"))

    # Paths are passed as Files, never baked into strings, so that path mapping
    # can rewrite them.
    args = ctx.actions.args()
    args.add(dll)
    args.add(object_file, format = "-o:%s")
    args.add("--targetos:" + aot.os)
    args.add("--targetarch:" + aot.arch)
    args.add_all(references.values(), format_each = "-r:%s")
    args.add("-O")

    # Dehydrated data is smaller and slower to start. The SDK only defaults to
    # it where relocations are expensive, which on Windows they are not.
    if not is_windows:
        args.add("--dehydrate")
    args.add(exports_file, format = "--exportsfile:%s")

    # A PE export has to say that it is data rather than code.
    args.add("--export-dynamic-symbol:" + aot.debugger_contract + (",DATA" if is_windows else ""))
    args.add_all(_INIT_ASSEMBLIES, format_each = "--initassembly:%s")

    # The bootstrapper calls into the class library through these.
    args.add("--generateunmanagedentrypoints:System.Private.CoreLib")
    args.add_all(_direct_pinvokes(aot.pack.link_inputs), format_each = "--directpinvoke:%s")
    args.add_all(aot.pack.direct_pinvoke_lists, format_each = "--directpinvokelist:%s")
    args.add_all(_feature_switch_args(is_windows))
    args.add("--runtimeknob:RUNTIME_IDENTIFIER=" + aot.rid)
    args.add(aot.stack_trace_data)
    args.add("--scanreflection")
    args.add("--methodbodyfolding:generic")
    if is_windows:
        args.add("--win32resourcemodule:" + aot.name)

    # Warnings from framework code are not the user's to fix, and one bad
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

def _link(ctx, toolchain, compiled, aot):
    """Links ilc's object file and the pack's runtime into an executable."""
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
    is_windows = aot.os == "windows"

    if is_windows and _linker_name(linker) not in _MSVC_STYLE_LINKERS:
        fail("NativeAOT links for Windows with link.exe or lld-link, but the C/C++ toolchain links with {}".format(linker))

    executable = ctx.actions.declare_file(aot.prefix + (".exe" if is_windows else ""))

    # The toolchain's own flags come first: the sysroot of a hermetic toolchain,
    # the SDK path on Apple. Some are output paths baked into strings, which is
    # why, unlike `Ilc`, this action cannot opt in to path mapping.
    toolchain_args = cc_common.get_memory_inefficient_command_line(
        feature_configuration = feature_configuration,
        action_name = CPP_LINK_EXECUTABLE_ACTION_NAME,
        variables = link_variables,
    )

    # Bazel's MSVC toolchain gives every executable `/SUBSYSTEM:CONSOLE`; the
    # subsystem is set with the rest of the MSVC arguments instead.
    if is_windows:
        toolchain_args = [arg for arg in toolchain_args if not arg.upper().lstrip("/-").startswith("SUBSYSTEM:")]

    args = ctx.actions.args()
    args.add_all(toolchain_args)
    args.add(compiled.object_file)

    if is_windows:
        link_inputs = _add_msvc_link_args(args, executable, compiled, aot)
    else:
        link_inputs = _add_unix_link_args(ctx, args, executable, compiled, aot)

    ctx.actions.run(
        executable = linker,
        arguments = [args],
        inputs = depset(
            [compiled.object_file, compiled.exports_file] + link_inputs,
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

def _add_msvc_link_args(args, executable, compiled, aot):
    """Adds link.exe's arguments, as Microsoft.NETCore.Native.Windows.targets passes them.

    Returns:
        The pack's files the link reads.
    """
    link_inputs = aot.pack.link_inputs
    missing = [basename for basename in _WINDOWS_LINK_INPUTS if basename not in link_inputs]

    if missing:
        fail("The NativeAOT pack for {} does not ship {}".format(aot.rid, ", ".join(missing)))

    libraries = [
        link_inputs[basename]
        for basename in _WINDOWS_LINK_INPUTS + _WINDOWS_OPTIONAL_LINK_INPUTS
        if basename in link_inputs
    ]

    args.add(executable, format = "/OUT:%s")
    args.add(compiled.exports_file, format = "/DEF:%s")
    args.add_all(libraries)
    args.add_all(_SYSTEM_LIBS[aot.os] + aot.windows_system_libs, format_each = "%s.lib")
    args.add("/NOLOGO")
    args.add("/MANIFEST:NO")
    args.add("/MERGE:.managedcode=.text")
    args.add("/MERGE:hydrated=.bss")
    args.add("/INCREMENTAL:NO")

    # As in the SDK, a GUI executable keeps the console entry point.
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

    # The SDK takes only the linker and its library paths from the toolchain.
    # Undo the C runtime and debug format a Bazel toolchain picks for the
    # compilation mode, which would link the debug runtime under `-c dbg` and
    # otherwise leave the executable needing vcruntime140.dll.
    args.add_all(_WINDOWS_FOREIGN_CRTS, format_each = "/NODEFAULTLIB:%s.lib")
    args.add("/DEBUG:NONE")
    args.add("/OPT:REF")
    args.add("/OPT:ICF")

    return libraries

def _add_unix_link_args(ctx, args, executable, compiled, aot):
    """Adds a compiler driver's link arguments, as Microsoft.NETCore.Native.Unix.targets passes them.

    Returns:
        The pack's files the link reads, and any written for it.
    """
    is_apple = aot.os == "osx"
    libraries = [
        aot.pack.link_inputs[basename]
        for name in _UNIX_LINK_ORDER
        for basename in ["lib{}.a".format(name), "lib{}.o".format(name)]
        if basename in aot.pack.link_inputs
    ]
    link_inputs = list(libraries)

    args.add("-o", executable)

    # Debuggers and dump tools look up the runtime's contract among the
    # executable's exports. On Apple, ilc's list exports it and hides the rest.
    if is_apple:
        args.add("-exported_symbols_list", compiled.exports_file)
    else:
        # The SDK hands GNU ld ilc's version script, which lld rejects for
        # hiding symbols a shared library refers to, such as glibc's
        # _IO_stdin_used. A dynamic list exports the contract alone and hides
        # nothing, with GNU ld, gold and lld alike.
        dynamic_list = ctx.actions.declare_file(aot.prefix + ".dynamic-list")
        ctx.actions.write(dynamic_list, "{\n    %s;\n};\n" % aot.debugger_contract)
        args.add(dynamic_list, format = "-Wl,--dynamic-list=%s")
        link_inputs.append(dynamic_list)

    args.add_all(libraries)

    if not is_apple:
        if aot.pull_debugger_contract:
            args.add("-Wl,-u," + aot.debugger_contract)
        args.add("-Wl,--build-id=sha1")
        args.add("-Wl,--as-needed")
        args.add("-pthread")

    args.add_all(_SYSTEM_LIBS[aot.os], format_each = "-l%s")

    if is_apple:
        args.add_all(_APPLE_FRAMEWORKS, before_each = "-framework")
    else:
        # The runtime's hardening: read-only relocations, immediate binding and
        # a position-independent executable.
        args.add("-Wl,-z,relro")
        args.add("-Wl,-z,now")
        args.add("-pie")
        args.add("-Wl,-pie")

    return link_inputs
