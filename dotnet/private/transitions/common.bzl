"Common functionality for transitions"

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@platforms//host:constraints.bzl", "HOST_CONSTRAINTS")
load(
    "//dotnet/private:common.bzl",
    "FRAMEWORK_COMPATIBILITY",
    "TRANSITIVE_FRAMEWORK_COMPATIBILITY",
)
load("//dotnet/private:portable_rids.bzl", "PORTABLE_RUNTIME_GRAPH", "to_portable_rid")

# Every transition that moves the TFM/RID graph writes the same settings.
TFM_RID_TRANSITION_OUTPUTS = ["//dotnet:target_framework", "//dotnet:rid"] + \
                             ["//dotnet:framework_compatible_%s" % framework for framework in FRAMEWORK_COMPATIBILITY.keys()] + \
                             ["//dotnet:rid_compatible_%s" % rid for rid in PORTABLE_RUNTIME_GRAPH.keys()]

def platform_to_rid():
    """Determines the .Net runtime identifier (RID) of the host that Bazel is running on.

    Returns:
        The .Net RID of the host platform, e.g. "osx-arm64", "linux-x64" or "win-x64".
    """
    cpu_constraint = None
    os_constraint = None
    for platform in HOST_CONSTRAINTS:
        if platform.startswith("@platforms//cpu"):
            cpu_constraint = platform.split(":")[1]
        if platform.startswith("@platforms//os"):
            os_constraint = platform.split(":")[1]

    if cpu_constraint == None or os_constraint == None:
        fail("Could not determine the cpu or os constraint: {}/{}".format(cpu_constraint, os_constraint))

    rid_cpu = None
    rid_os = None
    if os_constraint == "windows":
        rid_os = "win"
    elif os_constraint == "linux":
        rid_os = "linux"
    elif os_constraint == "macos" or os_constraint == "osx":
        rid_os = "osx"

    if cpu_constraint == "x86_64":
        rid_cpu = "x64"
    elif cpu_constraint == "aarch64" or cpu_constraint == "arm64":
        rid_cpu = "arm64"

    if rid_cpu == None or rid_os == None:
        fail("Could not determine the rid from the cpu/os constraint: {}/{}".format(cpu_constraint, os_constraint))

    return "{}-{}".format(rid_os, rid_cpu)

FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS = {
    tfm: {
        "//dotnet:framework_compatible_%s" % framework: sets.contains(tfm_compatible_set, framework)
        for framework in FRAMEWORK_COMPATIBILITY.keys()
    }
    for (tfm, tfm_compatible_set) in TRANSITIVE_FRAMEWORK_COMPATIBILITY.items()
}

# The table below tests every RID against every row, so index the rows first to
# keep each membership test a dict lookup rather than a scan of a list.
_COMPATIBLE_RID_SETS = {
    rid: {identifier: True for identifier in compatible_rids + [rid]}
    for (rid, compatible_rids) in PORTABLE_RUNTIME_GRAPH.items()
}

_RID_COMPATABILITY_TRANSITION_OUTPUTS = {
    rid: {
        "//dotnet:rid_compatible_%s" % identifier: identifier in compatible_set
        for identifier in PORTABLE_RUNTIME_GRAPH.keys()
    }
    for (rid, compatible_set) in _COMPATIBLE_RID_SETS.items()
}

def rid_compatability_transition_outputs(rid):
    """The `rid_compatible_*` settings a runtime identifier turns on.

    A version-qualified RID shares a row with its nearest portable ancestor,
    which it is compatible with exactly as much as the ancestor is.

    Args:
        rid: The runtime identifier being transitioned to.

    Returns:
        A dict of build setting label to bool, covering every portable RID.
    """
    portable = to_portable_rid(rid)

    if portable == None:
        fail("Unknown .NET runtime identifier: {}".format(rid))

    return _RID_COMPATABILITY_TRANSITION_OUTPUTS[portable]
