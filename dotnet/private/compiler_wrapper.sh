#! /usr/bin/env bash
set -eou pipefail

# This wrapper script is used because the C#/F# compilers both embed absolute paths
# into their outputs and those paths are not deterministic. The compilers also
# allow overriding these paths using pathmaps. Since the paths can not be known
# at analysis time we need to override them at execution time.

COMPILER="$2"
PATHMAP_FLAG="-pathmap"

# Needed because unfortunately the F# compiler uses a different flag name
if [[ $(basename "$COMPILER") == "fsc.dll" ]]; then
  PATHMAP_FLAG="--pathmap"
fi
PATHMAP="$PATHMAP_FLAG:$PWD=."

if [[ -n "${RULES_DOTNET_ANALYZER_CONFIG_TEMPLATE:-}" ]]; then
  ANALYZER_CONFIG=$(mktemp "${TMPDIR:-/tmp}/rules-dotnet-analyzer-config.XXXXXX")
  RESPONSE_FILE=$(mktemp "${TMPDIR:-/tmp}/rules-dotnet-response.XXXXXX")
  trap 'rm -f "$ANALYZER_CONFIG" "$RESPONSE_FILE"' EXIT
  ESCAPED_EXEC_ROOT=$(printf '%s' "$PWD" | sed 's/[&|\\]/\\&/g')
  sed "s|__RULES_DOTNET_EXEC_ROOT__|$ESCAPED_EXEC_ROOT|g" "$RULES_DOTNET_ANALYZER_CONFIG_TEMPLATE" > "$ANALYZER_CONFIG"
  RESPONSE_FILE_INPUT=${3#@}
  sed "s|__RULES_DOTNET_EXEC_ROOT__|$ESCAPED_EXEC_ROOT|g" "$RESPONSE_FILE_INPUT" > "$RESPONSE_FILE"
  ./"$1" "$2" "@$RESPONSE_FILE" "$PATHMAP" "/analyzerconfig:$ANALYZER_CONFIG"
else
  ./"$@" "$PATHMAP"
fi
