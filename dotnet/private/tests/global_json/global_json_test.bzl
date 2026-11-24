"""Tests for reading the SDK version out of a global.json."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/sdk:global_json.bzl", "global_json_sdk_version")

def _version(content):
    return global_json_sdk_version(content, "global.json")

def _global_json_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "9.0.300", _version('{"sdk": {"version": "9.0.300", "rollForward": "latestMajor"}}'))
    asserts.equals(env, "11.0.100-rc.2.25502.107", _version('{"sdk": {"version": "11.0.100-rc.2.25502.107"}}'))

    # The dotnet CLI accepts comments and trailing commas.
    asserts.equals(env, "10.0.100", _version("""// Pins the SDK.
{
  /* The SDK
     the repository builds with. */
  "sdk": {
    "version": "10.0.100", // Not rolled forward.
    "rollForward": "disable",
  },
  "msbuild-sdks": {
    "Example.Sdk": "1.0.0",
  },
}
"""))

    # Comment and comma lookalikes inside strings are kept.
    asserts.equals(env, "10.0.100", _version('{"sdk": {"paths": ["a//b", "/*c*/", ",]"], "version": "10.0.100"}}'))
    asserts.equals(env, "10.0.100", _version('{"x": "\\\\", "y": "\\"//", "sdk": {"version": "10.0.100"}}'))

    return unittest.end(env)

_global_json_test = unittest.make(_global_json_test_impl)

def global_json_test_suite(name):
    unittest.suite(name, _global_json_test)
