"The assertions the resolution tests are made of."

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

# buildifier: disable=bzl-visibility
load("//dotnet/private:common.bzl", "get_nuget_relative_path")

# buildifier: disable=bzl-visibility
load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "NuGetInfo")

# buildifier: disable=bzl-visibility
load("//dotnet/private/rules/nuget:dotnet_tool.bzl", "DotnetToolInfo")

# buildifier: disable=bzl-visibility
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _package_relative_paths(files):
    # A fixture repository holds one package per test, so a file's path starts
    # with the package it belongs to. A downloaded package is the repository
    # root and has none, which makes this a no-op there.
    paths = []

    for file in files:
        path = get_nuget_relative_path(file)
        package = file.owner.package if file.owner else ""

        if package and path.startswith(package + "/"):
            path = path[len(package) + 1:]

        paths.append(path)

    return paths

def _assert_equals(env, name, expected, actual):
    asserts.true(
        env,
        expected == actual,
        "\nExpected {}:\n{}\nActual {}:\n{}".format(name, expected, name, actual),
    )

def _assert_paths(env, name, expected, files):
    _assert_equals(env, name, sorted(expected), sorted(_package_relative_paths(files)))

def _resolution_test_impl(ctx):
    env = analysistest.begin(ctx)

    target = analysistest.target_under_test(env)
    compile_info = target[DotnetAssemblyCompileInfo]
    runtime_info = target[DotnetAssemblyRuntimeInfo]
    nuget_info = target[NuGetInfo]

    for (name, expected, files) in [
        ("libs", ctx.attr.expected_libs, runtime_info.libs),
        # A package ships one set of reference assemblies, so the internals
        # visible ones are the same files.
        ("refs", ctx.attr.expected_refs, compile_info.refs),
        ("irefs", ctx.attr.expected_refs, compile_info.irefs),
        ("analyzers", ctx.attr.expected_analyzers, compile_info.analyzers),
        ("analyzers_csharp", ctx.attr.expected_analyzers_csharp, compile_info.analyzers_csharp),
        ("analyzers_fsharp", ctx.attr.expected_analyzers_fsharp, compile_info.analyzers_fsharp),
        ("analyzers_vb", ctx.attr.expected_analyzers_vb, compile_info.analyzers_vb),
        ("native", ctx.attr.expected_native, runtime_info.native),
        ("resource_assemblies", ctx.attr.expected_resource_assemblies, runtime_info.resource_assemblies),
    ]:
        _assert_paths(env, name, expected, files)

    _assert_equals(env, "framework_list", ctx.attr.expected_framework_list, nuget_info.framework_list)
    _assert_equals(
        env,
        "targeting_pack_overrides",
        ctx.attr.expected_targeting_pack_overrides,
        nuget_info.targeting_pack_overrides,
    )

    return analysistest.end(env)

resolution_test = analysistest.make(
    _resolution_test_impl,
    attrs = {
        "expected_analyzers": attr.string_list(default = []),
        "expected_analyzers_csharp": attr.string_list(default = []),
        "expected_analyzers_fsharp": attr.string_list(default = []),
        "expected_analyzers_vb": attr.string_list(default = []),
        "expected_framework_list": attr.string_dict(default = {}),
        "expected_libs": attr.string_list(default = []),
        "expected_native": attr.string_list(default = []),
        "expected_refs": attr.string_list(default = []),
        "expected_resource_assemblies": attr.string_list(default = []),
        "expected_targeting_pack_overrides": attr.string_dict(default = {}),
    },
)

def _files_test_impl(ctx):
    env = analysistest.begin(ctx)
    files = analysistest.target_under_test(env)[DefaultInfo].files.to_list()

    _assert_paths(env, "files", ctx.attr.expected, files)

    return analysistest.end(env)

files_test = analysistest.make(
    _files_test_impl,
    attrs = {"expected": attr.string_list(default = [])},
    doc = "Asserts the files a group resolves to, without a package around it.",
)

def _tools_test_impl(ctx):
    env = analysistest.begin(ctx)
    files_by_tfm = analysistest.target_under_test(env)[DotnetToolInfo].files_by_tfm

    _assert_equals(env, "tool frameworks", sorted(ctx.attr.expected), sorted(files_by_tfm))

    for (tfm, target) in files_by_tfm.items():
        _assert_paths(
            env,
            "tools for {}".format(tfm),
            ctx.attr.expected.get(tfm, []),
            target[DefaultInfo].files.to_list(),
        )

    return analysistest.end(env)

tools_test = analysistest.make(
    _tools_test_impl,
    attrs = {"expected": attr.string_list_dict(default = {})},
    doc = "Asserts the files a package offers `dotnet tool`, keyed by framework.",
)

def _incompatible_test_impl(ctx):
    env = analysistest.begin(ctx)

    # A package that supports no framework the build can target resolves to a
    # target that fails analysis, which is observable only under
    # `--allow_analysis_failures`. `expect_failure` turns that on.
    asserts.expect_failure(env, "does not support the target framework being built")

    return analysistest.end(env)

incompatible_test = analysistest.make(
    _incompatible_test_impl,
    expect_failure = True,
)

def _resolved_package_impl(ctx):
    package = ctx.attr.package[0]

    return [
        package[DotnetAssemblyCompileInfo],
        package[DotnetAssemblyRuntimeInfo],
        package[NuGetInfo],
    ]

resolved_package = rule(
    _resolved_package_impl,
    doc = "Resolves a NuGet package at one target framework and runtime identifier.",
    attrs = {
        "package": attr.label(
            doc = "The NuGet package to resolve",
            mandatory = True,
            cfg = tfm_transition,
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo, NuGetInfo],
        ),
        "runtime_identifier": attr.string(
            doc = "The runtime identifier to resolve at",
        ),
        "target_framework": attr.string(
            doc = "The target framework to resolve at",
        ),
    },
    toolchains = [
        "//dotnet/toolchain:toolchain_type",
    ],
    executable = False,
)
