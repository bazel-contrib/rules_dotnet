"A transition that transitions between compatible target frameworks"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private/sdk:frameworks.bzl", "base_framework")
load("//dotnet/private/sdk:packs.bzl", "TARGETING_PACK_LOOKUP_TABLE", "frameworks_key", "resolve_framework_references")
load("//dotnet/private/transitions:common.bzl", "NO_READY_TO_RUN")

def _impl(settings, attr):
    frameworks = resolve_framework_references(attr.project_sdk, getattr(attr, "framework_references", []))
    incoming_target_framework = settings["//dotnet:target_framework"]

    # A platform specific framework, such as `net8.0-windows`, compiles
    # against the packs of the framework it is specific to.
    targeting_pack = TARGETING_PACK_LOOKUP_TABLE[attr._pack_set].get(frameworks_key(frameworks), {}).get(base_framework(incoming_target_framework))
    if targeting_pack:
        return dicts.add({"//dotnet/private/sdk/targeting_packs:targeting_pack": targeting_pack}, NO_READY_TO_RUN)

    fail("No targeting pack found for the shared frameworks {} and target framework {}".format(
        ", ".join(["Microsoft.NETCore.App"] + frameworks.keys()),
        incoming_target_framework,
    ))

# A pack's assemblies are never compiled to ReadyToRun.
targeting_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack", "//dotnet:target_framework"],
    outputs = ["//dotnet/private/sdk/targeting_packs:targeting_pack"] + NO_READY_TO_RUN.keys(),
)
