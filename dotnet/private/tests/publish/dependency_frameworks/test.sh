#! /usr/bin/env bash

set -eou pipefail

# Unset the runfiles related envs to make sure that runfiles work outside of Bazel
export RUNFILES_DIR=""
export JAVA_RUNFILES=""
export RUNFILES_MANIFEST_FILE=""
export RUNFILES_MANIFEST_ONLY=""

tars=./dotnet/private/tests/publish/dependency_frameworks

app=app
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    app=app.exe
fi

# A shared framework only a dependency references is published and loads.
for publish in self_contained ready_to_run; do
    tar -xf "$tars/${publish}_tar.tar"

    if [[ ! -f "$publish/Microsoft.AspNetCore.Http.Abstractions.dll" ]]; then
        echo "$publish: Microsoft.AspNetCore.App was not published"
        exit 1
    fi

    if ! grep -q '"Microsoft.AspNetCore.App"' "$publish/app.runtimeconfig.json"; then
        echo "$publish: app.runtimeconfig.json does not include Microsoft.AspNetCore.App"
        exit 1
    fi

    output=$("./$publish/$app")
    if [[ "$output" != "Microsoft.AspNetCore.Http.Abstractions"* ]]; then
        echo "$publish: unexpected output: $output"
        exit 1
    fi
done

# A shared framework nothing references is not.
tar -xf "$tars/no_shared_frameworks_tar.tar"
if compgen -G "no_shared_frameworks/Microsoft.AspNetCore*.dll" >/dev/null; then
    echo "no_shared_frameworks: Microsoft.AspNetCore.App was published"
    exit 1
fi
