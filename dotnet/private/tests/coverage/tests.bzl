"""Tests for `bazel coverage`.

They cover what a test target sets up under `bazel coverage` (the assemblies
to instrument and the launcher's coverage branch), that none of it exists
under `bazel test`, and a run of a test through the default coverage tool.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//dotnet/private:common.bzl", "to_rlocation_path")

_COVERAGE = "//command_line_option:collect_code_coverage"
_FILTER = "//command_line_option:instrumentation_filter"

# Selects :lib and leaves out :excluded and the test itself.
_FILTER_VALUE = "//dotnet/private/tests/coverage:lib"

def _launcher_coverage(env):
    """The launcher's coverage substitution, and whether it is a Windows launcher."""
    for action in analysistest.target_actions(env):
        substitutions = action.substitutions
        if substitutions and "TEMPLATED_coverage" in substitutions:
            return (substitutions["TEMPLATED_coverage"], action.outputs.to_list()[0].extension == "bat")
    fail("No launcher expansion among the target's actions")

def _assemblies_write(env):
    matching = [
        action
        for action in analysistest.target_actions(env)
        if action.mnemonic == "FileWrite" and action.outputs.to_list()[0].basename.endswith(".coverage_assemblies")
    ]
    return matching[0] if matching else None

def _coverage_assemblies_test_impl(ctx):
    env = analysistest.begin(ctx)

    (launcher, is_windows) = _launcher_coverage(env)
    write = _assemblies_write(env)

    # The coverage tool does not run on Windows: the launcher runs the test as
    # under bazel test.
    if is_windows:
        asserts.equals(env, "", launcher, "The coverage branch of a Windows launcher")
        asserts.equals(env, None, write, "A list of assemblies to instrument on Windows")
        return analysistest.end(env)

    asserts.true(env, "COVERAGE" in launcher, "The launcher has no coverage branch: '{}'".format(launcher))
    asserts.true(env, write != None, "No list of the assemblies to instrument")
    if write:
        listed = sorted([line.split("/")[-1] for line in write.content.splitlines()])
        asserts.equals(env, sorted(ctx.attr.expected), listed, "The assemblies to instrument")

    return analysistest.end(env)

coverage_assemblies_test = analysistest.make(
    _coverage_assemblies_test_impl,
    attrs = {"expected": attr.string_list(doc = "The file names of the DLLs to instrument.")},
    config_settings = {_COVERAGE: True, _FILTER: _FILTER_VALUE},
)

def _no_coverage_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.equals(env, None, _assemblies_write(env), "A list of assemblies to instrument outside bazel coverage")
    asserts.equals(env, "", _launcher_coverage(env)[0], "The launcher's coverage branch outside bazel coverage")
    return analysistest.end(env)

no_coverage_test = analysistest.make(
    _no_coverage_test_impl,
    # Pinned rather than left to the default, so that the test holds whatever
    # the command line sets.
    config_settings = {_COVERAGE: False},
)

def _with_coverage_impl(_settings, _attr):
    return {_COVERAGE: True, _FILTER: _FILTER_VALUE}

_with_coverage = transition(
    implementation = _with_coverage_impl,
    inputs = [],
    outputs = [_COVERAGE, _FILTER],
)

_RUN_SCRIPT = """#!/usr/bin/env bash
set -euo pipefail

export COVERAGE=1
export COVERAGE_DIR="$TEST_TMPDIR/coverage"
mkdir -p "$COVERAGE_DIR"

"$RUNFILES_DIR/{launcher}" 'an argument'

report="$COVERAGE_DIR/coverlet.dat"
fail() {{ echo "$1" >&2; cat "$report" >&2 || true; exit 1; }}

[[ -f "$report" ]] || fail "No LCOV report at $report"
grep -qx 'SF:{expected}' "$report" || fail "{expected} is not in the report"
if grep -q '^SF:{unexpected}' "$report"; then fail "{unexpected} is in the report"; fi
grep -qE '^DA:[0-9]+,[1-9]' "$report" || fail "No line of {expected} was hit"
grep -qE '^DA:[0-9]+,0$' "$report" || fail "No line of {expected} was missed"
if grep -E '^FN(DA)?:' "$report" | grep -qE '^[^,]*,.*,'; then fail "A method name keeps a comma"; fi
"""

def _coverage_run_test_impl(ctx):
    binary = ctx.attr.binary[0][DefaultInfo]
    script = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = script,
        content = _RUN_SCRIPT.format(
            launcher = to_rlocation_path(ctx, binary.files_to_run.executable),
            expected = ctx.attr.expected_source,
            unexpected = ctx.attr.unexpected_source,
        ),
        is_executable = True,
    )
    return [DefaultInfo(
        executable = script,
        runfiles = ctx.runfiles(files = [binary.files_to_run.executable]).merge(binary.default_runfiles),
    )]

coverage_run_test = rule(
    _coverage_run_test_impl,
    doc = "Runs a test, built for `bazel coverage`, through its coverage branch and checks the LCOV it writes.",
    attrs = {
        "binary": attr.label(
            doc = "The test to run, which takes 'an argument' as its one argument.",
            cfg = _with_coverage,
            executable = True,
            mandatory = True,
        ),
        "expected_source": attr.string(doc = "A source file the report covers.", mandatory = True),
        "unexpected_source": attr.string(doc = "A source file the report leaves out.", mandatory = True),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    test = True,
)
