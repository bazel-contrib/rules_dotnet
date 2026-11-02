"""Incoming transition for the rules that build rules_dotnet's own tools.

A tool is always built for the exec platform, so it is pinned to the one
framework it names and the host platform's RID rather than inheriting the TFM
and RID of whatever target depends on it. That framework has to be one the
bootstrap SDK knows, which need not be the newest the user's SDK does.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "NO_READY_TO_RUN",
    "TFM_RID_TRANSITION_OUTPUTS",
    "platform_to_rid",
    "rid_compatability_transition_outputs",
)

def _impl(_settings, attr):
    if len(attr.target_frameworks) != 1:
        fail("{} is a tool of rules_dotnet's, so its `target_frameworks` names the one framework it builds for".format(attr.name))

    tfm = attr.target_frameworks[0]
    rid = platform_to_rid()
    return dicts.add(
        {"//dotnet:target_framework": tfm, "//dotnet:rid": rid},
        FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[tfm],
        rid_compatability_transition_outputs(rid),
        NO_READY_TO_RUN,
    )

bootstrap_tool_transition = transition(
    implementation = _impl,
    inputs = [],
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
