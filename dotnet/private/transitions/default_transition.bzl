"""Resets the target framework and runtime identifier to their defaults.

For edges to sources and data, which are not built against the framework of
the target using them: a binary carried as data, for one, is then built once
rather than once per framework of the targets carrying it.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "DEFAULT_RID",
    "DEFAULT_TFM",
)
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "NO_READY_TO_RUN",
    "TFM_RID_TRANSITION_OUTPUTS",
    "rid_compatability_transition_outputs",
)

# The settings an untouched configuration starts with, compatibility settings
# included. Built once at load time.
DEFAULT_OUTPUTS = dicts.add(
    {"//dotnet:target_framework": DEFAULT_TFM, "//dotnet:rid": DEFAULT_RID},
    FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[DEFAULT_TFM],
    rid_compatability_transition_outputs(DEFAULT_RID),
    NO_READY_TO_RUN,
)

def _impl(_settings, _attr):
    return DEFAULT_OUTPUTS

default_transition = transition(
    implementation = _impl,
    inputs = [],
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
