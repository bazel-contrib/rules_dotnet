bazel run //tools/nuget2bazel:nuget2bazel.exe -- add -p c:/rules_dotnet/dotnet/private/deps -b xunit.bzl -c xunit.json -i -m xunit.console xunit.runner.console 2.4.1
bazel run //tools/nuget2bazel:nuget2bazel.exe -- add -p c:/rules_dotnet/dotnet/private/deps -b xunit.bzl -c xunit.json -i xunit.assert 2.4.1
bazel run //tools/nuget2bazel:nuget2bazel.exe -- add -p c:/rules_dotnet/dotnet/private/deps -b xunit.bzl -c xunit.json -i xunit 2.4.1
