"""
Rules to configure the .NET toolchain of rules_dotnet.
"""

load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "DotnetRuntimePackInfo",
    "DotnetTargetingPackInfo",
    "NuGetInfo",
)

def _compile_info(name, version, refs, project_sdk):
    return DotnetAssemblyCompileInfo(
        name = name,
        version = version,
        project_sdk = project_sdk,
        refs = refs,
        irefs = refs,
        analyzers = [],
        analyzers_csharp = [],
        analyzers_fsharp = [],
        analyzers_vb = [],
        compile_data = [],
        exports = [],
        transitive_compile_data = depset([]),
        transitive_refs = depset([]),
        transitive_analyzers = depset([]),
        transitive_analyzers_csharp = depset([]),
        transitive_analyzers_fsharp = depset([]),
        transitive_analyzers_vb = depset([]),
        internals_visible_to = [],
    )

def _runtime_info(name, version, libs, native):
    return DotnetAssemblyRuntimeInfo(
        name = name,
        version = version,
        libs = libs,
        pdbs = [],
        xml_docs = [],
        native = native,
        data = [],
        resource_assemblies = [],
        appsetting_files = depset([]),
        nuget_info = None,
        deps = depset([]),
        direct_deps_depsjson_fragment = {},
    )

def _nuget_info():
    return NuGetInfo(
        targeting_pack_overrides = {},
        framework_list = {},
        sha512 = "",
        nupkg = None,
    )

DotnetInfo = provider(
    doc = "Information about the dotnet toolchain",
    fields = {
        "runtime_path": "Path to the dotnet executable",
        "runtime_files": """depset[File]: Files required in runfiles to make the dotnet executable available.

This is the dotnet host and every shared framework, since a binary's
`project_sdk` decides which one it asks for, but not the SDK.

May be empty if the runtime_path points to a locally installed tool binary.""",
        "csharp_compiler_path": "Path to the C# compiler executable",
        "csharp_compiler_files": """depset[File]: Files required in runfiles to make the C# compiler executable available.

May be empty if the csharp_compiler_path points to a locally installed tool binary.""",
        "fsharp_compiler_path": "Path to the F# compiler executable",
        "fsharp_compiler_files": """depset[File]: Files required in runfiles to make the F# compiler executable available.

May be empty if the fsharp_compiler_path points to a locally installed tool binary.""",
        "apphost_path": "Path to the apphost executable",
        "apphost_files": """Files required in runfiles to make the apphost executable available.

May be empty if the apphost_path points to a locally installed tool binary.""",
        "sdk_version": "Version of the dotnet SDK",
        "runtime_version": "Version of the dotnet runtime",
        "wasm_runtime_version": "Version of the WebAssembly workload runtime",
        "runtime_tfm": "The target framework moniker for the current SDK",
        "csharp_default_version": "Default version of the C# language",
        "fsharp_default_version": "Default version of the F# language",
        "targeting_pack_infos": "dict[string, DotnetTargetingPackInfo]",
        "runtime_pack_infos": "dict[string, DotnetRuntimePackInfo]",
    },
)

# Avoid using non-normalized paths (workspace/../other_workspace/path)
def _to_manifest_path(ctx, file):
    if file.short_path.startswith("../"):
        return "external/" + file.short_path[3:]
    else:
        return ctx.workspace_name + "/" + file.short_path

def _tool(ctx, target, fallback_path):
    """The manifest path of a tool target and everything it carries.

    The files stay a depset so that every action and binary the toolchain reaches
    shares one node instead of a copy of the list.

    Args:
        ctx: The toolchain rule context.
        target: The tool target, or None when the toolchain names a path instead.
        fallback_path: The path to use when `target` is None.

    Returns:
        A (path, depset[File]) tuple.
    """
    if not target:
        return fallback_path, depset()

    # The tool itself is the filegroup's `srcs`; the runfiles carry the rest.
    return (
        _to_manifest_path(ctx, target.files.to_list()[0]),
        depset(transitive = [target.files, target.default_runfiles.files]),
    )

