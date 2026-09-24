#!/usr/bin/env bash
# A workspace status command, for the `version_file` of `:formatting_nightly`:
#
#   bazel build --workspace_status_command=nuget_pack/version.sh //nuget_pack:formatting_nightly
#
# Every line is a key and a value. A key starting with `STABLE_` is one Bazel
# reruns actions for when it changes, which is what a package version has to be.
set -euo pipefail
echo "STABLE_PACKAGE_VERSION 1.0.0-nightly.$(date -u +%Y%m%d)"
