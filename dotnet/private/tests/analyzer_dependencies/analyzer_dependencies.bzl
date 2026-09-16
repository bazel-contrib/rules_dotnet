"Tests for ensuring analyzers' dependencies are correctly passed in."

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet:defs.bzl", "csharp_library")
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
        actual_analyzer_libs = compile_info.analyzers_csharp + compile_info.transitive_analyzers_csharp.to_list()
    elif ctx.attr.target_language == "fsharp":
        actual_analyzer_libs = compile_info.analyzers_fsharp + compile_info.transitive_analyzers_fsharp.to_list()
    elif ctx.attr.target_language == "vb":
        actual_analyzer_libs = compile_info.analyzers_vb + compile_info.transitive_analyzers_vb.to_list()
    else:
        fail("Unknown target language: {}".format(ctx.attr.target_language))

    compile_action = [action for action in analysistest.target_actions(env) if action.mnemonic == "CSharpCompile"][0]
    compile_inputs = compile_action.inputs.to_list()
    for expected_analyzer in ctx.attr.analyzers:
        expected_compile_info = expected_analyzer[DotnetAssemblyCompileInfo]
        expected_runtime_info = expected_analyzer[DotnetAssemblyRuntimeInfo]
        if not expected_runtime_info.libs:
            # This assembly is an analyzer itself.
            expected_libs = expected_compile_info.analyzers
        else:
            for dependency in expected_runtime_info.libs:
                asserts.false(env, any([library.basename == dependency.basename for library in actual_analyzer_libs]))
                for analyzer in actual_analyzer_libs:
                    staged = [file for file in compile_inputs if file.basename == dependency.basename and file.dirname == analyzer.dirname]
                    asserts.equals(env, 1, len(staged), "Analyzer dependency must be staged beside " + analyzer.path)
                    if staged:
                        asserts.false(env, "/analyzer:" + staged[0].path in compile_action.argv)
            continue

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
