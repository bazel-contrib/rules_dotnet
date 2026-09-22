"""Tests for `//dotnet/settings:icu` set to the ICU the rules build.

Linux only, as the platform whose runtime loads ICU from shared libraries. The
flag has to reach the compile actions, the launchers and the runtime.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet/private/icu:settings.bzl", "ICU_VERSION_VARIABLES")
load("//dotnet/private/icu:sources.bzl", "ICU_MAJOR_VERSION")
load("//dotnet/private/tests:utils.bzl", "launcher_environment", "only_action", "runs_with_settings_test")

_HERMETIC_ICU = {str(Label("//dotnet/settings:icu")): str(Label("//dotnet/settings:hermetic_icu"))}

def _compile_env_test_impl(ctx):
    env = analysistest.begin(ctx)

    compile_env = only_action(env, "CSharpCompile").env
    for variable in ICU_VERSION_VARIABLES:
        asserts.equals(
            env,
            ICU_MAJOR_VERSION,
            compile_env.get(variable, ""),
            "{} in the environment of the compile".format(variable),
        )
    return analysistest.end(env)

compile_env_test = analysistest.make(
    _compile_env_test_impl,
    config_settings = _HERMETIC_ICU,
)

def _launcher_test_impl(ctx):
    env = analysistest.begin(ctx)

    block = launcher_environment(env)
    asserts.true(
        env,
        "LD_LIBRARY_PATH" in block and "libicuuc.so." + ICU_MAJOR_VERSION in block,
        "The launcher does not put the ICU on the loader's path: " + block,
    )
    for variable in ICU_VERSION_VARIABLES:
        asserts.true(
            env,
            '{}="{}"'.format(variable, ICU_MAJOR_VERSION) in block,
            "The launcher does not set {}: {}".format(variable, block),
        )
    return analysistest.end(env)

launcher_test = analysistest.make(
    _launcher_test_impl,
    config_settings = _HERMETIC_ICU,
)

runs_with_hermetic_icu_test = runs_with_settings_test(_HERMETIC_ICU)
