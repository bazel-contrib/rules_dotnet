"""What the packs' FrameworkList.xml and RuntimeList.xml say about their assemblies.

A shared framework can ship an assembly that Microsoft.NETCore.App ships too:
Microsoft.WindowsDesktop.App's `System.Drawing.dll` and `Microsoft.VisualBasic.dll`
are the Windows Forms versions of facades Microsoft.NETCore.App also carries.
The SDK settles which one a compilation and a publish get with its conflict
resolution, which keeps the higher assembly version, then the higher file
version. These helpers do the same, so that a compilation and the publish of
it agree on the file.
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

    As the SDK's ResolveTargetingPackAssets has it, an entry in no profile is
    only part of the whole framework.

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
