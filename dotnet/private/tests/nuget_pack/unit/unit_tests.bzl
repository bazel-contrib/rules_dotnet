"""Unit tests of the pure functions `nuget_pack`, the `version` attribute and dependency resolution build on.

Tables of inputs and what each gives. What a whole package comes out as is
`nuget_pack_test_suite`'s business, over real targets; the one case here that
is about layout is one no toolchain in this repository produces.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private:common.bzl", "FRAMEWORK_COMPATIBILITY", "nuget_framework_to_tfm", "tfm_to_nuget_framework")
load("//dotnet/private:nuget_version.bzl", "nuget_version")
load(
    "//dotnet/private/rules/nuget_pack:layout.bzl",
    "framework_reference_group",
    "is_valid_package_id",
    "library_layout",
)

# --- Versions ----------------------------------------------------------------

# version -> (assembly_version, normalize)
_VALID_VERSIONS = {
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

_INVALID_VERSIONS = [
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

# (older, newer) pairs: NuGet orders `newer` after `older`.
_ORDERINGS = [
    ("1.2.3", "1.2.4"),
    ("9.0.0", "10.0.0"),
    # A missing component is zero.
    ("1.2", "1.2.0.1"),
    ("10.0.14", "10.0.14.1"),
    ("1.2.3.4", "1.2.4"),
    ("8.0.0.0", "8.0.1"),
    ("01.02.003", "1.2.4"),
    # A package version can go past what an AssemblyVersion stores.
    ("1.0.65535", "1.0.70000"),
    # A release comes after its pre-releases.
    ("11.0.0-rc.2", "11.0"),
    ("11.0.0-rc.2.25502.107", "11.0.0"),
    ("10.0.0", "11.0.0-preview.1"),
    # SemVer's own example of precedence.
    ("1.0.0-alpha", "1.0.0-alpha.1"),
    ("1.0.0-alpha.1", "1.0.0-alpha.beta"),
    ("1.0.0-alpha.beta", "1.0.0-beta"),
    ("1.0.0-beta", "1.0.0-beta.2"),
    ("1.0.0-beta.2", "1.0.0-beta.11"),
    ("1.0.0-beta.11", "1.0.0-rc.1"),
    ("1.0.0-rc.1", "1.0.0"),
    # Labels are compared without regard to case, unlike in ASCII order.
    ("1.0.0-alpha", "1.0.0-Beta"),
    ("1.0.0-RC.1", "1.0.0-rc.2"),
]

# Pairs of which neither is newer: one version spelled two ways, or a side that
# is not a version at all, such as the empty one of an `import_dll` that sets
# none.
_UNORDERED = [
    ("10.0.14", "10.0.14.0"),
    ("11.0", "11.0.0.0"),
    ("01.2", "1.2.0"),
    ("1.0.0-RC.1", "1.0.0-rc.1"),
    ("1.2.3+abc", "1.2.3+def"),
    ("1.2.3-beta+abc", "1.2.3-beta"),
    ("", "10.0.0"),
    ("", ""),
    ("1", "0.1"),
    ("1.2.3.4.5", "1.0"),
    ("v2.0", "1.0"),
    ("2.0-", "1.0"),
]

def _valid_versions_test_impl(ctx):
    env = unittest.begin(ctx)
    for (version, (assembly_version, normalized)) in _VALID_VERSIONS.items():
        asserts.equals(env, None, nuget_version.error(version), version)
        asserts.equals(env, assembly_version, nuget_version.assembly_version(version), version)
        asserts.equals(env, normalized, nuget_version.normalize(version), version)
    return unittest.end(env)

def _invalid_versions_test_impl(ctx):
    env = unittest.begin(ctx)
    for version in _INVALID_VERSIONS:
        error = nuget_version.error(version)
        asserts.true(env, error != None and error != "", version)
    return unittest.end(env)

def _orderings_test_impl(ctx):
    env = unittest.begin(ctx)
    for (older, newer) in _ORDERINGS:
        asserts.true(env, nuget_version.is_newer(newer, older), "{} is newer than {}".format(newer, older))
        asserts.false(env, nuget_version.is_newer(older, newer), "{} is not newer than {}".format(older, newer))
    for (a, b) in _UNORDERED:
        asserts.false(env, nuget_version.is_newer(a, b), "{} is not newer than {}".format(repr(a), repr(b)))
        asserts.false(env, nuget_version.is_newer(b, a), "{} is not newer than {}".format(repr(b), repr(a)))
    return unittest.end(env)

# --- Frameworks --------------------------------------------------------------

# How a nuspec spells a target framework moniker.
_SPELLINGS = {
    "net11": ".NETFramework1.1",
    "net20": ".NETFramework2.0",
    "net403": ".NETFramework4.0.3",
    "net472": ".NETFramework4.7.2",
    "net48": ".NETFramework4.8",
    "net481": ".NETFramework4.8.1",
    "net8.0": "net8.0",
    "netcoreapp3.1": ".NETCoreApp3.1",
    "netstandard": "netstandard",
    "netstandard2.0": ".NETStandard2.0",
    "netstandard2.1": ".NETStandard2.1",
}

def _spellings_test_impl(ctx):
    env = unittest.begin(ctx)
    for (tfm, spelling) in _SPELLINGS.items():
        asserts.equals(env, spelling, tfm_to_nuget_framework(tfm), tfm)
    return unittest.end(env)

def _round_trip_test_impl(ctx):
    env = unittest.begin(ctx)
    for tfm in FRAMEWORK_COMPATIBILITY.keys():
        asserts.equals(env, tfm, nuget_framework_to_tfm(tfm_to_nuget_framework(tfm)), tfm)
    return unittest.end(env)

def _framework_reference_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(env, None, framework_reference_group("net9.0", "default"))
    asserts.equals(env, None, framework_reference_group("netstandard2.0", "web"))
    asserts.equals(env, None, framework_reference_group("netcoreapp2.1", "web"))
    asserts.equals(env, ["Microsoft.AspNetCore.App"], framework_reference_group("netcoreapp3.1", "web").frameworkReferences)
    asserts.equals(env, "net9.0", framework_reference_group("net9.0", "razor").targetFramework)
    return unittest.end(env)

# --- Package ids -------------------------------------------------------------

def _package_id_test_impl(ctx):
    env = unittest.begin(ctx)
    for valid in ["A", "Foo.Bar", "foo-bar_baz", "a1.b2", "_x", "x_", "a__b"]:
        asserts.true(env, is_valid_package_id(valid), valid)
    for invalid in ["", ".Foo", "Foo.", "Foo..Bar", "Foo-.Bar", "Foo Bar", "Foo/Bar", "Foo+Bar", "x" * 101]:
        asserts.false(env, is_valid_package_id(invalid), invalid)
    return unittest.end(env)

# --- An assembly with no reference assembly of its own -----------------------

def _file(path):
    """Stands in for a File: only the fields the layout reads."""
    return struct(path = path, basename = path.split("/")[-1], dirname = "/".join(path.split("/")[:-1]))

_DLL = _file("out/A/A.dll")

# F# on an SDK that cannot write a deterministic reference assembly compiles
# against the implementation, so `refs` is the implementation itself.
_WITHOUT_REF = struct(refs = [_DLL])
_A = struct(
    name = "A",
    libs = [_DLL],
    pdbs = [],
    xml_docs = [_file("out/A/A.xml")],
    native = [],
    resource_assemblies = [],
)

def _without_ref_assembly_test_impl(ctx):
    env = unittest.begin(ctx)

    # `ref/` would only repeat `lib/`, so it is left out.
    layout = library_layout("net9.0", None, _WITHOUT_REF, _A, [], "none", reference_assemblies = True, emit_portable = True)
    asserts.equals(env, ["lib/net9.0/A.dll", "lib/net9.0/A.xml"], sorted([path for (path, _) in layout.files]))

    # A RID-specific package has nothing under `lib/` to compile against, so it gets one anyway.
    layout = library_layout("net9.0", "linux-x64", _WITHOUT_REF, _A, [], "none", reference_assemblies = True, emit_portable = True)
    asserts.equals(env, ["ref/net9.0/A.dll", "ref/net9.0/A.xml", "runtimes/linux-x64/lib/net9.0/A.dll"], sorted([path for (path, _) in layout.files]))
    return unittest.end(env)

valid_versions_test = unittest.make(_valid_versions_test_impl)
invalid_versions_test = unittest.make(_invalid_versions_test_impl)
orderings_test = unittest.make(_orderings_test_impl)
spellings_test = unittest.make(_spellings_test_impl)
round_trip_test = unittest.make(_round_trip_test_impl)
framework_reference_test = unittest.make(_framework_reference_test_impl)
package_id_test = unittest.make(_package_id_test_impl)
without_ref_assembly_test = unittest.make(_without_ref_assembly_test_impl)

def unit_test_suite(name):
    unittest.suite(
        name,
        valid_versions_test,
        invalid_versions_test,
        orderings_test,
        spellings_test,
        round_trip_test,
        framework_reference_test,
        package_id_test,
        without_ref_assembly_test,
    )
