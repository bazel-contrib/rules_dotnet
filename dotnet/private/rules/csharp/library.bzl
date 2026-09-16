"""
Rule for compiling C# libraries.
"""

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
load("//dotnet/private/rules/common:attrs.bzl", "CSHARP_LIBRARY_COMMON_ATTRS")
load("//dotnet/private/rules/common:library.bzl", "build_library")
load("//dotnet/private/rules/common:stamping.bzl", "maybe_stamp_srcs")
load(
    "//dotnet/private/rules/csharp:global_usings.bzl",
    "collect_global_usings",
    "generate_global_usings_source",
)
load("//dotnet/private/rules/csharp/actions:csharp_assembly.bzl", "AssemblyAction")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _compile_action(ctx, tfm):
    toolchain = get_toolchain(ctx)
    assembly_name = ctx.attr.out or ctx.attr.name
    global_usings = collect_global_usings(ctx.attr.global_usings, ctx.attr.implicit_usings, [])
    global_using_srcs = generate_global_usings_source(
        ctx.actions,
        "%s/%s/%s.GlobalUsings.g.cs" % (ctx.attr.name, tfm, assembly_name),
        global_usings,
    )
    srcs = maybe_stamp_srcs(ctx, ctx.files.srcs + global_using_srcs, assembly_name, tfm, "csharp")

    return AssemblyAction(
        ctx.actions,
        get_compiler_wrapper(ctx),
        compiler_worker = get_compiler_worker(ctx),
        label = ctx.label,
        additionalfiles = ctx.files.additionalfiles,
        debug = is_debug(ctx),
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
        exports = ctx.attr.exports,
        targeting_pack = get_targeting_pack(ctx),
        internals_visible_to = ctx.attr.internals_visible_to,
        keyfile = ctx.file.keyfile,
        langversion = ctx.attr.langversion if ctx.attr.langversion != "" else toolchain.dotnetinfo.csharp_default_version,
        resources = ctx.files.resources,
        srcs = srcs,
        data = ctx.files.data,
        appsetting_files = [],
        compile_data = ctx.files.compile_data,
        out = ctx.attr.out,
        target = "library",
        target_name = ctx.attr.name,
        target_framework = tfm,
        toolchain = toolchain,
        strict_deps = toolchain.strict_deps[BuildSettingInfo].value,
        generate_documentation_file = ctx.attr.generate_documentation_file,
        include_host_model_dll = False,
        treat_warnings_as_errors = ctx.attr.treat_warnings_as_errors,
        warnings_as_errors = ctx.attr.warnings_as_errors,
        warnings_not_as_errors = ctx.attr.warnings_not_as_errors,
        warning_level = ctx.attr.warning_level,
        nowarn = ctx.attr.nowarn,
        project_sdk = ctx.attr.project_sdk,
        allow_unsafe_blocks = ctx.attr.allow_unsafe_blocks,
        nullable = ctx.attr.nullable,
        run_analyzers = ctx.attr.run_analyzers,
        is_analyzer = ctx.attr.is_analyzer,
        is_language_specific_analyzer = ctx.attr.is_language_specific_analyzer,
        analyzer_configs = ctx.files.analyzer_configs,
        compiler_options = ctx.attr.compiler_options,
        interceptors_namespaces = ctx.attr.interceptors_namespaces,
        is_windows = targets_windows(ctx),
    )

def _library_impl(ctx):
    return build_library(ctx, _compile_action)

csharp_library = rule(
    _library_impl,
    doc = "Compile a C# DLL",
    attrs = CSHARP_LIBRARY_COMMON_ATTRS,
    executable = False,
    toolchains = ["//dotnet:toolchain_type"],
    cfg = tfm_transition,
)
