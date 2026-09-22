"Test utilities"

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet/private:providers.bzl", "DotnetBinaryInfo")

ACTION_ARGS_TEST_ARGS = {
    "action_mnemonic": attr.string(),
    "expected_partial_args": attr.string_list(),
    "expected_nonexistent_partial_args": attr.string_list(),
    "expected_args_containing": attr.string_list(),
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

    for needle in ctx.attr.expected_args_containing:
        found_arg = None
        for actual_arg in action_under_test.argv:
            if needle in actual_arg:
                found_arg = actual_arg
                break

        if found_arg == None:
            fail("No arg containing substring: {}. Available args: {}".format(needle, action_under_test.argv))

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

RUN_ENVIRONMENT_INFO_TEST_ARGS = {
    "expected_inherited_environment": attr.string_list(),
}

def _run_environment_info_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    if RunEnvironmentInfo not in target:
        fail("Target does not return RunEnvironmentInfo provider")

    run_env_info = target[RunEnvironmentInfo]

    for expected in ctx.attr.expected_inherited_environment:
        asserts.true(
            env,
            expected in run_env_info.inherited_environment,
            "Expected inherited environment variable '{}' to be in '{}'".format(expected, run_env_info.inherited_environment),
        )

    return analysistest.end(env)

run_environment_info_test = analysistest.make(
    _run_environment_info_test_impl,
    attrs = RUN_ENVIRONMENT_INFO_TEST_ARGS,
)

def only_action(env, mnemonic):
    """The target's single action with the given mnemonic.

    Args:
        env: The `analysistest` environment.
        mnemonic: The mnemonic to look for.

    Returns:
        The action, failing when the target has no such action or several.
    """

    matching = [a for a in analysistest.target_actions(env) if a.mnemonic == mnemonic]
    if len(matching) != 1:
        fail("Expected one {} action, found {}".format(mnemonic, len(matching)))
    return matching[0]

def launcher_environment(env):
    """The environment block a target's launcher template is expanded with.

    Args:
        env: The `analysistest` environment.

    Returns:
        The `TEMPLATED_environment` substitution, failing when the target
        expands no launcher.
    """

    for action in analysistest.target_actions(env):
        substitutions = action.substitutions
        if substitutions and "TEMPLATED_environment" in substitutions:
            return substitutions["TEMPLATED_environment"]
    fail("No launcher expansion among the target's actions")

def runs_with_settings_test(settings):
    """A test rule that runs a binary built with the given build settings.

    The binary's launcher finds its runfiles through the test runner's
    environment, so it stands in for the test under another name.

    Args:
        settings: A dict of build setting label to the value to build with.

    Returns:
        A test rule with a `binary` attribute, which is to exit with zero.
    """

    def _transition_impl(_settings, _attr):
        return settings

    with_settings = transition(
        implementation = _transition_impl,
        inputs = [],
        outputs = settings.keys(),
    )

    def _impl(ctx):
        binary = ctx.attr.binary[0][DefaultInfo]
        launcher = binary.files_to_run.executable
        extension = ("." + launcher.extension) if launcher.extension else ""
        executable = ctx.actions.declare_file(ctx.label.name + extension)
        ctx.actions.symlink(output = executable, target_file = launcher, is_executable = True)
        return [DefaultInfo(executable = executable, runfiles = binary.default_runfiles)]

    return rule(
        _impl,
        doc = "Runs a binary, built with {}, as a test.".format(settings),
        attrs = {
            "binary": attr.label(
                doc = "The binary to run, which is to exit with zero.",
                cfg = with_settings,
                executable = True,
                mandatory = True,
            ),
            "_allowlist_function_transition": attr.label(
                default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
            ),
        },
        test = True,
    )
