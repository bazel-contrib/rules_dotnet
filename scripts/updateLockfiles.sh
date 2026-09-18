#! /usr/bin/env bash
set -eou pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_ROOT=$( cd -- "$SCRIPT_DIR/.." &> /dev/null && pwd )

cd "$REPO_ROOT"

while IFS= read -r -d '' dependencies; do
  dir=$( cd -- "$( dirname "$dependencies" )" &> /dev/null && pwd )
  echo "==> ${dir#"$REPO_ROOT"/}"
  bazel run --run_env=BUILD_WORKING_DIRECTORY="$dir" @rules_dotnet//tools/paket -- install
done < <(find . \( -name 'bazel-*' -o -name '.git' \) -prune -o -name paket.dependencies -print0 | sort -z)
