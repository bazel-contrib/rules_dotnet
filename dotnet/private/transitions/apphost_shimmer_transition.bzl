"""Incoming transition for the `apphost_shimmer_binary` rule.

This transition makes sure that the apphost shimmer is always transitioned to
the default TFM and the RID of the host platform. This is needed because
# the apphost shimmer is always built for the exec platform.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "DEFAULT_TFM",
    "FRAMEWORK_COMPATIBILITY",
)
load("//dotnet/private/sdk:rids.bzl", "RUNTIME_GRAPH")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "RID_COMPATABILITY_TRANSITION_OUTPUTS",
    "platform_to_rid",
)

def _impl(_settings, _attr):
    tfm = DEFAULT_TFM
    rid = platform_to_rid()
    return dicts.add(
        {"//dotnet:target_framework": tfm, "//dotnet:rid": rid},
        FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[tfm],
        RID_COMPATABILITY_TRANSITION_OUTPUTS[rid],
    )

apphost_shimmer_transition = transition(
    implementation = _impl,
    inputs = [],
    outputs = ["//dotnet:target_framework", "//dotnet:rid"] +
              ["//dotnet:framework_compatible_%s" % framework for framework in FRAMEWORK_COMPATIBILITY.keys()] +
              ["//dotnet:rid_compatible_%s" % rid for rid in RUNTIME_GRAPH.keys()],
)
