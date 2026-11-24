"A transition that transitions between compatible target frameworks"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "get_highest_compatible_runtime_identifier")
load("//dotnet/private/sdk:frameworks.bzl", "base_framework")
load(
    "//dotnet/private/sdk:packs.bzl",
    "RUNTIME_PACK_LOOKUP_TABLE",
    "WINDOWS_ONLY_FRAMEWORKS",
    "frameworks_key",
    "resolve_framework_references",
)
load("//dotnet/private/transitions:common.bzl", "NO_READY_TO_RUN")

_EMPTY_PACK = "//dotnet/private/sdk/runtime_packs:empty_pack"

def _impl(settings, attr):
    frameworks = resolve_framework_references(attr.project_sdk, getattr(attr, "framework_references", []))
    incoming_target_framework = settings["//dotnet:target_framework"]
    incoming_rid = settings["//dotnet:rid"]

    supported_rids = RUNTIME_PACK_LOOKUP_TABLE[frameworks_key(frameworks, profiles = False)].get(base_framework(incoming_target_framework))
    if supported_rids:
        highest_compatible_rid = get_highest_compatible_runtime_identifier(incoming_rid, supported_rids.keys())
        runtime_pack = supported_rids.get(highest_compatible_rid)
        if runtime_pack:
            return dicts.add({"//dotnet/private/sdk/runtime_packs:runtime_pack": runtime_pack}, NO_READY_TO_RUN)

        # A Windows only framework has no runtime pack for any other runtime
        # identifier, but an application on it still builds anywhere, as it
        # does with the SDK's EnableWindowsTargeting: it only takes a runtime
        # pack to publish it self-contained, which `publish_binary` asks a
        # Windows runtime identifier for.
        if [framework for framework in frameworks if framework in WINDOWS_ONLY_FRAMEWORKS]:
            return dicts.add({"//dotnet/private/sdk/runtime_packs:runtime_pack": _EMPTY_PACK}, NO_READY_TO_RUN)

    fail("No runtime pack found for the shared frameworks {}, target framework {} and runtime identifier {}".format(
        ", ".join(["Microsoft.NETCore.App"] + frameworks.keys()),
        incoming_target_framework,
        incoming_rid,
    ))

# A pack's assemblies are never compiled to ReadyToRun.
runtime_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack", "//dotnet:target_framework", "//dotnet:rid"],
    outputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack"] + NO_READY_TO_RUN.keys(),
)
