"extensions for bzlmod"

load("@bazel_skylib//lib:collections.bzl", "collections")
load("//dotnet/private:toolchains_repo.bzl", "BOOTSTRAP_TOOLCHAIN_TYPE")
load("//dotnet/private/sdk:pack_repos.bzl", "declare_pack_repos")
load("//dotnet/private/sdk:releases.bzl", "resolve_sdk", "sdk_fact_key")
load(":repositories.bzl", "dotnet_sdk_repositories", "dotnet_toolchains_repo")

_SDK_NAME = "dotnet"
_BOOTSTRAP_NAME = "dotnet_bootstrap"

# Only rules_dotnet may pin the bootstrap SDK, so that the SDK the user picks
# cannot decide what rules_dotnet's own tools are built with.
_BOOTSTRAP_MODULE = "rules_dotnet"

_DOTNET_VERSION_DOC = """Version of the .Net SDK, such as `11.0.100`.

Any SDK in Microsoft's release metadata can be used. Its archives and their
hashes are looked up there the first time and recorded in `MODULE.bazel.lock`,
after which builds no longer need the metadata."""

_VERSION_ATTRS = {
    "dotnet_version": attr.string(
        doc = _DOTNET_VERSION_DOC,
        mandatory = True,
    ),
}

_TOOLCHAIN_ATTRS = {
    "dotnet_version": attr.string(
        doc = _DOTNET_VERSION_DOC + "\n\nSet this or `global_json`.",
    ),
    "global_json": attr.label(
        doc = """A `global.json` whose `sdk.version` is the version of the .Net SDK.

This lets the `dotnet` CLI and IDEs outside Bazel pin the same SDK as the build.
Bazel uses exactly `sdk.version`: `rollForward` does not apply. Set this or
`dotnet_version`.""",
        allow_single_file = [".json"],
    ),
}

def _toolchain_version(module_ctx, toolchain):
    """The SDK version a toolchain tag names, directly or through its global.json."""
    if bool(toolchain.dotnet_version) == bool(toolchain.global_json):
        fail("dotnet.toolchain needs exactly one of dotnet_version and global_json")
    if toolchain.dotnet_version:
        return toolchain.dotnet_version
    version = json.decode(module_ctx.read(toolchain.global_json)).get("sdk", {}).get("version")
    if not version:
        fail("{} has no sdk.version for dotnet.toolchain to use".format(toolchain.global_json))
    return version

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
                sdk_version = _toolchain_version(module_ctx, toolchain)

    # rules_dotnet registers both itself, so only a module graph without it
    # lacks one.
    if sdk_version == None or bootstrap_version == None:
        fail("The dotnet extension needs {} to declare both of its SDKs.".format(_BOOTSTRAP_MODULE))

    # Release metadata documents by name, shared by every lookup below.
    releases = {}

    # One set of SDK repositories per distinct version, so a bootstrap SDK that
    # matches the user's is downloaded and extracted once and both compile with
    # identical action keys.
    sdks = {}
    for version in collections.uniq([sdk_version, bootstrap_version]):
        sdks[version] = resolve_sdk(module_ctx, version, releases)
        dotnet_sdk_repositories(sdks[version])

    dotnet_toolchains_repo(
        name = _SDK_NAME + "_toolchains",
        dotnet_version = sdk_version,
    )

    dotnet_toolchains_repo(
        name = _BOOTSTRAP_NAME + "_toolchains",
        dotnet_version = bootstrap_version,
        toolchain_type = BOOTSTRAP_TOOLCHAIN_TYPE,
    )

    facts = declare_pack_repos(module_ctx, sdks[sdk_version], sdks[bootstrap_version], releases)
    facts |= {sdk_fact_key(version): sdk.fact for (version, sdk) in sdks.items() if sdk.fact}

    metadata = {}
    if hasattr(module_ctx, "facts"):
        metadata["facts"] = facts

    return module_ctx.extension_metadata(reproducible = True, **metadata)

dotnet = module_extension(
    implementation = _toolchain_extension,
    tag_classes = {
        "toolchain": tag_class(
            attrs = _TOOLCHAIN_ATTRS,
            doc = "The .Net SDK to build with.",
        ),
        "bootstrap_toolchain": tag_class(
            attrs = _VERSION_ATTRS,
            doc = "Internal to rules_dotnet: the SDK that builds the apphost shimmer and the C# compiler worker.",
        ),
    },
)
