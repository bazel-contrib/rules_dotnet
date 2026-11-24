"""Checks that a .NET Framework publish carries its application in its runfiles."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _publish_runfiles_test_impl(ctx):
    env = analysistest.begin(ctx)
    publish = analysistest.target_under_test(env)

    # What a target running the publish as a tool gets.
    runfiles = [file.basename for file in publish[DefaultInfo].default_runfiles.files.to_list()]
    for name in ctx.attr.expected:
        asserts.true(env, name in runfiles, "{} is not in the runfiles of {}: {}".format(name, publish.label, sorted(runfiles)))

    return analysistest.end(env)

publish_runfiles_test = analysistest.make(
    _publish_runfiles_test_impl,
    attrs = {
        "expected": attr.string_list(),
    },
)
