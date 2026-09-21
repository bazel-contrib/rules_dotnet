"""A transition that always transitions back to the default target framework. 

This transition is used to create a disconnect between two TFM graphs. For example
if you have a binary that targets net7.0 and another binary that targets net6.0
but depends on the net7.0 binary as a data dependency then we do not want the TFM
graphqs to be connected since the compilation of the net7.0 binary is not in any way
related to the net6.0 binary since it's only used as a data dependency.

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
    "TFM_RID_TRANSITION_OUTPUTS",
    "rid_compatability_transition_outputs",
)

# Constant, so it is built once at load time rather than on every application
# of the transition. The state reset to is the one an untouched configuration
# starts in, compatibility settings included.
_DEFAULT_OUTPUTS = dicts.add(
    {"//dotnet:target_framework": DEFAULT_TFM, "//dotnet:rid": DEFAULT_RID},
    FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[DEFAULT_TFM],
    rid_compatability_transition_outputs(DEFAULT_RID),
)

def _impl(_settings, _attr):
    return _DEFAULT_OUTPUTS

default_transition = transition(
    implementation = _impl,
    inputs = [],
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
