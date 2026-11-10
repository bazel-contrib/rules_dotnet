"""The C/C++ toolchain a NativeAOT publish links with.

Only the native tools of a NativeAOT publish reach it, so no other build needs
a C/C++ toolchain registered. Those are configured for the binary's framework,
but the toolchain reads no .NET setting. Resolved through this target in the
configuration native code is built in, it is analysed once per runtime
identifier, beside any native library the application ships, rather than once
for every framework published.
"""

_CC_TOOLCHAIN_TYPE = "@bazel_tools//tools/cpp:toolchain_type"

CcLinkToolchainInfo = provider(
    doc = "The C/C++ toolchain of the platform being published for.",
    fields = {
        "toolchain": "The resolved `@bazel_tools//tools/cpp:toolchain_type`, or None if none is registered.",
    },
)

def _cc_link_toolchain_impl(ctx):
    return [CcLinkToolchainInfo(toolchain = ctx.toolchains[_CC_TOOLCHAIN_TYPE])]

cc_link_toolchain = rule(
    _cc_link_toolchain_impl,
    doc = "Resolves the C/C++ toolchain a NativeAOT publish links with.",
    # Only a NativeAOT publish links native code, so a build that never asks
    # for one does not need a C/C++ toolchain registered.
    toolchains = [config_common.toolchain_type(_CC_TOOLCHAIN_TYPE, mandatory = False)],
    provides = [CcLinkToolchainInfo],
)
