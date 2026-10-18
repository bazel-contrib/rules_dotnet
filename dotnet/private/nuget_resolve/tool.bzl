"""Builds the NuGet resolver tool offline, with the bootstrap SDK.

The tool's full transitive .nupkg closure is pinned below with sha512
integrity, downloaded into a local folder feed, and restored against a
NuGet.config that names only that feed — no network access beyond the pinned
downloads. The pinned downloads are integrity-checked and deduplicated by
Bazel's repository cache; the build itself re-runs on every refetch, always
from the same pinned inputs.
"""

load("//dotnet/private:toolchains_repo.bzl", "PLATFORMS")

# Keep in step with the `dotnet.bootstrap_toolchain` version in
# //:MODULE.bazel. //dotnet/private/nuget_resolve:tool_version_test fails when
# they diverge.
BOOTSTRAP_SDK_VERSION = "10.0.401"

# The TFM band of the bootstrap SDK; the tool's csproj targets it.
TOOL_TFM = "net10.0"

# The complete transitive .nupkg closure of the tool: (id, version, sha512 of
# the .nupkg as an SRI string). Repin procedure: `dotnet restore
# tools/nuget_resolver/NuGetResolver.csproj`, read the closure from
# obj/project.assets.json, download each
# https://api.nuget.org/v3-flatcontainer/<id-lower>/<version-lower>/<id-lower>.<version-lower>.nupkg
# and hash it (`openssl dgst -sha512 -binary | base64`).
TOOL_PACKAGES = [
    ("Newtonsoft.Json", "13.0.3", "sha512-mbJSvHfRxfX3tR/U6n1WU+mWHXswYc+SB/hkOpx8yZZe68hNZGfymJu0cjsaJEkVzCMqePiU6LdIyogqfIn7kg=="),
    ("NuGet.Common", "7.0.1", "sha512-BYeB6hyPQjGydptqKbeSbeUHnN4ODGZecW8C69m/fxO+jzznUPq2aCFsfx0Zm49o3bnkZPxOFNDWdoyVYJIuhw=="),
    ("NuGet.Configuration", "7.0.1", "sha512-qRY2f312PqXN3aRjclFdXbuKDH7xggRzMnedMpx3jz3jTQzR5gV0De0EM+HxV23/OulsIywW78HD8kBY7exibw=="),
    ("NuGet.DependencyResolver.Core", "7.0.1", "sha512-BbjqES1Gz1MNtyy1vvymBmaKad+UmBCRFoa0ST1c1/Me8mL3uEE8QSuMGhO3iGm2FWw+izCT4mRbhaMQMhghcQ=="),
    ("NuGet.Frameworks", "7.0.1", "sha512-m4YoXx/qKDHfHDry5BfsEejx2xI933Cw8fiF36XmxyT1E2a+z2kkzjon+qxlUy3X0UGYvBjS0BQvicqVaNMHVg=="),
    ("NuGet.LibraryModel", "7.0.1", "sha512-NMrWbnGT+gZzursqycpq/82tyLOZ3+JtDlKKnxw582RLl7Ho5ZOflZgHcrq2s3esElAtIS10398Ttz8oeSp9Ag=="),
    ("NuGet.Packaging", "7.0.1", "sha512-083yADb1esNQ/qmA5KkE/518QS52KLBCVoer+J9cibgB89k9gBXOgvgdN7emNYyU+5DGPm5OVUtkc5Z6cdVtDA=="),
    ("NuGet.Protocol", "7.0.1", "sha512-1T2I6/E84eX6aq3bJ6rdxGwvpXxbNNxeUXctN8GACIBZtLml9JXH7hQXt5yrdbsGojk0NaxObf00IOf9OvziKg=="),
    ("NuGet.Versioning", "7.0.1", "sha512-ibGcrpgA8foidKNcnf+AQ4zEaVZu4OyWjcPITii6mNgwt2uhd8VFsEq7/Mb0KDxrEJaew+nWJQb7Ju166SAyzw=="),
    ("System.Security.Cryptography.Pkcs", "9.0.6", "sha512-wpqmzVYr3B4FKcRrcnA26VzNeGK0GNlsx5IH5GMFSG8VKILfDB2BRGqYK3VZxTJq9fjai6A+sAXRQXCZkkXqvA=="),
    ("System.Security.Cryptography.ProtectedData", "9.0.6", "sha512-POnou/8+TN15ItlBZn3SerIAAAQeCABZhb+Oeirym8BGB/TVk3YUi3zFR26AbxprRVt06hFALYtfU+bNZ+lnvw=="),
]

_TOOL_SRCS = [
    "FeedDependencyProvider.cs",
    "LockFile.cs",
    "Netrc.cs",
    "NuGetResolver.csproj",
    "Program.cs",
    "ResolveException.cs",
    "ResolveSpec.cs",
    "Resolver.cs",
]

_NUGET_CONFIG = """\
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="feed" />
  </packageSources>
</configuration>
"""

def _host_os(os_name):
    os_name = os_name.lower()
    if os_name.find("windows") != -1:
        return "windows"
    if os_name.find("mac") != -1 or os_name.find("darwin") != -1:
        return "osx"
    if os_name.find("linux") != -1:
        return "linux"
    fail("unsupported host OS: " + os_name)

