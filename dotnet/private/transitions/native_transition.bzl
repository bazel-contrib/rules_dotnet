"""A transition for the native libraries and data files a .NET target ships.

They read no .NET setting but the runtime identifier, which picks the native
files of a package, so the rest goes back to its default: a native library is
built once, whatever framework or ReadyToRun publish reaches it. A .NET target
among them, such as a library in an import's `data`, has no .NET consumer, so it
builds for its newest framework as it would on the command line.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "DEFAULT_TFM")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "FRAMEWORK_FROM_CONSUMER",
    "NO_READY_TO_RUN",
)

_OUTPUTS = dicts.add(
    {"//dotnet:target_framework": DEFAULT_TFM, FRAMEWORK_FROM_CONSUMER: False},
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
