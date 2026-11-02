"""A transition for the ICU a toolchain carries.

ICU reads no .NET setting: the platform alone decides what is built. Left in
the configuration the toolchain is resolved in, it would be compiled again for
every framework, runtime identifier and pack that reaches the toolchain, and a
compile takes minutes. So every setting the rules' own transitions write goes
back to its default, while the flags of the build are kept: the configuration
is the one the build starts in, or its exec counterpart for a tool.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private/transitions:common.bzl", "TFM_RID_TRANSITION_OUTPUTS")
load("//dotnet/private/transitions:default_transition.bzl", "DEFAULT_OUTPUTS")

# The packs a binary resolves through a transition of its own, each back to the
# empty pack it starts at.
_PACKS = {
    "//dotnet/private/sdk/apphost_packs:apphost_pack": str(Label("//dotnet/private/sdk/apphost_packs:empty_pack")),
    "//dotnet/private/sdk/nativeaot_packs:nativeaot_pack": str(Label("//dotnet/private/sdk/nativeaot_packs:empty_pack")),
    "//dotnet/private/sdk/runtime_packs:runtime_pack": str(Label("//dotnet/private/sdk/runtime_packs:empty_pack")),
    "//dotnet/private/sdk/targeting_packs:targeting_pack": str(Label("//dotnet/private/sdk/targeting_packs:empty_pack")),
}

_OUTPUTS = dicts.add(DEFAULT_OUTPUTS, _PACKS)

def _impl(_settings, _attr):
    return _OUTPUTS

icu_transition = transition(
    implementation = _impl,
    inputs = [],
    outputs = TFM_RID_TRANSITION_OUTPUTS + _PACKS.keys(),
)
