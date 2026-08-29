#!/usr/bin/env bash

# Test whether the output of `file` contains a text string.
#
# Usage: test_file_type_contains.sh <filePath> <text>

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
# https://github.com/bazelbuild/bazel/blob/master/tools/bash/runfiles/runfiles.bash
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: runfiles.bash initializer cannot find $f. An executable rule may have forgotten to expose it in the runfiles, or the binary may require RUNFILES_DIR to be set."; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---

set -eou pipefail

# First we check that the executable is of the correct type
binary_path="$(rlocation "$1")"
file --dereference "$binary_path" | grep -q "$2"

# The binary is symlinked to the actual binary so we need to get the actual binary path
# so that we can check the native libraries that are next to it.
binary_path="$(readlink -f "$binary_path")"

# Then we check if the native libraries are also of the correct type
# We have a NuGet package that contains a native library:
find "$(dirname "$binary_path")/runtimes" -type f -name "*.so" -o -name "*.dylib" -o -name "*.dll" | while read native_lib; do
  file --dereference "$native_lib" | grep -q "$2"
done
