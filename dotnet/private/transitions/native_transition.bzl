"""A transition for the native libraries and data files a .NET target ships.

They read none of the .NET settings but the runtime identifier, which picks the
native files of a package, so the rest goes back to its default. Otherwise a
native library would be built again for every target framework, and for every
ReadyToRun publish, that reaches it.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "DEFAULT_TFM")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "NO_READY_TO_RUN",
)

# Constant, so it is built once at load time rather than on every application
# of the transition.
_OUTPUTS = dicts.add(
    {"//dotnet:target_framework": DEFAULT_TFM},
    FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[DEFAULT_TFM],
    NO_READY_TO_RUN,
)

def _impl(_settings, _attr):
    return _OUTPUTS

native_transition = transition(
    implementation = _impl,
    inputs = [],
    outputs = _OUTPUTS.keys(),
)
