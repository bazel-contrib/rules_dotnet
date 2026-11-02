"""Looks up .NET SDKs and runtime releases in Microsoft's release metadata.

Microsoft publishes every release of every .NET channel with the SDKs it
shipped: their archives and the SHA-512 of each, and the runtime and language
versions each SDK carries. The `dotnet` extension reads what it needs from
there when it first meets an SDK version, rather than from a table that would
have to be regenerated and released for every SDK Microsoft ships.

What it reads is handed back to Bazel as facts, which keeps it in
`MODULE.bazel.lock` for reviewers to see and for later evaluations to reuse, so
a build whose lock file records an SDK never reads the metadata again. Only
what a fact's key alone decides is kept: an SDK's archives never change once it
has shipped, and nor does which runtime of a channel had shipped by a given day.
"""

load("//dotnet/private:semver.bzl", "semver")
load("//dotnet/private:toolchains_repo.bzl", "PLATFORMS")
load("//dotnet/private/sdk:frameworks.bzl", "SDK_NETCOREAPP_FRAMEWORKS")

_RELEASE_METADATA = "https://builds.dotnet.microsoft.com/dotnet/release-metadata"

# The document listing every channel, under the name the others use for theirs.
_INDEX = "index"

# Bump when the shape of a fact changes so that stale entries are ignored
# rather than misread.
_FACT_VERSION = "v1"

# SDKs before .NET 6 were never supported: their packs are laid out
# differently.
_OLDEST_SUPPORTED_MAJOR = 6

_BASE64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

_HEX_DIGITS = "0123456789abcdef"

def hex_to_base64(digest):
    """Re-encodes a hex digest in standard base 64, which is what integrity takes.

    Args:
      digest: The digest as hex digits, in either case.

    Returns:
      The digest in base 64, or None if `digest` is not a whole number of bytes
      of hex digits.
    """
    digest = digest.lower()
    if not digest or len(digest) % 2 or not all([digit in _HEX_DIGITS for digit in digest.elems()]):
        return None

    data = [int(digest[i:i + 2], 16) for i in range(0, len(digest), 2)]
    encoded = []

    for start in range(0, len(data), 3):
        chunk = data[start:start + 3]
        bits = 0
        for byte in chunk:
            bits = bits * 256 + byte
        bits = bits << (8 * (3 - len(chunk)))

        # Every byte of input carries into one more character; the rest is padding.
        encoded += [_BASE64[(bits >> shift) & 63] for shift in [18, 12, 6, 0][:len(chunk) + 1]]
        encoded.append("=" * (3 - len(chunk)))

    return "".join(encoded)

def _version_key(version):
    return semver.to_comparable(version, relaxed = True)

def _is_stable(version):
    return version != "" and all([part.isdigit() for part in version.split(".")])

def sdk_channel(version):
    """The .NET channel an SDK version belongs to.

    Args:
      version: An SDK version, such as `10.0.401`.

    Returns:
      The channel, such as `10.0`.
    """
    parts = version.split(".")
    if len(parts) < 3 or not parts[0].isdigit() or not parts[1].isdigit():
        fail("'{}' is not a .NET SDK version, such as 10.0.100".format(version))

    return "{}.{}".format(parts[0], parts[1])

def channel_tfm(channel):
    """The target framework a channel's runtime is.

    Args:
      channel: A .NET channel, such as `10.0`.

    Returns:
      The target framework, such as `net10.0`.
    """
    return ("net" if int(channel.split(".")[0]) >= 5 else "netcoreapp") + channel

def tfm_channel(tfm):
    """The .NET channel a .NET Core target framework is the runtime of.

    Args:
      tfm: A target framework, such as `net10.0` or `netcoreapp3.1`.

    Returns:
      The channel, such as `10.0`.
    """
    return tfm[len("netcoreapp"):] if tfm.startswith("netcoreapp") else tfm[len("net"):]

def _download_json(module_ctx, requests):
    """Downloads `requests`, a dict of name to URL, concurrently and parses each."""
    pending = []
    for (name, url) in requests.items():
        output = "release-metadata/{}.json".format(name)
        pending.append((name, url, output, module_ctx.download(
            url = url,
            output = output,
            allow_fail = True,
            block = False,
        )))

    documents = {}
    for (name, url, output, token) in pending:
        if not token.wait().success:
            fail(
                "Could not download the .NET release metadata at {}.".format(url) +
                " It is needed once per SDK version: a MODULE.bazel.lock that records" +
                " the SDK lets a build go without it.",
            )

        documents[name] = json.decode(module_ctx.read(output))

    return documents

