"""Asserts how a publish splits into container layers."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:defs.bzl", "publish_binary")

LAYERS = ["runtime", "third_party", "first_party", "app"]

_APP = "//dotnet/private/tests/publish/app_to_publish"

# The linker for NativeAOT only drives Unix toolchains.
_NOT_WINDOWS = select({
    "@platforms//os:windows": ["@platforms//:incompatible"],
    "//conditions:default": [],
})

# The actions that fill the publish directory itself.
_PUBLISH_COPIES = ["DotnetPublishCopy", "DotnetCopySidecars"]

def _actions(target, mnemonics):
    return [action for action in target[TestingAspectInfo].actions if action.mnemonic in mnemonics]

def _copied(target, action):
    """What a copy action copies: its inputs, less the script doing it."""
    script_prefix = "{}/{}.".format(target.label.package, target.label.name)

    return [file for file in action.inputs.to_list() if not file.short_path.startswith(script_prefix)]

def _layers(target):
    """The files each layer is copied from, keyed by layer."""
    root = "{}/{}/layers/".format(target.label.package, target.label.name)

    return {
        output.short_path.removeprefix(root): _copied(target, action)
        for action in _actions(target, ["DotnetPublishLayer"])
        for output in action.outputs.to_list()
    }

def _publish_copy_outputs(target):
    return {
        file.path: None
        for action in _actions(target, _PUBLISH_COPIES)
        for file in action.outputs.to_list()
    }

def _repo_mapping(target):
    """The repository mapping the layers carry, which is the binary's."""
    return target[TestingAspectInfo].attrs.binary[0][DefaultInfo].files_to_run.repo_mapping_manifest

def _data(target):
    """The data files a publish carries as runfiles."""
    in_publish = {file.path: None for file in target[DefaultInfo].files.to_list()}

    return [file for file in target[DefaultInfo].default_runfiles.files.to_list() if file.path not in in_publish]

def _published(target):
    """The sources of what a publish's layers should hold.

    The files of the publish directory, plus the data files and repository
    mapping of its runfiles tree.
    """
    copy_outputs = _publish_copy_outputs(target)
    copied = [file for action in _actions(target, _PUBLISH_COPIES) for file in _copied(target, action)]
    generated = [file for file in target[DefaultInfo].files.to_list() if file.path not in copy_outputs]
    data = _data(target)

    return copied + generated + data + [_repo_mapping(target)]

def _basenames(files):
    return [file.basename for file in files]

def _owners(files):
    return {file.owner: None for file in files}.keys()

def _expect_layers_cover_the_publish(env, target):
    """Every published file is in exactly one layer, each in an output group."""
    layers = _layers(target)

    seen = {}
    for (layer, files) in layers.items():
        for file in files:
            if file.path in seen:
                env.fail("{} is in both the {} and the {} layer".format(file.short_path, seen[file.path], layer))
            seen[file.path] = layer

    env.expect.that_collection(layers.keys()).contains_exactly(LAYERS)
    env.expect.that_collection(seen.keys()).contains_exactly([file.path for file in _published(target)])
    env.expect.that_str(seen.get(target[DefaultInfo].files_to_run.executable.path)).equals("app")

    for layer in LAYERS:
        env.expect.that_target(target).output_group(layer + "_layer").contains_exactly([
            "{}/{}/layers/{}".format(target.label.package, target.label.name, layer),
        ])

def _expect_layers_independent_of_the_publish_copy(env, target):
    """Building a layer never goes through the copy of the whole publish.

    That copy takes every published file as input, so a layer reached through
    it would be rebuilt whenever any other layer changed.
    """
    copy_outputs = _publish_copy_outputs(target)

    for (layer, files) in _layers(target).items():
        for file in files:
            if file.path in copy_outputs:
                env.fail("The {} layer copies {} out of the publish directory".format(layer, file.short_path))

    for action in _actions(target, ["DotnetApphostShim"]):
        for file in action.inputs.to_list():
            if file.path in copy_outputs:
                env.fail("The apphost depends on {}, which the publish copy writes".format(file.short_path))

def _expect_dependencies_layered(env, target, runtime):
    """The app's dependencies land in the layer their origin puts them in."""
    layers = _layers(target)

    if runtime:
        env.expect.that_collection(_basenames(layers["runtime"])).contains("System.Private.CoreLib.dll")
        env.expect.that_bool(all([
            "microsoft.netcore.app.runtime." in owner.repo_name
            for owner in _owners(layers["runtime"])
        ])).equals(True)
    else:
        env.expect.that_collection(layers["runtime"]).has_size(0)

    # LibGit2Sharp and its native binaries both arrive as NuGet packages.
    env.expect.that_collection(_basenames(layers["third_party"])).contains("LibGit2Sharp.dll")
    env.expect.that_bool(all([
        "libgit2sharp" in owner.repo_name
        for owner in _owners(layers["third_party"])
    ])).equals(True)

    # The native library is wrapped in an `import_library` that names no
    # package, so it is ours even though it is imported.
    env.expect.that_collection(_owners(layers["first_party"])).contains_exactly([
        Label("//tools/runfiles"),
        Label(_APP + ":native"),
    ])

