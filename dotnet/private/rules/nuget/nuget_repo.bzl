"NuGet Repo"

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//dotnet/private/rules/nuget:nuget_archive.bzl", "nuget_archive")

_GLOBAL_NUGET_PREFIX = "nuget"

def _deps_select_statment(ctx, deps):
    if len(deps) == 0:
        return "\"//conditions:default\": []"

    return ",".join(["\n    \"@rules_dotnet//dotnet:tfm_{tfm}\": [{deps_list}]".format(tfm = tfm, deps_list = ",".join(["\"@{nuget_repo_name}//{dep_name}\"".format(dep_name = d.lower(), nuget_repo_name = ctx.attr.repo_name.lower()) for d in tfm_deps])) for (tfm, tfm_deps) in deps.items()])

def _nuget_repo_impl(ctx):
    for package in ctx.attr.packages:
        package = json.decode(package)
        name = package["name"]
        id = package["id"]
        version = package["version"]
        sha512 = package["sha512"]
        deps = package["dependencies"]

        targeting_pack_overrides = ctx.attr.targeting_pack_overrides[id.lower()]
        framework_list = ctx.attr.framework_list[id.lower()]

        ctx.template("{}/{}/BUILD.bazel".format(id.lower(), version), ctx.attr._template, {
            "{PREFIX}": _GLOBAL_NUGET_PREFIX,
            "{ID}": id,
            "{ID_LOWER}": id.lower(),
            "{VERSION}": version,
            "{DEPS}": _deps_select_statment(ctx, deps),
            "{TARGETING_PACK_OVERRIDES}": json.encode({override.lower().split("|")[0]: override.lower().split("|")[1] for override in targeting_pack_overrides}),
            "{FRAMEWORK_LIST}": json.encode({override.lower().split("|")[0]: override.lower().split("|")[1] for override in framework_list}),
            "{SHA_512}": sha512,
        })

        # currently we only support one version of a package
        ctx.file("{}/BUILD.bazel".format(name.lower()), r"""package(default_visibility = ["//visibility:public"])
alias(name = "{name}", actual = "//{id}/{version}")
alias(name = "content_files", actual = "@{prefix}.{id}.v{version}//:content_files")
alias(name = "files", actual = "@{prefix}.{id}.v{version}//:files")
""".format(prefix = _GLOBAL_NUGET_PREFIX, name = name.lower(), id = id.lower(), version = version))

_nuget_repo = repository_rule(
    _nuget_repo_impl,
    attrs = {
        "repo_name": attr.string(
            mandatory = True,
            doc = "The apparent name of the repo. This is needed because in bzlmod, the name attribute becomes the canonical name.",
        ),
        "packages": attr.string_list(
            mandatory = True,
            allow_empty = False,
        ),
        "targeting_pack_overrides": attr.string_list_dict(
            allow_empty = True,
            default = {},
        ),
        "framework_list": attr.string_list_dict(
            allow_empty = True,
            default = {},
        ),
        "_template": attr.label(
            default = "//dotnet/private/rules/nuget:template.BUILD",
        ),
    },
)

# buildifier: disable=function-docstring
def nuget_repo(name, packages):
    # TODO: Add docs
    # scaffold individual nuget archives
    for package in packages:
        id = package["id"].lower()
        version = package["version"].lower()

        # maybe another nuget_repo has the same nuget package dependency
        maybe(
            nuget_archive,
            name = "{}.{}.v{}".format(_GLOBAL_NUGET_PREFIX, id, version),
            sources = package["sources"],
            netrc = package.get("netrc", None),
            id = id,
            version = version,
            sha512 = package["sha512"],
        )

    # scaffold transitive @name// dependency tree
    _nuget_repo(
        name = name,
        repo_name = name,
        packages = [json.encode(package) for package in packages],
        targeting_pack_overrides = {"{}".format(package["id"].lower()): package["targeting_pack_overrides"] for package in packages},
        framework_list = {"{}".format(package["id"].lower()): package["framework_list"] for package in packages},
    )
