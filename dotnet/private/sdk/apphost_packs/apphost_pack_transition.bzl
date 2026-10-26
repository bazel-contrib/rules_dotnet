"A transition that transitions between compatible target frameworks"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "get_highest_compatible_runtime_identifier")
load("//dotnet/private/sdk:packs.bzl", "APPHOST_PACK_LOOKUP_TABLE")
load("//dotnet/private/transitions:common.bzl", "NO_READY_TO_RUN")

def _impl(settings, _attr):
    incoming_target_framework = settings["//dotnet:target_framework"]
    incoming_rid = settings["//dotnet:rid"]

    supported_rids = APPHOST_PACK_LOOKUP_TABLE.get(incoming_target_framework)
    if supported_rids:
        highest_compatible_rid = get_highest_compatible_runtime_identifier(incoming_rid, supported_rids.keys())
        apphost_pack = supported_rids.get(highest_compatible_rid)
        if apphost_pack:
            return dicts.add({"//dotnet/private/sdk/apphost_packs:apphost_pack": apphost_pack}, NO_READY_TO_RUN)

    fail("No apphost pack found for project target framework/runtime identifier: {}/{}".format(incoming_target_framework, incoming_rid))

# A pack's assemblies are never compiled to ReadyToRun here: a runtime pack
# ships its images already, and the others are not published.
apphost_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet/private/sdk/apphost_packs:apphost_pack", "//dotnet:target_framework", "//dotnet:rid"],
    outputs = ["//dotnet/private/sdk/apphost_packs:apphost_pack"] + NO_READY_TO_RUN.keys(),
)
