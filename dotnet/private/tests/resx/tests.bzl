"""Analysis tests for `.resx` resources: how they are named, where satellites go, and what fails."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//dotnet/private:common.bzl", "package_relative_path")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

def _satellites_test_impl(ctx):
    env = analysistest.begin(ctx)

    satellites = {}
    for action in analysistest.target_actions(env):
        if action.mnemonic == "ResxSatellite":
            output = action.outputs.to_list()[0]
            satellites[output.dirname.split("/")[-1] + "/" + output.basename] = action

    asserts.equals(env, sorted(ctx.attr.expected.keys()), sorted(satellites.keys()))

    for satellite, names in ctx.attr.expected.items():
        action = satellites.get(satellite)
        if action == None:
            continue
        argv = " ".join(action.argv)
        for name in names:
            asserts.true(env, name in argv, "{} does not embed {}: {}".format(satellite, name, argv))

    return analysistest.end(env)

_satellites_test = analysistest.make(
    _satellites_test_impl,
    doc = "Asserts the satellite assemblies a target builds, and the resource names each embeds.",
    attrs = {
        "expected": attr.string_list_dict(doc = "`<culture>/<assembly>.resources.dll` to the resource names it embeds."),
    },
)

def _deps_json_test_impl(ctx):
    env = analysistest.begin(ctx)

    content = None
    for action in analysistest.target_actions(env):
        if action.mnemonic == "FileWrite" and action.outputs.to_list()[0].basename.endswith(".deps.json"):
            content = action.content

    asserts.true(env, content != None, "the publish writes no deps.json")
    for fragment in ctx.attr.expected_fragments:
        asserts.true(env, fragment in content, "deps.json lacks {}: {}".format(fragment, content))

    return analysistest.end(env)

_deps_json_test = analysistest.make(
    _deps_json_test_impl,
    doc = "Asserts fragments of the deps.json a publish writes.",
    attrs = {
        "expected_fragments": attr.string_list(),
    },
)

def _fails_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.expected_message)
    return analysistest.end(env)

_fails_test = analysistest.make(
    _fails_test_impl,
    doc = "Asserts that the target under test fails with a message containing `expected_message`.",
    expect_failure = True,
    attrs = {
        "expected_message": attr.string(mandatory = True),
    },
)

def _distinct_files_test_impl(ctx):
    env = analysistest.begin(ctx)

    # `/resource:"<file>","<manifest name>"`
    files = {}
    for action in analysistest.target_actions(env):
        if action.mnemonic != "CSharpCompile":
            continue
        for arg in action.argv:
            for name in ctx.attr.manifest_names:
                suffix = "\",\"{}\"".format(name)
                if arg.startswith("/resource:\"") and arg.endswith(suffix):
                    files[name] = arg[len("/resource:\""):-len(suffix)]

    asserts.equals(env, sorted(ctx.attr.manifest_names), sorted(files.keys()))
    asserts.equals(env, len(files), len({file.lower(): None for file in files.values()}), "each resource is compiled to its own file: {}".format(files))

    return analysistest.end(env)

_distinct_files_test = analysistest.make(
    _distinct_files_test_impl,
    doc = "Asserts that the C# compile embeds each manifest name from a file of its own, whatever the case.",
    attrs = {
        "manifest_names": attr.string_list(),
    },
)

def _file(short_path):
    return struct(short_path = short_path, basename = short_path.rpartition("/")[2])

def _label(package, repo_name = ""):
    return struct(package = package, repo_name = repo_name)

# (short_path, label of the compiling target, path relative to its package)
_RELATIVE_PATHS = [
    ("Strings.resx", _label(""), "Strings.resx"),
    ("app/Strings.resx", _label("app"), "Strings.resx"),
    ("app/My Res/Strings.resx", _label("app"), "My Res/Strings.resx"),
    ("../other+/Strings.resx", _label("", "other+"), "Strings.resx"),
    ("../other+/app/sub/Strings.resx", _label("app", "other+"), "sub/Strings.resx"),
    # Outside the package, only the file name is kept.
    ("lib/Strings.resx", _label("app"), "Strings.resx"),
    ("appendix/Strings.resx", _label("app"), "Strings.resx"),
    ("../other+/app/Strings.resx", _label("app"), "Strings.resx"),
    ("../other+/app/Strings.resx", _label(""), "Strings.resx"),
    ("app/Strings.resx", _label("app", "other+"), "Strings.resx"),
]

def _package_relative_path_test_impl(ctx):
    env = unittest.begin(ctx)
    for short_path, label, expected in _RELATIVE_PATHS:
        asserts.equals(env, expected, package_relative_path(_file(short_path), label), "relative path of {} to {}".format(short_path, label))
    return unittest.end(env)

_package_relative_path_test = unittest.make(_package_relative_path_test_impl)

# buildifier: disable=unnamed-macro
def resx_tests():
    """The analysis tests of this package."""

    _package_relative_path_test(name = "project_relative_path_test")

    # Neutral resources go into the assembly, named after `root_namespace`,
    # and a culture's do not.
    for (language, mnemonic, root, quote) in [
        ("cs", "CSharpCompile", "ResxCsTest", "\""),
        ("fs", "FSharpCompile", "ResxFsTest", ""),
    ]:
        action_args_test(
            name = "{}_neutral_resources_test".format(language),
            target_under_test = ":greeter_" + language,
            action_mnemonic = mnemonic,
            expected_args_containing = [
                ",{q}{r}.Strings.resources{q}".format(q = quote, r = root),
                ",{q}{r}.Strings.api.resources{q}".format(q = quote, r = root),
                ",{q}{r}.My_Res._9lives.Thing.resources{q}".format(q = quote, r = root),
                ",{q}MyApp.Messages.resources{q}".format(q = quote),
                ",{q}{r}.Legacy.fr.resources{q}".format(q = quote, r = root),
            ],
            expected_args_not_containing = [
                "Strings.fr.resources",
                "Strings.es-419.resources",
                "Messages.fr.resources",
            ],
        )

        _satellites_test(
            name = "{}_satellites_test".format(language),
            target_under_test = ":greeter_" + language,
            expected = {
                "fr/Resx{}.App.resources.dll".format(language.capitalize()): [
                    "{}.Strings.fr.resources".format(root),
                    "MyApp.Messages.fr.resources",
                ],
                "es-419/Resx{}.App.resources.dll".format(language.capitalize()): ["{}.Strings.es-419.resources".format(root)],
                "sr-Latn-RS/Resx{}.App.resources.dll".format(language.capitalize()): ["{}.Strings.sr-Latn-RS.resources".format(root)],
            },
        )

    # Every locale's satellite has the same file name, so the locale is part of
    # its key.
    _deps_json_test(
        name = "publish_deps_json_test",
        target_under_test = ":publish_cs",
        expected_fragments = [
            "\"fr/ResxCs.App.resources.dll\":{\"locale\":\"fr\"}",
            "\"es-419/ResxCs.App.resources.dll\":{\"locale\":\"es-419\"}",
            "\"sr-Latn-RS/ResxCs.App.resources.dll\":{\"locale\":\"sr-Latn-RS\"}",
        ],
    )

    _fails_test(
        name = "duplicate_names_test",
        target_under_test = ":duplicate_names",
        expected_message = "would both be embedded as duplicate_names.Strings.resources",
    )

    _distinct_files_test(
        name = "similar_names_test",
        target_under_test = ":similar_names",
        manifest_names = [
            "similar_names.collide.A+B.resources",
            "similar_names.collide.A_B.resources",
            "similar_names.collide.a_b.resources",
        ],
    )

    for (attribute, path) in [("logical_name", "resources/Messages.resx"), ("culture", "resources/Messages.fr.resx")]:
        _fails_test(
            name = "{}_by_file_name_test".format(attribute),
            target_under_test = ":{}_by_file_name".format(attribute),
            expected_message = "use \"{}\"".format(path),
        )

    _fails_test(
        name = "logical_name_of_a_culture_test",
        target_under_test = ":logical_name_of_a_culture",
        expected_message = "which is a fr resource",
    )
