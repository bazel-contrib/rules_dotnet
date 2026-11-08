#! /usr/bin/env bash

set -eou pipefail

# Unset the runfiles related envs to make sure that runfiles work outside of Bazel
export RUNFILES_DIR=""
export JAVA_RUNFILES=""
export RUNFILES_MANIFEST_FILE=""
export RUNFILES_MANIFEST_ONLY=""

tar -xvf ./dotnet/private/tests/publish/single_file/tar.tar

# Managed assemblies must be bundled inside the executable rather than loose on disk.
if [[ -f "./app_to_publish.dll" ]]; then
    echo "Expected app_to_publish.dll to be bundled inside the single-file executable"
    exit 1
fi

if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
    export DOTNET_BUNDLE_EXTRACT_BASE_DIR="${TEST_TMPDIR}/bundle_extract"
    ./app_to_publish
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    ./app_to_publish.exe
else
    echo "Could not figure out which OS is running the test"
    exit 1
fi
