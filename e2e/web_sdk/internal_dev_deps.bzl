"""Module extension for internal dev_dependency=True setup."""

load("@bazel_ci_rules//:rbe_repo.bzl", "rbe_preconfig")

def _internal_dev_deps_impl(mctx):
    _ = mctx  # @unused

    rbe_preconfig(
        name = "buildkite_config",
        toolchain = "ubuntu1804-bazel-java11",
    )

internal_dev_deps = module_extension(
    implementation = _internal_dev_deps_impl,
    doc = "This extension creates internal rules_dotnet dev dependencies.",
)
