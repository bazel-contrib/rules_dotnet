"Generated"

load(":dotnet.runtime_packs.bzl", _runtime_packs = "runtime_packs")

def _runtime_packs_impl(module_ctx):
    _runtime_packs()
    return module_ctx.extension_metadata(reproducible = True)

runtime_packs_extension = module_extension(
    implementation = _runtime_packs_impl,
)
