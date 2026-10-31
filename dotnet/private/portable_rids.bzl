"""The subset of the .NET runtime identifier graph that rules_dotnet configures on.

`RUNTIME_GRAPH` is the full NuGet RID catalogue. Many of its entries name a
specific distribution release -- `ubuntu.16.04-x64`, `alpine.3.10-arm64` -- the
part of the graph .NET ignores under `UseRidGraph=false`. rules_dotnet declares
a build setting only for the portable RIDs and folds the rest onto their nearest
portable ancestor with `to_portable_rid`.

That is safe as long as the portable set is closed under compatibility and every
version-qualified RID has a portable ancestor. `rids.bzl` is a copy of the
upstream graph, so both properties are asserted in
`//dotnet/private/tests/portable_rids`.

The full graph is still used where the result is not a Bazel configuration:
validating what a package ships, and the RID fallback list in a self-contained
app's deps.json.
"""

load("//dotnet/private/sdk:rids.bzl", "RUNTIME_GRAPH")

def _is_portable(rid):
    # A version-qualified RID spells the version with a dot: `ubuntu.16.04-x64`,
    # `alpine.3.10`, `centos.7-x64`. Nothing else in the graph contains one.
    return "." not in rid

def _nearest_portable(compatible):
    # `RUNTIME_GRAPH` lists a RID's compatible RIDs most specific first, so the
    # first portable entry is the nearest portable ancestor.
    for candidate in compatible:
        if _is_portable(candidate):
            return candidate
    return None

PORTABLE_RUNTIME_GRAPH = {
    rid: compatible
    for (rid, compatible) in RUNTIME_GRAPH.items()
    if _is_portable(rid)
}

_LEGACY_RID_TO_PORTABLE = {
    rid: _nearest_portable(compatible)
    for (rid, compatible) in RUNTIME_GRAPH.items()
    if not _is_portable(rid)
}

def to_portable_rid(rid):
    """Maps a runtime identifier onto the one rules_dotnet configures on.

    Args:
        rid: Any runtime identifier from the full RID graph.

    Returns:
        `rid` itself when it is portable, its nearest portable ancestor when it
        names a specific distribution release, or None when it is not a RID the
        graph knows about.
    """
    if rid in PORTABLE_RUNTIME_GRAPH:
        return rid
    return _LEGACY_RID_TO_PORTABLE.get(rid)

# The architecture suffixes that appear in the RID graph. A RID carrying one is
# "architecture qualified"; `linux-musl` is not, `linux-musl-x64` is.
_ARCHITECTURES = [
    "x64",
    "x86",
    "arm64",
    "arm",
    "armv6",
    "s390x",
    "ppc64le",
    "mips64",
    "loongarch64",
    "riscv64",
    "wasm",
]

def _is_architecture_qualified(rid):
    for architecture in _ARCHITECTURES:
        if rid.endswith("-" + architecture):
            return True
    return False

# When several of a package's RID folders are compatible with the one being
# built, NuGet prefers every architecture qualified RID over every architecture
# agnostic one, and within each of those the more specific RID. Building
# `linux-musl-x64` against a package shipping both `linux-musl` and `linux-x64`
# resolves to `linux-x64`, not to the `linux-musl` the graph lists first.
#
# A RID's own compatibility list doubles as the specificity measure: the longer
# the list, the more of the graph the RID sits on top of.
_RID_PREFERENCE = {
    rank[2]: index
    for (index, rank) in enumerate(sorted([
        (0 if _is_architecture_qualified(rid) else 1, -len(compatible), rid)
        for (rid, compatible) in PORTABLE_RUNTIME_GRAPH.items()
    ]))
}

def rids_by_preference(rids):
    """Orders runtime identifiers the way NuGet picks between compatible ones.

    Args:
        rids: The runtime identifiers a package ships assets for.

    Returns:
        The same RIDs, most preferred first.
    """
    return [rid for (_, rid) in sorted([(_RID_PREFERENCE[rid], rid) for rid in rids])]
