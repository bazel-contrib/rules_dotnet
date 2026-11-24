"""The `dotnet` module extension, which registers the .NET SDK to build with."""

load("@bazel_skylib//lib:collections.bzl", "collections")
load("//dotnet/private:toolchains_repo.bzl", "BOOTSTRAP_TOOLCHAIN_TYPE")
load("//dotnet/private/sdk:global_json.bzl", "global_json_sdk_version")
load("//dotnet/private/sdk:pack_repos.bzl", "declare_pack_repos")
load("//dotnet/private/sdk:releases.bzl", "resolve_sdk", "sdk_fact_key")
load(":repositories.bzl", "dotnet_sdk_repositories", "dotnet_toolchains_repo")

# Only rules_dotnet may pin the bootstrap SDK, so that the SDK the user picks
# cannot decide what rules_dotnet's own tools are built with.
_BOOTSTRAP_MODULE = "rules_dotnet"

_DOTNET_VERSION_DOC = """Version of the .Net SDK, such as `11.0.100`.

Any SDK from .NET 6 onwards in Microsoft's release metadata can be used,
previews included. Its archives and their hashes are looked up there the first
time and recorded in `MODULE.bazel.lock`, after which builds no longer need the
metadata."""

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
Bazel uses exactly `sdk.version`: `rollForward` and `allowPrerelease` do not
apply. Comments and trailing commas are allowed, as the `dotnet` CLI allows
them. Set this or `dotnet_version`.""",
        allow_single_file = [".json"],
    ),
}

def _check_toolchain(mod, toolchain):
    """Fails unless a toolchain tag names its SDK version in exactly one way."""
    if bool(toolchain.dotnet_version) == bool(toolchain.global_json):
        fail("dotnet.toolchain in module '{}' needs exactly one of dotnet_version and global_json".format(mod.name))

def _toolchain_version(module_ctx, toolchain):
    """The SDK version a toolchain tag names, directly or through its global.json."""
    if toolchain.dotnet_version:
        return toolchain.dotnet_version

    if not module_ctx.path(toolchain.global_json).exists:
        fail("{}, the global_json of dotnet.toolchain, does not exist".format(toolchain.global_json))

    return global_json_sdk_version(module_ctx.read(toolchain.global_json), str(toolchain.global_json))

def _registered_versions(module_ctx):
    """Returns the (SDK, bootstrap SDK) versions the module graph registers."""
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
        # what everything compiles with and what it compiles against. Modules
        # come breadth-first, so the root-most registration wins. Every tag is
        # checked, so a module's mistake shows wherever it is used, but only
        # the winning tag's global.json is read.
        for toolchain in mod.tags.toolchain:
            _check_toolchain(mod, toolchain)
            if sdk_version == None:
                sdk_version = _toolchain_version(module_ctx, toolchain)

    # rules_dotnet registers both itself, so only a module graph without it
    # lacks one.
    if sdk_version == None or bootstrap_version == None:
        fail("The dotnet extension needs {} to declare both of its SDKs.".format(_BOOTSTRAP_MODULE))

    return (sdk_version, bootstrap_version)

def _toolchain_extension(module_ctx):
    (sdk_version, bootstrap_version) = _registered_versions(module_ctx)

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
        name = "dotnet_toolchains",
        dotnet_version = sdk_version,
    )

    dotnet_toolchains_repo(
        name = "dotnet_bootstrap_toolchains",
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
            doc = """The .Net SDK to build with.

When several modules declare one, the module closest to the root wins, so the
root module's choice overrides the default rules_dotnet declares.""",
        ),
        "bootstrap_toolchain": tag_class(
            attrs = _VERSION_ATTRS,
            doc = "Internal to rules_dotnet: the SDK that builds rules_dotnet's own tools.",
        ),
    },
)
