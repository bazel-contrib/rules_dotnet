"""Unit tests of the pure functions `nuget_pack` and the `version` attribute build on.

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
        spellings_test,
        round_trip_test,
        framework_reference_test,
        package_id_test,
        without_ref_assembly_test,
    )
