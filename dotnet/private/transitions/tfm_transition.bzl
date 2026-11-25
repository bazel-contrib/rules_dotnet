"""Moves each target onto the framework it builds for: the one its consumer can use, or its newest."""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private:common.bzl",
    "FRAMEWORK_COMPATIBILITY",
    "get_dependency_target_framework",
    "get_newest_target_framework",
    "is_core_framework",
    "is_netframework",
    "netframework_runtime_identifier",
    "shipped_shared_frameworks",
)
load("//dotnet/private/sdk:packs.bzl", "frameworks_key", "resolve_framework_references")
load(
    "//dotnet/private/transitions:common.bzl",
    "ALL_SHARED_FRAMEWORKS",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "FRAMEWORK_FROM_CONSUMER",
    "NATIVE_COMPILER",
    "NO_READY_TO_RUN",
    "PUBLISHED",
    "READY_TO_RUN_FRAMEWORK",
    "READY_TO_RUN_SHARED_FRAMEWORKS",
    "STRICT_FRAMEWORK_REFERENCES",
    "TFM_RID_TRANSITION_OUTPUTS",
    "TRIMMED",
    "platform_to_rid",
    "rid_compatability_transition_outputs",
    "strict_framework_references",
)

def _ready_to_run(settings, attr, transitioned_tfm, runtime_identifier):
    """The ReadyToRun settings a target passes down.

    The published binary keeps the native compiler its publish asked for,
    whether the publish trims it and whether it takes every shared framework,
    and names the runtime the images below it are compiled against: its own
    framework and shared frameworks, or every shared framework when it takes
    them all. Everything else passes the framework on.
    """

    # A publish asks its binary through publish_binary_transition.
    if hasattr(attr, "ready_to_run"):
        return NO_READY_TO_RUN

    framework = settings[READY_TO_RUN_FRAMEWORK]

    if not settings[PUBLISHED]:
        return dicts.add(NO_READY_TO_RUN, {
            READY_TO_RUN_FRAMEWORK: framework,
            READY_TO_RUN_SHARED_FRAMEWORKS: settings[READY_TO_RUN_SHARED_FRAMEWORKS],
        })

    # The same packs as runtime_pack_transition gives the binary, so that the
    # images below it match the publish's.
    shared_frameworks = ""
    if framework:
        if settings[ALL_SHARED_FRAMEWORKS]:
            frameworks = shipped_shared_frameworks(transitioned_tfm, runtime_identifier)
        else:
            frameworks = resolve_framework_references(attr.project_sdk, getattr(attr, "framework_references", []))
        shared_frameworks = frameworks_key(frameworks, profiles = False)

    return dicts.add(NO_READY_TO_RUN, {
        NATIVE_COMPILER: settings[NATIVE_COMPILER],
        TRIMMED: settings[TRIMMED],
        ALL_SHARED_FRAMEWORKS: settings[ALL_SHARED_FRAMEWORKS],
        READY_TO_RUN_FRAMEWORK: transitioned_tfm if framework else "",
        READY_TO_RUN_SHARED_FRAMEWORKS: shared_frameworks,
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

    if settings[FRAMEWORK_FROM_CONSUMER]:
        transitioned_tfm = get_dependency_target_framework(incoming_tfm, target_frameworks)
        if transitioned_tfm == None:
            fail("{} cannot be used by a {} target: none of its target frameworks {} is compatible".format(attr.name, incoming_tfm, target_frameworks))
    else:
        transitioned_tfm = get_newest_target_framework(incoming_tfm, target_frameworks)
        if transitioned_tfm == None:
            fail("{} cannot be built for {}: its target frameworks {} are all newer".format(attr.name, incoming_tfm, target_frameworks))

    runtime_identifier = settings["//dotnet:rid"]
    if hasattr(attr, "runtime_identifier") and attr.runtime_identifier != "":
        runtime_identifier = attr.runtime_identifier

        # A default from the target platform; .NET Framework only runs on Windows.
        if getattr(attr, "runtime_identifier_from_platform", False) and is_netframework(transitioned_tfm):
            runtime_identifier = netframework_runtime_identifier(runtime_identifier)
    elif runtime_identifier == "base":
        # Nothing above this target picked one.
        runtime_identifier = platform_to_rid()

        # .NET Framework only runs on Windows, whatever platform builds it.
        if is_netframework(transitioned_tfm):
            runtime_identifier = netframework_runtime_identifier(runtime_identifier)

    return dicts.add(
        {"//dotnet:target_framework": transitioned_tfm, "//dotnet:rid": runtime_identifier, FRAMEWORK_FROM_CONSUMER: True},
        FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[transitioned_tfm],
        rid_compatability_transition_outputs(runtime_identifier),
        _ready_to_run(settings, attr, transitioned_tfm, runtime_identifier),
    )

tfm_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet:target_framework", "//dotnet:rid", FRAMEWORK_FROM_CONSUMER] + NO_READY_TO_RUN.keys(),
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)

def _publish_binary_impl(settings, attr):
    binary = _impl(settings, attr)

    # Nothing is compiled ahead of time for .NET Framework; the publish
    # rejects those settings itself.
    if not is_core_framework(binary["//dotnet:target_framework"]):
        return {"binary": dicts.add(binary, {PUBLISHED: True})}

    # Any framework asks for images; the binary replaces it with its own.
    binary = dicts.add(binary, {
        PUBLISHED: True,
        READY_TO_RUN_FRAMEWORK: attr.target_framework if attr.ready_to_run and not attr.ready_to_run_composite else "",
        # NativeAOT is the only publish of a .NET binary that trims it.
        TRIMMED: attr.native_aot,
        # Only a publish that ships the runtime or compiles against it needs
        # its packs, and only when the frameworks of the binary's dependencies
        # count too. Otherwise the binary keeps the configuration it has
        # outside a publish. NativeAOT compiles the runtime in.
        ALL_SHARED_FRAMEWORKS: (attr.self_contained or attr.ready_to_run) and not attr.native_aot and not strict_framework_references(attr.strict_framework_references, settings[STRICT_FRAMEWORK_REFERENCES]),
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
    inputs = ["//dotnet:target_framework", "//dotnet:rid", FRAMEWORK_FROM_CONSUMER, STRICT_FRAMEWORK_REFERENCES] + NO_READY_TO_RUN.keys(),
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
