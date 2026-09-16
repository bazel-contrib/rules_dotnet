"""A transition that always transitions back to the default target framework. 

This transition is used to create a disconnect between two TFM graphs. For example
if you have a binary that targets net7.0 and another binary that targets net8.0
but depends on the net7.0 binary as a data dependency then we do not want the TFM
graphqs to be connected since the compilation of the net7.0 binary is not in any way
related to the net8.0 binary since it's only used as a data dependency.

"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "DEFAULT_RID",
    "DEFAULT_TFM",
    "FRAMEWORK_COMPATIBILITY",
)
load("//dotnet/private:portable_rids.bzl", "PORTABLE_RUNTIME_GRAPH")

# Constant, so it is built once at load time rather than on every application
# of the transition.
_DEFAULT_OUTPUTS = dicts.add(
    {"//dotnet:target_framework": DEFAULT_TFM, "//dotnet:rid": DEFAULT_RID},
    {"//dotnet:framework_compatible_{}".format(framework): False for framework in FRAMEWORK_COMPATIBILITY.keys()},
    {"//dotnet:rid_compatible_{}".format(rid): False for rid in PORTABLE_RUNTIME_GRAPH.keys()},
)

def _impl(_settings, _attr):
    return _DEFAULT_OUTPUTS

default_transition = transition(
    implementation = _impl,
    inputs = [],
    outputs = ["//dotnet:target_framework", "//dotnet:rid"] +
              ["//dotnet:framework_compatible_%s" % framework for framework in FRAMEWORK_COMPATIBILITY.keys()] +
              ["//dotnet:rid_compatible_%s" % rid for rid in PORTABLE_RUNTIME_GRAPH.keys()],
)
