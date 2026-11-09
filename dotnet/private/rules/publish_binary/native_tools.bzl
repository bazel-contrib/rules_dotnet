"""The native compiler a publish asks its binary for, for the binary's framework."""

load("//dotnet/private:providers.bzl", "DotnetNativeAotPackInfo", "DotnetNativeToolsInfo", "DotnetToolPackInfo")
load("//dotnet/private/sdk/nativeaot_packs:nativeaot_pack_transition.bzl", "nativeaot_pack_transition")
load("//dotnet/private/transitions:native_transition.bzl", "native_transition")
load(":cc_link_toolchain.bzl", "CcLinkToolchainInfo")

def _native_tools_impl(ctx):
    return [DotnetNativeToolsInfo(
        crossgen2 = ctx.attr.crossgen2[DotnetToolPackInfo] if ctx.attr.crossgen2 else None,
        ilcompiler = ctx.attr.ilcompiler[DotnetToolPackInfo] if ctx.attr.ilcompiler else None,
        nativeaot_pack = ctx.attr.nativeaot_pack[0][DotnetNativeAotPackInfo] if ctx.attr.nativeaot_pack else None,
        cc_link_toolchain = ctx.attr.cc_link_toolchain[0][CcLinkToolchainInfo].toolchain if ctx.attr.cc_link_toolchain else None,
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
        # Here rather than on the publish, so that only a NativeAOT publish
        # resolves a C/C++ toolchain. In the configuration native libraries are
        # built in, rather than the framework's: see cc_link_toolchain.bzl.
        "cc_link_toolchain": attr.label(
            cfg = native_transition,
            providers = [CcLinkToolchainInfo],
        ),
    },
    provides = [DotnetNativeToolsInfo],
)
