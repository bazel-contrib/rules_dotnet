"""Tests for the paket.lock parser."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/paket:dependencies.bzl", "parse_dependencies", "stale_requirements")
load("//dotnet/private/paket:lock.bzl", "normalize_version", "parse_lock")

_LOCK = """\
STORAGE: NONE
RESTRICTION: == net10.0
NUGET
  remote: https://api.nuget.org/v3/index.json
    Argu (6.2.3)
      FSharp.Core (>= 4.3.2)
      System.Configuration.ConfigurationManager (>= 4.4)
    FSharp.Core (10.1.401)
    System.ComponentModel.Composition (6.0)

GROUP Build
RESTRICTION: || (== net9.0) (== netstandard2.0)
NUGET
  remote: https://api.nuget.org/v3/index.json
  remote: https://pkgs.example.com/v3/index.json
    LibGit2Sharp (0.27.0-preview-0182)
      LibGit2Sharp.NativeBinaries (2.0.315-alpha.0.9)
    Microsoft.Bcl.AsyncInterfaces (8.0) - restriction: || (&& (== net9.0) (>= net462)) (== netstandard2.0)
    RocksDB (10.2.1.58549)
"""

_DEPENDENCIES = """\
storage: none
framework: net10.0
source https://api.nuget.org/v3/index.json

# A comment
nuget Argu 6.2.3
nuget FSharp.Core 10.1.401
nuget System.Text.Json 10.0

group Build
    source https://api.nuget.org/v3/index.json

    nuget LibGit2Sharp 0.27.0-preview-0182
    nuget Newtonsoft.Json
    nuget FSharp.Data ~> 4.2
    nuget NUnit >= 3.0
    nuget Humanizer.Core 3.0.0 framework: net9.0
    nuget CSharpier prerelease
"""

def _group_names(groups):
    return [group.name for group in groups]

def _package_versions(group):
    return {package.id: package.version for package in group.packages}

def _parse_lock_test_impl(ctx):
    env = unittest.begin(ctx)
    groups = parse_lock(_LOCK)

    asserts.equals(env, ["Main", "Build"], _group_names(groups))

    (main, build) = groups

    asserts.equals(env, ["https://api.nuget.org/v3/index.json"], main.sources)
    asserts.equals(
        env,
        {
            "Argu": "6.2.3",
            "FSharp.Core": "10.1.401",
            "System.ComponentModel.Composition": "6.0.0",
        },
        _package_versions(main),
        "transitive dependency lines are not packages, and versions are normalized",
    )

    asserts.equals(
        env,
        [
            "https://api.nuget.org/v3/index.json",
            "https://pkgs.example.com/v3/index.json",
        ],
        build.sources,
    )
    asserts.equals(
        env,
        {
            "LibGit2Sharp": "0.27.0-preview-0182",
            "Microsoft.Bcl.AsyncInterfaces": "8.0.0",
            "RocksDB": "10.2.1.58549",
        },
        _package_versions(build),
        "a trailing restriction is not part of the version",
    )

    return unittest.end(env)

_parse_lock_test = unittest.make(_parse_lock_test_impl)

_NORMALIZED_VERSIONS = {
    "6.0": "6.0.0",
    "10.0": "10.0.0",
    "7": "7.0.0",
    "1.2.3": "1.2.3",
    "1.0.0.0": "1.0.0",
    "10.2.1.58549": "10.2.1.58549",
    "4.0.3": "4.0.3",
    "0.27.0-preview-0182": "0.27.0-preview-0182",
    "10.0.0-alpha011": "10.0.0-alpha011",
    "3.0.0-beta.96": "3.0.0-beta.96",
    "2.0-rc": "2.0.0-rc",
    "1.0.0+build.1": "1.0.0",
    "01.2": "1.2.0",
}

def _normalize_version_test_impl(ctx):
    env = unittest.begin(ctx)

    for (version, expected) in _NORMALIZED_VERSIONS.items():
        asserts.equals(env, expected, normalize_version(version), version)

    return unittest.end(env)

_normalize_version_test = unittest.make(_normalize_version_test_impl)

def _parse_dependencies_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(
        env,
        {
            "Build": {
                "CSharpier": "",
                "FSharp.Data": "",
                "Humanizer.Core": "3.0.0",
                "LibGit2Sharp": "0.27.0-preview-0182",
                "NUnit": "",
                "Newtonsoft.Json": "",
            },
            "Main": {
                "Argu": "6.2.3",
                "FSharp.Core": "10.1.401",
                "System.Text.Json": "10.0.0",
            },
        },
        parse_dependencies(_DEPENDENCIES),
        "only an exact version is a pin; a constraint or a setting is not",
    )
    asserts.equals(
        env,
        {"Build": {"LibGit2Sharp": "0.27.0"}},
        parse_dependencies("group Build\n    nuget LibGit2Sharp 0.27.0\n"),
        "the main group only appears when packages sit outside a group",
    )

    return unittest.end(env)

_parse_dependencies_test = unittest.make(_parse_dependencies_test_impl)

_LOCK_WITH_SOURCES = """\
NUGET
  remote: https://api.nuget.org/v3/index.json
    Argu (6.2.3)

GROUP Docs
GITHUB
  remote: fsprojects/FAKE
    src/app/FakeLib/Globbing/Globbing.fs (0341a2e614eb2a7f34607cec914eb0ed83ce9add)
"""

def _unsupported_sections_test_impl(ctx):
    env = unittest.begin(ctx)
    groups = {group.name: group for group in parse_lock(_LOCK_WITH_SOURCES, "paket.lock")}

    asserts.equals(env, ["Main", "Docs"], groups.keys(), "a group of only unsupported sections is still a group")
    asserts.equals(env, "", groups["Main"].unsupported)
    asserts.equals(
        env,
        "paket.lock:7: the GITHUB section is not supported by rules_dotnet.",
        groups["Docs"].unsupported,
        "an unsupported section only fails the build when its group is used",
    )

    return unittest.end(env)

_unsupported_sections_test = unittest.make(_unsupported_sections_test_impl)

def _stale_requirements_test_impl(ctx):
    env = unittest.begin(ctx)
    locked = {group.name.lower(): group for group in parse_lock(_LOCK)}

    asserts.equals(
        env,
        [],
        stale_requirements(
            {
                "BUILD": {"libgit2sharp": "0.27.0-PREVIEW-0182", "RocksDB": ""},
                "Main": {"Argu": "6.2.3"},
            },
            locked,
        ),
        "group names, package ids and versions compare case insensitively",
    )
    asserts.equals(
        env,
        [
            "the 'Docs' group is missing",
            "Argu is pinned at 6.2.4 but the 'Main' group resolves 6.2.3",
            "Newtonsoft.Json is missing from the 'Main' group",
        ],
        stale_requirements(
            {
                "Docs": {"FSharp.Formatting": ""},
                "Main": {"Argu": "6.2.4", "Newtonsoft.Json": ""},
            },
            locked,
        ),
    )

    return unittest.end(env)

_stale_requirements_test = unittest.make(_stale_requirements_test_impl)

def lock_test_suite(name):
    unittest.suite(
        name,
        _normalize_version_test,
        _parse_dependencies_test,
        _parse_lock_test,
        _stale_requirements_test,
        _unsupported_sections_test,
    )
