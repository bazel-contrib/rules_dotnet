"""Checks that the BUILD files written for NuGet packages name rules_dotnet by canonical label."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//dotnet/private/rules/nuget:nuget_archive.bzl", "write_repository_for_testing")

# buildifier: disable=bzl-visibility
load("//dotnet/private/rules/nuget:nuget_repo.bzl", "write_hub_for_testing")

# buildifier: disable=bzl-visibility
load("//dotnet/private/rules/nuget:package.bzl", "deps_by_tfm")

_NUSPEC = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>A</id>
    <version>1.0.0</version>
    <description>fixture</description>
    <authors>fixture</authors>
  </metadata>
</package>
"""

_FILES = [
    "A.1.0.0.nupkg",
    "A.nuspec",
    "lib/net6.0/A.dll",
    "lib/netstandard2.0/A.dll",
    "lib/netcoreapp3.1/A.dll",
    "lib/net48/A.dll",
    "runtimes/linux-x64/lib/net6.0/A.dll",
    "runtimes/win-x64/native/a.dll",
]

def _build_file():
    written = {}
    ctx = struct(
        file = lambda path, content: written.update({path: content}),
        read = lambda path: _NUSPEC,
    )
    write_repository_for_testing(ctx, "A", "A.1.0.0.nupkg", _FILES)
    return written["BUILD.bazel"]

def _canonical_labels_test_impl(ctx):
    env = unittest.begin(ctx)
    build = _build_file()

    asserts.false(env, "@rules_dotnet//" in build, "BUILD file names @rules_dotnet by apparent name")
    asserts.true(env, 'load("%s"' % Label("//dotnet/private/rules/nuget:nuget_archive.bzl") in build, "missing the canonical load")
    return unittest.end(env)

canonical_labels_test = unittest.make(_canonical_labels_test_impl)

def _hub_build_files():
    written = {}
    ctx = struct(
        attr = struct(
            extra_build_files = {},
            packages = [json.encode({"id": "A", "name": "A", "sha512": "", "version": "1.0.0"})],
        ),
        file = lambda path, content: written.update({path: content}),
    )
    write_hub_for_testing(ctx)
    return written

def _hub_canonical_labels_test_impl(ctx):
    env = unittest.begin(ctx)
    written = _hub_build_files()
    package_bzl = 'load("%s"' % Label("//dotnet/private/rules/nuget:package.bzl")

    for (path, content) in written.items():
        asserts.false(env, "@rules_dotnet//" in content, "{} names @rules_dotnet by apparent name".format(path))

    asserts.true(env, package_bzl in written["a/1.0.0/BUILD.bazel"], "missing the canonical load of the package")
    asserts.true(env, package_bzl in written["a/tools/BUILD.bazel"], "missing the canonical load of the tools")

    for condition in deps_by_tfm({"netstandard2.0": ["B"]}, {"b": "b"}):
        asserts.false(env, condition.startswith("@rules_dotnet//"), "{} is an apparent label".format(condition))

    return unittest.end(env)

hub_canonical_labels_test = unittest.make(_hub_canonical_labels_test_impl)

def unit_test_suite(name):
    unittest.suite(name, canonical_labels_test, hub_canonical_labels_test)
