"""
Rules to load all the .NET SDK & framework dependencies of rules_dotnet.
"""

load("//dotnet/private:toolchains_repo.bzl", "PLATFORMS", "toolchains_repo")
load("//dotnet/private/sdk:versions.bzl", "TOOL_VERSIONS")

########
# Remaining content of the file is only used to support toolchains.
########
_DOC = "Fetch external tools needed for dotnet toolchain"
_ATTRS = {
    "dotnet_version": attr.string(mandatory = True, values = TOOL_VERSIONS.keys()),
    "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
}

_TOOLCHAIN_BUILD_TEMPLATE = Label("//dotnet/private/sdk:toolchain.build.tmpl")

_DOTNET_REPOSITORY_ALIAS_TARGETS = [
    "csc_binary",
    "runtime",
    "host_model",
    "fsc_binary",
    "targeting_pack_default_refs",
    "targeting_pack_web_refs",
    "runtime_pack_default_libs",
    "runtime_pack_default_native",
    "runtime_pack_web_libs",
    "runtime_pack_web_native",
    "wasm_workload_files",
    "dotnet_toolchain",
]

def _versioned_repository_name(name, dotnet_version):
    return "{}_{}".format(name, dotnet_version)

def _host_platform(repository_ctx):
    os_name = repository_ctx.os.name.lower()
    arch = repository_ctx.os.arch.lower()

    if "linux" in os_name:
        os_part = "unknown-linux-gnu"
    elif "mac" in os_name or "darwin" in os_name:
        os_part = "apple-darwin"
    elif "windows" in os_name:
        os_part = "pc-windows-msvc"
    else:
        fail("Unsupported host OS for wasm workload repository: {}".format(repository_ctx.os.name))

    if arch in ["x86_64", "amd64"]:
        arch_part = "x86_64"
    elif arch in ["aarch64", "arm64"]:
        arch_part = "aarch64" if "apple" in os_part else "arm64"
    else:
        fail("Unsupported host architecture for wasm workload repository: {}".format(repository_ctx.os.arch))

    platform = "{}-{}".format(arch_part, os_part)
    if platform not in PLATFORMS:
        fail("No .NET SDK platform mapping for host platform {}".format(platform))
    return platform

def _dotnet_executable(repository_ctx):
    if repository_ctx.path("dotnet.exe").exists:
        return "dotnet.exe"
    return "./dotnet"

def _install_wasm_tools(repository_ctx):
    repository_ctx.report_progress("Installing wasm-tools workload")
    repository_ctx.file("workload_tmp/.keep", "")
    result = repository_ctx.execute(
        [
            _dotnet_executable(repository_ctx),
            "workload",
            "install",
            "wasm-tools",
            "--skip-manifest-update",
            "--temp-dir",
            "workload_tmp",
            "--verbosity",
            "minimal",
        ],
        timeout = 1800,
        environment = {
            "DOTNET_CLI_HOME": str(repository_ctx.path(".dotnet_home")),
            "DOTNET_MULTILEVEL_LOOKUP": "0",
            "DOTNET_NOLOGO": "1",
            "DOTNET_ROOT": str(repository_ctx.path(".")),
            "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
        },
    )
    repository_ctx.delete("workload_tmp")
    repository_ctx.delete(".dotnet_home")

    if result.return_code != 0:
        fail("Failed to install wasm-tools workload into external .NET SDK repository:\n{}\n{}".format(result.stdout, result.stderr))

def _write_wasm_workload_build(repository_ctx):
    dotnet_executable = "dotnet.exe" if repository_ctx.path("dotnet.exe").exists else "dotnet"
    repository_ctx.file("BUILD.bazel", """
package(default_visibility = ["//visibility:public"])

exports_files(["{dotnet_executable}"])

filegroup(
    name = "wasm_workload_files",
    srcs = glob(["**/*"], exclude = ["BUILD.bazel"], allow_empty = False),
)
""".format(dotnet_executable = dotnet_executable))

