"""Tests for reading .NET SDKs and runtimes out of the release metadata.

The network side is exercised by every build; these pin down the decisions made
on what comes back, against hand-written excerpts of the metadata.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/sdk:releases.bzl",
    "channel_tfm",
    "find_sdk",
    "hex_to_base64",
    "is_superseded",
    "newest_shared_release",
    "resolve_sdk",
    "runtime_shipped_by",
    "runtimes_shipped_by",
    "sdk_channel",
    "sdk_fact_key",
    "select_archives",
    "tfm_channel",
)

_METADATA = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/"

def _fake_module_ctx(responses, facts = {}):
    """A module_ctx whose downloads answer from `responses`, a dict of URL to JSON."""
    files = {}
    requested = []

    def download(url, output, allow_fail = False, block = True, **_kwargs):
        requested.append(url)
        if url in responses:
            files[output] = json.encode(responses[url])
        elif not allow_fail:
            fail("unexpected download of " + url)

        result = struct(success = url in responses)
        return result if block else struct(wait = lambda: result)

    return struct(
        download = download,
        facts = facts,
        read = lambda path: files[path],
        requested = requested,
    )

def _hex_to_base64_test_impl(ctx):
    env = unittest.begin(ctx)

    # The linux-x64 archive of SDK 10.0.403, as the metadata publishes it and
    # as integrity wants it.
    sha512 = "b7b3d8461cf98b07d2552ce9199702fa3ad010ac2671a5f8cd5136f7534e50f6855ba7bbb02b11494563f1d04156276a31cda1103b900e5eecd0d9473dc7b9c5"
    expected = "t7PYRhz5iwfSVSzpGZcC+jrQEKwmcaX4zVE291NOUPaFW6e7sCsRSUVj8dBBVidqMc2hEDuQDl7s0NlHPce5xQ=="
    asserts.equals(env, expected, hex_to_base64(sha512))
    asserts.equals(env, expected, hex_to_base64(sha512.upper()))

    # One, two and three bytes: two, one and no padding characters.
    asserts.equals(env, "/w==", hex_to_base64("ff"))
    asserts.equals(env, "//8=", hex_to_base64("ffff"))
    asserts.equals(env, "////", hex_to_base64("ffffff"))
    asserts.equals(env, "AAECAw==", hex_to_base64("00010203"))

    for invalid in ["", "abc", "zz", "sha512-ab"]:
        asserts.equals(env, None, hex_to_base64(invalid), "'{}' is not a hex digest".format(invalid))

    return unittest.end(env)

_hex_to_base64_test = unittest.make(_hex_to_base64_test_impl)

def _versions_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "10.0", sdk_channel("10.0.401"))
    asserts.equals(env, "11.0", sdk_channel("11.0.100-rc.3.26522.148"))

    asserts.equals(env, "net10.0", channel_tfm("10.0"))
    asserts.equals(env, "netcoreapp3.1", channel_tfm("3.1"))

    asserts.equals(env, "10.0", tfm_channel("net10.0"))
    asserts.equals(env, "3.1", tfm_channel("netcoreapp3.1"))

    return unittest.end(env)

_versions_test = unittest.make(_versions_test_impl)

def _file(rid, name, hash = "ff"):
    return {
        "hash": hash,
        "name": name,
        "rid": rid,
        "url": "https://builds.dotnet.microsoft.com/dotnet/Sdk/10.0.403/" + name,
    }

def _select_archives_test_impl(ctx):
    env = unittest.begin(ctx)

    files = [
        _file("linux-arm", "dotnet-sdk-10.0.403-linux-arm.tar.gz"),
        _file("linux-arm64", "dotnet-sdk-10.0.403-linux-arm64.tar.gz"),
        _file("linux-musl-x64", "dotnet-sdk-10.0.403-linux-musl-x64.tar.gz"),
        # Some releases also have a zip for Linux.
        _file("linux-x64", "dotnet-sdk-10.0.403-linux-x64.zip"),
        _file("linux-x64", "dotnet-sdk-10.0.403-linux-x64.tar.gz", hash = "ffff"),
        _file("osx-arm64", "dotnet-sdk-10.0.403-osx-arm64.pkg"),
        _file("osx-arm64", "dotnet-sdk-10.0.403-osx-arm64.tar.gz"),
        _file("osx-x64", "dotnet-sdk-10.0.403-osx-x64.tar.gz"),
        _file("win-arm64", "dotnet-sdk-10.0.403-win-arm64.exe"),
        _file("win-arm64", "dotnet-sdk-10.0.403-win-arm64.zip"),
        _file("win-x64", "dotnet-sdk-10.0.403-win-x64.zip", hash = ""),
        _file("win-x86", "dotnet-sdk-10.0.403-win-x86.zip"),
    ]

    archives = select_archives(files)
    asserts.equals(
        env,
        {
            "aarch64-apple-darwin": "dotnet-sdk-10.0.403-osx-arm64.tar.gz",
            "arm64-pc-windows-msvc": "dotnet-sdk-10.0.403-win-arm64.zip",
            "arm64-unknown-linux-gnu": "dotnet-sdk-10.0.403-linux-arm64.tar.gz",
            "x86_64-apple-darwin": "dotnet-sdk-10.0.403-osx-x64.tar.gz",
            "x86_64-pc-windows-msvc": "dotnet-sdk-10.0.403-win-x64.zip",
            "x86_64-unknown-linux-gnu": "dotnet-sdk-10.0.403-linux-x64.tar.gz",
        },
        {platform: archive["url"].split("/")[-1] for (platform, archive) in archives.items()},
    )
    asserts.equals(env, "sha512-//8=", archives["x86_64-unknown-linux-gnu"]["integrity"])
    asserts.equals(env, "", archives["x86_64-pc-windows-msvc"]["integrity"], "an archive without a hash")

    # An early preview listed its Apple silicon archive as x64, and had no
    # archive for Apple silicon under its own name, nor one for Windows on Arm.
    early = select_archives([
        _file("osx-x64", "dotnet-sdk-6.0.100-preview.1-osx-x64.tar.gz"),
        _file("osx-x64", "dotnet-sdk-6.0.100-preview.1-osx-arm64.tar.gz"),
        _file("linux-x64", "dotnet-sdk-6.0.100-preview.1-linux-x64.tar.gz"),
    ])
    asserts.equals(
        env,
        {
            "aarch64-apple-darwin": "dotnet-sdk-6.0.100-preview.1-osx-x64.tar.gz",
            "x86_64-apple-darwin": "dotnet-sdk-6.0.100-preview.1-osx-x64.tar.gz",
            "x86_64-unknown-linux-gnu": "dotnet-sdk-6.0.100-preview.1-linux-x64.tar.gz",
        },
        {platform: archive["url"].split("/")[-1] for (platform, archive) in early.items()},
    )

    return unittest.end(env)

_select_archives_test = unittest.make(_select_archives_test_impl)

def _release(date, runtime, sdks = []):
    return {
        "release-date": date,
        "runtime": {"version": runtime} if runtime else None,
        "sdks": [{"runtime-version": runtime, "version": sdk} for sdk in sdks],
    }

_RELEASES = {
    "releases": [
        _release("2026-09-08", "10.0.12", ["10.0.401", "10.0.112"]),
        _release("2026-08-11", "10.0.11", ["10.0.400"]),
        # A release of the SDK alone.
        _release("2026-07-22", None, ["10.0.302"]),
        _release("2026-07-14", "10.0.10", ["10.0.301"]),
        _release("2025-10-14", "10.0.0-rc.2.25502.107", ["10.0.100-rc.2.25502.107"]),
    ],
}

def _find_sdk_test_impl(ctx):
    env = unittest.begin(ctx)

    (release, sdk) = find_sdk(_RELEASES, "10.0.112")
    asserts.equals(env, "2026-09-08", release["release-date"])
    asserts.equals(env, "10.0.12", sdk["runtime-version"])

    asserts.equals(env, "2026-07-22", find_sdk(_RELEASES, "10.0.302")[0]["release-date"])
    asserts.equals(env, None, find_sdk(_RELEASES, "10.0.999"))

    # Old releases list their one SDK under `sdk` alone.
    old = {"releases": [{"release-date": "2021-11-08", "sdk": {"version": "6.0.100"}}]}
    asserts.equals(env, "2021-11-08", find_sdk(old, "6.0.100")[0]["release-date"])

    # An SDK a later release lists again shipped with the first.
    relisted = {"releases": [
        _release("2026-09-08", "10.0.12", ["10.0.401"]),
        _release("2026-08-11", "10.0.11", ["10.0.401"]),
    ]}
    asserts.equals(env, "2026-08-11", find_sdk(relisted, "10.0.401")[0]["release-date"])

    return unittest.end(env)

_find_sdk_test = unittest.make(_find_sdk_test_impl)

def _runtime_shipped_by_test_impl(ctx):
    env = unittest.begin(ctx)

    # A release out on the day itself counts: the bands of one Patch Tuesday
    # ship together.
    asserts.equals(env, "10.0.12", runtime_shipped_by(_RELEASES, "2026-09-08"))
    asserts.equals(env, "10.0.11", runtime_shipped_by(_RELEASES, "2026-09-07"))

    # A release of the SDK alone carries no runtime.
    asserts.equals(env, "10.0.10", runtime_shipped_by(_RELEASES, "2026-07-30"))

    # Previews are not releases of a band.
    asserts.equals(env, None, runtime_shipped_by(_RELEASES, "2026-01-01"))
    asserts.equals(env, None, runtime_shipped_by({}, "2026-01-01"))

    return unittest.end(env)

_runtime_shipped_by_test = unittest.make(_runtime_shipped_by_test_impl)

# Microsoft.NETCore.App.Ref and Microsoft.AspNetCore.App.Ref each skip patches
# the other has.
_PUBLISHED = [
    ["6.0.0", "6.0.1", "6.0.2", "8.0.8", "8.0.10", "8.0.31", "8.0.33", "9.0.1", "10.0.0-rc.2.25502.107", "10.0.0"],
    ["6.0.0", "6.0.2", "8.0.8", "8.0.9", "8.0.10", "8.0.31", "8.0.33", "9.0.1", "10.0.0-rc.2.25502.107", "10.0.0"],
]

def _newest_shared_release_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "8.0.31", newest_shared_release("8.0", "8.0.31", _PUBLISHED))
    asserts.equals(env, "8.0.33", newest_shared_release("8.0", "8.0.40", _PUBLISHED))

    # A patch that one of the packs skipped gives way to the one before it.
    asserts.equals(env, "8.0.8", newest_shared_release("8.0", "8.0.9", _PUBLISHED))
    asserts.equals(env, "6.0.0", newest_shared_release("6.0", "6.0.1", _PUBLISHED))

    # A preview SDK's band is at the preview, if its packs are.
    asserts.equals(env, "10.0.0-rc.2.25502.107", newest_shared_release("10.0", "10.0.0-rc.2.25502.107", _PUBLISHED))
    asserts.equals(env, None, newest_shared_release("10.0", "10.0.0-rc.1.25451.107", _PUBLISHED))

    # Other channels never stand in.
    asserts.equals(env, None, newest_shared_release("7.0", "7.0.20", _PUBLISHED))
    asserts.equals(env, None, newest_shared_release("8.0", "8.0.31", []))

    # A skipped patch is only for good once a later one is out: until then its
    # packs may just not have reached the feed.
    asserts.true(env, is_superseded("8.0", "8.0.9", _PUBLISHED))
    asserts.false(env, is_superseded("8.0", "8.0.34", _PUBLISHED))
    asserts.false(env, is_superseded("8.0", "8.0.33", _PUBLISHED))
    asserts.true(env, is_superseded("10.0", "10.0.0-rc.2.25502.107", _PUBLISHED), "a release supersedes its previews")
    asserts.false(env, is_superseded("7.0", "7.0.1", _PUBLISHED), "other channels never supersede")

    return unittest.end(env)

_newest_shared_release_test = unittest.make(_newest_shared_release_test_impl)

# One archive for every toolchain platform, each with a hash.
_FILES = [
    _file(rid, "dotnet-sdk-10.0.401-{}.{}".format(rid, "zip" if rid.startswith("win") else "tar.gz"))
    for rid in ["linux-arm64", "linux-x64", "osx-arm64", "osx-x64", "win-arm64", "win-x64"]
]

def _channel(sdk_files):
    return {"releases": [{
        "release-date": "2026-09-08",
        "runtime": {"version": "10.0.12"},
        "sdks": [{
            "csharp-version": "14.0",
            "files": sdk_files,
            "fsharp-version": "10.0",
            "runtime-version": "10.0.12",
            "version": "10.0.401",
        }],
    }]}

def _resolve_sdk_test_impl(ctx):
    env = unittest.begin(ctx)

    module_ctx = _fake_module_ctx({_METADATA + "10.0/releases.json": _channel(_FILES)})
    sdk = resolve_sdk(module_ctx, "10.0.401", {})
    asserts.equals(env, "net10.0", sdk.tfm)
    asserts.equals(env, "10.0.12", sdk.runtime_version)
    asserts.equals(env, "2026-09-08", sdk.release_date)
    asserts.equals(env, "14.0", sdk.csharp_version)
    asserts.equals(env, 6, len(sdk.archives))
    asserts.true(env, sdk.fact != None, "complete metadata is remembered")

    # What is remembered is used without asking again.
    remembered = _fake_module_ctx({}, facts = {sdk_fact_key("10.0.401"): sdk.fact})
    asserts.equals(env, sdk.archives, resolve_sdk(remembered, "10.0.401", {}).archives)
    asserts.equals(env, [], remembered.requested)

    # An archive without a hash, or a platform without an archive, may be
    # metadata that has yet to catch up.
    for files in [_FILES[1:], [_file(f["rid"], f["name"], hash = "") for f in _FILES]]:
        partial = resolve_sdk(_fake_module_ctx({_METADATA + "10.0/releases.json": _channel(files)}), "10.0.401", {})
        asserts.equals(env, None, partial.fact)
        asserts.false(
            env,
            resolve_sdk(_fake_module_ctx({_METADATA + "10.0/releases.json": _channel(_FILES)}, facts = {
                sdk_fact_key("10.0.401"): partial.fact or {"archives": {}},
            }), "10.0.401", {}).fact == None,
            "an incomplete fact is looked up again",
        )

    return unittest.end(env)

_resolve_sdk_test = unittest.make(_resolve_sdk_test_impl)

def _runtimes_shipped_by_test_impl(ctx):
    env = unittest.begin(ctx)

    index = {"releases-index": [
        {"channel-version": "10.0", "latest-release-date": "2026-10-25", "latest-runtime": "10.0.14"},
        {"channel-version": "7.0", "latest-release-date": "2024-05-28", "latest-runtime": "7.0.20"},
    ]}
    module_ctx = _fake_module_ctx({
        _METADATA + "releases-index.json": index,
        _METADATA + "10.0/releases.json": _RELEASES,
    })

    asserts.equals(
        env,
        {"10.0": "10.0.11", "7.0": "7.0.20", "12.0": None},
        runtimes_shipped_by(module_ctx, {}, ["10.0", "7.0", "12.0"], "2026-09-07"),
    )

    # A channel with nothing newer than the day is answered from the index.
    asserts.equals(
        env,
        [_METADATA + "releases-index.json", _METADATA + "10.0/releases.json"],
        module_ctx.requested,
    )

    return unittest.end(env)

_runtimes_shipped_by_test = unittest.make(_runtimes_shipped_by_test_impl)

def releases_test_suite(name):
    unittest.suite(
        name,
        _find_sdk_test,
        _hex_to_base64_test,
        _newest_shared_release_test,
        _resolve_sdk_test,
        _runtime_shipped_by_test,
        _runtimes_shipped_by_test,
        _select_archives_test,
        _versions_test,
    )
