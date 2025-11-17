"""
Rule for compiling F# libraries.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:common.bzl",
    "get_toolchain",
    "is_debug",
)
load("//dotnet/private/rules/common:attrs.bzl", "FSHARP_LIBRARY_COMMON_ATTRS")
load("//dotnet/private/rules/common:library.bzl", "build_library")
load("//dotnet/private/rules/fsharp/actions:fsharp_assembly.bzl", "AssemblyAction")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _compile_action(ctx, tfm):
    toolchain = get_toolchain(ctx)

    return AssemblyAction(
        ctx.actions,
        ctx.executable._compiler_wrapper_bat if ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]) else ctx.executable._compiler_wrapper_sh,
        label = ctx.label,
        debug = is_debug(ctx),
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
        exports = ctx.attr.exports,
        targeting_pack = ctx.attr._targeting_pack[0],
        internals_visible_to = ctx.attr.internals_visible_to,
        keyfile = ctx.file.keyfile,
        langversion = ctx.attr.langversion if ctx.attr.langversion != "" else toolchain.dotnetinfo.fsharp_default_version,
        resources = ctx.files.resources,
        srcs = ctx.files.srcs,
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
        treat_warnings_as_errors = ctx.attr.treat_warnings_as_errors,
        warnings_as_errors = ctx.attr.warnings_as_errors,
        warnings_not_as_errors = ctx.attr.warnings_not_as_errors,
        warning_level = ctx.attr.warning_level,
        nowarn = ctx.attr.nowarn,
        project_sdk = ctx.attr.project_sdk,
        compiler_options = ctx.attr.compiler_options,
        is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo]),
    )

def _library_impl(ctx):
    return build_library(ctx, _compile_action)

fsharp_library = rule(
    _library_impl,
    doc = "Compile a F# DLL",
    attrs = FSHARP_LIBRARY_COMMON_ATTRS,
    executable = False,
    toolchains = ["//dotnet:toolchain_type"],
    cfg = tfm_transition,
)
