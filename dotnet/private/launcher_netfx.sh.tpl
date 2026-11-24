#!/usr/bin/env bash

echo >&2 "ERROR: TEMPLATED_label targets .NET Framework (TEMPLATED_target_framework), which only runs on Windows."
echo >&2 "Build it for a Windows platform to run it, or add"
echo >&2 "    target_compatible_with = [\"@platforms//os:windows\"]"
echo >&2 "to it to skip it when building and testing for other platforms."
exit 1
