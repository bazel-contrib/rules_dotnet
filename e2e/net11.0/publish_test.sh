#!/usr/bin/env bash
set -euo pipefail

archive="$PWD/$1"
dotnet_root="$(cd "$TEST_SRCDIR/$(dirname "${2#external/}")" && pwd)"
executable="$3"
mode="$4"

case "$OSTYPE" in
    msys*|cygwin*|win32*)
        dotnet_root="$(cygpath -w "$dotnet_root")"
        executable="$executable.exe"
        ;;
    linux*|darwin*) ;;
    *)
        echo "Unsupported publish test host: $OSTYPE" >&2
        exit 1
        ;;
esac

tar -xf "$archive" -C "$TEST_TMPDIR"
cd "$TEST_TMPDIR"

unset RUNFILES_DIR JAVA_RUNFILES RUNFILES_MANIFEST_FILE RUNFILES_MANIFEST_ONLY
unset DOTNET_ROOT_X64 DOTNET_ROOT_ARM64 DOTNET_ROOT_X86
unset DOTNET_ROLL_FORWARD DOTNET_ROLL_FORWARD_TO_PRERELEASE
if [[ "$mode" == "framework_dependent" ]]; then
    export DOTNET_ROOT="$dotnet_root"
else
    export DOTNET_ROOT="$TEST_TMPDIR/no-installed-runtime"
fi

test -f "$3.runtimeconfig.json"
test -f "$3.deps.json"
output=$("./$executable")
printf '%s\n' "$output"
[[ "$output" == *"runtime=11"* ]]

set +e
"./$executable" 23
status=$?
set -e
if [[ "$status" != 23 ]]; then
    echo "Expected application exit code 23, got $status" >&2
    exit 1
fi
