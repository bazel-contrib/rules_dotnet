#!/usr/bin/env bash

# A quoted here-document, so that the shell expands nothing in the label: a
# target name can contain `"`, `$` and parentheses.
cat >&2 <<'EOF'
ERROR: TEMPLATED_label targets .NET Framework (TEMPLATED_target_framework), which only runs on Windows.
Build it for a Windows platform to run it, or add
    target_compatible_with = ["@platforms//os:windows"]
to it to skip it when building and testing for other platforms.
EOF
exit 1
