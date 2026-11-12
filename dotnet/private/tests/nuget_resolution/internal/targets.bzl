"""Turns the test declarations into targets.

What is being tested lives in `//dotnet/private/tests/nuget_resolution:tests.bzl`,
one declaration per test. This file only builds the targets.
"""

load(
    "@nuget_fixtures//a_targeting_pack_declares_its_metadata:package_info.bzl",
    "FRAMEWORK_LIST",
    "TARGETING_PACK_OVERRIDES",
)

# buildifier: disable=bzl-visibility
load("//dotnet/private/rules/nuget:package.bzl", "nuget_package")

# buildifier: disable=bzl-visibility
load("//dotnet/private/tests/nuget_resolution:tests.bzl", "TESTS")
load(
    "//dotnet/private/tests/nuget_resolution/internal:assertions.bzl",
    "files_test",
    "incompatible_test",
    "portable_test",
    "resolution_test",
    "resolved_package",
    "tools_test",
)

# The metadata a targeting pack declares is read back out of its own archive,
# which needs a load with a literal label. Only this test has one, so only this
# test can assert on it.
_METADATA_TEST = "a_targeting_pack_declares_its_metadata"

def _check(tests):
    seen = {}

    for test in tests:
        if test.name in seen:
            fail("{}: two tests cannot share a name".format(test.name))
        seen[test.name] = True

        if test.name == _METADATA_TEST:
            continue

        if test.expected_framework_list or test.expected_targeting_pack_overrides:
            fail(
                "{}: only `{}` can assert on package metadata, because reading ".format(
                    test.name,
                    _METADATA_TEST,
                ) + "it back needs a load with a literal label",
            )

# buildifier: disable=unnamed-macro
def nuget_resolution_tests():
    "A package and a test per declaration"
    _check(TESTS)

    for test in TESTS:
        archive = "@nuget_fixtures//{}".format(test.name)

        if test.expected_content_files:
            # Not resolved per framework, so there is no package to go through.
            files_test(
                name = test.name,
                expected = test.expected_content_files,
                target_under_test = "{}:content_files".format(archive),
            )
            continue

        if test.expected_tools:
            # Offered to `dotnet tool` rather than resolved into a package.
            tools_test(
                name = test.name,
                expected = test.expected_tools,
                target_under_test = "{}:tools".format(archive),
            )
            continue

        if test.default_configuration:
            # No package and no wrapper: the group is asserted on directly, in
            # the configuration anything outside the .NET rules sees.
            files_test(
                name = test.name,
                expected = test.expected_libs,
                target_under_test = "{}:libs".format(archive),
            )
            continue

        nuget_package(
            version = "fixture_{}".format(test.name),
            library_name = "fixture.{}".format(test.name),
            archive = archive,
            packages = {},
            # The metadata reaches the package the way a generated hub
            # repository passes it: read back out of the archive, not handed in
            # from the expectation.
            framework_list = FRAMEWORK_LIST if test.expected_framework_list else {},
            targeting_pack_overrides = TARGETING_PACK_OVERRIDES if test.expected_targeting_pack_overrides else {},
            tags = ["manual"],
        )

        resolved_package(
            name = "{}_subject".format(test.name),
            package = ":fixture_{}".format(test.name),
            runtime_identifier = test.runtime_identifier,
            tags = ["manual"],
            target_framework = test.target_framework,
        )

        if test.expect_incompatible:
            incompatible_test(
                name = test.name,
                target_under_test = ":{}_subject".format(test.name),
            )
        elif test.portable:
            portable_test(
                name = test.name,
                expected_libs = test.expected_libs,
                expected_runtime_targets = test.expected_runtime_targets,
                target_under_test = ":{}_subject".format(test.name),
            )
        else:
            resolution_test(
                name = test.name,
                expected_analyzers = test.expected_analyzers,
                expected_analyzers_csharp = test.expected_analyzers_csharp,
                expected_analyzers_fsharp = test.expected_analyzers_fsharp,
                expected_analyzers_vb = test.expected_analyzers_vb,
                expected_framework_list = test.expected_framework_list,
                expected_libs = test.expected_libs,
                expected_native = test.expected_native,
                expected_refs = test.expected_refs,
                expected_resource_assemblies = test.expected_resource_assemblies,
                expected_targeting_pack_overrides = test.expected_targeting_pack_overrides,
                target_under_test = ":{}_subject".format(test.name),
            )
