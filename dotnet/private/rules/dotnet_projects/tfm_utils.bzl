"Utilities for mapping Target Framework Monikers (TFMs) to SDK versions"

# Mapping of TFM to minimum SDK major version required
# SDK versions are backward compatible, so a higher SDK can build lower TFMs
# buildifier: disable=unsorted-dict-items
_TFM_TO_MIN_SDK_MAJOR = {
    "net10.0": 10,
    "net9.0": 9,
    "net8.0": 8,
    "net7.0": 7,
    "net6.0": 6,
    "net5.0": 5,
    # .NET Standard can be built by any modern SDK
    "netstandard2.1": 3,
    "netstandard2.0": 2,
    "netstandard1.6": 2,
    "netstandard1.5": 2,
    "netstandard1.4": 2,
    "netstandard1.3": 2,
    "netstandard1.2": 2,
    "netstandard1.1": 2,
    "netstandard1.0": 2,
    # .NET Core (legacy)
    "netcoreapp3.1": 3,
    "netcoreapp3.0": 3,
    "netcoreapp2.2": 2,
    "netcoreapp2.1": 2,
    "netcoreapp2.0": 2,
    # .NET Framework (can be built by any SDK with targeting packs)
    "net48": 5,
    "net472": 5,
    "net471": 5,
    "net47": 5,
    "net462": 5,
    "net461": 5,
    "net46": 5,
    "net452": 5,
    "net451": 5,
    "net45": 5,
}

def get_min_sdk_major_for_tfm(tfm):
    """Get the minimum SDK major version required for a TFM.

    Args:
        tfm: Target Framework Moniker (e.g., "net9.0", "netstandard2.0")

    Returns:
        Minimum SDK major version number, or None if unknown.
    """
    normalized = tfm.lower()
    return _TFM_TO_MIN_SDK_MAJOR.get(normalized)

def get_sdk_major_version(sdk_version):
    """Extract the major version from an SDK version string.

    Args:
        sdk_version: SDK version string (e.g., "10.0.100", "9.0.300")

    Returns:
        Major version as int (e.g., 10, 9)
    """
    parts = sdk_version.split(".")
    if not parts:
        return 0

    first = parts[0]

    # Handle preview/rc versions like "10.0.100-preview.1"
    if "-" in first:
        first = first.split("-")[0]

    if first.isdigit():
        return int(first)
    return 0

def sdk_supports_tfm(sdk_version, tfm):
    """Check if an SDK version supports a given TFM.

    Args:
        sdk_version: SDK version string (e.g., "10.0.100")
        tfm: Target Framework Moniker (e.g., "net9.0")

    Returns:
        True if the SDK can build the TFM.
    """
    sdk_major = get_sdk_major_version(sdk_version)
    min_major = get_min_sdk_major_for_tfm(tfm)

    if min_major == None:
        # Unknown TFM - assume it's supported
        return True

    return sdk_major >= min_major

def get_suggested_sdk_for_tfm(tfm):
    """Get a suggested SDK version for a TFM.

    Args:
        tfm: Target Framework Moniker

    Returns:
        Suggested SDK version string, or None.
    """
    min_major = get_min_sdk_major_for_tfm(tfm)
    if min_major == None:
        return None

    # Suggest a typical SDK version
    suggestions = {
        10: "10.0.100",
        9: "9.0.300",
        8: "8.0.410",
        7: "7.0.410",
        6: "6.0.428",
        5: "5.0.408",
        3: "3.1.426",
        2: "2.1.818",
    }

    return suggestions.get(min_major)

def find_best_toolchain_for_tfms(registered_sdks, tfms):
    """Find which registered toolchains cover which TFMs.

    Args:
        registered_sdks: Dict mapping toolchain name to SDK version.
        tfms: List of TFMs that need to be supported.

    Returns:
        Struct with:
            - covered: Dict mapping TFM to list of toolchain names that support it
            - uncovered: List of TFMs not covered by any toolchain
            - suggestions: Dict mapping uncovered TFM to suggested SDK version
    """
    covered = {}
    uncovered = []
    suggestions = {}

    for tfm in tfms:
        supporting_toolchains = []
        for name, sdk_version in registered_sdks.items():
            if sdk_supports_tfm(sdk_version, tfm):
                supporting_toolchains.append(name)

        if supporting_toolchains:
            covered[tfm] = supporting_toolchains
        else:
            uncovered.append(tfm)
            suggested = get_suggested_sdk_for_tfm(tfm)
            if suggested:
                suggestions[tfm] = suggested

    return struct(
        covered = covered,
        uncovered = uncovered,
        suggestions = suggestions,
    )
