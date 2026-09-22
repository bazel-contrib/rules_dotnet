"""Host .NET SDK repository definitions."""

load("//dotnet/private:toolchains_repo.bzl", "ARCHITECTURES", "PLATFORMS", "toolchains_repo")

def _dotnet_from_root(ctx, root):
    for executable in ["dotnet", "dotnet.exe"]:
        dotnet_bin = ctx.path(root).get_child(executable)
        if dotnet_bin.exists:
            return dotnet_bin.realpath
    return None

def _find_dotnet_executable(ctx):
    # 1. Arch-specific dotnet root (e.g. DOTNET_ROOT_X64)
    arch_root_env = "DOTNET_ROOT_{}".format(ctx.attr.dotnet_arch)
    p = ctx.getenv(arch_root_env)
    if p:
        dotnet_bin = _dotnet_from_root(ctx, p)
        if dotnet_bin:
            return dotnet_bin

    p = ctx.getenv("DOTNET_ROOT")
    if p:
        dotnet_bin = _dotnet_from_root(ctx, p)
        if dotnet_bin:
            return dotnet_bin

    # 3. Path lookup
    dotnet_bin = ctx.which("dotnet")
    if dotnet_bin:
        return dotnet_bin.realpath

    fail("Could not find 'dotnet' executable for architecture {}".format(ctx.attr.dotnet_arch))

def _find_default_dotnet_executable(ctx):
    arch = ctx.os.arch.lower()
    arch_root_env = ""
    if arch in ["amd64", "x86_64"]:
        arch_root_env = "DOTNET_ROOT_X64"
    elif arch in ["aarch64", "arm64"]:
        arch_root_env = "DOTNET_ROOT_ARM64"

    if arch_root_env:
        p = ctx.getenv(arch_root_env)
        if p:
            dotnet_bin = _dotnet_from_root(ctx, p)
            if dotnet_bin:
                return dotnet_bin

    p = ctx.getenv("DOTNET_ROOT")
    if p:
        dotnet_bin = _dotnet_from_root(ctx, p)
        if dotnet_bin:
            return dotnet_bin

    dotnet_bin = ctx.which("dotnet")
    if dotnet_bin:
        return dotnet_bin.realpath

    fail("Could not find 'dotnet' executable")

def _version_key(version):
    return [int(part) for part in version.split("-", 1)[0].split(".")]

def _matches_version_prefix(version, requested):
    requested_parts = requested.split(".")
    version_parts = version.split("-", 1)[0].split(".")
    return len(requested_parts) < 3 and version_parts[:len(requested_parts)] == requested_parts

def _find_sdk_version(ctx, dotnet_root):
    sdk_root = dotnet_root.get_child("sdk")
    versions = [
        path.basename
        for path in sdk_root.readdir()
        if path.get_child("Microsoft.NETCoreSdk.BundledVersions.props").exists
    ]
    if ctx.attr.dotnet_version:
        matching_versions = [
            version
            for version in versions
            if version == ctx.attr.dotnet_version or _matches_version_prefix(version, ctx.attr.dotnet_version)
        ]
        if len(matching_versions) == 0:
            fail("Host .NET SDK {} is not installed under {}. Installed SDKs: {}.".format(
                ctx.attr.dotnet_version,
                dotnet_root,
                ", ".join(sorted(versions, key = _version_key)),
            ))
        return sorted(matching_versions, key = _version_key)[-1]

    if len(versions) == 0:
        fail("No .NET SDK is installed under {}.".format(dotnet_root))
    return sorted(versions, key = _version_key)[-1]

def _pack_versions(packs_root, exact = "", prefix = "", contains = "", suffix = ""):
    versions = {}
    for pack in packs_root.readdir():
        name = pack.basename
        if exact and name != exact:
            continue
        if prefix and not name.startswith(prefix):
            continue
        if contains and contains not in name:
            continue
        if suffix and not name.endswith(suffix):
            continue
        for version in pack.readdir():
            versions[version.basename] = True
    return versions

def _find_wasm_runtime_version(dotnet_root, runtime_version, required):
    packs_root = dotnet_root.get_child("packs")
    pack_groups = [
        struct(exact = "Microsoft.NET.Runtime.WebAssembly.Sdk"),
        struct(exact = "Microsoft.NETCore.App.Runtime.Mono.browser-wasm"),
        struct(prefix = "Microsoft.NETCore.App.Runtime.AOT.", suffix = ".Cross.browser-wasm"),
        struct(exact = "Microsoft.NET.Runtime.MonoAOTCompiler.Task"),
        struct(exact = "Microsoft.NET.Runtime.MonoTargets.Sdk"),
        struct(prefix = "Microsoft.NET.Runtime.Emscripten.", contains = ".Sdk."),
        struct(prefix = "Microsoft.NET.Runtime.Emscripten.", contains = ".Cache."),
        struct(prefix = "Microsoft.NET.Runtime.Emscripten.", contains = ".Node."),
    ]
    candidates = None
    for group in pack_groups:
        versions = _pack_versions(
            packs_root,
            exact = getattr(group, "exact", ""),
            prefix = getattr(group, "prefix", ""),
            contains = getattr(group, "contains", ""),
            suffix = getattr(group, "suffix", ""),
        )
        if candidates == None:
            candidates = versions
        else:
            candidates = {version: True for version in candidates if version in versions}

    runtime_family = runtime_version.split(".")[:2]
    matching_versions = [
        version
        for version in candidates
        if version.split("-", 1)[0].split(".")[:2] == runtime_family
    ]
    if len(matching_versions) > 0:
        return sorted(matching_versions, key = _version_key)[-1]
    if required:
        fail("The host SDK root {} does not contain a complete wasm-tools workload compatible with .NET {}. Install wasm-tools into that SDK root; user-local workload locations are not searched.".format(
            dotnet_root,
            ".".join(runtime_family),
        ))
    return ""

