"""Checks that the BUILD file written for a NuGet package names rules_dotnet by canonical label."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//dotnet/private/rules/nuget:nuget_archive.bzl", "write_repository_for_testing")

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

def unit_test_suite(name):
    unittest.suite(name, canonical_labels_test)
