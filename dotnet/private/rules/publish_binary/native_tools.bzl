"""The native compiler a publish asks its binary for, for the binary's framework."""

load("//dotnet/private:providers.bzl", "DotnetNativeAotPackInfo", "DotnetNativeToolsInfo")
load("//dotnet/private/sdk/nativeaot_packs:nativeaot_pack_transition.bzl", "nativeaot_pack_transition")

_CROSSGEN2_TOOLCHAIN_TYPE = Label("//dotnet/private/sdk/crossgen2_packs:toolchain_type")
_ILCOMPILER_TOOLCHAIN_TYPE = Label("//dotnet/private/sdk/ilcompiler_packs:toolchain_type")

def _host_tool_pack(ctx, toolchain_type, attr_name):
    toolchain = ctx.toolchains[toolchain_type]

    if toolchain == None:
        fail("{} needs {}, but no execution platform has one registered".format(attr_name, toolchain_type))

    return toolchain.pack

def _native_tools_impl(ctx):
    return [DotnetNativeToolsInfo(
        crossgen2 = _host_tool_pack(ctx, _CROSSGEN2_TOOLCHAIN_TYPE, "ready_to_run") if ctx.attr.compiler == "crossgen2" else None,
        ilcompiler = _host_tool_pack(ctx, _ILCOMPILER_TOOLCHAIN_TYPE, "native_aot") if ctx.attr.compiler == "ilcompiler" else None,
        nativeaot_pack = ctx.attr.nativeaot_pack[0][DotnetNativeAotPackInfo] if ctx.attr.nativeaot_pack else None,
    )]

native_tools = rule(
    _native_tools_impl,
    doc = """The native compiler a ReadyToRun or NativeAOT publish asks its binary for.

Resolved in the binary's configuration, so that crossgen2, ilc and the NativeAOT
framework follow the framework the binary picked.""",
    attrs = {
        "compiler": attr.string(
            values = ["crossgen2", "ilcompiler"],
            mandatory = True,
        ),
        "nativeaot_pack": attr.label(
            cfg = nativeaot_pack_transition,
            providers = [DotnetNativeAotPackInfo],
        ),
    },
    toolchains = [
        config_common.toolchain_type(_CROSSGEN2_TOOLCHAIN_TYPE, mandatory = False),
        config_common.toolchain_type(_ILCOMPILER_TOOLCHAIN_TYPE, mandatory = False),
    ],
    provides = [DotnetNativeToolsInfo],
)
