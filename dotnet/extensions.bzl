"extensions for bzlmod"

load("//dotnet/private:toolchains_repo.bzl", "BOOTSTRAP_TOOLCHAIN_TYPE")
load("//dotnet/private/sdk:pack_repos.bzl", "declare_pack_repos")
load(":repositories.bzl", "dotnet_register_toolchains")

_DEFAULT_NAME = "dotnet"
_BOOTSTRAP_MODULE = "rules_dotnet"
_BOOTSTRAP_NAME = "dotnet_bootstrap"

_ATTRS = {
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
    sdk_version = None
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
            # One SDK is registered for the toolchain type, so one SDK decides
            # what everything compiles with and which reference packs it
            # compiles against. Modules are processed breadth-first, so the
            # root-most registration wins and any further one is ignored.
            if sdk_version == None:
                sdk_version = toolchain.dotnet_version

    if sdk_version != None:
        dotnet_register_toolchains(
            name = _DEFAULT_NAME,
            dotnet_version = sdk_version,
            register = False,
        )

    if bootstrap_version != None:
        dotnet_register_toolchains(
            name = _BOOTSTRAP_NAME,
            dotnet_version = bootstrap_version,
            register = False,
            toolchain_type = BOOTSTRAP_TOOLCHAIN_TYPE,
        )

    # Each SDK moves only its own pack set, so neither can decide what the other
    # compiles against.
    facts = declare_pack_repos(module_ctx, sdk_version, bootstrap_version)

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
