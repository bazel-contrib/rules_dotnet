#!/usr/bin/env bash
# Checks what `nuget_push` runs, and that it can push into a folder feed.
#
# Usage: push_test.sh <push launcher> <launcher with no source>

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
# https://github.com/bazelbuild/bazel/blob/master/tools/bash/runfiles/runfiles.bash
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: runfiles.bash initializer cannot find $f. An executable rule may have forgotten to expose it in the runfiles, or the binary may require RUNFILES_DIR to be set."; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---
runfiles_export_envvars

set -euo pipefail

launcher="$(rlocation "$1")"
launcher_no_source="$(rlocation "$2")"

# Nothing of the machine's own .NET state is read or written.
export HOME="$TEST_TMPDIR/home"
export DOTNET_CLI_HOME="$HOME"
export NUGET_PACKAGES="$TEST_TMPDIR/nuget"
mkdir -p "$HOME"

run_launcher() {
  case "$OSTYPE" in
    msys*|cygwin*) cmd //c "$(cygpath -w "$1")" "${@:2}" ;;
    *) "$@" ;;
  esac
}

fail() {
  echo >&2 "FAIL: $1"
  echo >&2 "$2"
  exit 1
}

# 1. The target's source and flags, and the API key from the environment.
output="$(RULES_DOTNET_NUGET_PUSH_DRY_RUN=1 NUGET_API_KEY=SECRET run_launcher "$launcher")"
[[ "$output" == *"nuget push"* ]] || fail "dry run does not push" "$output"
[[ "$output" == *"RulesDotnet.Tests.Lib.1.2.3-beta.1.nupkg"* ]] || fail "dry run does not name the package" "$output"
[[ "$output" == *"--source https://example.invalid/never-used/v3/index.json"* ]] || fail "dry run lacks the target's source" "$output"
[[ "$output" == *"--skip-duplicate"* ]] || fail "dry run lacks --skip-duplicate" "$output"
[[ "$output" == *"--timeout 42"* ]] || fail "dry run lacks --timeout" "$output"
[[ "$output" == *"--api-key SECRET"* ]] || fail "dry run lacks the API key from the environment" "$output"

# 2. Explicit arguments win, and the target's are left out.
output="$(RULES_DOTNET_NUGET_PUSH_DRY_RUN=1 NUGET_API_KEY=SECRET run_launcher "$launcher" --api-key OTHER --source /elsewhere)"
[[ "$output" == *"--api-key OTHER"* ]] || fail "explicit --api-key was dropped" "$output"
[[ "$output" != *"SECRET"* ]] || fail "the environment's API key was passed alongside an explicit one" "$output"
[[ "$output" == *"--source /elsewhere"* ]] || fail "explicit --source was dropped" "$output"
[[ "$output" != *"example.invalid"* ]] || fail "the target's source was passed alongside an explicit one" "$output"
[[ "$(grep -o -- "--source" <<<"$output" | wc -l)" -eq 1 ]] || fail "--source passed more than once" "$output"

# 3. Without a source anywhere the launcher refuses, before running dotnet.
if output="$(RULES_DOTNET_NUGET_PUSH_DRY_RUN=1 run_launcher "$launcher_no_source" 2>&1)"; then
  fail "a push with no source succeeded" "$output"
fi
[[ "$output" == *"no package source"* ]] || fail "a push with no source gave the wrong message" "$output"

# 4. A real push, into a folder: no network, and the whole SDK has to be in the runfiles.
feed="$TEST_TMPDIR/feed"
mkdir -p "$feed"
output="$(run_launcher "$launcher" --source "$feed" 2>&1)" || fail "pushing to a folder feed failed" "$output"
count="$(find "$feed" -name '*.nupkg' | wc -l)"
[[ "$count" -eq 1 ]] || fail "expected one package in the feed, found $count" "$(find "$feed")"

echo "PASS"
