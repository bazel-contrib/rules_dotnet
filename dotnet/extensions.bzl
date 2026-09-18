"extensions for bzlmod"

load("//dotnet/private:toolchains_repo.bzl", "BOOTSTRAP_TOOLCHAIN_TYPE")
load("//dotnet/private/sdk:pack_repos.bzl", "declare_pack_repos")
load(":repositories.bzl", "dotnet_register_toolchains")

_DEFAULT_NAME = "dotnet"
_BOOTSTRAP_MODULE = "rules_dotnet"
_BOOTSTRAP_NAME = "dotnet_bootstrap"

_ATTRS = {
    "name": attr.string(
        doc = "Base name for generated repositories",
        default = _DEFAULT_NAME,
    ),
    "dotnet_version": attr.string(
        doc = "Version of the .Net SDK",
    ),
}

_BOOTSTRAP_ATTRS = {
    "dotnet_version": attr.string(
        doc = "Version of the .Net SDK",
        mandatory = True,
    ),
}

def _toolchain_extension(module_ctx):
    registrations = {}
    bootstrap_version = None
    for mod in module_ctx.modules:
        for bootstrap in mod.tags.bootstrap_toolchain:
            if mod.name != _BOOTSTRAP_MODULE:
                fail(
                    "dotnet.bootstrap_toolchain is internal to {}: it pins the SDK that ".format(_BOOTSTRAP_MODULE) +
                    "rules_dotnet builds its own tools with. Module '{}' should use ".format(mod.name) +
                    "dotnet.toolchain instead.",
                )
            if bootstrap_version != None and bootstrap_version != bootstrap.dotnet_version:
                fail("Multiple conflicting bootstrap toolchains declared ({} and {})".format(
                    bootstrap.dotnet_version,
                    bootstrap_version,
                ))
            bootstrap_version = bootstrap.dotnet_version

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

    sdk_versions = dict(registrations)
    if bootstrap_version != None:
        dotnet_register_toolchains(
            name = _BOOTSTRAP_NAME,
            dotnet_version = bootstrap_version,
            register = False,
            toolchain_type = BOOTSTRAP_TOOLCHAIN_TYPE,
        )

        sdk_versions[_BOOTSTRAP_NAME] = bootstrap_version

    facts = declare_pack_repos(module_ctx, sdk_versions)

    metadata = {}
    if hasattr(module_ctx, "facts"):
        metadata["facts"] = facts

    return module_ctx.extension_metadata(reproducible = True, **metadata)

dotnet = module_extension(
    implementation = _toolchain_extension,
    tag_classes = {
        "toolchain": tag_class(attrs = _ATTRS),
        "bootstrap_toolchain": tag_class(
            attrs = _BOOTSTRAP_ATTRS,
            doc = """Internal to rules_dotnet. Used to build internal tools like the apphost shimmer and the C# compiler worker.""",
        ),
    },
)
