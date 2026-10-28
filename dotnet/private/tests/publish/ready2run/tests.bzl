"""Asserts which publishes ask the targets below their binary for ReadyToRun images."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("//dotnet:defs.bzl", "publish_binary")
load("//dotnet/private/tests:utils.bzl", "ready_to_run_images_below")

_APP = "//dotnet/private/tests/publish/app_to_publish"

def _no_images_test(name, **kwargs):
    publish_binary(
        name = name + "_publish",
        binary = _APP,
        # Analysis is all the test needs.
        tags = ["manual"],
        target_framework = "net10.0",
        **kwargs
    )

    analysis_test(name = name, impl = _no_images_test_impl, target = name + "_publish")

def _no_images_test_impl(env, target):
    # Only a ReadyToRun publish compiling image by image asks the targets below
    # its binary for images. Any other leaves them, and the packs they would
    # fetch, out of the build.
    env.expect.that_collection(ready_to_run_images_below(target)).has_size(0)

def _no_images_when_self_contained_test(name):
    _no_images_test(name, self_contained = True)

def _no_images_when_framework_dependent_test(name):
    _no_images_test(name, self_contained = False)

def _no_images_when_composite_test(name):
    _no_images_test(name, ready_to_run = True, ready_to_run_composite = True, self_contained = True)

def _no_images_when_native_aot_test(name):
    _no_images_test(
        name,
        native_aot = True,
        self_contained = True,
        # The linker for NativeAOT only drives Unix toolchains.
        target_compatible_with = select({
            "@platforms//os:windows": ["@platforms//:incompatible"],
            "//conditions:default": [],
        }),
    )

def ready_to_run_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _no_images_when_self_contained_test,
            _no_images_when_framework_dependent_test,
            _no_images_when_composite_test,
            _no_images_when_native_aot_test,
        ],
    )
