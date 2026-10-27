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
    "NATIVE_COMPILER",
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
            return dicts.add(NO_READY_TO_RUN, {READY_TO_RUN_FRAMEWORK: attr.target_framework, READY_TO_RUN_PROJECT_SDK: DEFAULT_SDK})

        return NO_READY_TO_RUN

    is_binary = hasattr(attr, "winexe")

    # Only the binary resolves the native compiler its publish asked for, so
    # nothing below it is configured again for it.
    native_compiler = {NATIVE_COMPILER: settings[NATIVE_COMPILER] if is_binary else ""}

    if settings[READY_TO_RUN_FRAMEWORK] and is_binary:
        return dicts.add(native_compiler, {
            READY_TO_RUN_FRAMEWORK: transitioned_tfm,
            READY_TO_RUN_PROJECT_SDK: normalize_project_sdk(attr.project_sdk),
        })

    return dicts.add(native_compiler, {
        READY_TO_RUN_FRAMEWORK: settings[READY_TO_RUN_FRAMEWORK],
        READY_TO_RUN_PROJECT_SDK: settings[READY_TO_RUN_PROJECT_SDK],
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
    binary = _impl(settings, attr)

    if attr.native_aot:
        native_compiler = "ilcompiler"
    elif attr.ready_to_run:
        native_compiler = "crossgen2"
    else:
        return {"binary": binary}

    # The compiler's band and packs follow the framework the binary picks, which
    # can be lower than the publish's, and only the binary knows it. So the
    # publish reaches the binary a second time, where it compiles nothing and
    # resolves the compiler instead.
    return {
        "binary": binary,
        "native_tools": dicts.add(binary, NO_READY_TO_RUN, {NATIVE_COMPILER: native_compiler}),
    }

# The edge from a publish to its binary: `binary` is the binary itself, and a
# ReadyToRun or NativeAOT publish also gets `native_tools`, the native compiler
# for the binary's framework.
publish_binary_transition = transition(
    implementation = _publish_binary_impl,
    inputs = ["//dotnet:target_framework", "//dotnet:rid"] + NO_READY_TO_RUN.keys(),
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
