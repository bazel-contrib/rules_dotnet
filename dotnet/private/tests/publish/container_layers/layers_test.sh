#! /usr/bin/env bash

# Stacks image layers the way a container runtime does, checks them against
# what rules_img packs from the publish in one layer and against the publish
# directory, and runs the application from them.
#
# Usage: layers_test.sh <publish executable> <single layer> <layer>...

set -eou pipefail

export LC_ALL=C

publish_dir=$(dirname "$1")
executable=$(basename "$1")
single_layer=$2
shift 2

stacked="${TEST_TMPDIR}/stacked"
single="${TEST_TMPDIR}/single"
mkdir -p "$stacked" "$single"

for layer in "$@"; do
    tar -xzf "$layer" -C "$stacked"
done

tar -xzf "$single_layer" -C "$single"

if [[ "$(ls -A "$stacked")" != "app" ]]; then
    echo "Expected the layers to hold nothing but /app, found: $(ls -A "$stacked")"
    exit 1
fi

# The same files, the runfiles tree included. Only the repository mappings
# differ: the layers carry the binary's, which has to hold every row of the
# publish's that rules_img carries.
diff -r -x "_repo_mapping" -x "*.repo_mapping" "$stacked" "$single"

for mapping in "app/$executable.repo_mapping" "app/$executable.runfiles/_repo_mapping"; do
    if [[ ! -f "$stacked/$mapping" ]]; then
        echo "The layers hold no $mapping"
        exit 1
    fi

    missing=$(comm -13 <(sort "$stacked/$mapping") <(sort "$single/$mapping"))

    if [[ -n "$missing" ]]; then
        echo "The layers' $mapping lacks:"
        echo "$missing"
        exit 1
    fi
done

# The publish directory Bazel hands the test has no runfiles tree or
# repository mapping beside the executable.
diff -r -x "*.runfiles" -x "*.repo_mapping" "$stacked/app" "$publish_dir"

# Started the way a container starts it: from outside the runfiles tree, with
# none of Bazel's runfiles variables set, so that the application can only find
# its data files through the tree and the mapping the layers carry.
unset RUNFILES_DIR JAVA_RUNFILES RUNFILES_MANIFEST_FILE RUNFILES_MANIFEST_ONLY
cd "$TEST_TMPDIR"

"$stacked/app/$executable"
