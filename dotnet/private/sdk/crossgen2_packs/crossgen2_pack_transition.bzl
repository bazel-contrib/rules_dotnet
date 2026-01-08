"A transition that selects the appropriate crossgen2 pack based on TFM and host RID"

load("//dotnet/private:common.bzl", "get_highest_compatible_runtime_identifier")
load(":crossgen2_pack_lookup_table.bzl", "crossgen2_pack_lookup_table")

def _impl(settings, _attr):
    incoming_target_framework = settings["//dotnet:target_framework"]

    # For crossgen2, we need the execution/host platform RID, not the target RID
    # The crossgen2 binary runs on the host and cross-compiles to the target
    incoming_rid = settings["//dotnet:rid"]

    supported_rids = crossgen2_pack_lookup_table.get(incoming_target_framework)
    if supported_rids:
        highest_compatible_rid = get_highest_compatible_runtime_identifier(incoming_rid, supported_rids.keys())
        crossgen2_pack = supported_rids.get(highest_compatible_rid)
        if crossgen2_pack:
            return {"//dotnet/private/sdk/crossgen2_packs:crossgen2_pack": crossgen2_pack}

    # Return empty pack if no crossgen2 pack is available for this TFM
    # This allows the rule to gracefully handle older TFMs that don't support crossgen2
    return {"//dotnet/private/sdk/crossgen2_packs:crossgen2_pack": "//dotnet/private/sdk/crossgen2_packs:empty_pack"}

crossgen2_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet/private/sdk/crossgen2_packs:crossgen2_pack", "//dotnet:target_framework", "//dotnet:rid"],
    outputs = ["//dotnet/private/sdk/crossgen2_packs:crossgen2_pack"],
)
