#! /usr/bin/env bash

# The application checks itself: it round-trips data through zstd, and reads
# the name of the method that threw from a stack trace.

set -eou pipefail

"$1"
