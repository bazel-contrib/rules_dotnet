"""The canonical input hash of a `nuget.resolve` tag.

The hash is computed in Starlark — never in the resolver tool — so the
unpinned and pinned sides are guaranteed to agree (the pattern of
`compute_dependency_inputs_signature` in rules_jvm_external). It is a
staleness detector, not a security boundary: integrity comes from the
per-package sha512 in the lock file.
"""

# Hashes produced by superseded algorithms. A lock file stamped with one of
# these warns ("run repin") instead of failing, the same trade-off
# rules_jvm_external makes with `old_hashes`. Empty: the current algorithm is
# the first.
LEGACY_INPUT_HASHES = []

def compute_input_hash(packages, frameworks, sources):
    """Returns the canonical hash of the tag inputs as a decimal string.

    Args:
      packages: The `packages` dict of the tag (package id to version range).
      frameworks: The `frameworks` list of the tag.
      sources: The `sources` list of the tag, in lookup order.

    Returns:
      `hash()` over a canonical JSON encoding, as a decimal string.
    """
    canonical = json.encode({
        "frameworks": sorted(frameworks),
        "packages": {id: packages[id] for id in sorted(packages)},
        "sources": sources,
    })
    # Starlark hash() is signed; mask to non-negative so the stamped value is
    # always a decimal string of digits.
    return str(hash(canonical) & 0x7fffffff)

def classify_input_hash(lock_hash, computed_hash, legacy = LEGACY_INPUT_HASHES):
    """Compares the hash in the lock file with the freshly computed one.

    Args:
      lock_hash: The `inputHash` recorded in the lock file.
      computed_hash: The hash of the current tag inputs.
      legacy: Hashes produced by superseded algorithms.

    Returns:
      "current" when they match, "legacy" when the lock file carries a
      superseded algorithm, "mismatch" otherwise.
    """
    if lock_hash == computed_hash:
        return "current"
    if lock_hash in legacy:
        return "legacy"
    return "mismatch"
