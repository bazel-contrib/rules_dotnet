"Generated"

load(":paket.paket2bazel_dependencies.bzl", _paket2bazel_dependencies = "paket2bazel_dependencies")

def _paket2bazel_dependencies_impl(_ctx):
    _paket2bazel_dependencies()

paket2bazel_dependencies_extension = module_extension(
    implementation = _paket2bazel_dependencies_impl,
)
