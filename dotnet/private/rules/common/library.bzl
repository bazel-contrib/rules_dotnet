"Common implementation for building .Net libraries"

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//dotnet/private:common.bzl", "collect_transitive_runfiles")

def build_library(ctx, compile_action, toolchain):
    """Builds a .Net library from a compilation action

    Args:
        ctx: Bazel build ctx.
        compile_action: A function taking (ctx, tfm, toolchain) that compiles the srcs
            and returns a (DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo) tuple.
        toolchain: The .Net toolchain to compile with.
    Returns:
        A collection of the references, runfiles and native dlls.
    """
    tfm = ctx.attr._target_framework[BuildSettingInfo].value

    (compile_provider, runtime_provider) = compile_action(ctx, tfm, toolchain)

    return [
        compile_provider,
        runtime_provider,
        DefaultInfo(
            files = depset(runtime_provider.libs + runtime_provider.xml_docs),
            default_runfiles = collect_transitive_runfiles(
                ctx,
                runtime_provider,
                ctx.attr.deps,
            ),
        ),
    ]
