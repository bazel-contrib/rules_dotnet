#! /usr/bin/env bash

set -eou pipefail

# Unset the runfiles related envs to make sure that runfiles work outside of Bazel
export RUNFILES_DIR=""
export JAVA_RUNFILES=""
export RUNFILES_MANIFEST_FILE=""
export RUNFILES_MANIFEST_ONLY=""

tars=./dotnet/private/tests/publish/dependency_frameworks

app=app
plain_app=plain_app
if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    app=app.exe
    plain_app=plain_app.exe
fi

# Nothing references Microsoft.WindowsDesktop.App, which the runtime packs of a
# Windows publish that takes every shared framework include.
no_windows_desktop() {
    local publish=$1

    for assembly in System.Windows.Forms.dll PresentationFramework.dll; do
        if [[ -f "$publish/$assembly" ]]; then
            echo "$publish: Microsoft.WindowsDesktop.App was published"
            exit 1
        fi
    done
}

# A shared framework only a dependency references is published and loads.
ships_dependency_framework() {
    local publish=$1

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
}

# A framework-dependent publish ships no framework, but asks for the one only a
# dependency references.
asks_for_dependency_framework() {
    local publish=$1

    if compgen -G "$publish/Microsoft.AspNetCore*.dll" >/dev/null; then
        echo "$publish: Microsoft.AspNetCore.App was published"
        exit 1
    fi

    if ! grep -q '"Microsoft.AspNetCore.App"' "$publish/app.runtimeconfig.json"; then
        echo "$publish: app.runtimeconfig.json does not ask for Microsoft.AspNetCore.App"
        exit 1
    fi
}

# A shared framework nothing references is not published.
ships_no_shared_framework() {
    local publish=$1

    if compgen -G "$publish/Microsoft.AspNetCore*.dll" >/dev/null; then
        echo "$publish: Microsoft.AspNetCore.App was published"
        exit 1
    fi

    output=$("./$publish/$plain_app")
    if [[ "$output" != "PlainLib"* ]]; then
        echo "$publish: unexpected output: $output"
        exit 1
    fi
}

for publish in "$@"; do
    tar -xf "$tars/${publish}_tar.tar"

    case "$publish" in
    framework_dependent_*) asks_for_dependency_framework "$publish" ;;
    no_shared_frameworks) ships_no_shared_framework "$publish" ;;
    *) ships_dependency_framework "$publish" ;;
    esac

    no_windows_desktop "$publish"
done
