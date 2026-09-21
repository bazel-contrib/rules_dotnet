"""
Rule for compiling C# binaries.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:common.bzl",
    "default_csharp_lang_version",
    "get_compiler_wrapper",
    "get_csharp_compiler_worker",
    "get_toolchain",
    "is_debug",
    "targets_windows",
)
load("//dotnet/private:toolchains_repo.bzl", "BOOTSTRAP_TOOLCHAIN_TYPE")
load("//dotnet/private/rules/common:attrs.bzl", "CSHARP_BINARY_COMMON_ATTRS")
load("//dotnet/private/rules/common:binary.bzl", "build_binary")
load("//dotnet/private/rules/csharp/actions:csharp_assembly.bzl", "AssemblyAction")
load("//dotnet/private/sdk:packs.bzl", "BOOTSTRAP_PACKS")
load("//dotnet/private/transitions:bootstrap_tool_transition.bzl", "bootstrap_tool_transition")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _compile_action(ctx, tfm, toolchain):
    return AssemblyAction(
        ctx.actions,
        get_compiler_wrapper(ctx),
        compiler_worker = get_csharp_compiler_worker(ctx),
        label = ctx.label,
        additionalfiles = ctx.files.additionalfiles,
        debug = is_debug(ctx),
        embed_sources = ctx.attr.embed_sources,
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
        exports = [],
        targeting_pack = ctx.attr._targeting_pack[0],
        internals_visible_to = ctx.attr.internals_visible_to,
        keyfile = ctx.file.keyfile,
        langversion = ctx.attr.langversion if ctx.attr.langversion != "" else default_csharp_lang_version(tfm, toolchain.dotnetinfo.csharp_default_version),
        resources = ctx.files.resources,
        srcs = ctx.files.srcs,
        data = ctx.files.data,
        appsetting_files = ctx.files.appsetting_files,
        compile_data = ctx.files.compile_data,
        out = ctx.attr.out,
        target = "exe",
        target_name = ctx.attr.name,
        target_framework = tfm,
        toolchain = toolchain,
        strict_deps = toolchain.strict_deps[BuildSettingInfo].value,
        generate_documentation_file = ctx.attr.generate_documentation_file,
        include_host_model_dll = ctx.attr.include_host_model_dll,
        include_msbuild_dlls = ctx.attr.include_msbuild_dlls,
        treat_warnings_as_errors = ctx.attr.treat_warnings_as_errors,
        warnings_as_errors = ctx.attr.warnings_as_errors,
        warnings_not_as_errors = ctx.attr.warnings_not_as_errors,
        warning_level = ctx.attr.warning_level,
        nowarn = ctx.attr.nowarn,
        project_sdk = ctx.attr.project_sdk,
        root_namespace = ctx.attr.root_namespace,
        scoped_css_tool = ctx.attr._scoped_css_tool,
        allow_unsafe_blocks = ctx.attr.allow_unsafe_blocks,
        nullable = ctx.attr.nullable,
        run_analyzers = ctx.attr.run_analyzers,
        is_analyzer = False,
        is_language_specific_analyzer = False,
        analyzer_configs = ctx.files.analyzer_configs,
        compiler_options = ctx.attr.compiler_options,
        interceptors_namespaces = ctx.attr.interceptors_namespaces,
        is_windows = targets_windows(ctx),
    )

def _binary_impl(ctx):
    return build_binary(ctx, _compile_action, get_toolchain(ctx))

def _bootstrap_binary_impl(ctx):
    return build_binary(ctx, _compile_action, ctx.toolchains[BOOTSTRAP_TOOLCHAIN_TYPE])

_BINARY_ATTRS = dicts.add(
    CSHARP_BINARY_COMMON_ATTRS,
    {
        "include_host_model_dll": attr.bool(
            doc = "Whether to include Microsoft.NET.HostModel from the toolchain. This is only required to build tha apphost shimmer.",
            default = False,
        ),
        "include_msbuild_dlls": attr.bool(
            doc = "Whether to include the MSBuild interfaces from the toolchain. This is only required by tools that run an SDK build task directly.",
            default = False,
        ),
    },
)

csharp_binary = rule(
    _binary_impl,
    doc = """Compile a C# exe""",
    attrs = _BINARY_ATTRS,
    executable = True,
    toolchains = [
        "//dotnet:toolchain_type",
    ],
    cfg = tfm_transition,
)

# The rules below build tools of rules_dotnet's own, so they follow the
# bootstrap toolchain rather than the user's: its SDK compiles them and its
# packs are what they compile against. The attributes pointing at rules_dotnet's
# own tools are stubbed out rather than dropped - a tool cannot depend on
# itself, and nothing these rules compile has Razor sources or web assets, so
# neither tool is ever invoked.
_BOOTSTRAP_ATTRS = dicts.add(
    _BINARY_ATTRS,
    {
        "_pack_set": attr.string(default = BOOTSTRAP_PACKS),
        "_scoped_css_tool": attr.label(default = "//dotnet/private:no_tool", cfg = "exec"),
        "_static_web_assets_tool": attr.label(default = "//dotnet/private:no_tool", cfg = "exec"),
    },
)

# A tool is built for the exec configuration, but `cfg = "exec"` is not enough
# on its own: the TFM/RID graph has to be reset to the defaults as well, so that
# the depending target's target framework does not infect the tool's build.
bootstrap_tool_binary = rule(
    _bootstrap_binary_impl,
    doc = """Compile a C# exe that is part of rules_dotnet itself.""",
    attrs = _BOOTSTRAP_ATTRS,
    executable = True,
    toolchains = [
        BOOTSTRAP_TOOLCHAIN_TYPE,
    ],
    cfg = bootstrap_tool_transition,
)

# Every other C# target compiles with the worker, so the workers themselves have
# to compile without it: the C# one would otherwise depend on itself.
_COMPILER_WORKER_ATTRS = {
    name: value
    for (name, value) in _BOOTSTRAP_ATTRS.items()
    if name != "_csharp_compiler_worker"
}

compiler_worker_binary = rule(
    _bootstrap_binary_impl,
    doc = """Compile a persistent compiler worker C# exe.""",
    attrs = _COMPILER_WORKER_ATTRS,
    executable = True,
    toolchains = [
        BOOTSTRAP_TOOLCHAIN_TYPE,
    ],
    cfg = bootstrap_tool_transition,
)
