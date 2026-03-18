"NuGet structure tests"

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

# buildifier: disable=bzl-visibility
load("//dotnet/private:common.bzl", "collect_compile_info")

# buildifier: disable=bzl-visibility
load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetTargetingPackInfo", "NuGetInfo")

load("//dotnet/private/tests/nuget_structure:common.bzl", "nuget_structure_test", "nuget_test_wrapper")

def _mock_dep_impl(ctx):
    return [DotnetAssemblyCompileInfo(
        name = "package.with.override.only",
        version = "8.0.0",
        project_sdk = "",
        refs = [],
        irefs = [],
        analyzers = [],
        analyzers_csharp = [],
        analyzers_fsharp = [],
        analyzers_vb = [],
        internals_visible_to = [],
        compile_data = [],
        exports = [],
        transitive_refs = depset([]),
        transitive_compile_data = depset([]),
        transitive_analyzers = depset([]),
        transitive_analyzers_csharp = depset([]),
        transitive_analyzers_fsharp = depset([]),
        transitive_analyzers_vb = depset([]),
    )]

mock_dep = rule(
    implementation = _mock_dep_impl,
)

def _mock_targeting_pack_impl(ctx):
    # Keep framework_list empty while providing an override entry to cover
    # the regression where framework_list.pop(name) raised a KeyError.
    nupkg = ctx.actions.declare_file(ctx.label.name + ".nupkg")
    ctx.actions.write(output = nupkg, content = "")

    return [DotnetTargetingPackInfo(
        assembly_runtime_infos = [],
        assembly_compile_infos = [DotnetAssemblyCompileInfo(
            name = "mock_targeting_pack",
            version = "1.0.0",
            project_sdk = "",
            refs = [],
            irefs = [],
            analyzers = [],
            analyzers_csharp = [],
            analyzers_fsharp = [],
            analyzers_vb = [],
            internals_visible_to = [],
            compile_data = [],
            exports = [],
            transitive_refs = depset([]),
            transitive_compile_data = depset([]),
            transitive_analyzers = depset([]),
            transitive_analyzers_csharp = depset([]),
            transitive_analyzers_fsharp = depset([]),
            transitive_analyzers_vb = depset([]),
        )],
        nuget_infos = [NuGetInfo(
            targeting_pack_overrides = {
                "package.with.override.only": "8.0.0",
            },
            framework_list = {},
            sha512 = "",
            nupkg = nupkg,
        )],
    )]

mock_targeting_pack = rule(
    implementation = _mock_targeting_pack_impl,
)

def _collect_compile_info_regression_target_impl(ctx):
    collect_compile_info(
        name = ctx.label.name,
        deps = ctx.attr.deps,
        targeting_pack = ctx.attr.targeting_pack,
        exports = [],
        strict_deps = True,
    )

    return [DefaultInfo()]

collect_compile_info_regression_target = rule(
    implementation = _collect_compile_info_regression_target_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [DotnetAssemblyCompileInfo],
            mandatory = True,
        ),
        "targeting_pack": attr.label(
            providers = [DotnetTargetingPackInfo],
            mandatory = True,
        ),
    },
)

def _collect_compile_info_regression_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.true(env, True, "collect_compile_info analyzed successfully")
    return analysistest.end(env)

collect_compile_info_regression_test = analysistest.make(
    _collect_compile_info_regression_test_impl,
)

# buildifier: disable=unnamed-macro
def resolution_structure():
    "Tests for the resolution of files depending on target framework"
    nuget_test_wrapper(
        name = "System.Memory.netstandard2.0",
        target_framework = "netstandard2.0",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.memory",
    )

    nuget_structure_test(
        name = "should_resolve_system.memory_netstandard2.0_linux-x64_correctly",
        target_under_test = ":System.Memory.netstandard2.0",
        expected_libs = ["lib/netstandard2.0/System.Memory.dll"],
        expected_refs = ["lib/netstandard2.0/System.Memory.dll"],
    )

    mock_dep(
        name = "dep_in_package_overrides_only",
    )

    mock_targeting_pack(
        name = "targeting_pack_with_override_only_entry",
    )

    collect_compile_info_regression_target(
        name = "collect_compile_info_package_override_framework_list_mismatch",
        deps = [":dep_in_package_overrides_only"],
        targeting_pack = ":targeting_pack_with_override_only_entry",
    )

    collect_compile_info_regression_test(
        name = "collect_compile_info_should_not_fail_when_override_missing_from_framework_list",
        target_under_test = ":collect_compile_info_package_override_framework_list_mismatch",
    )
