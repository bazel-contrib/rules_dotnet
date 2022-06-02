"""
Common implementation for building a .Net library
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

def build_library(ctx, compile_action):
    """Builds a .Net library from a compilation action

    Args:
        ctx: Bazel build ctx.
        compile_action: A compilation function
            Args:
                ctx: Bazel build ctx.
                tfm: Target framework string
                stdrefs: .Net standard library references
            Returns:
                An DotnetAssemblyInfo provider
    Returns:
        A collection of the references, runfiles and native dlls.
    """
    tfm = ctx.attr._target_framework[BuildSettingInfo].value

    result = [compile_action(ctx, tfm)]

    result.append(DefaultInfo(
        files = depset(result[0].libs),
        default_runfiles = ctx.runfiles(files = result[0].data),
    ))

    return result
