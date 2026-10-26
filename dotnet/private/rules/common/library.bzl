"Common implementation for building .Net libraries"

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//dotnet/private:common.bzl", "collect_transitive_runfiles")
load("//dotnet/private/rules/common:compilation.bzl", "compile_once")

def build_library(ctx, compile_action, toolchain):
    """Builds a .Net library from a compilation action

    Args:
        ctx: Bazel build ctx.
        compile_action: A function taking (ctx, tfm, toolchain) that compiles the srcs
            and returns a (DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo,
            generated static web assets) tuple.
        toolchain: The .Net toolchain to compile with.
    Returns:
        A collection of the references, runfiles and native dlls.
    """
    tfm = ctx.attr._target_framework[BuildSettingInfo].value

    compiled = compile_once(ctx, compile_action, tfm, toolchain, is_application = False)

    return [
        compiled.compile_info,
        compiled.runtime_info,
        compiled.static_web_assets_info,
        compiled.inputs_info,
        DefaultInfo(
            files = depset(compiled.files),
            default_runfiles = collect_transitive_runfiles(
                ctx,
                compiled.runtime_info,
                ctx.attr.deps,
            ),
        ),
    ]
