"A transition that selects the NativeAOT runtime pack for the target framework"

load("//dotnet/private:common.bzl", "get_highest_compatible_runtime_identifier")
load("//dotnet/private/sdk:packs.bzl", "NATIVEAOT_PACK_LOOKUP_TABLE")

_SETTING = "//dotnet/private/sdk/nativeaot_packs:nativeaot_pack"

def _impl(settings, _attr):
    by_rid = NATIVEAOT_PACK_LOOKUP_TABLE.get(settings["//dotnet:target_framework"], {})
    rid = get_highest_compatible_runtime_identifier(settings["//dotnet:rid"], by_rid.keys())

    # Every publish carries this attribute but only a NativeAOT one reads it, so
    # a framework or platform without a pack keeps the empty default and is
    # reported at the point of use.
    return {_SETTING: by_rid.get(rid) or settings[_SETTING]}

nativeaot_pack_transition = transition(
    implementation = _impl,
    inputs = [_SETTING, "//dotnet:target_framework", "//dotnet:rid"],
    outputs = [_SETTING],
)
