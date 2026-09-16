"extensions for bzlmod"

load("//dotnet/private/sdk:pack_repos.bzl", "declare_pack_repos")
load(":host.bzl", "dotnet_register_host_toolchains")
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
    "host": attr.bool(
        doc = "Use a preinstalled toolchain if available",
        default = False,
    ),
}

def _toolchain_extension(module_ctx):
    registrations = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name in registrations.keys():
                registration = registrations[toolchain.name]
                if toolchain.name == _DEFAULT_NAME:
                    # Prioritize the root-most registration of the default dotnet toolchain version and
                    # ignore any further registrations (modules are processed breadth-first)
                    continue
                if toolchain.dotnet_version == registration.dotnet_version and toolchain.host == registration.host:
                    # No problem to register a matching toolchain twice
                    continue
                fail("Multiple conflicting toolchains declared for name {} ({} host={} and {} host={})".format(
                    toolchain.name,
                    toolchain.dotnet_version,
                    toolchain.host,
                    registration.dotnet_version,
                    registration.host,
                ))
            else:
                registrations[toolchain.name] = struct(
                    dotnet_version = toolchain.dotnet_version,
                    host = toolchain.host,
                )

    for name, registration in registrations.items():
        if registration.host:
            dotnet_register_host_toolchains(
                name = name,
                dotnet_version = registration.dotnet_version,
            )
        else:
            dotnet_register_toolchains(
                name = name,
                dotnet_version = registration.dotnet_version,
                register = False,
            )

    facts = declare_pack_repos(module_ctx, {
        name: registration.dotnet_version
        for (name, registration) in registrations.items()
    })

    metadata = {}
    if hasattr(module_ctx, "facts"):
        metadata["facts"] = facts

    return module_ctx.extension_metadata(reproducible = True, **metadata)

dotnet = module_extension(
    implementation = _toolchain_extension,
    tag_classes = {
        "toolchain": tag_class(attrs = _ATTRS),
    },
)
