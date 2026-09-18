"""
Rule for compiling C# binaries.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:common.bzl",
    "BOOTSTRAP_TOOLCHAIN_TYPE",
    "default_csharp_lang_version",
    "get_compiler_worker",
    "get_compiler_wrapper",
    "get_toolchain",
    "is_debug",
    "targets_windows",
)
load("//dotnet/private/rules/common:attrs.bzl", "CSHARP_BINARY_COMMON_ATTRS")
load("//dotnet/private/rules/common:binary.bzl", "build_binary")
load("//dotnet/private/rules/csharp/actions:csharp_assembly.bzl", "AssemblyAction")
load("//dotnet/private/transitions:apphost_shimmer_transition.bzl", "apphost_shimmer_transition")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _compile_action(ctx, tfm, toolchain):
    return AssemblyAction(
        ctx.actions,
        get_compiler_wrapper(ctx),
        compiler_worker = get_compiler_worker(ctx),
        label = ctx.label,
        additionalfiles = ctx.files.additionalfiles,
        debug = is_debug(ctx),
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
        treat_warnings_as_errors = ctx.attr.treat_warnings_as_errors,
        warnings_as_errors = ctx.attr.warnings_as_errors,
        warnings_not_as_errors = ctx.attr.warnings_not_as_errors,
        warning_level = ctx.attr.warning_level,
        nowarn = ctx.attr.nowarn,
        project_sdk = ctx.attr.project_sdk,
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

def _binary_private_impl(ctx):
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
    },
)

csharp_binary = rule(
    _binary_private_impl,
    doc = """Compile a C# exe""",
    attrs = _BINARY_ATTRS,
    executable = True,
    toolchains = [
        "//dotnet:toolchain_type",
    ],
    cfg = tfm_transition,
)

# Both rules below build a tool of rules_dotnet's own, so neither takes the
# `dotnet_toolchain` override: the toolchain they compile with is not the user's
# to choose. See `BOOTSTRAP_TOOLCHAIN_TYPE`.
_BOOTSTRAP_ATTRS = {
    name: value
    for (name, value) in _BINARY_ATTRS.items()
    if name != "dotnet_toolchain"
}

# This rule is purely for building the apphost
# shimmer. It is needed because the apphost shimmer
# has to target the exec configuration but we can't
# just set `cfg = "exec"` in publish_binary because
# we also need to reset the TFM/RID graph back to the
# defaults so that the publish_binary's target
# framework does not infect the apphost shimmer build.
apphost_shimmer_binary = rule(
    _bootstrap_binary_impl,
    doc = """Compile the apphost shimmer C# exe.""",
    attrs = _BOOTSTRAP_ATTRS,
    executable = True,
    toolchains = [
        BOOTSTRAP_TOOLCHAIN_TYPE,
    ],
    cfg = apphost_shimmer_transition,
)

# Every other C# target compiles with the worker, so the worker itself has to
# compile without it: depending on itself would be a cycle.
_COMPILER_WORKER_ATTRS = {
    name: value
    for (name, value) in _BOOTSTRAP_ATTRS.items()
    if name != "_compiler_worker"
}

compiler_worker_binary = rule(
    _bootstrap_binary_impl,
    doc = """Compile the persistent compiler worker C# exe.""",
    attrs = _COMPILER_WORKER_ATTRS,
    executable = True,
    toolchains = [
        BOOTSTRAP_TOOLCHAIN_TYPE,
    ],
    cfg = apphost_shimmer_transition,
)
