"""Asserts that building for a release newer than the SDK says which SDK it needs."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _sdk_too_old_test_impl(ctx):
    env = analysistest.begin(ctx)

    for fragment in ctx.attr.expected_message_fragments:
        asserts.expect_failure(env, fragment)

    return analysistest.end(env)

sdk_too_old_test = analysistest.make(
    _sdk_too_old_test_impl,
    doc = "Asserts that the target under test fails with a message containing every fragment.",
    expect_failure = True,
    attrs = {
        "expected_message_fragments": attr.string_list(mandatory = True),
    },
)
