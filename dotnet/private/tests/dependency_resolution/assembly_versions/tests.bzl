"""Asserts the `assemblyVersion` a deps.json gives each runtime assembly.

The host reads it as a `System.Version` to choose between an app's assembly
and a framework's of the same name, and takes one it cannot parse for no
version at all. So it is either four numbers, as the framework's own deps.json
spells it, or left out.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:defs.bzl", "csharp_binary", "import_dll", "publish_binary")

# The version each imported DLL carries, by its assembly name.
_VERSIONS = {
    "Unset": "",
    "TwoPart": "4.5",
    "ThreePart": "7.0.3",
    "FourPart": "1.2.3.4",
    "Prerelease": "1.2.3-beta.1+sha.5114f85",
    "TooLarge": "1.70000.0",
    "NotAVersion": "latest",
}

_PUBLISH = "assembly_versions_publish"

def _runtime(env, target, assembly):
    """The `runtime` section the publish's deps.json gives `assembly`."""
    depsjson = [
        output.short_path
        for action in target[TestingAspectInfo].actions
        for output in action.outputs.to_list()
        if output.basename == "assembly_versions_app.deps.json"
    ]
    env.expect.that_collection(depsjson).has_size(1)

    # Written at analysis, so its content is on the action.
    content = env.expect.that_target(target).action_generating(depsjson[0]).actual.content
    libraries = json.decode(content)["targets"].values()[0]

    name = "{}/{}".format(assembly, _VERSIONS[assembly])
    env.expect.that_collection(libraries.keys()).contains(name)
    return libraries.get(name, {}).get("runtime", {})

def _runtime_test(name, assembly, expected):
    def _impl(env, target):
        env.expect.that_dict(_runtime(env, target, assembly)).contains_exactly({assembly + ".dll": expected})

    analysis_test(name = name, impl = _impl, target = _PUBLISH)

# With no version, nothing says which assembly is newer.
def _unset_version_test(name):
    _runtime_test(name, "Unset", {})

def _two_part_version_test(name):
    _runtime_test(name, "TwoPart", {"assemblyVersion": "4.5.0.0"})

def _three_part_version_test(name):
    _runtime_test(name, "ThreePart", {"assemblyVersion": "7.0.3.0"})

def _four_part_version_test(name):
    _runtime_test(name, "FourPart", {"assemblyVersion": "1.2.3.4"})

# An assembly version is numbers only.
def _prerelease_version_test(name):
    _runtime_test(name, "Prerelease", {"assemblyVersion": "1.2.3.0"})

# Each number of an assembly version is 16 bits.
def _too_large_version_test(name):
    _runtime_test(name, "TooLarge", {})

def _not_a_version_test(name):
    _runtime_test(name, "NotAVersion", {})

def assembly_versions_test_suite(name):
    """Declares the tests, and the publish they analyze.

    Args:
        name: The name of the test suite.
    """
    for assembly, version in _VERSIONS.items():
        # Never built: the tests only read what analysis writes.
        write_file(
            name = "{}_dll".format(assembly),
            out = "{}.dll".format(assembly),
            content = [],
            tags = ["manual"],
        )

        import_dll(
            name = "{}_import".format(assembly),
            dll = "{}.dll".format(assembly),
            tags = ["manual"],
            version = version,
        )

    csharp_binary(
        name = "assembly_versions_app",
        srcs = ["Main.cs"],
        tags = ["manual"],
        target_frameworks = ["net10.0"],
        deps = ["{}_import".format(assembly) for assembly in _VERSIONS],
    )

    publish_binary(
        name = _PUBLISH,
        binary = ":assembly_versions_app",
        self_contained = False,
        tags = ["manual"],
        target_framework = "net10.0",
    )

    test_suite(
        name = name,
        tests = [
            _unset_version_test,
            _two_part_version_test,
            _three_part_version_test,
            _four_part_version_test,
            _prerelease_version_test,
            _too_large_version_test,
            _not_a_version_test,
        ],
    )
