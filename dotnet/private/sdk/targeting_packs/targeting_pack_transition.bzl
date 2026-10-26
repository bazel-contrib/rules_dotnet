"A transition that transitions between compatible target frameworks"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private/sdk:packs.bzl", "TARGETING_PACK_LOOKUP_TABLE", "normalize_project_sdk")
load("//dotnet/private/transitions:common.bzl", "NO_READY_TO_RUN")

def _impl(settings, attr):
    project_sdk = normalize_project_sdk(attr.project_sdk)
    incoming_target_framework = settings["//dotnet:target_framework"]

    supported_tfms = TARGETING_PACK_LOOKUP_TABLE[attr._pack_set].get(project_sdk)
    if supported_tfms:
        targeting_pack = supported_tfms.get(incoming_target_framework)
        if targeting_pack:
            return dicts.add({"//dotnet/private/sdk/targeting_packs:targeting_pack": targeting_pack}, NO_READY_TO_RUN)

    fail("No targeting pack found for project SDK/target framework: {}/{}".format(project_sdk, incoming_target_framework))

# A pack's assemblies are never compiled to ReadyToRun here: a runtime pack
# ships its images already, and the others are not published.
targeting_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack", "//dotnet:target_framework"],
    outputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack"] + NO_READY_TO_RUN.keys(),
)
