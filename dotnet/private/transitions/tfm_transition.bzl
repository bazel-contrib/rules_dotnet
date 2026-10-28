"A transition that transitions between compatible target frameworks"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "FRAMEWORK_COMPATIBILITY",
    "get_highest_compatible_target_framework",
)
load("//dotnet/private/sdk:packs.bzl", "normalize_project_sdk")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "NATIVE_COMPILER",
    "NO_READY_TO_RUN",
    "PUBLISHED",
    "READY_TO_RUN_FRAMEWORK",
    "READY_TO_RUN_PROJECT_SDK",
    "TFM_RID_TRANSITION_OUTPUTS",
    "platform_to_rid",
    "rid_compatability_transition_outputs",
)

def _ready_to_run(settings, attr, transitioned_tfm):
    """The ReadyToRun settings a target passes down.

    The published binary keeps the native compiler its publish asked for, and
    names the runtime the images below it are compiled against: its own
    framework and project SDK. Everything else passes the framework on.
    """

    # A publish asks its binary through publish_binary_transition.
    if hasattr(attr, "ready_to_run"):
        return NO_READY_TO_RUN

    framework = settings[READY_TO_RUN_FRAMEWORK]

    if not settings[PUBLISHED]:
        return dicts.add(NO_READY_TO_RUN, {
            READY_TO_RUN_FRAMEWORK: framework,
            READY_TO_RUN_PROJECT_SDK: settings[READY_TO_RUN_PROJECT_SDK],
        })

    return dicts.add(NO_READY_TO_RUN, {
        NATIVE_COMPILER: settings[NATIVE_COMPILER],
        READY_TO_RUN_FRAMEWORK: transitioned_tfm if framework else "",
        READY_TO_RUN_PROJECT_SDK: normalize_project_sdk(attr.project_sdk) if framework else "",
    })

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

def _publish_binary_impl(settings, attr):
    # Any framework asks for images; the binary replaces it with its own.
    binary = dicts.add(_impl(settings, attr), {
        PUBLISHED: True,
        READY_TO_RUN_FRAMEWORK: attr.target_framework if attr.ready_to_run and not attr.ready_to_run_composite else "",
    })

    if attr.native_aot:
        native_compiler = "ilcompiler"
    elif attr.ready_to_run:
        native_compiler = "crossgen2"
    else:
        return {"binary": binary}

    # The compiler's band follows the framework the binary picks, which only the
    # binary knows, so the publish reaches it a second time for the compiler.
    return {
        "binary": binary,
        "native_tools": dicts.add(binary, {NATIVE_COMPILER: native_compiler}),
    }

# `binary` is the binary itself; a ReadyToRun or NativeAOT publish also gets
# `native_tools`, the native compiler for the binary's framework.
publish_binary_transition = transition(
    implementation = _publish_binary_impl,
    inputs = ["//dotnet:target_framework", "//dotnet:rid"] + NO_READY_TO_RUN.keys(),
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
