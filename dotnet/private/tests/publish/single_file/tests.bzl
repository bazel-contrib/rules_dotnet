"""Tests for single-file publish (`single_file = True`)."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet:defs.bzl", "publish_binary")

_APP = "//dotnet/private/tests/publish/app_to_publish"

def _single_file_action_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    actions = analysistest.target_actions(env)

    bundle_actions = [a for a in actions if a.mnemonic == "DotnetSingleFileBundle"]
    asserts.equals(env, 1, len(bundle_actions), "Expected exactly one DotnetSingleFileBundle action")

    # Managed assemblies are bundled into the executable, so app_to_publish.dll
    # is not in DefaultInfo.files.
    files = [f.basename for f in target[DefaultInfo].files.to_list()]
    asserts.false(
        env,
        "app_to_publish.dll" in files,
        "Expected app_to_publish.dll to be bundled inside the executable, got: %s" % files,
    )

    return analysistest.end(env)

single_file_action_test = analysistest.make(_single_file_action_test_impl)

def _single_file_failure_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, ctx.attr.expected_message)
    return analysistest.end(env)

single_file_failure_test = analysistest.make(
    _single_file_failure_test_impl,
    expect_failure = True,
    attrs = {
        "expected_message": attr.string(mandatory = True),
    },
)

# buildifier: disable=unnamed-macro
def single_file_test_suite():
    """Declares analysis tests for `single_file` on `publish_binary`."""
    publish_binary(
        name = "single_file_action_publish",
        binary = _APP,
        self_contained = True,
        single_file = True,
        tags = ["manual"],
        target_framework = "net10.0",
    )

    single_file_action_test(
        name = "single_file_action_test",
        target_under_test = ":single_file_action_publish",
    )

    publish_binary(
        name = "single_file_not_self_contained_publish",
        binary = _APP,
        self_contained = False,
        single_file = True,
        tags = ["manual"],
        target_framework = "net10.0",
    )

    single_file_failure_test(
        name = "single_file_requires_self_contained_test",
        expected_message = "single_file requires self_contained",
        target_under_test = ":single_file_not_self_contained_publish",
    )

    publish_binary(
        name = "single_file_options_without_single_file_publish",
        binary = _APP,
        enable_compression_in_single_file = True,
        self_contained = True,
        single_file = False,
        tags = ["manual"],
        target_framework = "net10.0",
    )

    single_file_failure_test(
        name = "single_file_options_require_single_file_test",
        expected_message = "require single_file",
        target_under_test = ":single_file_options_without_single_file_publish",
    )
