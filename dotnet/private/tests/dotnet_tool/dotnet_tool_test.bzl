"""Test rule for `dotnet_tool`."""

TOOL_WRAPPER = """#!/usr/bin/env bash

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${{RUNFILES_DIR:-/dev/null}}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${{RUNFILES_MANIFEST_FILE:-/dev/null}}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  {{ echo>&2 "ERROR: cannot find $f"; exit 1; }}; f=; set -e
# --- end runfiles.bash initialization v3 ---
runfiles_export_envvars

set -o pipefail -o errexit -o nounset

TOOL="$(rlocation "{tool}")"
EXPECTED_SUBSTRING="{expected_stdout_contains}"
EXPECTED_SUBSTRING="${{EXPECTED_SUBSTRING%%$'\\n'}}"

# Filter arguments such that arguments starting with RLOCATION: are replaced
# with their runfile locations.
args=()
for arg in "$@"; do
  if [[ "$arg" == RLOCATION:* ]]; then
    runfile_path="${{arg#RLOCATION:}}"
    resolved_path="$(rlocation "$runfile_path")"
    args+=("$resolved_path")
  else
    args+=("$arg")
  fi
done

result="$("$TOOL" "${{args[@]}}")"
if [[ "$result" != *"$EXPECTED_SUBSTRING"* ]]; then
  echo "Expected output to contain: $EXPECTED_SUBSTRING"
  echo "Actual output:"
  echo "$result"
  exit 1
fi
"""

def _dotnet_tool_test_impl(ctx):
    tool_info = ctx.attr.tool[DefaultInfo]
    tool = tool_info.files_to_run.executable

    wrapper = ctx.actions.declare_file(ctx.label.name + "_wrapper.sh")
    ctx.actions.write(
        output = wrapper,
        content = TOOL_WRAPPER.format(
            tool = ctx.attr.tool.label.repo_name + "/" + tool.short_path,
            expected_stdout_contains = ctx.attr.expected_stdout_contains.replace('"', '\\"'),
        ),
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = ctx.files.deps)
    runfiles = runfiles.merge(ctx.attr._bash_runfiles[DefaultInfo].default_runfiles)
    runfiles = runfiles.merge(tool_info.default_runfiles)

    return [
        DefaultInfo(
            executable = wrapper,
            runfiles = runfiles,
        ),
    ]

dotnet_tool_test = rule(
    implementation = _dotnet_tool_test_impl,
    test = True,
    doc = "Use a tool to run a test and verify its output.",
    attrs = {
        "tool": attr.label(
            mandatory = True,
            doc = "The dotnet tool to use to run the test.",
            executable = True,
            providers = [DefaultInfo],
            cfg = "exec",
        ),
        "deps": attr.label_list(
            doc = "The dependencies required for the test to run. Makes them available in location substition.",
            default = [],
        ),
        "expected_stdout_contains": attr.string(
            doc = "A string that is expected to be contained in the standard output of the tool execution.",
            default = "",
        ),
        "_bash_runfiles": attr.label(default = "@rules_shell//shell/runfiles"),
    },
)
