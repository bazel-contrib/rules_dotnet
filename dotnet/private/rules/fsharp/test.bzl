"""
Rule for compiling and running test binaries.

This rule can be used to compile and run any F# binary and run it as
a Bazel test.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:common.bzl",
    "get_compiler_wrapper",
    "get_toolchain",
    "is_debug",
    "targets_windows",
)
load("//dotnet/private/rules/common:attrs.bzl", "FSHARP_BINARY_COMMON_ATTRS")
load("//dotnet/private/rules/common:binary.bzl", "build_binary")
load("//dotnet/private/rules/fsharp/actions:fsharp_assembly.bzl", "AssemblyAction")
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _compile_action(ctx, tfm, toolchain):
    return AssemblyAction(
        ctx.actions,
        get_compiler_wrapper(ctx),
        label = ctx.label,
        debug = is_debug(ctx),
        defines = ctx.attr.defines,
        deps = ctx.attr.deps,
        exports = [],
        targeting_pack = ctx.attr._targeting_pack[0],
        internals_visible_to = ctx.attr.internals_visible_to,
        keyfile = ctx.file.keyfile,
        # MSBuild passes no --langversion for F#; fsc then defaults to latest.
        langversion = ctx.attr.langversion,
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
        treat_warnings_as_errors = ctx.attr.treat_warnings_as_errors,
        warnings_as_errors = ctx.attr.warnings_as_errors,
        warnings_not_as_errors = ctx.attr.warnings_not_as_errors,
        warning_level = ctx.attr.warning_level,
        nowarn = ctx.attr.nowarn,
        project_sdk = ctx.attr.project_sdk,
        compiler_options = ctx.attr.compiler_options,
        is_windows = targets_windows(ctx),
    )

def _fsharp_test_impl(ctx):
    return build_binary(ctx, _compile_action, get_toolchain(ctx))

fsharp_test = rule(
    _fsharp_test_impl,
    doc = """Compile a F# executable and runs it as a test""",
    attrs = FSHARP_BINARY_COMMON_ATTRS,
    test = True,
    toolchains = [
        "//dotnet:toolchain_type",
    ],
    cfg = tfm_transition,
)