def _release_metadata(module_ctx, cache, names):
    """Returns release metadata documents, downloading those `cache` lacks.

    Args:
      module_ctx: The module extension context.
      cache: Documents by name, which this call adds to.
      names: `_INDEX` for the list of channels, or a channel for its releases.

    Returns:
      A dict of name to the parsed document.
    """
    cache.update(_download_json(module_ctx, {
        name: "{}/{}".format(
            _RELEASE_METADATA,
            "releases-index.json" if name == _INDEX else name + "/releases.json",
        )
        for name in names
        if name not in cache
    }))

    return {name: cache[name] for name in names}

def find_sdk(releases, version):
    """Finds an SDK in a channel's releases.

    Args:
      releases: A channel's parsed `releases.json`.
      version: The SDK version.

    Returns:
      A (release, sdk) tuple of the entries that list it, or None. An SDK
      that more than one release lists shipped with the earliest of them.
    """
    found = None

    for release in releases.get("releases", []):
        for sdk in release.get("sdks") or [release.get("sdk")]:
            if not sdk or sdk.get("version") != version:
                continue

            if found == None or release.get("release-date", "") < found[0].get("release-date", ""):
                found = (release, sdk)

    return found

def _archive(files, rid, extension):
    for file in files:
        url = file.get("url", "")

        # The URL is matched as well as the runtime identifier: early previews
        # listed Apple silicon archives as x64.
        if file.get("rid") == rid and url.endswith("-{}{}".format(rid, extension)):
            integrity = hex_to_base64(file.get("hash", ""))
            return {"integrity": "sha512-" + integrity if integrity else "", "url": url}

    return None

def select_archives(files):
    """Picks the archive each toolchain platform downloads from an SDK's files.

    Args:
      files: The `files` of an SDK entry in the release metadata.

    Returns:
      A dict of platform to a dict of the archive's `url` and `integrity`. A
      platform the SDK was not released for is left out, and an archive the
      metadata publishes no hash for has an empty integrity.
    """
    archives = {}

    for (platform, meta) in PLATFORMS.items():
        extension = ".zip" if meta.os == "windows" else ".tar.gz"
        archive = _archive(files, meta.rid, extension)

        # The earliest SDKs shipped no Apple silicon build. The x64 one runs
        # there under Rosetta.
        if archive == None and meta.rid == "osx-arm64":
            archive = _archive(files, "osx-x64", extension)

        if archive != None:
            archives[platform] = archive

    return archives

def sdk_fact_key(version):
    """Returns the key an SDK's release metadata is remembered under.

    Args:
      version: The SDK version.

    Returns:
      The fact key.
    """
    return "dotnet-sdk/{}:{}".format(_FACT_VERSION, version)

def _read_sdk(module_ctx, cache, channel, version):
    releases = _release_metadata(module_ctx, cache, [channel])[channel]
    found = find_sdk(releases, version)

    if found == None:
        fail(
            "There is no .NET SDK {} in the release metadata for .NET {}.".format(version, channel) +
            " The released SDKs are listed at https://dotnet.microsoft.com/download/dotnet/{}".format(channel),
        )

    (release, sdk) = found

    return {
        "archives": select_archives(sdk.get("files") or []),
        "csharp_version": sdk.get("csharp-version") or "",
        "fsharp_version": sdk.get("fsharp-version") or "",
        "release_date": release.get("release-date") or "",
        "runtime_version": sdk.get("runtime-version") or (release.get("runtime") or {}).get("version", ""),
    }

def _is_complete(fact):
    """Whether the metadata had everything about an SDK, so it can be remembered.

    An archive without a hash, or a platform without an archive, may just be
    metadata that has yet to catch up, so it is looked up again next time.
    """
    archives = fact["archives"]

    return (
        sorted(archives.keys()) == sorted(PLATFORMS.keys()) and
        all([archive.get("url") and archive.get("integrity") for archive in archives.values()]) and
        all([fact[key] for key in ["release_date", "runtime_version"]])
    )

def _is_sdk_fact(fact):
    return (
        type(fact) == "dict" and
        type(fact.get("archives")) == "dict" and
        all([type(archive) == "dict" for archive in fact["archives"].values()]) and
        all([
            type(fact.get(key)) == "string"
            for key in ["csharp_version", "fsharp_version", "release_date", "runtime_version"]
        ]) and
        _is_complete(fact)
    )

