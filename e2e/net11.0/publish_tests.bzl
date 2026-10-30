"""Runs .NET 11 publishes outside Bazel's runfiles tree."""

load("@rules_dotnet//dotnet:defs.bzl", "publish_binary")
load("@rules_pkg//pkg:tar.bzl", "pkg_tar")
load("@rules_shell//shell:sh_test.bzl", "sh_test")

_HOST_RIDS = {
    "@rules_dotnet//dotnet/private:linux-x64": "linux-x64",
    "@rules_dotnet//dotnet/private:linux-arm64": "linux-arm64",
    "@rules_dotnet//dotnet/private:osx-x64": "osx-x64",
    "@rules_dotnet//dotnet/private:osx-arm64": "osx-arm64",
    "@rules_dotnet//dotnet/private:windows-x64": "win-x64",
    "@rules_dotnet//dotnet/private:windows-arm64": "win-arm64",
}

def publish_test_suite(name):
    """Checks framework-dependent, self-contained, and ReadyToRun outputs.

    Args:
        name: Prefix for the publish targets and tests.
    """
    for language, binary, executable in [
        ("csharp", "//basic_csharp:hello", "hello"),
        ("fsharp", "//basic_fsharp:hello", "hello"),
        ("web", "//basic_csharp:web", "web"),
    ]:
        for mode in ["framework_dependent", "self_contained", "ready_to_run"]:
            target = "{}_{}_{}".format(name, language, mode)
            publish_binary(
                name = target,
                binary = binary,
                ready_to_run = mode == "ready_to_run",
                self_contained = mode != "framework_dependent",
                target_framework = "net11.0",
            )
            pkg_tar(
                name = target + "_tar",
                srcs = [":" + target],
                include_runfiles = True,
                mode = "0755",
                package_dir = "/",
                strip_prefix = select({
                    host: "{}/publish/{}".format(target, rid)
                    for host, rid in _HOST_RIDS.items()
                }),
            )
            sh_test(
                name = target + "_test",
                srcs = ["publish_test.sh"],
                args = [
                    "$(rootpath :{}_tar)".format(target),
                    "$(DOTNET_BIN)",
                    executable,
                    mode,
                ],
                data = [
                    ":" + target + "_tar",
                    "@rules_dotnet//dotnet:resolved_toolchain",
                ],
                toolchains = ["@rules_dotnet//dotnet:resolved_toolchain"],
            )
