"Generated"

load(":paket.example_deps.bzl", _example_deps = "example_deps")

def _example_deps_impl(_ctx):
    _example_deps()

example_deps_extension = module_extension(
    implementation = _example_deps_impl,
)
