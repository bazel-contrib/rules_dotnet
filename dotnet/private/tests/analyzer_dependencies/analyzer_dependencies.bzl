"Tests for ensuring analyzers' dependencies are correctly passed in."

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet:defs.bzl", "csharp_library", "csharp_nunit_test")
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
)

def _force_netstandard20_transition_impl(_settings, _attr):
    return {"//dotnet:target_framework": "netstandard2.0"}

force_netstandard20_transition = transition(
    implementation = _force_netstandard20_transition_impl,
    inputs = [],
    outputs = ["//dotnet:target_framework"],
)

def _has_analyzer_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    compile_info = target_under_test[DotnetAssemblyCompileInfo]
    if ctx.attr.target_language == "any":
        actual_analyzer_libs = compile_info.analyzers + compile_info.transitive_analyzers.to_list()
    elif ctx.attr.target_language == "csharp":
        actual_analyzer_libs = compile_info.csharp_analyzers + compile_info.transitive_csharp_analyzers.to_list()
    elif ctx.attr.target_language == "fsharp":
        actual_analyzer_libs = compile_info.fsharp_analyzers + compile_info.transitive_fsharp_analyzers.to_list()
    elif ctx.attr.target_language == "vb":
        actual_analyzer_libs = compile_info.vb_analyzers + compile_info.transitive_vb_analyzers.to_list()
    else:
        fail("Unknown target language: {}".format(ctx.attr.target_language))

    for expected_analyzer in ctx.attr.analyzers:
        expected_compile_info = expected_analyzer[DotnetAssemblyCompileInfo]
        expected_runtime_info = expected_analyzer[DotnetAssemblyRuntimeInfo]
        if not expected_runtime_info.libs:
            # This assembly is an analyzer itself.
            expected_libs = expected_compile_info.analyzers
        else:
            # This assembly is not an analyzer, but its runtime libraries will be
            # used by analyzers.
            expected_libs = expected_runtime_info.libs

        for expected_lib in expected_libs:
            if expected_lib not in actual_analyzer_libs:
                fail(
                    "Expected analyzer library {} not found in: {}".format(
                        expected_lib,
                        actual_analyzer_libs,
                    ),
                )

    return analysistest.end(env)

has_analyzer_test = analysistest.make(
    _has_analyzer_test_impl,
    doc = "Tests whether the given target has an analyzer dependency.",
    attrs = {
        "analyzers": attr.label_list(
            doc = "The list of analyzer dependencies to check for.",
            mandatory = True,
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
            cfg = force_netstandard20_transition,
        ),
        "target_language": attr.string(
            doc = "The target language to check for analyzers. Can be one of 'any', 'csharp', 'fsharp', or 'vb'.",
            mandatory = True,
            values = ["any", "csharp", "fsharp", "vb"],
        ),
    },
)

def _runtime_graph_test_impl(ctx):
    env = analysistest.begin(ctx)
    runtime_info = analysistest.target_under_test(env)[DotnetAssemblyRuntimeInfo]

    runtime_deps = [dep.name for dep in runtime_info.deps.to_list()]
    depsjson_deps = runtime_info.direct_deps_depsjson_fragment.keys()

    for name in ctx.attr.present:
        asserts.true(env, name in runtime_deps, "{} is missing from the runtime deps: {}".format(name, runtime_deps))
        asserts.true(env, name in depsjson_deps, "{} is missing from the deps.json fragment: {}".format(name, depsjson_deps))

    for name in ctx.attr.absent:
        asserts.false(env, name in runtime_deps, "{} is in the runtime deps: {}".format(name, runtime_deps))
        asserts.false(env, name in depsjson_deps, "{} is in the deps.json fragment: {}".format(name, depsjson_deps))

    return analysistest.end(env)

runtime_graph_test = analysistest.make(
    _runtime_graph_test_impl,
    doc = "Tests which dependencies a target carries into its runtime graph, and so into deps.json and a package.",
    attrs = {
        "present": attr.string_list(doc = "Assembly names the runtime graph must hold."),
        "absent": attr.string_list(doc = "Assembly names the runtime graph must not hold."),
    },
)

def _analyzer_assemblies_test_impl(ctx):
    env = analysistest.begin(ctx)
    compile_info = analysistest.target_under_test(env)[DotnetAssemblyCompileInfo]

    handed = compile_info.analyzers + compile_info.analyzers_csharp
    names = [dll.basename for dll in handed]

    for name in ctx.attr.present:
        asserts.true(env, name in names, "{} is not handed to the compiler: {}".format(name, names))

    # A package's files are source files, which tells them apart from the ones
    # built here.
    from_packages = sorted([dll.basename for dll in handed if dll.is_source])
    asserts.equals(env, sorted(ctx.attr.packages), from_packages, "the NuGet assemblies handed to the compiler beside the analyzer")

    return analysistest.end(env)