def _dotnet_repo_impl(repository_ctx):
    url = TOOL_VERSIONS[repository_ctx.attr.dotnet_version][repository_ctx.attr.platform]["url"]
    repository_ctx.download_and_extract(
        url = url,
        integrity = TOOL_VERSIONS[repository_ctx.attr.dotnet_version][repository_ctx.attr.platform]["hash"],
    )

    repository_ctx.template(
        "BUILD.bazel",
        _TOOLCHAIN_BUILD_TEMPLATE,
        substitutions = {
            "{sdk_version}": repository_ctx.attr.dotnet_version,
            "{runtime_version}": TOOL_VERSIONS[repository_ctx.attr.dotnet_version]["runtimeVersion"],
            "{runtime_tfm}": TOOL_VERSIONS[repository_ctx.attr.dotnet_version]["runtimeTfm"],
            "{runtime_identifier}": PLATFORMS[repository_ctx.attr.platform].dotnet.rid,
            "{csharp_default_version}": TOOL_VERSIONS[repository_ctx.attr.dotnet_version]["csharpDefaultVersion"],
            "{fsharp_default_version}": TOOL_VERSIONS[repository_ctx.attr.dotnet_version]["fsharpDefaultVersion"],
        },
        executable = False,
    )

dotnet_repositories = repository_rule(
    _dotnet_repo_impl,
    doc = _DOC,
    attrs = _ATTRS,
)

def _dotnet_wasm_workload_repo_impl(repository_ctx):
    platform = _host_platform(repository_ctx)
    url = TOOL_VERSIONS[repository_ctx.attr.dotnet_version][platform]["url"]
    repository_ctx.download_and_extract(
        url = url,
        integrity = TOOL_VERSIONS[repository_ctx.attr.dotnet_version][platform]["hash"],
    )

    _install_wasm_tools(repository_ctx)
    _write_wasm_workload_build(repository_ctx)

dotnet_wasm_workload_repository = repository_rule(
    _dotnet_wasm_workload_repo_impl,
    doc = "Fetches a .NET SDK and installs wasm-tools for Blazor publishing.",
    attrs = {
        "dotnet_version": attr.string(mandatory = True, values = TOOL_VERSIONS.keys()),
    },
)

def _dotnet_repository_alias_impl(repository_ctx):
    build_content = ["# Generated by dotnet/repositories.bzl"]
    for target in _DOTNET_REPOSITORY_ALIAS_TARGETS:
        build_content.append("""
alias(
    name = "{target}",
    actual = "@{actual_repository}//:{target}",
    visibility = ["//visibility:public"],
)
""".format(
            actual_repository = repository_ctx.attr.actual_repository,
            target = target,
        ))

    repository_ctx.file("BUILD.bazel", "\n".join(build_content))

dotnet_repository_alias = repository_rule(
    _dotnet_repository_alias_impl,
    attrs = {
        "actual_repository": attr.string(mandatory = True),
    },
)

# Wrapper macro around everything above, this is the primary API
def dotnet_register_toolchains(name, dotnet_version, register = True, **kwargs):
    """Convenience macro for users which does typical setup.

    - create a repository for each built-in platform like "dotnet_linux_amd64" -
      this repository is lazily fetched when node is needed for that platform.
    - create a repository exposing toolchains for each platform like "dotnet_platforms"
    - register a toolchain pointing at each platform
    Users can avoid this macro and do these steps themselves, if they want more control.

    Args:
        name: base name for all created repos, like "dotnet"
        dotnet_version: The .Net SDK version to use e.g. 8.0.100
        register: whether to call through to native.register_toolchains.
            Should be True for WORKSPACE users, but false when used under bzlmod extension
        **kwargs: passed to each dotnet_repositories call
    """

    versioned_repository_name = _versioned_repository_name(name, dotnet_version)

    for platform in PLATFORMS.keys():
        actual_repository = versioned_repository_name + "_" + platform
        dotnet_repositories(
            name = actual_repository,
            platform = platform,
            dotnet_version = dotnet_version,
            **kwargs
        )
        dotnet_repository_alias(
            name = name + "_" + platform,
            actual_repository = actual_repository,
        )
        if register:
            native.register_toolchains("@%s_toolchains//:%s_toolchain" % (name, platform))

    toolchains_repo(
        name = name + "_toolchains",
        user_repository_name = name,
    )

    dotnet_wasm_workload_repository(
        name = name + "_wasm_workload",
        dotnet_version = dotnet_version,
    )
