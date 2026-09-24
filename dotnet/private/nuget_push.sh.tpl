#!/usr/bin/env bash
# Pushes the packages of a `nuget_push` target with `dotnet nuget push`.
#
# Arguments given on the command line win over what the target declares: an
# explicit --source or --api-key is passed through and the target's own left
# out. NUGET_API_KEY (and NUGET_SYMBOL_API_KEY) stand in for a missing
# --api-key (--symbol-api-key). Set RULES_DOTNET_NUGET_PUSH_DRY_RUN to print
# the commands instead of running them.

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
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE="1"
export DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE="1"
# HOME and DOTNET_CLI_HOME stay as they are: `dotnet nuget push` reads the
# user's NuGet.Config, API keys and credential providers from there.

dotnet="$(rlocation TEMPLATED_dotnet)"
export DOTNET_ROOT="$(dirname "$dotnet")"

# Resolved before any `cd`; the results are absolute.
packages=TEMPLATED_packages
resolved=()
for package in "${packages[@]}"; do
  resolved+=("$(rlocation "$package")")
done

source_from_target=TEMPLATED_source
push_args=TEMPLATED_push_args
config_file=TEMPLATED_config_file

has_source=false
has_api_key=false
has_symbol_api_key=false
for arg in "$@"; do
  case "$arg" in
    -s|--source|--source=*|--source:*) has_source=true ;;
    -k|--api-key|--api-key=*|--api-key:*) has_api_key=true ;;
    -sk|--symbol-api-key|--symbol-api-key=*|--symbol-api-key:*) has_symbol_api_key=true ;;
  esac
done

args=()
if [[ "$has_source" == false ]]; then
  if [[ -z "$source_from_target" ]]; then
    echo >&2 "nuget_push: no package source. Set \`source\` on the target or pass --source <feed>."
    exit 1
  fi
  args+=(--source "$source_from_target")
fi
if [[ "$has_api_key" == false && -n "${NUGET_API_KEY:-}" ]]; then
  args+=(--api-key "$NUGET_API_KEY")
fi
if [[ "$has_symbol_api_key" == false && -n "${NUGET_SYMBOL_API_KEY:-}" ]]; then
  args+=(--symbol-api-key "$NUGET_SYMBOL_API_KEY")
fi
if [[ -n "$config_file" ]]; then
  args+=(--configfile "$(rlocation "$config_file")")
fi

# `bazel run` starts in the runfiles tree; a relative --source or --configfile
# is meant relative to where the command was typed.
if [[ -n "${BUILD_WORKING_DIRECTORY:-}" ]]; then
  cd "$BUILD_WORKING_DIRECTORY"
fi

# `${array[@]+"${array[@]}"}` rather than `"${array[@]}"`: the latter is an
# unbound variable on an empty array in the bash 3.2 that macOS ships.
for package in "${resolved[@]}"; do
  cmd=("$dotnet" nuget push "$package" ${push_args[@]+"${push_args[@]}"} ${args[@]+"${args[@]}"} "$@")
  if [[ -n "${RULES_DOTNET_NUGET_PUSH_DRY_RUN:-}" ]]; then
    printf '%q ' "${cmd[@]}"
    printf '\n'
    continue
  fi
  "${cmd[@]}"
done
