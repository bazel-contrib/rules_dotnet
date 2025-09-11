"Common functionality for nuget structure tests"

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

# buildifier: disable=bzl-visibility
load("//dotnet:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "NuGetInfo")

# buildifier: disable=bzl-visibility
load("//dotnet/private:common.bzl", "get_nuget_relative_path")

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

    analyzers_csharp_files = _get_nuget_relative_paths(compile_provider.analyzers_csharp)
    asserts.true(
        env,
        sorted(ctx.attr.expected_analyzers_csharp) == sorted(analyzers_csharp_files),
        "\nExpected analyzers_csharp:\n{}\nActual analyzers_csharp:\n{}".format(ctx.attr.expected_analyzers_csharp, analyzers_csharp_files),
    )

    analyzers_fsharp_files = _get_nuget_relative_paths(compile_provider.analyzers_fsharp)
    asserts.true(
        env,
        sorted(ctx.attr.expected_analyzers_fsharp) == sorted(analyzers_fsharp_files),
        "\nExpected analyzers_fsharp:\n{}\nActual analyzers_fsharp:\n{}".format(ctx.attr.expected_analyzers_fsharp, analyzers_fsharp_files),
    )

    analyzers_vb_files = _get_nuget_relative_paths(compile_provider.analyzers_vb)
    asserts.true(
        env,
        sorted(ctx.attr.expected_analyzers_vb) == sorted(analyzers_vb_files),
        "\nExpected analyzers_vb:\n{}\nActual analyzers_vb:\n{}".format(ctx.attr.expected_analyzers_vb, analyzers_vb_files),
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

    resource_assemblies = _get_nuget_relative_paths(runtime_provider.resource_assemblies)
    asserts.true(
        env,
        sorted(ctx.attr.expected_resource_assemblies) == sorted(resource_assemblies),
        "\nExpected resource_assemblies:\n{}\nActual resource_assemblies:\n{}".format(ctx.attr.expected_native, resource_assemblies),
    )

    return analysistest.end(env)

nuget_structure_test = analysistest.make(
    _nuget_structure_test_impl,
    attrs = {
        "expected_libs": attr.string_list(default = []),
        "expected_refs": attr.string_list(default = []),
        "expected_analyzers": attr.string_list(default = []),
        "expected_analyzers_csharp": attr.string_list(default = []),
        "expected_analyzers_fsharp": attr.string_list(default = []),
        "expected_analyzers_vb": attr.string_list(default = []),
        "expected_data": attr.string_list(default = []),
        "expected_native": attr.string_list(default = []),
        "expected_resource_assemblies": attr.string_list(default = []),
    },
)

def _nuget_targeting_pack_overrides_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    nuget_provider = target_under_test[NuGetInfo]

    targeting_pack_overrides = nuget_provider.targeting_pack_overrides
    asserts.true(
        env,
        sorted(ctx.attr.expected_targeting_pack_overrides) == sorted(targeting_pack_overrides),
        "\nExpected targeting_pack_overrides:\n{}\nActual targeting_pack_overrides:\n{}".format(ctx.attr.expected_targeting_pack_overrides, targeting_pack_overrides),
    )

    return analysistest.end(env)

nuget_targeting_pack_overrides_test = analysistest.make(
    _nuget_targeting_pack_overrides_test_impl,
    attrs = {
        "expected_targeting_pack_overrides": attr.string_dict(default = {}),
    },
)

def _nuget_framework_list_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)
    nuget_provider = target_under_test[NuGetInfo]

    framework_list = nuget_provider.framework_list
    asserts.true(
        env,
        sorted(ctx.attr.expected_framework_list) == sorted(framework_list),
        "\nExpected framework_list:\n{}\nActual framework_list:\n{}".format(ctx.attr.expected_framework_list, framework_list),
    )

    return analysistest.end(env)

nuget_framework_list_test = analysistest.make(
    _nuget_framework_list_test_impl,
    attrs = {
        "expected_framework_list": attr.string_dict(default = {}),
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
        "//dotnet:toolchain_type",
    ],
    executable = False,
)
