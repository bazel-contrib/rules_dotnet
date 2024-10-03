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
    "FRAMEWORK_COMPATIBILITY",
)
load("//dotnet/private/sdk:rids.bzl", "RUNTIME_GRAPH")

def _impl(_settings, _attr):
    default_framework_compatibility = {"//dotnet:framework_compatible_{}".format(framework): False for framework in FRAMEWORK_COMPATIBILITY.keys()}
    default_rid_compatibility = {"//dotnet:rid_compatible_{}".format(rid): False for rid in RUNTIME_GRAPH.keys()}
    return dicts.add({"//dotnet:target_framework": DEFAULT_TFM}, {"//dotnet:rid": DEFAULT_RID}, default_framework_compatibility, default_rid_compatibility)

default_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet:target_framework", "//dotnet:rid", "//command_line_option:cpu", "//command_line_option:platforms"],
    outputs = ["//dotnet:target_framework", "//dotnet:rid"] +
              ["//dotnet:framework_compatible_%s" % framework for framework in FRAMEWORK_COMPATIBILITY.keys()] +
              ["//dotnet:rid_compatible_%s" % rid for rid in RUNTIME_GRAPH.keys()],
)
