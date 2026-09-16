"C# proto compiler definitions."

load("@com_google_protobuf//bazel/common:proto_lang_toolchain_info.bzl", "ProtoLangToolchainInfo")
load("@com_google_protobuf//bazel/toolchains:proto_lang_toolchain.bzl", "proto_lang_toolchain")
load("//proto/private:providers.bzl", "CsharpProtoCompilerInfo")

def _native_proto_plugin_impl(ctx):
    executable = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = executable,
        target_file = ctx.file.src,
        is_executable = True,
    )
    return [DefaultInfo(files = depset([executable]), executable = executable)]

_native_proto_plugin = rule(
    implementation = _native_proto_plugin_impl,
    executable = True,
    attrs = {
        "src": attr.label(
            allow_single_file = True,
            cfg = "exec",
            mandatory = True,
        ),
    },
)

def _grpc_tools_platform(ctx):
    operating_system = None
    architecture = None
    for name, constraint in [
        ("linux", ctx.attr._linux),
        ("macosx", ctx.attr._macos),
        ("windows", ctx.attr._windows),
    ]:
        if ctx.target_platform_has_constraint(constraint[platform_common.ConstraintValueInfo]):
            operating_system = name
    for name, constraint in [
        ("x86", ctx.attr._x86),
        ("x64", ctx.attr._x64),
        ("arm64", ctx.attr._arm64),
    ]:
        if ctx.target_platform_has_constraint(constraint[platform_common.ConstraintValueInfo]):
            architecture = name
    if operating_system == None or architecture == None:
        fail("Grpc.Tools has no known plugin for this execution platform. Supply a source-built executable with csharp_grpc_proto_compiler(plugin = ...).")
    return operating_system, architecture

def _grpc_csharp_plugin_impl(ctx):
    operating_system, architecture = _grpc_tools_platform(ctx)
    filename = "grpc_csharp_plugin.exe" if operating_system == "windows" else "grpc_csharp_plugin"
    platform = operating_system + "_" + architecture
    suffix = "/tools/{}/{}".format(platform, filename)
    matches = [file for file in ctx.files.grpc_tools if file.path.endswith(suffix)]
    if not matches and operating_system == "macosx" and architecture in ["x64", "arm64"]:
        suffix = "/tools/macosx_universal/" + filename
        matches = [file for file in ctx.files.grpc_tools if file.path.endswith(suffix)]
    if not matches and operating_system == "windows" and architecture == "arm64":
        suffix = "/tools/windows_x64/" + filename
        matches = [file for file in ctx.files.grpc_tools if file.path.endswith(suffix)]
    if len(matches) > 1:
        fail("Grpc.Tools contains multiple plugins matching " + suffix)
    if not matches:
        fail("Grpc.Tools does not provide a native {} for {}. Supply a compatible Paket package or a source-built executable with csharp_grpc_proto_compiler(plugin = ...).".format(filename, platform))

    executable = ctx.actions.declare_file(ctx.label.name + (".exe" if operating_system == "windows" else ""))
    ctx.actions.symlink(
        output = executable,
        target_file = matches[0],
        is_executable = True,
    )
    return [DefaultInfo(files = depset([executable]), executable = executable)]

grpc_csharp_plugin = rule(
    implementation = _grpc_csharp_plugin_impl,
    executable = True,
    doc = "Select a gRPC C# plugin from a Paket Grpc.Tools file target. Use as an exec-configured tool, not as a target-platform binary. Native binaries are preferred; macOS supports universal binaries without Rosetta, and Windows ARM64 can fall back to x64 emulation.",
    attrs = {
        "grpc_tools": attr.label(
            doc = "Pinned Paket package files, for example @paket.main//grpc.tools:files.",
            allow_files = True,
            mandatory = True,
        ),
        "_linux": attr.label(default = "@platforms//os:linux"),
        "_macos": attr.label(default = "@platforms//os:macos"),
        "_windows": attr.label(default = "@platforms//os:windows"),
        "_x86": attr.label(default = "@platforms//cpu:x86_32"),
        "_x64": attr.label(default = "@platforms//cpu:x86_64"),
        "_arm64": attr.label(default = "@platforms//cpu:arm64"),
    },
)

