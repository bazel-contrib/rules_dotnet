"A transition that transitions between compatible target frameworks"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "FRAMEWORK_COMPATIBILITY",
    "get_highest_compatible_target_framework",
)
load("//dotnet/private/sdk:packs.bzl", "DEFAULT_SDK", "normalize_project_sdk")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "NO_READY_TO_RUN",
    "READY_TO_RUN_FRAMEWORK",
    "READY_TO_RUN_PROJECT_SDK",
    "TFM_RID_TRANSITION_OUTPUTS",
    "platform_to_rid",
    "rid_compatability_transition_outputs",
)

def _ready_to_run(settings, attr, transitioned_tfm):
    """The ReadyToRun settings a target passes down.

    A publish that compiles image by image asks for the images of what it
    ships, and the binary it publishes then names the runtime they are compiled
    against: its own framework and project SDK, whatever the publish asked for.
    Everything below the binary passes that on.
    """
    if hasattr(attr, "ready_to_run"):
        if attr.ready_to_run and not attr.ready_to_run_composite:
            return {READY_TO_RUN_FRAMEWORK: attr.target_framework, READY_TO_RUN_PROJECT_SDK: DEFAULT_SDK}

        return NO_READY_TO_RUN

    if settings[READY_TO_RUN_FRAMEWORK] and hasattr(attr, "winexe"):
        return {
            READY_TO_RUN_FRAMEWORK: transitioned_tfm,
            READY_TO_RUN_PROJECT_SDK: normalize_project_sdk(attr.project_sdk),
        }

    return {key: settings[key] for key in NO_READY_TO_RUN}

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

    return dicts.add({"//dotnet:target_framework": transitioned_tfm}, {"//dotnet:rid": runtime_identifier}, FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[transitioned_tfm], rid_compatability_transition_outputs(runtime_identifier), _ready_to_run(settings, attr, transitioned_tfm))

tfm_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet:target_framework", "//dotnet:rid"] + NO_READY_TO_RUN.keys(),
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