def _dotnet_toolchain_impl(ctx):
    if ctx.attr.runtime and ctx.attr.runtime_path:
        fail("Can only set one of runtime or runtime_path but both were set.")
    if not ctx.attr.runtime and not ctx.attr.runtime_path:
        fail("Must set one of runtime or runtime_path.")

    if ctx.attr.csharp_compiler and ctx.attr.csharp_compiler_path:
        fail("Can only set one of csharp_compiler or csharp_compiler_path but both were set.")
    if not ctx.attr.csharp_compiler and not ctx.attr.csharp_compiler_path:
        fail("Must set one of csharp_compiler or csharp_compiler_path.")

    if ctx.attr.fsharp_compiler and ctx.attr.fsharp_compiler_path:
        fail("Can only set one of fsharp_compiler or fsharp_compiler_path but both were set.")
    if not ctx.attr.fsharp_compiler and not ctx.attr.fsharp_compiler_path:
        fail("Must set one of fsharp_compiler or fsharp_compiler_path.")

    runtime_path, runtime_files = _tool(ctx, ctx.attr.runtime, ctx.attr.runtime_path)
    csharp_compiler_path, csharp_compiler_files = _tool(ctx, ctx.attr.csharp_compiler, ctx.attr.csharp_compiler_path)
    fsharp_compiler_path, fsharp_compiler_files = _tool(ctx, ctx.attr.fsharp_compiler, ctx.attr.fsharp_compiler_path)

    # A binary runs on the host, which carries every shared framework but not the
    # SDK. Fall back to `runtime` when the toolchain does not name a host.
    runtime_host_files = runtime_files
    if ctx.attr.runtime_host:
        _, runtime_host_files = _tool(ctx, ctx.attr.runtime_host, "")

    # Make the $(tool_BIN) variable available in places like genrules.
    # See https://docs.bazel.build/versions/main/be/make-variables.html#custom_variables
    template_variables = platform_common.TemplateVariableInfo({
        "DOTNET_BIN": runtime_path,
        "CSC_BIN": csharp_compiler_path,
        "FSC_BIN": fsharp_compiler_path,
        "DOTNET_SDK_VERSION": ctx.attr.sdk_version,
        "DOTNET_RUNTIME_VERSION": ctx.attr.runtime_version,
        "DOTNET_RUNTIME_TFM": ctx.attr.runtime_tfm,
    })

    toolchain_files = depset(transitive = [runtime_files, csharp_compiler_files, fsharp_compiler_files])
    default = DefaultInfo(
        files = toolchain_files,
        runfiles = ctx.runfiles(transitive_files = toolchain_files),
    )

    targeting_pack_infos = {
        "default": DotnetTargetingPackInfo(
            assembly_compile_infos = [_compile_info("Microsoft.NETCore.App.Ref", ctx.attr.runtime_version, ctx.files.targeting_pack_default_refs, "default")],
            assembly_runtime_infos = [],
            nuget_infos = [_nuget_info()],
        ),
        "web": DotnetTargetingPackInfo(
            assembly_compile_infos = [
                _compile_info("Microsoft.NETCore.App.Ref", ctx.attr.runtime_version, ctx.files.targeting_pack_default_refs, "web"),
                _compile_info("Microsoft.AspNetCore.App.Ref", ctx.attr.runtime_version, ctx.files.targeting_pack_web_refs, "web"),
            ],
            assembly_runtime_infos = [],
            nuget_infos = [_nuget_info(), _nuget_info()],
        ),
    }
    runtime_pack_infos = {
        "default": DotnetRuntimePackInfo(
            runtime_identifier = ctx.attr.runtime_identifier,
            assembly_runtime_infos = [
                _runtime_info("Microsoft.NETCore.App.Runtime.{}".format(ctx.attr.runtime_identifier), ctx.attr.runtime_version, ctx.files.runtime_pack_default_libs, ctx.files.runtime_pack_default_native),
            ],
            nuget_infos = [],
        ),
        "web": DotnetRuntimePackInfo(
            runtime_identifier = ctx.attr.runtime_identifier,
            assembly_runtime_infos = [
                _runtime_info("Microsoft.NETCore.App.Runtime.{}".format(ctx.attr.runtime_identifier), ctx.attr.runtime_version, ctx.files.runtime_pack_default_libs, ctx.files.runtime_pack_default_native),
                _runtime_info("Microsoft.AspNetCore.App.Runtime.{}".format(ctx.attr.runtime_identifier), ctx.attr.runtime_version, ctx.files.runtime_pack_web_libs, ctx.files.runtime_pack_web_native),
            ],
            nuget_infos = [],
        ),
    }

    dotnetinfo = DotnetInfo(
        runtime_path = runtime_path,
        runtime_files = runtime_host_files,
        csharp_compiler_path = csharp_compiler_path,
        csharp_compiler_files = csharp_compiler_files,
        fsharp_compiler_path = fsharp_compiler_path,
        fsharp_compiler_files = fsharp_compiler_files,
        sdk_version = ctx.attr.sdk_version,
        runtime_version = ctx.attr.runtime_version,
        wasm_runtime_version = ctx.attr.wasm_runtime_version or ctx.attr.runtime_version,
        runtime_tfm = ctx.attr.runtime_tfm,
        csharp_default_version = ctx.attr.csharp_default_version,
        fsharp_default_version = ctx.attr.fsharp_default_version,
        targeting_pack_infos = targeting_pack_infos,
        runtime_pack_infos = runtime_pack_infos,
    )

    # Export all the providers inside our ToolchainInfo
    # so the resolved_toolchain rule can grab and re-export them.
    toolchain_info = platform_common.ToolchainInfo(
        default = default,
        dotnetinfo = dotnetinfo,
        template_variables = template_variables,
        runtime = ctx.attr.runtime,
        compiler_host = ctx.attr.compiler_host or ctx.attr.runtime,
        csharp_compiler = ctx.attr.csharp_compiler,
        fsharp_compiler = ctx.attr.fsharp_compiler,
        host_model = ctx.attr.host_model,
        strict_deps = ctx.attr._strict_deps,
        aspnetcore_razor_toolset = ctx.attr.aspnetcore_razor_toolset,
        wasm_workload_files = ctx.files.wasm_workload_files,
    )
    return [
        default,
        toolchain_info,
        template_variables,
    ]

