#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo >&2 "Usage: $0 /path/to/binary expected_file_type expected_arch"
    exit 1
fi

binary="$1"
expected_file_type="$2"
expected_arches="${@:3}"

out="$(file "$(readlink "${binary}")")"

# Loop over all expected arches and check if the output contains any of them
for expected_arch in ${expected_arches}; do
    if [[ "${out}" == *"${expected_arch}"* ]]; then
        if [[ "${out}" == *"${expected_file_type}"* ]]; then
            exit 0
        fi
    fi
done

echo >&2 "Wrong file type: ${out}"
exit 1

