"""Tests that an analyzer shipped by both a targeting pack and a NuGet package reaches the compiler once.

The `Microsoft.NETCore.App.Ref` targeting pack ships the `System.Text.Json.SourceGeneration`
source generator and so does the `System.Text.Json` NuGet package. The package (7.0.3) is newer
than the minimum the net7.0 pack records for it in `PackageOverride.txt` (7.0.0), so the package
supersedes the pack's reference assembly and the same generator is available from both sides.
See https://github.com/bazel-contrib/rules_dotnet/issues/467.

The libraries under test are not tagged `manual`: their sources use the generator, so building
them fails outright if it runs twice. The tests pin down which copy survives.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet:defs.bzl", "csharp_library")

_ANALYZER_ARG_PREFIX = "/analyzer:"

_DUPLICATED_ANALYZER = "System.Text.Json.SourceGeneration.dll"

# The repository names carry the package version, so match on the part of them
# that an SDK or lock file update does not move.
_TARGETING_PACK_REPO = "nuget.microsoft.netcore.app.ref"

_NUGET_PACKAGE_REPO = "nuget.system.text.json"

def _analyzer_paths(env):
    action_under_test = None
    for action in analysistest.target_actions(env):
        if action.mnemonic == "CSharpCompile":
            if action_under_test != None:
                fail("Multiple actions with mnemonic: CSharpCompile")
            action_under_test = action

    if action_under_test == None:
        fail("No action with mnemonic: CSharpCompile")

    return [
        arg[len(_ANALYZER_ARG_PREFIX):].strip("\"")
        for arg in action_under_test.argv
        if arg.startswith(_ANALYZER_ARG_PREFIX)
    ]

def _analyzer_args_test_impl(ctx):
    env = analysistest.begin(ctx)

    analyzer_paths = _analyzer_paths(env)

    seen = {}
    for analyzer_path in analyzer_paths:
        file_name = analyzer_path.rpartition("/")[-1]
        asserts.false(
            env,
            file_name in seen,
            "Analyzer passed to the compiler more than once: {}. Analyzers: {}".format(file_name, analyzer_paths),
        )
        seen[file_name] = None

    matches = [
        analyzer_path
        for analyzer_path in analyzer_paths
        if analyzer_path.endswith("/" + _DUPLICATED_ANALYZER)
    ]
    asserts.equals(
        env,
        1,
        len(matches),
        "Expected {} exactly once. Analyzers: {}".format(_DUPLICATED_ANALYZER, analyzer_paths),
    )

    if matches:
        asserts.true(
            env,
            ctx.attr.expected_analyzer_repo in matches[0],
            "Expected {} to come from {} but it came from {}".format(
                _DUPLICATED_ANALYZER,
                ctx.attr.expected_analyzer_repo,
                matches[0],
            ),
        )

    return analysistest.end(env)

analyzer_args_test = analysistest.make(
    _analyzer_args_test_impl,
    doc = "Asserts that no analyzer is passed to the C# compiler twice and that the analyzer under test comes from the expected repository.",
    attrs = {
        "expected_analyzer_repo": attr.string(
            doc = "Substring of the name of the repository the surviving analyzer is expected to be read from.",
            mandatory = True,
        ),
    },
)

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def csharp_duplicate_analyzers():
    csharp_library(
        name = "library_without_nuget_analyzer",
        srcs = ["duplicate_analyzers.cs"],
        target_frameworks = ["net7.0"],
    )

    analyzer_args_test(
        name = "targeting_pack_provides_the_analyzer_test",
        target_under_test = ":library_without_nuget_analyzer",
        expected_analyzer_repo = _TARGETING_PACK_REPO,
    )

    csharp_library(
        name = "library_with_nuget_analyzer",
        srcs = ["duplicate_analyzers.cs"],
        target_frameworks = ["net7.0"],
        deps = ["@paket.rules_dotnet_dev_nuget_packages//system.text.json"],
    )

    analyzer_args_test(
        name = "nuget_analyzer_supersedes_targeting_pack_analyzer_test",
        target_under_test = ":library_with_nuget_analyzer",
        expected_analyzer_repo = _NUGET_PACKAGE_REPO,
    )

    # With strict deps off the generator also arrives through the closure, which
    # loses to the targeting pack.
    csharp_library(
        name = "library_with_transitive_nuget_analyzer",
        srcs = ["transitive_duplicate_analyzers.cs"],
        target_frameworks = ["net7.0"],
        deps = [":library_with_nuget_analyzer"],
    )

    analyzer_args_test(
        name = "transitive_nuget_analyzer_does_not_duplicate_test",
        target_under_test = ":library_with_transitive_nuget_analyzer",
        expected_analyzer_repo = _TARGETING_PACK_REPO,
    )
