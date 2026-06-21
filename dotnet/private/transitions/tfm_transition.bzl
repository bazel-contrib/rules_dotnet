"A transition that transitions between compatible target frameworks"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "FRAMEWORK_COMPATIBILITY",
    "get_highest_compatible_target_framework",
)
load("//dotnet/private/sdk:rids.bzl", "RUNTIME_GRAPH")
load("//dotnet/private/transitions:common.bzl", "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS", "RID_COMPATABILITY_TRANSITION_OUTPUTS", "platform_to_rid")

def _impl(settings, attr):
    incoming_tfm = settings["//dotnet:target_framework"]

    if incoming_tfm not in FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS:
        fail("Error setting //dotnet:target_framework: invalid value '" + incoming_tfm + "'. Allowed values are " + str(FRAMEWORK_COMPATIBILITY.keys()))

    target_frameworks = []
    if hasattr(attr, "target_framework"):
        target_frameworks.append(attr.target_framework)
    if hasattr(attr, "target_frameworks"):
        target_frameworks += attr.target_frameworks

    transitioned_tfm = get_highest_compatible_target_framework(incoming_tfm, target_frameworks)

    if transitioned_tfm == None:
        fail("Label {0} does not support the target framework: {1}".format(attr.name, incoming_tfm))

    runtime_identifier = settings["//dotnet:rid"]
    if hasattr(attr, "runtime_identifier") and attr.runtime_identifier != "":
        runtime_identifier = attr.runtime_identifier
    elif runtime_identifier == "base":
        # If the runtime_identifier attribute is not set and the incoming value is "base", we will use the platform to determine the rid since no upstream target has set the runtime identifier
        runtime_identifier = platform_to_rid()

    return dicts.add({"//dotnet:target_framework": transitioned_tfm}, {"//dotnet:rid": runtime_identifier}, FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[transitioned_tfm], RID_COMPATABILITY_TRANSITION_OUTPUTS[runtime_identifier])

tfm_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet:target_framework", "//dotnet:rid", "//command_line_option:cpu", "//command_line_option:platforms"],
    outputs = ["//dotnet:target_framework", "//dotnet:rid"] +
              ["//dotnet:framework_compatible_%s" % framework for framework in FRAMEWORK_COMPATIBILITY.keys()] +
              ["//dotnet:rid_compatible_%s" % rid for rid in RUNTIME_GRAPH.keys()],
)
