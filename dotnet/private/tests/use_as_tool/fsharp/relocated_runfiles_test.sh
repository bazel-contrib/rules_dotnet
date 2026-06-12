#!/usr/bin/env bash
set -euo pipefail

launcher="$(find "$TEST_SRCDIR" -path "*/$1" -print -quit)"
if [[ -z "$launcher" ]]; then
  echo "Could not find launcher matching $1 under $TEST_SRCDIR" >&2
  exit 1
fi
tmp="${TEST_TMPDIR}/relocated"
mkdir -p "$tmp"

cp "$launcher" "$tmp/app"
cp -R "$TEST_SRCDIR" "$tmp/app.runfiles"

"$tmp/app" "$tmp/output"
grep -F "Hello World!" "$tmp/output"
