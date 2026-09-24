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

def _check(version):
    """Parses `version`, returning a `(parsed, error)` pair with exactly one side set."""
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
        if number > _MAX_COMPONENT:
            return (None, "version {}: component {} exceeds {}, the AssemblyVersion limit".format(repr(version), part, _MAX_COMPONENT))
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

nuget_version = struct(
    error = _error,
    assembly_version = _assembly_version,
    normalize = _normalize,
)
