"""Checks what the action that writes a .NET Framework binary's `<exe>.config` reads."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

def _netfx_config_inputs_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = [action for action in analysistest.target_actions(env) if action.mnemonic == "DotnetNetFxConfig"]
    asserts.equals(env, 1, len(actions), "one DotnetNetFxConfig action")
    inputs = [file.basename for file in actions[0].inputs.to_list()]

    for name in ctx.attr.expected:
        asserts.true(env, name in inputs, "{} is not an input: {}".format(name, sorted(inputs)))
    for name in ctx.attr.unexpected:
        asserts.false(env, name in inputs, "{} is an input: {}".format(name, sorted(inputs)))

    return analysistest.end(env)

netfx_config_inputs_test = analysistest.make(
    _netfx_config_inputs_test_impl,
    attrs = {
        "expected": attr.string_list(),
        "unexpected": attr.string_list(),
    },
)
