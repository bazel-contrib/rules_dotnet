"""Asserts that a publish rejects two files that would take the same path."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _publish_conflict_test_impl(ctx):
    env = analysistest.begin(ctx)

    for fragment in ctx.attr.expected_message_fragments:
        asserts.expect_failure(env, fragment)

    return analysistest.end(env)

publish_conflict_test = analysistest.make(
    _publish_conflict_test_impl,
    doc = "Asserts that the publish under test fails with a message containing every fragment.",
    expect_failure = True,
    attrs = {
        "expected_message_fragments": attr.string_list(
            doc = "Substrings the failure message has to contain. Given in pieces " +
                  "because the message spells labels with their canonical repository " +
                  "prefix, which buildifier will not allow in a source string.",
            mandatory = True,
        ),
    },
)

def _publish_succeeds_test_impl(ctx):
    env = analysistest.begin(ctx)

    return analysistest.end(env)

publish_succeeds_test = analysistest.make(
    _publish_succeeds_test_impl,
    doc = "Asserts that the publish under test analyses without a path conflict.",
)

def _one_file_per_path_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = [action for action in analysistest.target_actions(env) if action.mnemonic == ctx.attr.mnemonic]
    asserts.equals(env, 1, len(actions))

    # A failed assertion does not stop the test; without exactly one action
    # there is nothing to inspect.
    if len(actions) != 1:
        return analysistest.end(env)

    files = [file for file in actions[0].inputs.to_list() if file.basename == ctx.attr.basename]
    asserts.equals(env, 1, len(files), "{} reads {}".format(ctx.attr.mnemonic, [file.short_path for file in files]))

    return analysistest.end(env)

one_file_per_path_test = analysistest.make(
    _one_file_per_path_test_impl,
    doc = "Asserts that an action of the publish under test reads only one of the files taking a path.",
    attrs = {
        "basename": attr.string(
            doc = "The name the files share.",
            mandatory = True,
        ),
        "mnemonic": attr.string(
            doc = "The mnemonic of the action.",
            mandatory = True,
        ),
    },
)
