#! /usr/bin/env bash

set -eou pipefail

# Unset the runfiles related envs to make sure that runfiles work outside of Bazel
export RUNFILES_DIR=""
export JAVA_RUNFILES=""
export RUNFILES_MANIFEST_FILE=""
export RUNFILES_MANIFEST_ONLY=""

tar -xf ./dotnet/private/tests/publish/native_aot/web_tar.tar

# Nothing managed is left to load: ASP.NET Core is compiled in too.
for unwanted in web.dll Microsoft.AspNetCore.dll web.runtimeconfig.json web.deps.json; do
    if [[ -f "./$unwanted" ]]; then
        echo "NativeAOT publish should not contain $unwanted"
        exit 1
    fi
done

./web