def resolve_sdk(module_ctx, version, cache):
    """Looks up an SDK: where to download it from, and what it ships.

    Args:
      module_ctx: The module extension context.
      version: The SDK version.
      cache: Release metadata by name, shared across calls.

    Returns:
      A struct of the SDK's `version`, its `channel`, the `tfm` its runtime
      is, its `runtime_version`, `csharp_version` and `fsharp_version`, the
      `release_date` it shipped on, the `archives` from `select_archives`, and
      the `fact` to remember all of it by under `sdk_fact_key`, or None if the
      metadata was missing something and should be read again next time.
    """
    channel = sdk_channel(version)
    if int(channel.split(".")[0]) < _OLDEST_SUPPORTED_MAJOR:
        fail(".NET SDK {} is too old: rules_dotnet supports .NET {}.0 and later.".format(
            version,
            _OLDEST_SUPPORTED_MAJOR,
        ))

    # Its runtime's framework is what tools run on and what the SDK's own pack
    # band is, so it has to be one rules_dotnet declares.
    tfm = channel_tfm(channel)
    if tfm not in SDK_NETCOREAPP_FRAMEWORKS:
        fail(".NET SDK {} would be for {}, which is not one of the frameworks this version of rules_dotnet declares, up to {}.".format(
            version,
            tfm,
            SDK_NETCOREAPP_FRAMEWORKS[-1],
        ))

    fact = getattr(module_ctx, "facts", {}).get(sdk_fact_key(version))
    if not _is_sdk_fact(fact):
        fact = _read_sdk(module_ctx, cache, channel, version)

    return struct(
        version = version,
        channel = channel,
        tfm = tfm,
        runtime_version = fact["runtime_version"],
        csharp_version = fact["csharp_version"],
        fsharp_version = fact["fsharp_version"],
        release_date = fact["release_date"],
        archives = fact["archives"],
        fact = fact if _is_complete(fact) else None,
    )

def runtime_shipped_by(releases, date):
    """The newest generally-available runtime of a channel out by a given day.

    Args:
      releases: A channel's parsed `releases.json`.
      date: The day, as `YYYY-MM-DD`.

    Returns:
      The runtime version, or None if the channel had no stable release yet.
    """
    newest = None

    for release in releases.get("releases", []):
        version = (release.get("runtime") or {}).get("version") or ""
        if release.get("release-date", "") > date or not _is_stable(version):
            continue

        if newest == None or _version_key(version) > _version_key(newest):
            newest = version

    return newest

def runtimes_shipped_by(module_ctx, cache, channels, date):
    """The newest generally-available runtime of each channel out by a given day.

    That is what an SDK bundles the packs of: it ships knowing about the
    releases out on or before its own release day, as near as the dates in the
    metadata tell. A channel with nothing newer than that day is answered from
    the index of channels; only the others need their own, much larger, list of
    releases.

    Args:
      module_ctx: The module extension context.
      cache: Release metadata by name, shared across calls.
      channels: The channels to look up, such as `8.0`.
      date: The day, as `YYYY-MM-DD`.

    Returns:
      A dict of channel to runtime version, or to None where the channel had no
      stable release yet.
    """
    if not channels:
        return {}

    index = {
        entry.get("channel-version"): entry
        for entry in _release_metadata(module_ctx, cache, [_INDEX])[_INDEX].get("releases-index", [])
    }

    shipped = {}
    unsettled = []

    for channel in channels:
        entry = index.get(channel)
        if entry == None:
            shipped[channel] = None
            continue

        latest = entry.get("latest-runtime") or ""
        latest_date = entry.get("latest-release-date") or ""
        if _is_stable(latest) and latest_date and latest_date <= date:
            shipped[channel] = latest
        else:
            unsettled.append(channel)

    for (channel, releases) in _release_metadata(module_ctx, cache, unsettled).items():
        shipped[channel] = runtime_shipped_by(releases, date)

    return shipped

def _shared(published):
    """The versions every list has, in the order of the first."""
    if not published:
        return []

    others = [{version: None for version in versions} for versions in published[1:]]

    return [
        version
        for version in published[0]
        if all([version in other for other in others])
    ]

def newest_shared_release(channel, target, published):
    """The newest release of a channel, up to `target`, that every list has.

    A release is only skipped over when some list lacks it, so a prerelease is
    only ever chosen when it is the target itself.

    Args:
      channel: The channel, such as `8.0`.
      target: The newest acceptable version.
      published: Lists of versions, such as the versions of several packages
        that a feed publishes.

    Returns:
      The version, or None if no release up to `target` is in every list.
    """
    target_key = _version_key(target)
    newest = None
    newest_key = None

    for version in _shared(published):
        if version != target and not (version.startswith(channel + ".") and _is_stable(version)):
            continue

        key = _version_key(version)
        if key <= target_key and (newest == None or key > newest_key):
            newest = version
            newest_key = key

    return newest

def is_superseded(channel, version, published):
    """Whether every list has a stable release of a channel newer than `version`.

    A patch missing from a list that already has a later one is never going to
    be published; one missing from its end may just not have been yet.

    Args:
      channel: The channel, such as `8.0`.
      version: The version.
      published: Lists of versions, as for `newest_shared_release`.

    Returns:
      True if a newer release of the channel is in every list.
    """
    key = _version_key(version)

    return any([
        _version_key(candidate) > key
        for candidate in _shared(published)
        if candidate.startswith(channel + ".") and _is_stable(candidate)
    ])
