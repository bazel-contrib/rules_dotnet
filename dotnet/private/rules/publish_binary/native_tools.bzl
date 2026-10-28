"""The native compiler a publish asks its binary for, for the binary's framework."""

load("//dotnet/private:providers.bzl", "DotnetNativeAotPackInfo", "DotnetNativeToolsInfo", "DotnetToolPackInfo")
load("//dotnet/private/sdk/nativeaot_packs:nativeaot_pack_transition.bzl", "nativeaot_pack_transition")

def _native_tools_impl(ctx):
    return [DotnetNativeToolsInfo(
        crossgen2 = ctx.attr.crossgen2[DotnetToolPackInfo] if ctx.attr.crossgen2 else None,
        ilcompiler = ctx.attr.ilcompiler[DotnetToolPackInfo] if ctx.attr.ilcompiler else None,
        nativeaot_pack = ctx.attr.nativeaot_pack[0][DotnetNativeAotPackInfo] if ctx.attr.nativeaot_pack else None,
    )]

native_tools = rule(
    _native_tools_impl,
    doc = """The native compiler a ReadyToRun or NativeAOT publish asks its binary for.

Resolved in the binary's configuration, so that crossgen2, ilc and the NativeAOT
framework follow the framework the binary picked.""",
    attrs = {
        "crossgen2": attr.label(providers = [DotnetToolPackInfo]),
        "ilcompiler": attr.label(providers = [DotnetToolPackInfo]),
        "nativeaot_pack": attr.label(
            cfg = nativeaot_pack_transition,
            providers = [DotnetNativeAotPackInfo],
        ),
    },
    provides = [DotnetNativeToolsInfo],
)
