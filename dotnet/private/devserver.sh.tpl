#!/usr/bin/env bash
# Runs the SDK's Blazor WebAssembly development server against the application
# assembled beside it. `--applicationpath` names the assembly; the server finds
# the endpoint manifest and the `wwwroot` as its siblings.

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---
runfiles_export_envvars

set -o pipefail -o errexit -o nounset

export DOTNET_MULTILEVEL_LOOKUP="false"
export DOTNET_NOLOGO="1"
export DOTNET_CLI_TELEMETRY_OPTOUT="1"
export DOTNET_ROOT="$(dirname "$(rlocation TEMPLATED_dotnet)")"

# The server resolves `wwwroot` against the content root, and would otherwise
# take that from the working directory. The served directory need not sit beside
# the application, so the content root is derived from it rather than assumed.
exec "$(rlocation TEMPLATED_dotnet)" exec "$(rlocation TEMPLATED_devserver)" \
  --applicationpath "$(rlocation TEMPLATED_application)" \
  --contentroot "$(dirname "$(rlocation TEMPLATED_wwwroot)")" "$@"
