#! /usr/bin/env bash

set -eou pipefail

# Unset the runfiles related envs to make sure that runfiles work outside of Bazel
export RUNFILES_DIR=""
export JAVA_RUNFILES=""
export RUNFILES_MANIFEST_FILE=""
export RUNFILES_MANIFEST_ONLY=""

TOOLCHAIN_LOCATION=$(dirname "$1")
DOTNET_ROOT="../${TOOLCHAIN_LOCATION#'external/'}/"
export DOTNET_ROOT

tar -xf ./dotnet/private/tests/publish/static_web_assets/tar.tar

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    ./app_to_publish.exe
else
    ./app_to_publish
fi
