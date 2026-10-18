#!/usr/bin/env bash
# Guards that the bootstrap SDK version the tool build pins matches the one
# rules_dotnet's MODULE.bazel pins via dotnet.bootstrap_toolchain.
set -euo pipefail

# The main repository's runfiles directory is "_main" under bzlmod on some
# Bazel versions and the module name on others; accept both.
root=""
for candidate in "$TEST_SRCDIR/rules_dotnet" "$TEST_SRCDIR/_main"; do
  if [[ -f "$candidate/MODULE.bazel" ]]; then
    root="$candidate"
    break
  fi
done
if [[ -z "$root" ]]; then
  echo "MODULE.bazel not found in the runfiles tree ($TEST_SRCDIR)" >&2
  exit 1
fi

module_bazel="$root/MODULE.bazel"
tool_bzl="$root/dotnet/private/nuget_resolve/tool.bzl"

module_version=$(sed -n 's/^[[:space:]]*dotnet\.bootstrap_toolchain(dotnet_version = "\([^"]*\)").*/\1/p' "$module_bazel")
tool_version=$(sed -n 's/^BOOTSTRAP_SDK_VERSION = "\([^"]*\)".*/\1/p' "$tool_bzl")

if [[ -z "$module_version" ]]; then
  echo "no dotnet.bootstrap_toolchain version found in MODULE.bazel" >&2
  exit 1
fi
if [[ "$module_version" != "$tool_version" ]]; then
  echo "BOOTSTRAP_SDK_VERSION in dotnet/private/nuget_resolve/tool.bzl is $tool_version," >&2
  echo "but MODULE.bazel pins bootstrap_toolchain $module_version." >&2
  echo "Update both, and TOOL_TFM if the TFM band changed." >&2
  exit 1
fi
