"""Reads the requirements out of a `paket.dependencies` file.

Everything needed to build comes from `paket.lock`. The dependencies file is
read to notice when it has been edited without re-running Paket, which would
otherwise surface much later as a missing package or a stale version.
"""

load("//dotnet/private/paket:lock.bzl", "MAIN_GROUP", "normalize_version")

def _parse_version(tokens):
    """Returns the exact version a `nuget` line pins, or "" if it does not."""
    if len(tokens) < 3:
        return ""

    version = tokens[2]

    # A constraint such as `~> 6.2` can resolve to anything, and a setting such
    # as `framework: net45` or `prerelease` names no version.
    if not version[0].isdigit():
        return ""

    return normalize_version(version)

def parse_dependencies(content):
    """Parses the package requirements of a `paket.dependencies` file.

    Args:
      content: The contents of the `paket.dependencies` file.

    Returns:
      A dict of group name to a dict of package id to the exact version it is
      pinned at, or "" when it is declared without one. The implicit top group
      is called "Main" and is only present when packages are declared outside
      of any group.
    """
    groups = {}
    group = MAIN_GROUP

    for raw in content.replace("\r\n", "\n").split("\n"):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue

        tokens = [token for token in line.replace("\t", " ").split(" ") if token]
        keyword = tokens[0].lower()

        if keyword == "group" and len(tokens) > 1:
            group = tokens[1]
        elif keyword == "nuget" and len(tokens) > 1:
            groups.setdefault(group, {})[tokens[1]] = _parse_version(tokens)

    return groups

def stale_requirements(declared, locked_groups):
    """Lists what a dependencies file asks for that its lock file does not cover.

    Only exact versions are compared; a constraint such as `~> 6.2` can
    legitimately resolve to anything, so for those only the package's presence
    is checked.

    Args:
      declared: The requirements, from `parse_dependencies`.
      locked_groups: The lock file's groups, from `parse_lock`, keyed by lower
        cased name.

    Returns:
      A message per requirement the lock file is out of date with.
    """
    stale = []

    for (group_name, packages) in declared.items():
        group = locked_groups.get(group_name.lower())
        if group == None:
            stale.append("the '{}' group is missing".format(group_name))
            continue

        locked = {package.id.lower(): package.version for package in group.packages}

        # Package ids and versions both compare case insensitively in NuGet.
        for (id, version) in packages.items():
            locked_version = locked.get(id.lower())

            if locked_version == None:
                stale.append("{} is missing from the '{}' group".format(id, group_name))
            elif version and version.lower() != locked_version.lower():
                stale.append("{} is pinned at {} but the '{}' group resolves {}".format(
                    id,
                    version,
                    group_name,
                    locked_version,
                ))

    return stale
