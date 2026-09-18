"extensions for bzlmod"

load("@bazel_skylib//lib:collections.bzl", "collections")
load("//dotnet/private:toolchains_repo.bzl", "BOOTSTRAP_TOOLCHAIN_TYPE")
load("//dotnet/private/sdk:pack_repos.bzl", "declare_pack_repos")
load(":repositories.bzl", "dotnet_sdk_repositories", "dotnet_toolchains_repo")

_SDK_NAME = "dotnet"
_BOOTSTRAP_NAME = "dotnet_bootstrap"

# Only rules_dotnet may pin the bootstrap SDK, so that the SDK the user picks
# cannot decide what rules_dotnet's own tools are built with.
_BOOTSTRAP_MODULE = "rules_dotnet"

_VERSION_ATTRS = {
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
                fail("dotnet.bootstrap_toolchain is internal to {}; module '{}' should use dotnet.toolchain instead.".format(
                    _BOOTSTRAP_MODULE,
                    mod.name,
                ))
            if bootstrap_version != None:
                fail("dotnet.bootstrap_toolchain declared twice ({} and {})".format(bootstrap_version, bootstrap.dotnet_version))
            bootstrap_version = bootstrap.dotnet_version

        # One SDK is registered per toolchain type, so a single SDK decides both
        # what everything compiles with and what it compiles against. Modules are
        # processed breadth-first, so the root-most registration wins.
        for toolchain in mod.tags.toolchain:
            if sdk_version == None:
                sdk_version = toolchain.dotnet_version

    # One set of SDK repositories per distinct version, so a bootstrap SDK that
    # matches the user's is downloaded and extracted once and both compile with
    # identical action keys.
    for version in collections.uniq([v for v in [sdk_version, bootstrap_version] if v != None]):
        dotnet_sdk_repositories(version)

    if sdk_version != None:
        dotnet_toolchains_repo(
            name = _SDK_NAME + "_toolchains",
            dotnet_version = sdk_version,
        )

    if bootstrap_version != None:
        dotnet_toolchains_repo(
            name = _BOOTSTRAP_NAME + "_toolchains",
            dotnet_version = bootstrap_version,
            toolchain_type = BOOTSTRAP_TOOLCHAIN_TYPE,
        )

    facts = declare_pack_repos(module_ctx, sdk_version, bootstrap_version)

    metadata = {}
    if hasattr(module_ctx, "facts"):
        metadata["facts"] = facts

    return module_ctx.extension_metadata(reproducible = True, **metadata)

dotnet = module_extension(
    implementation = _toolchain_extension,
    tag_classes = {
        "toolchain": tag_class(
            attrs = _VERSION_ATTRS,
            doc = "The .Net SDK to build with.",
        ),
        "bootstrap_toolchain": tag_class(
            attrs = _VERSION_ATTRS,
            doc = "Internal to rules_dotnet: the SDK that builds the apphost shimmer and the C# compiler worker.",
        ),
    },
)
