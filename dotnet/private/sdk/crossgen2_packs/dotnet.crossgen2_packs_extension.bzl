"Generated"

load(":dotnet.crossgen2_packs.bzl", _crossgen2_packs = "crossgen2_packs")

def _crossgen2_packs_impl(module_ctx):
    _crossgen2_packs()
    return module_ctx.extension_metadata(reproducible = True)

crossgen2_packs_extension = module_extension(
    implementation = _crossgen2_packs_impl,
)