dotnet_toolchain = rule(
    implementation = _dotnet_toolchain_impl,
    attrs = {
        "runtime": attr.label(
            doc = "The dotnet CLI",
            mandatory = False,
            executable = True,
            cfg = "exec",
        ),
        "compiler_host": attr.label(
            doc = """The dotnet host a compilation runs on: the muxer, hostfxr and Microsoft.NETCore.App.

Defaults to `runtime`, which also carries the SDK the compilers do not need.""",
            mandatory = False,
            executable = True,
            cfg = "exec",
        ),
        "runtime_host": attr.label(
            doc = """The dotnet host a binary runs on: the muxer, hostfxr and every shared framework.

Defaults to `runtime`, which also carries the SDK a binary does not need.""",
            mandatory = False,
            executable = True,
            cfg = "target",
        ),
        "runtime_path": attr.string(
            doc = "Path to the dotnet CLI. Do not set if `runtime` is set",
            mandatory = False,
        ),
        "csharp_compiler": attr.label(
            doc = "The C# compiler binary",
            mandatory = False,
            executable = True,
            cfg = "exec",
        ),
        "csharp_compiler_path": attr.string(
            doc = "Path to the C# compiler binary. Do not set if `csharp_compiler` is set",
            mandatory = False,
        ),
        "fsharp_compiler": attr.label(
            doc = "The F# compiler binary",
            mandatory = False,
            executable = True,
            cfg = "exec",
        ),
        "fsharp_compiler_path": attr.string(
            doc = "Path to the F# compiler binary. Do not set if `fsharp_compiler` is set",
            mandatory = False,
        ),
        "host_model": attr.label(
            doc = "The System.NET.HostModel DLL",
            mandatory = False,
        ),
        "sdk_version": attr.string(
            doc = "The SDK version of the current dotnet SDK",
            mandatory = True,
        ),
        "runtime_version": attr.string(
            doc = "The runtime version of the current dotnet SDK",
            mandatory = True,
        ),
        "wasm_runtime_version": attr.string(
            doc = "The WebAssembly workload runtime version available to the current SDK",
        ),
        "runtime_tfm": attr.string(
            doc = "The runtime target framework moniker of the current dotnet SDK",
            mandatory = True,
        ),
        "csharp_default_version": attr.string(
            doc = "The default C# version used by the current dotnet SDK",
            mandatory = True,
        ),
        "fsharp_default_version": attr.string(
            doc = "The default F# version used by the current dotnet SDK",
            mandatory = True,
        ),
        "aspnetcore_razor_toolset": attr.label(
            doc = "The ASP.NET Core Razor toolset assemblies from Microsoft.NET.Sdk.Razor",
            mandatory = False,
        ),
        "_strict_deps": attr.label(
            doc = "Whether to use strict deps or not",
            default = "//dotnet/settings:strict_deps",
        ),
        "runtime_identifier": attr.string(
            doc = "The runtime identifier of the current SDK",
            mandatory = True,
        ),
        "targeting_pack_default_refs": attr.label_list(allow_files = [".dll"]),
        "targeting_pack_web_refs": attr.label_list(allow_files = [".dll"]),
        "runtime_pack_default_libs": attr.label_list(allow_files = [".dll"]),
        "runtime_pack_default_native": attr.label_list(allow_files = True),
        "runtime_pack_web_libs": attr.label_list(allow_files = [".dll"]),
        "runtime_pack_web_native": attr.label_list(allow_files = True),
        "wasm_workload_files": attr.label_list(allow_files = True),
    },
    doc = """Defines a dotnet compiler/runtime toolchain.

For usage see https://docs.bazel.build/versions/main/toolchains.html#defining-toolchains.
""",
)
