"A transition that transitions between compatible target frameworks"

load("//dotnet/private:common.bzl", "get_highest_compatible_runtime_identifier")
load(":runtime_pack_lookup_table.bzl", "runtime_pack_lookup_table")

def _impl(settings, attr):
    project_sdk = attr.project_sdk
    incoming_target_framework = settings["//dotnet:target_framework"]
    incoming_rid = settings["//dotnet:rid"]

    supported_tfms = runtime_pack_lookup_table.get(project_sdk)
    if supported_tfms:
        supported_rids = supported_tfms.get(incoming_target_framework)
        if supported_rids:
            highest_compatible_rid = get_highest_compatible_runtime_identifier(incoming_rid, supported_rids.keys())
            runtime_pack = supported_rids.get(highest_compatible_rid)
            if runtime_pack:
                return {"//dotnet/private/sdk/runtime_packs:runtime_pack": runtime_pack}

    fail("No runtime pack found for project SDK/target framework: {}/{}".format(project_sdk, incoming_target_framework))

runtime_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack", "//dotnet:target_framework", "//dotnet:rid"],
    outputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack"],
)
