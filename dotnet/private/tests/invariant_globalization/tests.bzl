"""Tests for `//dotnet/settings:invariant_globalization`.

The flag has to reach three places, which these cover: the environment of a
compile action, the launcher a binary or test starts through, and the runtime
of a binary built under it.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet/private/icu:settings.bzl", "INVARIANT_GLOBALIZATION_VARIABLE")
load("//dotnet/private/tests:utils.bzl", "launcher_environment", "only_action", "runs_with_settings_test")

_FLAG = str(Label("//dotnet/settings:invariant_globalization"))

# What a launcher sets on each platform: a default the environment can override.
_SH_LINE = 'export {v}="${{{v}:-1}}"'.format(v = INVARIANT_GLOBALIZATION_VARIABLE)
_BAT_LINE = "if not defined {v} set {v}=1".format(v = INVARIANT_GLOBALIZATION_VARIABLE)

_COMPILE_ENV_ATTRS = {
    "expected": attr.string(
        doc = "The value the variable carries in the compile environment, or empty when it is to be absent.",
    ),
    "mnemonic": attr.string(mandatory = True),
}

def _compile_env_test_impl(ctx):
    env = analysistest.begin(ctx)

    asserts.equals(
        env,
        ctx.attr.expected,
        only_action(env, ctx.attr.mnemonic).env.get(INVARIANT_GLOBALIZATION_VARIABLE, ""),
        "{} in the environment of {}".format(INVARIANT_GLOBALIZATION_VARIABLE, ctx.attr.mnemonic),
    )
    return analysistest.end(env)

compile_env_with_flag_test = analysistest.make(
    _compile_env_test_impl,
    attrs = _COMPILE_ENV_ATTRS,
    config_settings = {_FLAG: True},
)

compile_env_without_flag_test = analysistest.make(
    _compile_env_test_impl,
    attrs = _COMPILE_ENV_ATTRS,
    # Pinned rather than left to the default, so that the test holds whatever
    # the command line sets.
    config_settings = {_FLAG: False},
)

def _launcher_test_impl(ctx):
    env = analysistest.begin(ctx)

    line = launcher_environment(env)
    if ctx.attr.expect_line:
        asserts.true(
            env,
            line in [_SH_LINE, _BAT_LINE],
            "The launcher line '{}' is neither '{}' nor '{}'".format(line, _SH_LINE, _BAT_LINE),
        )
    else:
        asserts.equals(env, "", line, "The launcher line")
    return analysistest.end(env)

_LAUNCHER_ATTRS = {
    "expect_line": attr.bool(
        doc = "Whether the launcher is to set the variable, rather than leave the environment alone.",
    ),
}

launcher_with_flag_test = analysistest.make(
    _launcher_test_impl,
    attrs = _LAUNCHER_ATTRS,
    config_settings = {_FLAG: True},
)

launcher_without_flag_test = analysistest.make(
    _launcher_test_impl,
    attrs = _LAUNCHER_ATTRS,
    # Pinned rather than left to the default, so that the test holds whatever
    # the command line sets.
    config_settings = {_FLAG: False},
)

runs_with_flag_test = runs_with_settings_test({_FLAG: True})
