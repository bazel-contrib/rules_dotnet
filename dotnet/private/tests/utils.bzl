"Test utilities"

load("@bazel_skylib//lib:unittest.bzl", "analysistest")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:providers.bzl", "DotnetBinaryInfo")

ACTION_ARGS_TEST_ARGS = {
    "action_mnemonic": attr.string(),
    "expected_partial_args": attr.string_list(),
    "expected_nonexistent_partial_args": attr.string_list(),
}

# We also expose the implementation so that it can be used for testing
# with config flags
# buildifier: disable=function-docstring
def action_args_test_impl(ctx):
    env = analysistest.begin(ctx)

    action_under_test = None
    for action in analysistest.target_actions(env):
        if action.mnemonic == ctx.attr.action_mnemonic:
            if action_under_test == None:
                action_under_test = action
            else:
                fail("Multiple actions with mnemonic: {}".format(ctx.attr.action_mnemonic))

    if action_under_test == None:
        fail("No action with mnemonic: {}".format(ctx.attr.action_mnemonic))

    for expected_arg in ctx.attr.expected_partial_args:
        found_arg = None
        for actual_arg in action_under_test.argv:
            if actual_arg == expected_arg:
                if found_arg == None:
                    found_arg = actual_arg
                else:
                    fail("Multiple matches for arg: {}".format(expected_arg))

        if found_arg == None:
            fail("No match for arg: {}".format(expected_arg))

    for unexpected_arg in ctx.attr.expected_nonexistent_partial_args:
        for actual_arg in action_under_test.argv:
            if actual_arg == unexpected_arg:
                fail("Expected arg not to be present: {}".format(unexpected_arg))

    return analysistest.end(env)

action_args_test = analysistest.make(
    action_args_test_impl,
    attrs = ACTION_ARGS_TEST_ARGS,
)

def get_target_tfm(target):
    """Returns the target framework of the given target.

    Args:
        target: The target to get the target framework of.

    Returns:
        The target framework of the given target.
    """
    return target[TestingAspectInfo].attrs._target_framework[BuildSettingInfo].value

def get_target_rid(target):
    """Returns the target runtime identifier of the given target.

    Args:
        target: The target to get the target runtime identifier of.

    Returns:
        The target runtime identifier of the given target.
    """

    if getattr(target[TestingAspectInfo].attrs, "runtime_identifier", None):
        return target[TestingAspectInfo].attrs.runtime_identifier

    if getattr(target[TestingAspectInfo].attrs, "binary", None):
        return target[TestingAspectInfo].attrs.binary[0][DotnetBinaryInfo].runtime_pack_info.runtime_identifier

    fail("Could not determine target runtime identifier")
