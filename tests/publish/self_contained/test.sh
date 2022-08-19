#! /usr/bin/env bash

set -eou pipefail

# Unset the runfiles related envs to make sure that runfiles work outside of Bazel
export RUNFILES_DIR=""
export JAVA_RUNFILES=""
export RUNFILES_MANIFEST_FILE=""
export RUNFILES_MANIFEST_ONLY=""

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    ./tests/publish/self_contained/self_contained/publish/linux-x64/app_to_publish
elif [[ "$OSTYPE" == "darwin"* ]]; then
    ./tests/publish/self_contained/self_contained/publish/osx-x64/app_to_publish
elif [[ "$OSTYPE" == "cygwin" ]]; then
    ./tests/publish/self_contained/self_contained/publish/win-x64/app_to_publish
elif [[ "$OSTYPE" == "msys" ]]; then
    ./tests/publish/self_contained/self_contained/publish/win-x64/app_to_publish
elif [[ "$OSTYPE" == "win32" ]]; then
    ./tests/publish/self_contained/self_contained/publish/win-x64/app_to_publish
else
    echo "Could not figure out which OS is running the test"
    exit 1
fi

