"""Incoming transition for the rules that build rules_dotnet's own tools.

A tool is always built for the exec platform, so it is pinned to the default TFM
and the host platform's RID rather than inheriting the TFM and RID of whatever
target depends on it.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "DEFAULT_TFM",
)
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "TFM_RID_TRANSITION_OUTPUTS",
    "platform_to_rid",
    "rid_compatability_transition_outputs",
)

def _impl(_settings, _attr):
    tfm = DEFAULT_TFM
    rid = platform_to_rid()
    return dicts.add(
        {"//dotnet:target_framework": tfm, "//dotnet:rid": rid},
        FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[tfm],
        rid_compatability_transition_outputs(rid),
    )

bootstrap_tool_transition = transition(
    implementation = _impl,
    inputs = [],
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