def _csharp_proto_compiler_impl(ctx):
    return [CsharpProtoCompilerInfo(
        proto_lang_toolchain_info = ctx.attr.proto_lang_toolchain[ProtoLangToolchainInfo],
    )]

_csharp_proto_compiler = rule(
    implementation = _csharp_proto_compiler_impl,
    attrs = {
        "proto_lang_toolchain": attr.label(
            providers = [ProtoLangToolchainInfo],
            mandatory = True,
        ),
    },
)

def _default_csharp_command_line(options):
    if len(options) == 0:
        return "--csharp_out=$(OUT)"
    return "--csharp_out=%s:$(OUT)" % ",".join(options)

def csharp_proto_compiler(name, command_line = None, options = [], plugin_file = None, visibility = None, **kwargs):
    """Defines a protoc invocation for csharp_proto_library.

    Runtime dependencies for generated code are intentionally not modeled here;
    users must add those assemblies to csharp_proto_library.deps.

    Args:
        name: Compiler target name.
        command_line: Optional protoc output argument containing $(OUT).
        options: C# code-generation options, mutually exclusive with command_line.
        plugin_file: Optional single native plugin file wrapped as an executable.
        visibility: Visibility of the compiler target.
        **kwargs: Additional proto_lang_toolchain arguments, including an executable plugin.
    """
    if "runtime" in kwargs:
        fail("csharp_proto_compiler does not accept runtime; add generated-code runtime assemblies to csharp_proto_library.deps instead")
    if "output_files" in kwargs:
        fail("csharp_proto_compiler does not accept output_files; generated C# sources are written under a declared output directory")
    if command_line and options:
        fail("Only one of command_line or options may be specified")
    if plugin_file and "plugin" in kwargs:
        fail("Only one of plugin_file and plugin may be specified")

    if plugin_file:
        plugin_name = name + "_plugin"
        _native_proto_plugin(
            name = plugin_name,
            src = plugin_file,
            visibility = ["//visibility:private"],
        )
        kwargs["plugin"] = ":" + plugin_name

    toolchain_name = name + "_proto_lang_toolchain"
    proto_lang_toolchain(
        name = toolchain_name,
        command_line = command_line or _default_csharp_command_line(options),
        output_files = "legacy",
        visibility = ["//visibility:private"],
        **kwargs
    )
    _csharp_proto_compiler(
        name = name,
        proto_lang_toolchain = ":" + toolchain_name,
        visibility = visibility,
    )

def csharp_grpc_proto_compiler(name, grpc_tools = None, plugin = None, options = [], visibility = None, **kwargs):
    """Define gRPC C# generation using an execution-platform-compatible plugin.

    Args:
        name: Compiler target name.
        grpc_tools: Pinned Paket Grpc.Tools file target, mutually exclusive with plugin.
        plugin: Optional Bazel executable, such as a source-built cc_binary, used in the execution configuration.
        options: gRPC code-generation options such as no_server or internal_access.
        visibility: Visibility of the compiler target.
        **kwargs: Additional proto_lang_toolchain arguments.
    """
    if (grpc_tools == None) == (plugin == None):
        fail("Specify exactly one of grpc_tools or plugin for csharp_grpc_proto_compiler")
    for argument in ["command_line", "plugin_file", "plugin_format_flag"]:
        if argument in kwargs:
            fail("csharp_grpc_proto_compiler controls " + argument)
    if grpc_tools != None:
        plugin_name = name + "_plugin"
        grpc_csharp_plugin(
            name = plugin_name,
            grpc_tools = grpc_tools,
            visibility = ["//visibility:private"],
        )
        plugin = ":" + plugin_name

    csharp_proto_compiler(
        name = name,
        command_line = "--grpc_out=" + (",".join(options) + ":" if options else "") + "$(OUT)",
        plugin = plugin,
        plugin_format_flag = "--plugin=protoc-gen-grpc=%s",
        visibility = visibility,
        **kwargs
    )
