"""Parser for Paket's `paket.lock` files.

`paket.lock` is the output of Paket's resolver: it pins an exact version for
every package in every dependency group, along with the feeds they were
resolved from. That is everything the module extension needs, because the
remaining package metadata (per-framework dependencies, targeting pack
overrides, framework lists and dotnet tools) is read out of the `.nupkg`
itself when it is fetched.

The file is line oriented and indentation sensitive:

    STORAGE: NONE
    RESTRICTION: == net10.0
    NUGET
      remote: https://api.nuget.org/v3/index.json
        Argu (6.2.3)
          FSharp.Core (>= 4.3.2)
    GROUP Build
    ...
"""

# The name Paket gives the implicit, unnamed group at the top of the file.
MAIN_GROUP = "Main"

_NUGET_SECTION = "NUGET"

# Sections that introduce packages; only NUGET is supported.
_SOURCE_SECTIONS = [_NUGET_SECTION, "GITHUB", "GIT", "HTTP"]

# Paket writes the lock file with a byte order mark on Windows.
_BOM = "﻿"

def normalize_version(version):
    """Normalizes a NuGet version string the way the NuGet client does.

    Paket writes versions in their shortest form, but NuGet's flat container
    addresses packages by the normalized version, so `6.0` has to become
    `6.0.0` before it can be turned into a download URL.

    Args:
      version: A version as it appears in `paket.lock`, e.g. "6.0".

    Returns:
      The normalized version, e.g. "6.0.0".
    """

    # Build metadata takes no part in identifying a package.
    version = version.partition("+")[0]

    (release, _, prerelease) = version.partition("-")

    parts = release.split(".")
    for i in range(len(parts)):
        part = parts[i]

        # Leading zeroes are not significant, but a component that is all
        # zeroes must survive as a single "0".
        if part.isdigit():
            parts[i] = str(int(part))

    for _ in range(3 - len(parts)):
        parts.append("0")

    # NuGet keeps a fourth component only when it is not zero.
    if len(parts) == 4 and parts[3] == "0":
        parts = parts[:3]

    normalized = ".".join(parts)

    return normalized + "-" + prerelease if prerelease else normalized

def _parse_package_line(line, path, line_number):
    """Parses `Package.Id (1.2.3) - settings` into (id, version)."""

    # Trailing settings such as `- restriction: ...` or `- copy_local: true`
    # are separated by a spaced hyphen, which cannot occur in a package id.
    entry = line.split(" - ")[0].strip()

    open_paren = entry.find("(")
    close_paren = entry.rfind(")")
    if open_paren == -1 or close_paren < open_paren:
        fail("{}:{}: could not parse the package entry '{}'".format(path, line_number, line.strip()))

    id = entry[:open_paren].strip()
    version = entry[open_paren + 1:close_paren].strip()

    if not id or not version:
        fail("{}:{}: could not parse the package entry '{}'".format(path, line_number, line.strip()))

    return (id, normalize_version(version))

def _new_group(name):
    return {
        "name": name,
        # Keyed by lower cased id: a package can be listed under more than one
        # remote in a group, but Paket resolves it to a single version.
        "packages": {},
        "sources": [],
        "unsupported": "",
    }

def _finish(group):
    return struct(
        name = group["name"],
        packages = group["packages"].values(),
        sources = group["sources"],
        unsupported = group["unsupported"],
    )

def parse_lock(content, path = "paket.lock"):
    """Parses the contents of a `paket.lock` file.

    Args:
      content: The file contents.
      path: The path to report in error messages.

    Returns:
      A list of structs, one per dependency group, each with:
        name: The group name. The unnamed top group is called "Main".
        sources: The package feeds the group resolves against.
        packages: A list of structs with `id` and `version` fields, in the
          order they appear in the file.
        unsupported: Where the group first uses a GITHUB, GIT or HTTP
          section, which rules_dotnet cannot provide, or "".
    """
    groups = []
    group = _new_group(MAIN_GROUP)
    section = _NUGET_SECTION

    if content.startswith(_BOM):
        content = content[len(_BOM):]

    for (index, raw) in enumerate(content.replace("\r\n", "\n").split("\n")):
        line_number = index + 1
        stripped = raw.strip()
        if not stripped:
            continue

        indent = len(raw) - len(raw.lstrip(" "))

        if indent == 0:
            if stripped.startswith("GROUP "):
                groups.append(_finish(group))
                group = _new_group(stripped[len("GROUP "):].strip())
                section = _NUGET_SECTION
                continue

            keyword = stripped.split(" ")[0].upper()
            if keyword in _SOURCE_SECTIONS:
                section = keyword

            # Everything else at the top level is a group option such as
            # `STORAGE: NONE`, none of which affect the resolved packages.
            continue

        if section != _NUGET_SECTION:
            # GITHUB/GIT/HTTP dependencies resolve to source files rather than
            # packages. Recorded rather than failed on, so that only using the
            # group is an error.
            if not group["unsupported"]:
                group["unsupported"] = "{}:{}: the {} section is not supported by rules_dotnet.".format(path, line_number, section)
            continue

        if stripped.startswith("remote:"):
            remote = stripped[len("remote:"):].strip()
            if remote and remote not in group["sources"]:
                group["sources"].append(remote)
            continue

        # Older Paket versions emit a `specs:` marker after the remote.
        if stripped == "specs:":
            continue

        # Package entries sit directly under the remote; anything deeper is a
        # transitive dependency edge, which we re-derive from the nuspec.
        if indent > 4:
            continue

        (id, version) = _parse_package_line(stripped, path, line_number)
        group["packages"].setdefault(id.lower(), struct(id = id, version = version))

    groups.append(_finish(group))

    # Paket always writes the main group first, even when it is empty.
    return [group for group in groups if group.packages or group.unsupported]
