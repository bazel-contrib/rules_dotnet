"Generated"

load(":paket.example_deps.bzl", _example_deps = "example_deps")

def _example_deps_impl(module_ctx):
    _example_deps()
    return module_ctx.extension_metadata(reproducible = True)

example_deps_extension = module_extension(
    implementation = _example_deps_impl,
)
