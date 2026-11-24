#! /usr/bin/env bash

# The application checks itself: it round-trips data through zstd, reads the
# name of the method that threw from a stack trace, and finds the runtime's
# contract with debuggers among its own exports.

set -eou pipefail

"$1"
