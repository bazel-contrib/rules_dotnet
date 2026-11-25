"""Analysis tests of where a framework-dependent publish puts native libraries."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:defs.bzl", "publish_binary")

def _depsjson_action(env, target):
    """The action writing the publish's deps.json."""
    actions = [
        action
        for action in target[TestingAspectInfo].actions
        if action.mnemonic == "FileWrite" and action.outputs.to_list()[0].basename.endswith(".deps.json")
    ]
    env.expect.that_collection(actions).has_size(1)
    return actions[0]

def _published_paths(target, root):
    """The paths the publish copies files to, relative to its directory."""
    return [
        file.path.removeprefix(root)
        for action in target[TestingAspectInfo].actions
        if action.mnemonic == "DotnetPublishCopy"
        for file in action.outputs.to_list()
        if file.path.startswith(root)
    ]

def _listed_natives(depsjson):
    """Where the deps.json tells the host to look for each native library.

    A `native` asset beside the main assembly, a `runtimeTargets` one at the
    path it is keyed by.
    """
    libraries = json.decode(depsjson)["targets"].values()[0]

    listed = []
    for entry in libraries.values():
        listed += entry.get("native", {}).keys()
        listed += [
            path
            for (path, asset) in entry.get("runtimeTargets", {}).items()
            if asset["assetType"] == "native"
        ]
    return listed

def _natives_where_the_depsjson_says_test(name):
    publish_binary(
        name = name + "_publish",
        binary = ":native_layout_app",
        tags = ["manual"],
        target_framework = "net10.0",
    )

    analysis_test(
        name = name,
        impl = _natives_where_the_depsjson_says_test_impl,
        target = name + "_publish",
    )

def _natives_where_the_depsjson_says_test_impl(env, target):
    depsjson = _depsjson_action(env, target)
    published = _published_paths(target, depsjson.outputs.to_list()[0].dirname + "/")
    listed = _listed_natives(depsjson.content)

    # Every native library is published where the host will look for it, and
    # none is published under `runtimes/` unless the deps.json says it is there.
    env.expect.that_collection(published).contains_at_least(listed)
    env.expect.that_collection(listed).contains_at_least([path for path in published if path.startswith("runtimes/")])

    # A native library an `import_library` names without a package is a
    # `native` asset wherever it sits in the source tree.
    env.expect.that_collection(published).contains("libhandwritten.so")

    # LibGit2Sharp's are `runtimeTargets` and keep their RID folders.
    env.expect.that_bool(any([path.startswith("runtimes/") for path in published])).equals(True)

def framework_dependent_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _natives_where_the_depsjson_says_test,
        ],
    )
