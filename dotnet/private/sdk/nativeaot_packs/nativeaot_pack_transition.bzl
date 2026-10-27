"A transition that selects the NativeAOT runtime pack for the target framework"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:common.bzl", "get_highest_compatible_runtime_identifier")
load("//dotnet/private/sdk:packs.bzl", "NATIVEAOT_PACK_LOOKUP_TABLE")
load("//dotnet/private/transitions:common.bzl", "NO_READY_TO_RUN")

_SETTING = "//dotnet/private/sdk/nativeaot_packs:nativeaot_pack"

def _impl(settings, _attr):
    by_rid = NATIVEAOT_PACK_LOOKUP_TABLE.get(settings["//dotnet:target_framework"], {})
    rid = get_highest_compatible_runtime_identifier(settings["//dotnet:rid"], by_rid.keys())

    # A framework or platform without a pack keeps the empty default, and the
    # publish reports it where it reads the pack.
    return dicts.add({_SETTING: by_rid.get(rid) or settings[_SETTING]}, NO_READY_TO_RUN)

# A pack's assemblies are never compiled to ReadyToRun here: a runtime pack
# ships its images already, and the others are not published.
nativeaot_pack_transition = transition(
    implementation = _impl,
    inputs = [_SETTING, "//dotnet:target_framework", "//dotnet:rid"],
    outputs = [_SETTING] + NO_READY_TO_RUN.keys(),
)
