"""
Rule for compiling C# binaries.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:common.bzl",
    "get_compiler_worker",
    "get_compiler_wrapper",
    "get_targeting_pack",
    "get_toolchain",
    "is_debug",
    "targets_windows",
)
load("//dotnet/private/rules/common:attrs.bzl", "CSHARP_BINARY_COMMON_ATTRS", "CSHARP_BOOTSTRAP_BINARY_COMMON_ATTRS")
load("//dotnet/private/rules/common:binary.bzl", "build_binary")
load("//dotnet/private/rules/common:stamping.bzl", "maybe_stamp_srcs")
load("//dotnet/private/rules/csharp/actions:csharp_assembly.bzl", "AssemblyAction")
load("//dotnet/private/transitions:apphost_shimmer_transition.bzl", "apphost_shimmer_transition")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _compile_action(ctx, tfm):
    toolchain = get_toolchain(ctx)
    srcs = maybe_stamp_srcs(ctx, ctx.files.srcs, ctx.attr.out or ctx.attr.name, tfm, "csharp")

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
        targeting_pack = get_targeting_pack(ctx),
        internals_visible_to = ctx.attr.internals_visible_to,
        keyfile = ctx.file.keyfile,
        langversion = ctx.attr.langversion if ctx.attr.langversion != "" else toolchain.dotnetinfo.csharp_default_version,
        resources = ctx.files.resources,
        srcs = srcs,
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
    result = build_binary(ctx, _compile_action)
    return result

_INCLUDE_HOST_MODEL_ATTR = {
    "include_host_model_dll": attr.bool(
        doc = "Whether to include Microsoft.NET.HostModel from the toolchain. This is only required to build tha apphost shimmer.",
        default = False,
    ),
}

_BINARY_ATTRS = dicts.add(CSHARP_BINARY_COMMON_ATTRS, _INCLUDE_HOST_MODEL_ATTR)
_BOOTSTRAP_BINARY_ATTRS = dicts.add(CSHARP_BOOTSTRAP_BINARY_COMMON_ATTRS, _INCLUDE_HOST_MODEL_ATTR)

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

apphost_shimmer_binary = rule(
    _binary_private_impl,
    doc = """Compile the apphost shimmer C# exe.""",
    attrs = _BINARY_ATTRS,
    executable = True,
    toolchains = [
        "//dotnet:toolchain_type",
    ],
    cfg = apphost_shimmer_transition,
)

_COMPILER_WORKER_ATTRS = {
    name: value
    for (name, value) in _BOOTSTRAP_BINARY_ATTRS.items()
    if name != "_compiler_worker"
}

compiler_worker_binary = rule(
    _binary_private_impl,
    doc = """Compile the persistent compiler worker C# exe.""",
    attrs = _COMPILER_WORKER_ATTRS,
    executable = True,
    toolchains = [
        "//dotnet:toolchain_type",
    ],
    cfg = apphost_shimmer_transition,
)

csharp_bootstrap_binary = rule(
    _binary_private_impl,
    doc = "Compile an internal C# exe without stamping support.",
    attrs = _BOOTSTRAP_BINARY_ATTRS,
    executable = True,
    toolchains = [
        "//dotnet:toolchain_type",
    ],
    cfg = apphost_shimmer_transition,
)