analyzer_assemblies_test = analysistest.make(
    _analyzer_assemblies_test_impl,
    doc = "Tests which assemblies an analyzer hands the compiler beside itself.",
    attrs = {
        "present": attr.string_list(doc = "File names that must be handed to the compiler."),
        "packages": attr.string_list(doc = "File names of all the NuGet assemblies handed to the compiler: those of its `analyzer_runtime_deps`."),
    },
)

def _analyzer_runtime_deps_need_an_analyzer_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "`analyzer_runtime_deps` is only for an analyzer or source generator")
    return analysistest.end(env)

analyzer_runtime_deps_need_an_analyzer_test = analysistest.make(
    _analyzer_runtime_deps_need_an_analyzer_test_impl,
    expect_failure = True,
    doc = "Tests that a library that is no analyzer cannot list `analyzer_runtime_deps`.",
)

_ROSLYN = [
    "@paket.rules_dotnet_dev_nuget_packages//microsoft.codeanalysis.common",
    "@paket.rules_dotnet_dev_nuget_packages//microsoft.codeanalysis.csharp",
    "@paket.rules_dotnet_dev_nuget_packages//system.collections.immutable",
    "@paket.rules_dotnet_dev_nuget_packages//system.memory",
]

# A NuGet package the compiler does not bring, unlike Roslyn and its own
# dependencies.
_HUMANIZER = "@paket.rules_dotnet_dev_nuget_packages//humanizer.core"

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def test_analyzer_dependencies():
    csharp_library(
        name = "core_lib",
        srcs = ["Core.cs"],
        target_frameworks = ["net9.0", "netstandard2.0"],
        langversion = "latest",
    )

    csharp_library(
        name = "analyzer_lib",
        is_analyzer = True,
        srcs = ["Analyzer.cs"],
        deps = [":core_lib"],
        target_frameworks = ["netstandard2.0"],
        langversion = "latest",
    )

    csharp_library(
        name = "user_lib",
        srcs = ["User.cs"],
        deps = [":core_lib", ":analyzer_lib"],
        target_frameworks = ["net9.0"],
    )

    has_analyzer_test(
        name = "analyzer_dependency_was_passed_in",
        target_under_test = ":user_lib",
        analyzers = [":core_lib", ":analyzer_lib"],
        target_language = "any",
    )

    # The analyzer runs in the compiler and nothing loads it at run time, so it
    # stays out of the runtime graph, while the library it shares with
    # `user_lib` stays in.
    runtime_graph_test(
        name = "analyzer_stays_out_of_the_runtime_graph",
        target_under_test = ":user_lib",
        present = ["core_lib"],
        absent = ["analyzer_lib"],
    )

    csharp_library(
        name = "wrapper_lib",
        srcs = ["Wrapper.cs"],
        deps = [":core_lib"],
        target_frameworks = ["netstandard2.0"],
        langversion = "latest",
    )

    csharp_library(
        name = "packaged_deps_analyzer",
        is_analyzer = True,
        srcs = ["Analyzer.cs"],
        deps = [
            ":wrapper_lib",
            "@paket.rules_dotnet_dev_nuget_packages//microsoft.codeanalysis.csharp",
        ],
        target_frameworks = ["netstandard2.0"],
        langversion = "latest",
    )

    # Every library built here goes beside the analyzer, `core_lib` through
    # `wrapper_lib` included. Roslyn comes with the compiler.
    analyzer_assemblies_test(
        name = "analyzer_hands_over_no_package_assemblies",
        target_under_test = ":packaged_deps_analyzer",
        present = ["packaged_deps_analyzer.dll", "wrapper_lib.dll", "core_lib.dll"],
    )

    # A source generator calling into a NuGet package the compiler does not
    # bring, which it lists to travel with it.
    csharp_library(
        name = "humanizing_generator",
        srcs = ["HumanizingGenerator.cs"],
        analyzer_runtime_deps = [_HUMANIZER],
        is_analyzer = True,
        is_language_specific_analyzer = True,
        target_frameworks = ["netstandard2.0"],
        version = "1.0.0",
        visibility = ["//dotnet/private/tests/nuget_pack:__subpackages__"],
        deps = _ROSLYN,
    )

    # Humanizer goes beside the generator; Roslyn and its dependencies do not.
    analyzer_assemblies_test(
        name = "analyzer_hands_over_its_runtime_deps",
        target_under_test = ":humanizing_generator",
        present = ["humanizing_generator.dll"],
        packages = ["Humanizer.dll"],
    )

    # The generator only generates if it finds Humanizer in the compiler.
    csharp_nunit_test(
        name = "analyzer_runtime_deps_reach_the_compiler",
        srcs = ["Humanized.cs"],
        target_frameworks = ["net9.0"],
        deps = [":humanizing_generator"],
    )

    csharp_library(
        name = "analyzer_runtime_deps_without_an_analyzer",
        srcs = ["Core.cs"],
        analyzer_runtime_deps = [_HUMANIZER],
        tags = ["manual"],
        target_frameworks = ["net9.0"],
    )

    analyzer_runtime_deps_need_an_analyzer_test(
        name = "analyzer_runtime_deps_need_an_analyzer",
        target_under_test = ":analyzer_runtime_deps_without_an_analyzer",
    )
