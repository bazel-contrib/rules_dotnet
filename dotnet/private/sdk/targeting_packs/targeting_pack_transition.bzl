"A transition that transitions between compatible target frameworks"

load("//dotnet/private/sdk:packs.bzl", "TARGETING_PACK_LOOKUP_TABLE")

def _transition(settings, project_sdk):
    incoming_target_framework = settings["//dotnet:target_framework"]

    supported_tfms = TARGETING_PACK_LOOKUP_TABLE.get(project_sdk)
    if supported_tfms:
        targeting_pack = supported_tfms.get(incoming_target_framework)
        if targeting_pack:
            return {"//dotnet/private/sdk/targeting_packs:targeting_pack": targeting_pack}

    fail("No targeting pack found for project SDK/target framework: {}/{}".format(project_sdk, incoming_target_framework))

def _impl(settings, attr):
    return _transition(settings, attr.project_sdk)

def _default_impl(settings, _attr):
    return _transition(settings, "default")

def _web_impl(settings, _attr):
    return _transition(settings, "web")

targeting_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack", "//dotnet:target_framework"],
    outputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack"],
)

targeting_pack_default_transition = transition(
    implementation = _default_impl,
    inputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack", "//dotnet:target_framework"],
    outputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack"],
)

targeting_pack_web_transition = transition(
    implementation = _web_impl,
    inputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack", "//dotnet:target_framework"],
    outputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack"],
)
