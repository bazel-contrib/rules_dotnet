"""Tests for the packages.lock.json parser."""

load("@bazel_skylib//lib:partial.bzl", "partial")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//dotnet/private/packages_lock:lock.bzl", "parse_lock")

_LOCK = """\
{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "Argu": {
        "type": "Direct",
        "requested": "[6.2.3, )",
        "resolved": "6.2.3",
        "contentHash": "NNJpIQzjKB/GrXoSHOo5SLNMZLr70LQRE/by6HplFjRSdy8M+ZxoN2DTbt78/uu6sx0Fya6ibn+iEu0F5HmFDQ==",
        "dependencies": {
          "FSharp.Core": "4.3.2"
        }
      },
      "FSharp.Core": {
        "type": "Direct",
        "requested": "[10.1.401, )",
        "resolved": "10.1.401",
        "contentHash": "/lvOK51KD8IangBYkfDVna3/HrE/r4VUnX3dI01KDspctoYXmind3POeoYkqWKeXHwiKlf6Hc9TxwSnoSCWcjw=="
      },
      "Newtonsoft.Json": {
        "type": "Transitive",
        "resolved": "13.0.3",
        "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
      }
    },
    "net9.0": {
      "LibGit2Sharp": {
        "type": "Direct",
        "requested": "[0.27.0-preview-0182, )",
        "resolved": "0.27.0-preview-0182",
        "contentHash": "YgSFGX7q+KwzkjiD04sZ6Zr8GVrG4o7dHUwM9eDsliT350HxX83smtJc8kyMBiBLyjX4X3qB7aIs2KJL3Uh1og=="
      },
      "LibGit2Sharp.NativeBinaries": {
        "type": "Transitive",
        "resolved": "2.0.315-alpha.0.9",
        "contentHash": "Cl9E9ZRZm2ma5k/gD/9+f5WAh/9ayhENos/jLkSmPmzkuKl8qkTaLHA9j70qEZ1RSRceDlIwbfSYzVD5JaxHzg=="
      }
    }
  }
}
"""

def _package_versions(group):
    return {package.id: package.version for package in group.packages}

def _package_content_hashes(group):
    return {package.id: package.content_hash for package in group.packages}

def _parse_lock_test_impl(ctx):
    env = unittest.begin(ctx)
    groups = parse_lock(_LOCK)

    asserts.equals(env, ["net10.0", "net9.0"], [group.name for group in groups])
    asserts.equals(
        env,
        {
            "Argu": "6.2.3",
            "FSharp.Core": "10.1.401",
            "Newtonsoft.Json": "13.0.3",
        },
        _package_versions(groups[0]),
        "direct and transitive packages are both included",
    )
    asserts.equals(
        env,
        {
            "Argu": "NNJpIQzjKB/GrXoSHOo5SLNMZLr70LQRE/by6HplFjRSdy8M+ZxoN2DTbt78/uu6sx0Fya6ibn+iEu0F5HmFDQ==",
            "FSharp.Core": "/lvOK51KD8IangBYkfDVna3/HrE/r4VUnX3dI01KDspctoYXmind3POeoYkqWKeXHwiKlf6Hc9TxwSnoSCWcjw==",
            "Newtonsoft.Json": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
        },
        _package_content_hashes(groups[0]),
    )
    asserts.equals(
        env,
        {
            "LibGit2Sharp": "0.27.0-preview-0182",
            "LibGit2Sharp.NativeBinaries": "2.0.315-alpha.0.9",
        },
        _package_versions(groups[1]),
    )
    asserts.equals(
        env,
        {
            "LibGit2Sharp": "YgSFGX7q+KwzkjiD04sZ6Zr8GVrG4o7dHUwM9eDsliT350HxX83smtJc8kyMBiBLyjX4X3qB7aIs2KJL3Uh1og==",
            "LibGit2Sharp.NativeBinaries": "Cl9E9ZRZm2ma5k/gD/9+f5WAh/9ayhENos/jLkSmPmzkuKl8qkTaLHA9j70qEZ1RSRceDlIwbfSYzVD5JaxHzg==",
        },
        _package_content_hashes(groups[1]),
    )

    return unittest.end(env)

_parse_lock_test = unittest.make(_parse_lock_test_impl)

_MISSING_HASH_LOCK = """\
{
  "dependencies": {
    "net8.0": {
      "Missing.Hash": {
        "type": "Transitive",
        "resolved": "1.0.0"
      }
    }
  }
}
"""

def _missing_hash_target_impl(ctx):
    parse_lock(_MISSING_HASH_LOCK, str(ctx.label))
    return []

_missing_hash_target = rule(implementation = _missing_hash_target_impl)

def _missing_hash_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "has no contentHash")
    return analysistest.end(env)

_missing_hash_test = analysistest.make(
    _missing_hash_test_impl,
    expect_failure = True,
)

def lock_test_suite(name):
    missing_hash_target = name + "_missing_hash_target"
    _missing_hash_target(name = missing_hash_target)
    unittest.suite(
        name,
        _parse_lock_test,
        partial.make(
            _missing_hash_test,
            target_under_test = ":" + missing_hash_target,
        ),
    )
