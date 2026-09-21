"""A transition onto the browser, for the packs a WebAssembly publish reads.

Only the packs make this move. The application itself is an ordinary managed
assembly built for the host, and transitioning it would send it looking for an
apphost and a runtime pack that no browser has.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private/sdk:packs.bzl", "WASM_RID")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "TFM_RID_TRANSITION_OUTPUTS",
    "rid_compatability_transition_outputs",
)

def _impl(_settings, attr):
    return dicts.add(
        {
            "//dotnet:target_framework": attr.target_framework,
            "//dotnet:rid": WASM_RID,
        },
        FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[attr.target_framework],
        rid_compatability_transition_outputs(WASM_RID),
    )

wasm_pack_transition = transition(
    implementation = _impl,
    inputs = [],
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