def host_platform(os_name, os_arch):
    """Maps a Bazel host os/arch pair onto a key of PLATFORMS.

    Args:
      os_name: `repository_ctx.os.name` / `module_ctx.os.name`.
      os_arch: `repository_ctx.os.arch` / `module_ctx.os.arch`.

    Returns:
      The PLATFORMS key for the host, e.g. "x86_64-unknown-linux-gnu".
    """
    want_os = _host_os(os_name)

    # aarch64-family entries in PLATFORMS declare either @platforms//cpu:aarch64
    # or @platforms//cpu:arm64, so accept both.
    if os_arch in ("aarch64", "arm64"):
        want_cpus = ["@platforms//cpu:aarch64", "@platforms//cpu:arm64"]
    elif os_arch in ("x86_64", "amd64"):
        want_cpus = ["@platforms//cpu:x86_64"]
    else:
        fail("unsupported host architecture: " + os_arch)

    for (key, meta) in PLATFORMS.items():
        if meta.os == want_os:
            for want_cpu in want_cpus:
                if want_cpu in meta.compatible_with:
                    return key
    fail("no .NET SDK platform for %s/%s" % (os_name, os_arch))

def bootstrap_sdk_dotnet_label(os_name, os_arch):
    """The label of the pinned bootstrap SDK's dotnet binary on this host."""
    platform = host_platform(os_name, os_arch)
    binary = "dotnet.exe" if PLATFORMS[platform].os == "windows" else "dotnet"
    return "@dotnet_sdk.{}_{}//:{}".format(BOOTSTRAP_SDK_VERSION, platform, binary)

def _nuget_resolver_tool_impl(ctx):
    for (id, version, integrity) in TOOL_PACKAGES:
        lower_id = id.lower()
        lower_version = version.lower()
        ctx.download(
            url = "https://api.nuget.org/v3-flatcontainer/{}/{}/{}.{}.nupkg".format(
                lower_id,
                lower_version,
                lower_id,
                lower_version,
            ),
            output = "feed/{}.{}.nupkg".format(lower_id, lower_version),
            integrity = integrity,
        )

    for src in ctx.attr.srcs:
        ctx.file("src/" + src.name, ctx.read(src))

    ctx.file("NuGet.config", _NUGET_CONFIG)

    dotnet = str(ctx.path(ctx.attr.dotnet))
    home = str(ctx.path("home"))
    ctx.file("home/.keep", "")
    env = {
        "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
        "DOTNET_CLI_HOME": home,
        "DOTNET_NOLOGO": "1",
        "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
        "NUGET_PACKAGES": str(ctx.path("nuget_packages")),
        "NUGET_HTTP_CACHE_PATH": str(ctx.path("nuget_http_cache")),
        # Signed-package verification on Linux can otherwise attempt online
        # certificate-revocation checks, which hang in offline/sandboxed
        # fetch contexts.
        "NUGET_CERT_REVOCATION_MODE": "offline",
    }
    if _host_os(ctx.os.name) == "windows":
        env["USERPROFILE"] = home
    else:
        env["HOME"] = home

    result = ctx.execute(
        [
            dotnet,
            "publish",
            "src/NuGetResolver.csproj",
            "-c",
            "Release",
            "-o",
            "publish",
            "--disable-build-servers",
            "/p:UseSharedCompilation=false",
            # Targeting packs the SDK does not bundle (Microsoft.AspNetCore.App.Ref
            # on distro-packaged SDKs) would otherwise be restored from NuGet,
            # which the offline folder feed cannot serve. The tool only compiles
            # against Microsoft.NETCore.App, which every SDK bundles.
            "/p:EnableTargetingPackDownload=false",
            # NuGet then uses ONLY this config file instead of merging
            # user/machine-level configs (on Windows the user config derives
            # from %APPDATA%, which the env redirect does not cover; a stray
            # config could re-add nuget.org).
            "/p:RestoreConfigFile=NuGet.config",
            # NuGetAudit defaults to on and would reach the network during
            # restore.
            "/p:NuGetAudit=false",
        ],
        environment = env,
        timeout = 1200,
    )
    if result.return_code != 0:
        fail("Building the NuGet resolver tool failed:\n" + result.stdout + result.stderr)

    ctx.file("BUILD.bazel", """\
"GENERATED"

package(default_visibility = ["//visibility:public"])

exports_files(glob(["publish/**"], allow_empty = False))
""")

nuget_resolver_tool = repository_rule(
    _nuget_resolver_tool_impl,
    doc = "Builds the NuGet resolver tool offline against a pinned .nupkg folder feed.",
    attrs = {
        "dotnet": attr.label(
            doc = "The dotnet binary of the bootstrap SDK: the label bootstrap_sdk_dotnet_label returns.",
            mandatory = True,
        ),
        "srcs": attr.label_list(
            doc = "The tool's sources, copied next to a NuGet.config that only names the pinned folder feed.",
            default = [
                "@rules_dotnet//tools/nuget_resolver:{}".format(src)
                for src in _TOOL_SRCS
            ],
        ),
    },
)
