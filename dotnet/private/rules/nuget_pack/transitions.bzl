"""The split that builds a library once per framework a package ships.

A library compiles for exactly one of its `target_frameworks` in any
configuration, and a package wants all of them, so `nuget_pack` splits its
`library` (or `binary`) attribute: once per framework and, when the package is
RID-specific, once per runtime identifier.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//dotnet/private/transitions:common.bzl",
    "FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS",
    "TFM_RID_TRANSITION_OUTPUTS",
    "rid_compatability_transition_outputs",
)

# Neither a framework moniker nor a runtime identifier contains this.
_SEPARATOR = "|"

def split_key(tfm, rid = None):
    """The key `ctx.split_attr` files a framework (and runtime identifier) under.

    Args:
      tfm: The target framework moniker.
      rid: The runtime identifier, or None when the package is not RID-specific.

    Returns:
      The key.
    """
    return tfm if rid == None else tfm + _SEPARATOR + rid

def parse_split_key(key):
    """The inverse of `split_key`.

    Args:
      key: A key of `ctx.split_attr`.

    Returns:
      A `(tfm, rid)` pair, `rid` being None when the key names no runtime identifier.
    """
    (tfm, _, rid) = key.partition(_SEPARATOR)
    return (tfm, rid or None)

def _impl(settings, attr):
    incoming_rid = settings["//dotnet:rid"]

    # None keeps the incoming runtime identifier, which the library's own
    # transition resolves to the host's when nothing upstream set one, as it
    # does for any other build.
    rids = attr.runtime_identifiers or [None]

    splits = {}
    for tfm in attr.target_frameworks:
        if tfm not in FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS:
            fail("{}: unknown target framework {}. Allowed values are {}".format(
                attr.name,
                tfm,
                ", ".join(FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS.keys()),
            ))

        for rid in rids:
            resolved = rid or incoming_rid
            splits[split_key(tfm, rid)] = dicts.add(
                {"//dotnet:target_framework": tfm, "//dotnet:rid": resolved},
                FRAMEWORK_COMPATABILITY_TRANSITION_OUTPUTS[tfm],
                # Fails on an unknown runtime identifier, as tfm_transition does.
                rid_compatability_transition_outputs(resolved),
            )

    return splits

nuget_pack_transition = transition(
    implementation = _impl,
    inputs = ["//dotnet:rid"],
    outputs = TFM_RID_TRANSITION_OUTPUTS,
)
