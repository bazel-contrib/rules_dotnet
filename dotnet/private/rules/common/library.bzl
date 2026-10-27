"Common implementation for building .Net libraries"

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("//dotnet/private:common.bzl", "collect_transitive_runfiles")
load("//dotnet/private/rules/common:static_web_assets.bzl", "collect_static_web_assets")
load("//dotnet/private/rules/ready_to_run:ready_to_run.bzl", "with_ready_to_run_images")

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

    (compile_provider, runtime_provider, generated_assets) = compile_action(ctx, tfm, toolchain)
    runtime_provider = with_ready_to_run_images(ctx, runtime_provider)

    return [
        compile_provider,
        runtime_provider,
        collect_static_web_assets(
            label = ctx.label,
            assembly_name = runtime_provider.name,
            files = ctx.files.static_web_assets,
            deps = ctx.attr.deps,
            is_application = False,
            generated = generated_assets,
        ),
        DefaultInfo(
            files = depset(
                runtime_provider.libs + runtime_provider.xml_docs +
                [asset.file for asset in generated_assets],
            ),
            default_runfiles = collect_transitive_runfiles(
                ctx,
                runtime_provider,
                ctx.attr.deps,
            ),
        ),
    ]
