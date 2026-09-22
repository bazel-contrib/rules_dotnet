#! /usr/bin/env bash
set -eou pipefail

# This wrapper script is used because the C#/F# compilers both embed absolute paths
# into their outputs and those paths are not deterministic. The compilers also
# allow overriding these paths using pathmaps. Since the paths can not be known
# at analysis time we need to override them at execution time.

# The ICU the build carries, if any: the runtime looks the libraries up by name,
# so their directory goes on the loader's path.
if [[ "${1:-}" == --icu=* ]]; then
  export LD_LIBRARY_PATH="$PWD/$(dirname "${1#--icu=}")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  shift
fi

COMPILER="$2"
PATHMAP_FLAG="-pathmap"

# Needed because unfortunately the F# compiler uses a different flag name
if [[ $(basename "$COMPILER") == "fsc.dll" ]]; then
  PATHMAP_FLAG="--pathmap"
fi
PATHMAP="$PATHMAP_FLAG:$PWD=."

# shellcheck disable=SC2145
./"$@" "$PATHMAP"
