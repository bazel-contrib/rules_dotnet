"NuGet version tests"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private:nuget_version.bzl", "nuget_version")

# version -> (assembly_version, normalize)
_VALID = {
    "1.2": ("1.2.0.0", "1.2.0"),
    "1.2.3": ("1.2.3.0", "1.2.3"),
    "1.2.3.4": ("1.2.3.4", "1.2.3.4"),
    "1.2.3.0": ("1.2.3.0", "1.2.3"),
    "01.02.003": ("1.2.3.0", "1.2.3"),
    "01.2-rc.1+meta": ("1.2.0.0", "1.2.0-rc.1"),
    "1.2.3-beta.1": ("1.2.3.0", "1.2.3-beta.1"),
    "1.2.3-beta.1+sha.abcdef": ("1.2.3.0", "1.2.3-beta.1"),
    "1.2.3+build-7": ("1.2.3.0", "1.2.3"),
    "1.0.0-alpha-2": ("1.0.0.0", "1.0.0-alpha-2"),
    "65535.65535.65535.65535": ("65535.65535.65535.65535", "65535.65535.65535.65535"),
    "0.0": ("0.0.0.0", "0.0.0"),
}

_INVALID = [
    "",
    "1",
    "1.2.3.4.5",
    "1.a.3",
    "1..2",
    ".1.2",
    "1.2.",
    "v1.2.3",
    "1.2.3-",
    "1.2.3-beta..1",
    "1.2.3-beta.",
    "1.2.3-be_ta",
    "1.2.3+",
    "1.2.3+a+b",
    "1.2.3 ",
    " 1.2.3",
    "1.2.3-beta 1",
    "70000.0",
    "1.65536",
    "-1.2.3",
]

def _valid_versions_test_impl(ctx):
    env = unittest.begin(ctx)
    for (version, (assembly_version, normalized)) in _VALID.items():
        asserts.equals(env, None, nuget_version.error(version), version)
        asserts.equals(env, assembly_version, nuget_version.assembly_version(version), version)
        asserts.equals(env, normalized, nuget_version.normalize(version), version)
    return unittest.end(env)

def _invalid_versions_test_impl(ctx):
    env = unittest.begin(ctx)
    for version in _INVALID:
        error = nuget_version.error(version)
        asserts.true(env, error != None and error != "", version)
    return unittest.end(env)

valid_versions_test = unittest.make(_valid_versions_test_impl)
invalid_versions_test = unittest.make(_invalid_versions_test_impl)

def nuget_version_test_suite(name):
    unittest.suite(
        name,
        valid_versions_test,
        invalid_versions_test,
    )
