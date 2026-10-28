"A transition that transitions between compatible target frameworks"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "get_highest_compatible_runtime_identifier")
load("//dotnet/private/sdk:packs.bzl", "RUNTIME_PACK_LOOKUP_TABLE", "normalize_project_sdk")
load("//dotnet/private/transitions:common.bzl", "NO_READY_TO_RUN")

def _impl(settings, attr):
    project_sdk = normalize_project_sdk(attr.project_sdk)
    incoming_target_framework = settings["//dotnet:target_framework"]
    incoming_rid = settings["//dotnet:rid"]

    supported_tfms = RUNTIME_PACK_LOOKUP_TABLE.get(project_sdk)
    if supported_tfms:
        supported_rids = supported_tfms.get(incoming_target_framework)
        if supported_rids:
            highest_compatible_rid = get_highest_compatible_runtime_identifier(incoming_rid, supported_rids.keys())
            runtime_pack = supported_rids.get(highest_compatible_rid)
            if runtime_pack:
                return dicts.add({"//dotnet/private/sdk/runtime_packs:runtime_pack": runtime_pack}, NO_READY_TO_RUN)

    fail("No runtime pack found for project SDK/target framework: {}/{}".format(project_sdk, incoming_target_framework))

# A pack's assemblies are never compiled to ReadyToRun.
runtime_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack", "//dotnet:target_framework", "//dotnet:rid"],
    outputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack"] + NO_READY_TO_RUN.keys(),
)
