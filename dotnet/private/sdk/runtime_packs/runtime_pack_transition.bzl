"A transition that transitions between compatible target frameworks"

load("//dotnet/private:common.bzl", "get_highest_compatible_runtime_identifier")
load("//dotnet/private/sdk:packs.bzl", "RUNTIME_PACK_LOOKUP_TABLE")

def _transition(settings, project_sdk):
    incoming_target_framework = settings["//dotnet:target_framework"]
    incoming_rid = settings["//dotnet:rid"]

    supported_tfms = RUNTIME_PACK_LOOKUP_TABLE.get(project_sdk)
    if supported_tfms:
        supported_rids = supported_tfms.get(incoming_target_framework)
        if supported_rids:
            highest_compatible_rid = get_highest_compatible_runtime_identifier(incoming_rid, supported_rids.keys())
            runtime_pack = supported_rids.get(highest_compatible_rid)
            if runtime_pack:
                return {"//dotnet/private/sdk/runtime_packs:runtime_pack": runtime_pack}

    fail("No runtime pack found for project SDK/target framework/runtime identifier: {}/{}/{}".format(project_sdk, incoming_target_framework, incoming_rid))

def _impl(settings, attr):
    return _transition(settings, attr.project_sdk)

def _default_impl(settings, _attr):
    return _transition(settings, "default")

def _web_impl(settings, _attr):
    return _transition(settings, "web")

runtime_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack", "//dotnet:target_framework", "//dotnet:rid"],
    outputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack"],
)

runtime_pack_default_transition = transition(
    implementation = _default_impl,
    inputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack", "//dotnet:target_framework", "//dotnet:rid"],
    outputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack"],
)

runtime_pack_web_transition = transition(
    implementation = _web_impl,
    inputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack", "//dotnet:target_framework", "//dotnet:rid"],
    outputs = ["//dotnet/private/sdk/runtime_packs:runtime_pack"],
)