def _read_property(content, name):
    start_tag = "<{}>".format(name)
    end_tag = "</{}>".format(name)
    start = content.find(start_tag)
    if start < 0:
        fail("Unable to find {} in Microsoft.NETCoreSdk.BundledVersions.props.".format(name))
    start += len(start_tag)
    end = content.find(end_tag, start)
    if end < 0:
        fail("Unable to read {} from Microsoft.NETCoreSdk.BundledVersions.props.".format(name))
    return content[start:end].strip()

def _inspect_dotnet_root(ctx, dotnet_bin):
    dotnet_root = ctx.path(dotnet_bin).dirname
    sdk_version = _find_sdk_version(ctx, dotnet_root)
    props = ctx.read(dotnet_root.get_child("sdk").get_child(sdk_version).get_child("Microsoft.NETCoreSdk.BundledVersions.props"))
    sdk_major = int(sdk_version.split(".")[0])
    runtime_version = _read_property(props, "BundledNETCoreAppPackageVersion")
    return struct(
        dotnet_root = dotnet_root,
        sdk_version = sdk_version,
        runtime_version = runtime_version,
        wasm_runtime_version = _find_wasm_runtime_version(dotnet_root, runtime_version, False),
        runtime_identifier = _read_property(props, "NETCoreSdkRuntimeIdentifier"),
        csharp_default = "{}.0".format(sdk_major + 4),
        fsharp_default = ".".join(sdk_version.split(".")[:2]),
    )

def _dotnet_host_repo_impl(ctx):
    dotnet_bin = _find_dotnet_executable(ctx)
    host_info = _inspect_dotnet_root(ctx, dotnet_bin)
    dotnet_root = host_info.dotnet_root

    for item in ctx.path(dotnet_root).readdir():
        ctx.symlink(item, item.basename)

    ctx.template("BUILD.bazel", Label("//dotnet/private/sdk:toolchain.build.tmpl"), substitutions = {
        "{sdk_version}": host_info.sdk_version,
        "{runtime_version}": host_info.runtime_version,
        "{wasm_runtime_version}": host_info.wasm_runtime_version,
        "{runtime_tfm}": "net" + ".".join(host_info.runtime_version.split(".")[:2]),
        "{csharp_default_version}": host_info.csharp_default,
        "{fsharp_default_version}": host_info.fsharp_default,
        "{runtime_identifier}": host_info.runtime_identifier,
    }, executable = False)

dotnet_host_repository = repository_rule(
    _dotnet_host_repo_impl,
    local = True,
    attrs = {
        "platform": attr.string(mandatory = True, values = PLATFORMS.keys()),
        "dotnet_version": attr.string(default = ""),
        "dotnet_arch": attr.string(mandatory = True, values = ARCHITECTURES),
    },
    environ = ["DOTNET_ROOT", "DOTNET_ROOT_ARM64", "DOTNET_ROOT_X64", "PATH"],
    doc = "Links node local tools needed for dotnet toolchain",
)

def _dotnet_host_wasm_workload_repo_impl(ctx):
    dotnet_bin = _find_default_dotnet_executable(ctx)
    host_info = _inspect_dotnet_root(ctx, dotnet_bin)
    dotnet_root = host_info.dotnet_root
    _find_wasm_runtime_version(dotnet_root, host_info.runtime_version, True)
    for item in ctx.path(dotnet_root).readdir():
        ctx.symlink(item, item.basename)

    dotnet_executable = "dotnet.exe" if ctx.path("dotnet.exe").exists else "dotnet"
    ctx.file("BUILD.bazel", """
package(default_visibility = ["//visibility:public"])

exports_files(["{dotnet_executable}"])

filegroup(
    name = "wasm_workload_files",
    srcs = glob(["**/*"], exclude = ["BUILD.bazel"], allow_empty = True),
)
""".format(dotnet_executable = dotnet_executable))

dotnet_host_wasm_workload_repository = repository_rule(
    _dotnet_host_wasm_workload_repo_impl,
    local = True,
    attrs = {
        "dotnet_version": attr.string(default = ""),
    },
    environ = ["DOTNET_ROOT", "DOTNET_ROOT_ARM64", "DOTNET_ROOT_X64", "PATH"],
    doc = "Exposes wasm-tools files from a preinstalled host .NET SDK if present.",
)

def dotnet_register_host_toolchains(name, dotnet_version, **kwargs):
    """Convenience macro for users which does typical setup.

    - create a repository for platforms available on the host, like "dotnet_linux_amd64" -
      this repository is linked in when node is needed for that platform.
    - create a repository exposing toolchains for each platform like "dotnet_platforms"
    - register a toolchain pointing at each platform
    Users can avoid this macro and do these steps themselves, if they want more control.

    Args:
        name: base name for all created repos, like "dotnet"
        dotnet_version: The .NET SDK version to use, such as 8.0.100 for an
                        exact version or 8.0 for the latest matching installed SDK
        **kwargs: passed to each dotnet_repositories call
    """
    for platform, desc in PLATFORMS.items():
        dotnet_host_repository(
            name = name + "_" + platform,
            platform = platform,
            dotnet_version = dotnet_version,
            dotnet_arch = desc.dotnet.arch,
            **kwargs
        )

    toolchains_repo(
        name = name + "_toolchains",
        user_repository_name = name,
    )

    dotnet_host_wasm_workload_repository(
        name = name + "_wasm_workload",
        dotnet_version = dotnet_version,
    )
