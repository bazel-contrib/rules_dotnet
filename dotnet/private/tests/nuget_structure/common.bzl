"Common functionality for nuget structure tests"

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

# buildifier: disable=bzl-visibility
load("//dotnet/private:common.bzl", "get_nuget_relative_path")

# buildifier: disable=bzl-visibility
load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "NuGetInfo")

# buildifier: disable=bzl-visibility
load("//dotnet/private/transitions:tfm_transition.bzl", "tfm_transition")

def _get_nuget_relative_paths(files):
    return [get_nuget_relative_path(file) for file in files]

def _nuget_structure_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    compile_provider = target_under_test[DotnetAssemblyCompileInfo]
    runtime_provider = target_under_test[DotnetAssemblyRuntimeInfo]

    libs_files = _get_nuget_relative_paths(runtime_provider.libs)
    asserts.true(
        env,
        sorted(ctx.attr.expected_libs) == sorted(libs_files),
        "\nExpected libs:\n{}\nActual libs:\n{}".format(ctx.attr.expected_libs, libs_files),
    )

    prefs_files = _get_nuget_relative_paths(compile_provider.refs)
    asserts.true(
        env,
        sorted(ctx.attr.expected_refs) == sorted(prefs_files),
        "\nExpected prefs:\n{}\nActual prefs:\n{}".format(ctx.attr.expected_refs, prefs_files),
    )

    irefs_files = _get_nuget_relative_paths(compile_provider.irefs)
    asserts.true(
        env,
        sorted(ctx.attr.expected_refs) == sorted(irefs_files),
        "\nExpected irefs:\n{}\nActual irefs:\n{}".format(ctx.attr.expected_refs, irefs_files),
    )

    analyzers_files = _get_nuget_relative_paths(compile_provider.analyzers)
    asserts.true(
        env,
        sorted(ctx.attr.expected_analyzers) == sorted(analyzers_files),
        "\nExpected analyzers:\n{}\nActual analyzers:\n{}".format(ctx.attr.expected_analyzers, analyzers_files),
    )

    data_files = _get_nuget_relative_paths(runtime_provider.data)
    asserts.true(
        env,
        sorted(ctx.attr.expected_data) == sorted(data_files),
        "\nExpected data:\n{}\nActual data:\n{}".format(ctx.attr.expected_data, data_files),
    )

    native_files = _get_nuget_relative_paths(runtime_provider.native)
    asserts.true(
        env,
        sorted(ctx.attr.expected_native) == sorted(native_files),
        "\nExpected native:\n{}\nActual native:\n{}".format(ctx.attr.expected_native, native_files),
    )

    return analysistest.end(env)

nuget_structure_test = analysistest.make(
    _nuget_structure_test_impl,
    attrs = {
        "expected_libs": attr.string_list(default = []),
        "expected_refs": attr.string_list(default = []),
        "expected_analyzers": attr.string_list(default = []),
        "expected_data": attr.string_list(default = []),
        "expected_native": attr.string_list(default = []),
    },
)

def _nuget_test_wrapper(ctx):
    return [ctx.attr.package[0][DotnetAssemblyCompileInfo], ctx.attr.package[0][DotnetAssemblyRuntimeInfo], ctx.attr.package[0][NuGetInfo]]

nuget_test_wrapper = rule(
    _nuget_test_wrapper,
    doc = "Used for testing nuget structure parsing",
    attrs = {
        "package": attr.label(
            doc = "The NuGet package to test",
            mandatory = True,
            cfg = tfm_transition,
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo, NuGetInfo],
        ),
        "target_framework": attr.string(
            doc = "The target framework to test",
        ),
        "runtime_identifier": attr.string(
            doc = "The runtime identifier to test",
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    toolchains = [
        "@rules_dotnet//dotnet:toolchain_type",
    ],
    executable = False,
)
