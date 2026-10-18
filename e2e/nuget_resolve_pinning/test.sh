#!/usr/bin/env bash
# Proves the repin flow:
#  1. a lock file whose input hash no longer matches the tag fails the build
#     with the repin instructions;
#  2. `REPIN=1 bazel run @nuget.net10.0//:pin` refreshes the lock file;
#  3. the build succeeds again.
# Restores MODULE.bazel and nuget_resolve.json on exit.
set -euo pipefail
cd "$(dirname "$0")"

backup_dir="$(mktemp -d)"
cp MODULE.bazel nuget_resolve.json "$backup_dir"/

cleanup() {
  cp "$backup_dir/MODULE.bazel" MODULE.bazel
  cp "$backup_dir/nuget_resolve.json" nuget_resolve.json
  rm -rf "$backup_dir" build.log
}
trap cleanup EXIT

echo "--- baseline: the pinned build succeeds"
bazel build //...

echo "--- make the lock stale: add Serilog to the packages"
sed -i 's|"Newtonsoft.Json": "13.0.3"|"Newtonsoft.Json": "13.0.3",\n        "Serilog": "4.0.0"|' MODULE.bazel
grep -q '"Serilog": "4.0.0"' MODULE.bazel || {
  echo "FAIL: the stale-ization edit did not apply" >&2
  exit 1
}

echo "--- the build must now fail with the repin instructions"
if bazel build //... 2> build.log; then
  echo "FAIL: expected the build to fail with a stale lock file" >&2
  exit 1
fi
grep -q "REPIN=1 bazel run @nuget.net10.0//:pin" build.log || {
  echo "FAIL: the failure did not name the repin command" >&2
  cat build.log >&2
  exit 1
}

echo "--- repin"
REPIN=1 bazel run @nuget.net10.0//:pin

echo "--- the lock file now contains Serilog and the build succeeds"
grep -q '"Serilog"' nuget_resolve.json
bazel build //...

echo "PASS"