def _publish_test(name, impl, binary = _APP, **kwargs):
    publish_binary(
        name = name + "_publish",
        binary = binary,
        # Analysis is all the test needs.
        tags = ["manual"],
        target_framework = "net10.0",
        **kwargs
    )

    analysis_test(name = name, impl = impl, target = name + "_publish")

def _self_contained_test(name):
    _publish_test(name, _self_contained_test_impl, self_contained = True)

def _self_contained_test_impl(env, target):
    _expect_layers_cover_the_publish(env, target)
    _expect_layers_independent_of_the_publish_copy(env, target)
    _expect_dependencies_layered(env, target, runtime = True)

    # The binary's own data file travels with it, beside the repository mapping.
    env.expect.that_collection(_basenames(_layers(target)["app"])).contains_exactly([
        target[DefaultInfo].files_to_run.executable.basename,
        "app_to_publish.dll",
        "app_to_publish.deps.json",
        "app_to_publish.runtimeconfig.json",
        "data-file",
        _repo_mapping(target).basename,
    ])

def _framework_dependent_test(name):
    _publish_test(name, _framework_dependent_test_impl, self_contained = False)

def _framework_dependent_test_impl(env, target):
    _expect_layers_cover_the_publish(env, target)
    _expect_layers_independent_of_the_publish_copy(env, target)
    _expect_dependencies_layered(env, target, runtime = False)

def _ready_to_run_test(name):
    _publish_test(name, _ready_to_run_test_impl, ready_to_run = True, self_contained = True)

def _ready_to_run_test_impl(env, target):
    _expect_layers_cover_the_publish(env, target)
    _expect_layers_independent_of_the_publish_copy(env, target)

    # Each image is compiled against what its assembly can reference, so that
    # changing the application recompiles none of its dependencies, and
    # changing a library of ours leaves the packages alone.
    inputs = {
        image.basename: _basenames(action.inputs.to_list())
        for action in _actions(target, ["Crossgen2"])
        for image in action.outputs.to_list()
    }

    for image in ["LibGit2Sharp.dll", "runfiles.dll", "app_to_publish.dll"]:
        env.expect.that_collection(inputs[image]).contains("System.Private.CoreLib.dll")

    env.expect.that_collection(inputs["LibGit2Sharp.dll"]).contains_none_of(["runfiles.dll", "app_to_publish.dll"])
    env.expect.that_collection(inputs["runfiles.dll"]).contains("LibGit2Sharp.dll")
    env.expect.that_collection(inputs["runfiles.dll"]).not_contains("app_to_publish.dll")
    env.expect.that_collection(inputs["app_to_publish.dll"]).contains_at_least(["LibGit2Sharp.dll", "runfiles.dll"])

def _ready_to_run_composite_test(name):
    _publish_test(
        name,
        _ready_to_run_composite_test_impl,
        ready_to_run = True,
        ready_to_run_composite = True,
        self_contained = True,
    )

def _ready_to_run_composite_test_impl(env, target):
    _expect_layers_cover_the_publish(env, target)
    _expect_layers_independent_of_the_publish_copy(env, target)

    # Each image stays in the layer of the assembly it replaces, while the
    # composite image, which covers them all, changes with the application.
    layers = _layers(target)
    env.expect.that_collection(_basenames(layers["runtime"])).contains("System.Private.CoreLib.dll")
    env.expect.that_collection(_basenames(layers["third_party"])).contains("LibGit2Sharp.dll")
    env.expect.that_collection(_basenames(layers["app"])).contains("app_to_publish.r2r.dll")

def _native_aot_test(name):
    _publish_test(
        name,
        _native_aot_test_impl,
        native_aot = True,
        self_contained = True,
        target_compatible_with = _NOT_WINDOWS,
    )

def _native_aot_test_impl(env, target):
    _expect_layers_cover_the_publish(env, target)
    _expect_layers_independent_of_the_publish_copy(env, target)

    # The runtime and every assembly are compiled into the executable; only
    # the native libraries it loads and the data it reads at run time are
    # left to layer.
    layers = _layers(target)
    env.expect.that_collection(layers["runtime"]).has_size(0)
    env.expect.that_collection(_basenames(layers["app"])).contains_exactly([
        target[DefaultInfo].files_to_run.executable.basename,
        "data-file",
        _repo_mapping(target).basename,
    ])
    env.expect.that_collection(_owners(layers["first_party"])).contains_exactly([Label(_APP + ":native")])
    env.expect.that_collection(layers["third_party"]).has_size(1)

def _data_test(name):
    _publish_test(name, _data_test_impl, binary = ":data_app", self_contained = True)

def _data_test_impl(env, target):
    _expect_layers_cover_the_publish(env, target)

    # A data file lands in the layer of the target it belongs to.
    layers = _layers(target)
    env.expect.that_collection(_basenames(layers["first_party"])).contains_at_least(["data_lib.dll", "lib-data.txt"])
    env.expect.that_collection(_basenames(layers["app"])).contains_at_least(["data_app.dll", "app-data.txt"])
    env.expect.that_collection(layers["app"]).contains(_repo_mapping(target))

def container_layers_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _self_contained_test,
            _framework_dependent_test,
            _ready_to_run_test,
            _ready_to_run_composite_test,
            _native_aot_test,
            _data_test,
        ],
    )
