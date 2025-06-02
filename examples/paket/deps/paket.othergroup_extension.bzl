"Generated"

load(":paket.othergroup.bzl", _othergroup = "othergroup")

def _othergroup_impl(module_ctx):
    _othergroup()
    return module_ctx.extension_metadata(reproducible = True)

othergroup_extension = module_extension(
    implementation = _othergroup_impl,
)
