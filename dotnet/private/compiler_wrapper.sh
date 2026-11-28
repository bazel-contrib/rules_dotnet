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

# fsc sizes the PE debug directory from the absolute pdb path before the
# pathmap applies, so the pdb path needs a root whose length does not follow
# the exec root. macOS has no /proc/self/cwd: a symlink in a mktemp directory
# has a fixed-length name, and the pathmap hides its random part.
if [[ $(basename "$COMPILER") == "fsc.dll" ]]; then
  if [[ -d /proc/self/cwd ]]; then
    ROOT=/proc/self/cwd
  else
    LINK_DIR=$(mktemp -d /tmp/dx_fsc.XXXXXXXX)
    trap 'rm -f "$LINK_DIR/r"; rmdir "$LINK_DIR"' EXIT
    ln -s "$PWD" "$LINK_DIR/r"
    ROOT="$LINK_DIR/r"
  fi
  for arg in "$@"; do
    if [[ "$arg" == @* ]]; then
      while IFS= read -r line; do
        if [[ "$line" == --pdb:* && "$line" != --pdb:/* ]]; then
          set -- "$@" "--pdb:$ROOT/${line#--pdb:}"
        fi
      done <"${arg#@}"
    fi
  done
  PATHMAP="$PATHMAP,$ROOT=."
fi

# shellcheck disable=SC2145
./"$@" "$PATHMAP"
