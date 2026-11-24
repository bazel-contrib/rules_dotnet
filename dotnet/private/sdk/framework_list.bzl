"""Orders and filters the FrameworkList.xml and RuntimeList.xml entries of packs.

Microsoft.WindowsDesktop.App ships newer copies of some assemblies that
Microsoft.NETCore.App also ships, such as `System.Drawing.dll`. As in the SDK's
conflict resolution, the copy with the higher assembly version, then file
version, wins.
"""

def _version_key(version):
    """A version string as a list of ints, so that versions compare numerically."""
    if not version:
        return []

    parts = []
    for part in version.split("."):
        digits = ""
        for char in part.elems():
            if not char.isdigit():
                break
            digits += char
        parts.append(int(digits) if digits else 0)

    return parts

def framework_assembly_key(nuget_info, name):
    """What orders two packs' copies of an assembly: assembly then file version.

    Args:
      nuget_info: The NuGetInfo of the pack.
      name: The lower cased assembly name.

    Returns:
      A value that compares greater for the copy the SDK keeps.
    """
    return (
        _version_key(nuget_info.framework_list.get(name, "")),
        _version_key(nuget_info.framework_list_file_versions.get(name, "")),
    )

def in_profiles(entry_profiles, profiles):
    """Whether a FrameworkList entry belongs to any of the profiles referenced.

    An entry without a profile is only part of the whole framework.

    Args:
      entry_profiles: The entry's `Profile` attribute, `;` separated, or "".
      profiles: The profiles referenced, or None for the whole framework.

    Returns:
      Whether to keep the entry.
    """
    if profiles == None:
        return True

    if not entry_profiles:
        return False

    wanted = [profile.lower() for profile in profiles]
    return any([profile.strip().lower() in wanted for profile in entry_profiles.split(";")])
