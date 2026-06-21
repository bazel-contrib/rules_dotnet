"Common functinality for transitions"

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@platforms//host:constraints.bzl", "HOST_CONSTRAINTS")
load(
    "//dotnet/private:common.bzl",
    "FRAMEWORK_COMPATIBILITY",
    "TRANSITIVE_FRAMEWORK_COMPATIBILITY",
)
load("//dotnet/private/sdk:rids.bzl", "RUNTIME_GRAPH")

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

RID_COMPATABILITY_TRANSITION_OUTPUTS = {
    rid: {
        "//dotnet:rid_compatible_%s" % identifier: (identifier in compatible_rids) or (identifier == rid)
        for identifier in RUNTIME_GRAPH.keys()
    }
    for (rid, compatible_rids) in RUNTIME_GRAPH.items()
}
