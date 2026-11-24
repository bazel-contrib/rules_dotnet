"""NuGet version strings.

A NuGet version is `major.minor[.patch[.revision]][-prerelease][+metadata]`:
two to four numeric release components, then the optional pre-release and
build-metadata parts of SemVer 2.0. NuGet is more lenient than SemVer in two
ways that matter here: it accepts a fourth release component, and it accepts
leading zeros, which it drops when normalizing (`1.02` is `1.2`).

`dotnet/private/tools/nuget_pack/NuGetVersion.cs` parses the same grammar,
for the version the packer reads from a `version_file` at build time.
"""

# `AssemblyVersion` stores each component as a 16-bit number.
_MAX_COMPONENT = 65535

# What an assembly reports as its version when its target sets none, and so
# what it is named by in a `deps.json`.
DEFAULT_ASSEMBLY_VERSION = "1.0.0"

def _valid_identifiers(part):
    """Whether `part` is a dot-separated list of non-empty `[0-9A-Za-z-]` identifiers."""
    for identifier in part.split("."):
        if not identifier:
            return False
        for char in identifier.elems():
            if not (char.isalnum() or char == "-"):
                return False
    return True

def _check(version, max_component = _MAX_COMPONENT):
    """Parses `version`, returning a `(parsed, error)` pair with exactly one side set.

    `max_component` bounds each release component, or is None for no bound.
    """
    if type(version) != "string" or not version:
        return (None, "a version must be a non-empty string, got {}".format(repr(version)))

    (rest, plus, metadata) = version.partition("+")
    if plus and not _valid_identifiers(metadata):
        return (None, "version {} has invalid build metadata after '+'".format(repr(version)))

    (release, dash, prerelease) = rest.partition("-")
    if dash and not _valid_identifiers(prerelease):
        return (None, "version {} has an invalid pre-release label after '-'".format(repr(version)))

    parts = release.split(".")
    if len(parts) < 2 or len(parts) > 4:
        return (None, "version {} must have two to four numeric components".format(repr(version)))

    numbers = []
    for part in parts:
        # `isdigit` is false for the empty string, which rejects `1..2`.
        if not part.isdigit():
            return (None, "version {}: component {} is not a number".format(repr(version), repr(part)))
        number = int(part)
        if max_component != None and number > max_component:
            return (None, "version {}: component {} exceeds {}, the AssemblyVersion limit".format(repr(version), part, max_component))
        numbers.append(number)

    for _ in range(4 - len(numbers)):
        numbers.append(0)

    return (struct(
        major = numbers[0],
        minor = numbers[1],
        patch = numbers[2],
        revision = numbers[3],
        prerelease = prerelease,
    ), None)

def _parse_or_fail(version):
    (parsed, error) = _check(version)
    if error:
        fail(error)
    return parsed

def _error(version):
    """The reason `version` is not a valid NuGet version, or None when it is.

    Args:
      version: The version string.

    Returns:
      A message naming the problem, or None.
    """
    (_, error) = _check(version)
    return error

def _assembly_version(version):
    """The `a.b.c.d` form of `version` for an `AssemblyVersion` attribute.

    Missing components are zero; the pre-release label and metadata are
    dropped, since an assembly version is numbers only.

    Args:
      version: The version string. Fails when it is not a valid version.

    Returns:
      The four-component version string.
    """
    parsed = _parse_or_fail(version)
    return "{}.{}.{}.{}".format(parsed.major, parsed.minor, parsed.patch, parsed.revision)

def _normalize(version):
    """The normalized form of `version`, as NuGet spells it.

    Three components, a fourth only when it is not zero, the pre-release label
    if any, and no metadata: `1.02.3.0-Beta+sha` is `1.2.3-Beta`. This is the
    version in a package's file name and in a feed.

    Args:
      version: The version string. Fails when it is not a valid version.

    Returns:
      The normalized version string.
    """
    parsed = _parse_or_fail(version)
    normalized = "{}.{}.{}".format(parsed.major, parsed.minor, parsed.patch)
    if parsed.revision != 0:
        normalized += ".{}".format(parsed.revision)
    if parsed.prerelease:
        normalized += "-" + parsed.prerelease
    return normalized

def _compare_labels(left, right):
    """Orders two pre-release labels, as NuGet does: SemVer 2.0, ignoring case."""
    left = left.split(".") if left else []
    right = right.split(".") if right else []
    for (a, b) in zip(left, right):
        if a.isdigit() and b.isdigit():
            (a, b) = (int(a), int(b))
        elif a.isdigit() or b.isdigit():
            # A numeric identifier sorts before an alphanumeric one.
            return -1 if a.isdigit() else 1
        else:
            (a, b) = (a.lower(), b.lower())

        if a != b:
            return -1 if a < b else 1

    if len(left) == len(right):
        return 0
    return -1 if len(left) < len(right) else 1

def _is_newer(version, other):
    """Whether `version` orders after `other`, as NuGet orders versions.

    Release components are compared as four numbers, a missing one being zero,
    so `10.0.14.0` is `10.0.14`. A release orders after its pre-releases, and
    build metadata is ignored. A version that is not one - an empty string
    among them, which is what a target that sets none has - is never newer,
    and nothing is newer than it.

    Args:
      version: The version that might be newer.
      other: The version to compare it with.

    Returns:
      True if `version` is the newer of the two.
    """
    (a, error) = _check(version, max_component = None)
    if error:
        return False
    (b, error) = _check(other, max_component = None)
    if error:
        return False

    for (x, y) in [(a.major, b.major), (a.minor, b.minor), (a.patch, b.patch), (a.revision, b.revision)]:
        if x != y:
            return x > y

    if not a.prerelease or not b.prerelease:
        return not a.prerelease and bool(b.prerelease)

    return _compare_labels(a.prerelease, b.prerelease) > 0

nuget_version = struct(
    error = _error,
    assembly_version = _assembly_version,
    is_newer = _is_newer,
    normalize = _normalize,
)
