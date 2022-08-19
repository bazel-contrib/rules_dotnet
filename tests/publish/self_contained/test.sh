#! /usr/bin/env bash

set -eou pipefail

# Unset the runfiles related envs to make sure that runfiles work outside of Bazel
export RUNFILES_DIR=""
export JAVA_RUNFILES=""
export RUNFILES_MANIFEST_FILE=""
export RUNFILES_MANIFEST_ONLY=""

# MacOS/Win do not have readlink -f so we need to do some bash hacking
realpath_macos_win() (
  OURPWD=$PWD
  cd "$(dirname "$1")"
  LINK=$(readlink "$(basename "$1")")
  while [ "$LINK" ]; do
    cd "$(dirname "$LINK")"
    LINK=$(readlink "$(basename "$1")")
  done
  REALPATH="$PWD/$(basename "$1")"
  cd "$OURPWD"
  echo "$REALPATH"
)

# Since we are in the runfiles tree of the sh_test target the binary
# is a symlink to the actual binary. We follow the symlink to the
# actual binary so that we can emulate starting outside runfiles
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    bin=$(readlink -f ./tests/publish/self_contained/self_contained/publish/linux-x64/app_to_publish)
    $bin
elif [[ "$OSTYPE" == "darwin"* ]]; then
    bin=$(realpath_macos_win ./tests/publish/self_contained/self_contained/publish/osx-x64/app_to_publish)
    $bin
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    bin=$(realpath_macos_win ./tests/publish/self_contained/self_contained/publish/win-x64/app_to_publish)
    $bin
else
    echo "Could not figure out which OS is running the test"
    exit 1
fi
