#! /usr/bin/env bash
set -eou pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( cd -- "$SCRIPT_DIR/.." &> /dev/null && pwd )

cd "$REPO_ROOT"

# `paket install` restores the projects it updates, and their
# `.paket/Paket.Restore.targets` runs Paket again. It reads the Paket to run from
# this property, so that is this Paket rather than one installed on the machine.
bazel build @rules_dotnet//tools/paket
PaketExePath="$(bazel info execution_root)/$(bazel cquery --output=files @rules_dotnet//tools/paket 2> /dev/null)"
export PaketExePath

while IFS= read -r -d '' dependencies; do
  dir=$( cd -- "$( dirname "$dependencies" )" &> /dev/null && pwd )
  echo "==> ${dir#"$REPO_ROOT"/}"
  bazel run --run_env=BUILD_WORKING_DIRECTORY="$dir" @rules_dotnet//tools/paket -- install
done < <(find . \( -name 'bazel-*' -o -name '.git' \) -prune -o -name paket.dependencies -print0 | sort -z)
