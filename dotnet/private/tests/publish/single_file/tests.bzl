"""Asserts what a single-file publish bundles, and which publishes it rejects.

What it leaves beside the executable is asserted with the other publish models
in //dotnet/private/tests/publish/container_layers.
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:defs.bzl", "publish_binary")

_APP = "//dotnet/private/tests/publish/app_to_publish"

# The linker for NativeAOT only drives Unix toolchains.
_NOT_WINDOWS = select({
    "@platforms//os:windows": ["@platforms//:incompatible"],
    "//conditions:default": [],
})

def _publish_test(name, impl, expect_failure = False, **kwargs):
    publish_binary(
        name = name + "_publish",
        binary = _APP,
        # Analysis is all the test needs.
        tags = ["manual"],
        target_framework = "net10.0",
        **kwargs
    )

    analysis_test(name = name, impl = impl, target = name + "_publish", expect_failure = expect_failure)

def _basenames(files):
    return [file.basename for file in files]

def _owners(files):
    return {file.owner: None for file in files}.keys()

def _bundled(env, target):
    """The files the publish bundles into its executable."""
    actions = [action for action in target[TestingAspectInfo].actions if action.mnemonic == "DotnetSingleFileBundle"]
    env.expect.that_collection(actions).has_size(1)

    # The bundler runs on a runtime of its own, which is no part of the bundle.
    bundler = target[TestingAspectInfo].attrs._apphost_shimmer[DefaultInfo]
    tool = {file.path: None for file in bundler.files.to_list() + bundler.default_runfiles.files.to_list()}

    return [file for file in actions[0].inputs.to_list() if file.path not in tool]

def _bundles_managed_test(name):
    _publish_test(name, _bundles_managed_test_impl, self_contained = True, single_file = True)

def _bundles_managed_test_impl(env, target):
    bundled = _bundled(env, target)

    # The application's assemblies, its dependencies' and the runtime's, with
    # the files that describe them.
    env.expect.that_collection(_basenames(bundled)).contains_at_least([
        "app_to_publish.dll",
        "app_to_publish.deps.json",
        "app_to_publish.runtimeconfig.json",
        "LibGit2Sharp.dll",
        "System.Private.CoreLib.dll",
    ])

    # Native libraries stay beside the executable unless asked for, and the
    # runtime's are linked into the host already.
    env.expect.that_collection(_owners(bundled)).not_contains(Label(_APP + ":native"))
    env.expect.that_collection(_basenames(bundled)).not_contains_predicate(matching.str_matches("*coreclr*"))

    # None of what is bundled is published as well.
    env.expect.that_collection(_basenames(target[DefaultInfo].files.to_list())).not_contains("app_to_publish.dll")

def _bundles_native_test(name):
    _publish_test(
        name,
        _bundles_native_test_impl,
        include_native_libraries_for_self_extract = True,
        self_contained = True,
        single_file = True,
    )

def _bundles_native_test_impl(env, target):
    bundled = _bundled(env, target)

    env.expect.that_collection(_owners(bundled)).contains(Label(_APP + ":native"))
    env.expect.that_collection(_basenames(bundled)).not_contains_predicate(matching.str_matches("*coreclr*"))

def _bundles_ready_to_run_images_test(name):
    _publish_test(name, _bundles_ready_to_run_images_test_impl, ready_to_run = True, self_contained = True, single_file = True)

def _bundles_ready_to_run_images_test_impl(env, target):
    # Each image takes the place of the assembly it was compiled from.
    app = [file for file in _bundled(env, target) if file.basename == "app_to_publish.dll"]
    env.expect.that_collection([file.short_path for file in app]).contains_exactly_predicates([matching.str_matches("*/r2r/app_to_publish.dll")])

def _expect_failure(fragment):
    def _impl(env, target):
        env.expect.that_target(target).failures().contains_predicate(matching.contains(fragment))

    return _impl

def _requires_self_contained_test(name):
    _publish_test(
        name,
        _expect_failure("single_file requires self_contained"),
        expect_failure = True,
        self_contained = False,
        single_file = True,
    )

def _options_require_single_file_test(name):
    _publish_test(
        name,
        _expect_failure("require single_file"),
        enable_compression_in_single_file = True,
        expect_failure = True,
        self_contained = True,
    )

def _not_with_native_aot_test(name):
    _publish_test(
        name,
        _expect_failure("single_file cannot be combined with native_aot"),
        expect_failure = True,
        native_aot = True,
        self_contained = True,
        single_file = True,
        target_compatible_with = _NOT_WINDOWS,
    )

def single_file_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _bundles_managed_test,
            _bundles_native_test,
            _bundles_ready_to_run_images_test,
            _requires_self_contained_test,
            _options_require_single_file_test,
            _not_with_native_aot_test,
        ],
    )
