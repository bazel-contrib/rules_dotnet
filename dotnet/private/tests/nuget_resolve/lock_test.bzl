"""Tests for the nuget_resolve.json parser and validator."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/nuget_resolve:lock.bzl", "parse_lock", "validate_lock")

_LOCK = """\
{
  "version": 1,
  "inputHash": "737269301",
  "frameworks": {
    "net10.0": {
      "packages": [
        {
          "id": "Newtonsoft.Json",
          "version": "13.0.3",
          "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
          "urls": [
            "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg"
          ]
        },
        {
          "id": "Serilog",
          "version": "4.0.0",
          "sha512": "sha512-AAAA",
          "urls": ["https://feed/serilog.4.0.0.nupkg"]
        }
      ]
    },
    "net8.0": {
      "packages": [
        {
          "id": "Newtonsoft.Json",
          "version": "13.0.3",
          "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
          "urls": ["https://feed/newtonsoft.json.13.0.3.nupkg"]
        }
      ]
    }
  }
}
"""

def _parse_lock_test_impl(ctx):
    env = unittest.begin(ctx)

    lock = parse_lock(_LOCK, "nuget_resolve.json")

    asserts.equals(env, "737269301", lock.input_hash)
    asserts.equals(env, ["net10.0", "net8.0"], lock.frameworks.keys(), "insertion order is preserved")
    packages = lock.frameworks["net10.0"]
    asserts.equals(env, ["Newtonsoft.Json", "Serilog"], [p.id for p in packages])
    asserts.equals(env, "13.0.3", packages[0].version)
    asserts.equals(
        env,
        "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
        packages[0].sha512,
    )
    asserts.equals(
        env,
        ["https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg"],
        packages[0].urls,
    )

    return unittest.end(env)

_parse_lock_test = unittest.make(_parse_lock_test_impl)

def _validate_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, [], validate_lock(_LOCK), "the valid lock file has no problems")

    errors = validate_lock('{"version": 2, "inputHash": "1", "frameworks": {"net10.0": {"packages": []}}}')
    asserts.true(env, len(errors) == 1, "one error for the unknown version: %s" % errors)
    asserts.true(env, errors[0].find("version") != -1, "the error names the version field: %s" % errors[0])
    asserts.true(env, errors[0].find("REPIN") != -1, "the error points at repinning: %s" % errors[0])

    errors = validate_lock('{"version": 1, "frameworks": {"net10.0": {"packages": []}}}')
    asserts.true(env, len(errors) == 1, "one error for the missing inputHash: %s" % errors)
    asserts.true(env, errors[0].find("inputHash") != -1, "the error names inputHash: %s" % errors[0])

    errors = validate_lock('{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [{"id": "A", "version": "1.0.0"}]}}}')
    asserts.true(env, len(errors) == 2, "missing sha512 and urls are both reported: %s" % errors)

    errors = validate_lock('{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [{"id": "A", "version": "1.0.0", "sha512": "md5-AAAA", "urls": []}]}}}')
    asserts.true(env, len(errors) == 2, "a non-SRI sha512 and empty urls are both reported: %s" % errors)

    errors = validate_lock('{"version": 1, "inputHash": "1"}')
    asserts.true(env, len(errors) == 1, "one error for the missing frameworks map: %s" % errors)

    return unittest.end(env)

_validate_test = unittest.make(_validate_test_impl)

def lock_test_suite(name):
    unittest.suite(
        name,
        _parse_lock_test,
        _validate_test,
    )
