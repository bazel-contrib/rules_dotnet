load("@io_bazel_rules_dotnet//dotnet:defs.bzl", "core_binary", "core_library", "core_resource")
load("@io_bazel_rules_dotnet//3rd_party:abstractions.xunit/repo.bzl", "buildall")

framework = "v2.1.502"

buildall(framework)
