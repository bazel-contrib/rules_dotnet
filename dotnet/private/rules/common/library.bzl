"Common implementation for building .Net libraries"

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//dotnet/private:common.bzl", "collect_transitive_runfiles")
load(
    "//dotnet/private/rules/common:compile_info.bzl",
    "gather_compile_info"
)

def build_library(ctx, compile_action):
    """Builds a .Net library from a compilation action

    Args:
        ctx: Bazel build ctx.
        compile_action: A compilation function
            Args:
                ctx: Bazel build ctx.
                tfm: Target framework string
            Returns:
                An tuple of (DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo)
    Returns:
        A collection of the references, runfiles and native dlls.
    """
    tfm = ctx.attr._target_framework[BuildSettingInfo].value

    (compile_provider, runtime_provider) = compile_action(ctx, tfm)

    compile_info_provider = gather_compile_info(ctx)

    return [
        compile_provider,
        runtime_provider,
        compile_info_provider,
        DefaultInfo(
            files = depset(runtime_provider.libs + runtime_provider.xml_docs),
            default_runfiles = collect_transitive_runfiles(
                ctx,
                runtime_provider,
                ctx.attr.deps,
            ),
        ),
    ]
