"extensions for bzlmod"

load(":repositories.bzl", "dotnet_register_toolchains")

_DEFAULT_NAME = "dotnet"

_ATTRS = {
    "name": attr.string(
        doc = "Base name for generated repositories",
        default = _DEFAULT_NAME,
    ),
    "dotnet_version": attr.string(
        doc = "Version of the .Net SDK",
    ),
}

def _toolchain_extension(module_ctx):
    registrations = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name in registrations.keys():
                if toolchain.name == _DEFAULT_NAME:
                    # Prioritize the root-most registration of the default dotnet toolchain version and
                    # ignore any further registrations (modules are processed breadth-first)
                    continue
                if toolchain.dotnet_version == registrations[toolchain.name]:
                    # No problem to register a matching toolchain twice
                    continue
                fail("Multiple conflicting toolchains declared for name {} ({} and {})".format(
                    toolchain.name,
                    toolchain.dotnet_version,
                    registrations[toolchain.name],
                ))
            else:
                registrations[toolchain.name] = toolchain.dotnet_version
    for name, dotnet_version in registrations.items():
        dotnet_register_toolchains(
            name = name,
            dotnet_version = dotnet_version,
            register = False,
        )

dotnet = module_extension(
    implementation = _toolchain_extension,
    tag_classes = {
        "toolchain": tag_class(attrs = _ATTRS),
    },
)
