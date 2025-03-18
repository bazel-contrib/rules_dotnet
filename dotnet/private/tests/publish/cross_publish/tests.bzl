"Cross publishing tests"

load(
    "//dotnet:defs.bzl",
    "publish_binary",
)

permutations = [
    ("linux-x64", "'ELF 64-bit'", "'x86-64'"),
    ("linux-arm64", "'ELF 64-bit'", "'aarch64'"),
    ("osx-x64", "'Mach-O'", "'x86_64'"),
    ("osx-arm64", "'Mach-O'", "'arm64'"),
    ("win-x64", "'PE32+'", "'x86-64'"),
    ("win-arm64", "'PE32+'", "'ARM64'"),
    ("linux-musl-x64", "'ELF 64-bit'", "'x86-64'"),
    ("linux-musl-arm64", "'ELF 64-bit'", "'aarch64'"),
    # The permutations below are to verify that if we use a higher level rid like `fedora-x64` or `alpine-x64`
    # then we will find the closes rid that matches and has the runtime/apphost packs
    ("fedora-x64", "'ELF 64-bit'", "'x86-64'"),
    ("ubuntu.20.04-x64", "'ELF 64-bit'", "'x86-64'"),
    ("alpine-x64", "'ELF 64-bit'", "'x86-64'"),
    ("fedora-arm64", "'ELF 64-bit'", "'aarch64'"),
    ("ubuntu.20.04-arm64", "'ELF 64-bit'", "'aarch64'"),
    ("alpine-arm64", "'ELF 64-bit'", "'aarch64'"),
]

# buildifier: disable=unnamed-macro
def tests():
    for (rid, expected_file_type, expected_arch) in permutations:
        publish_binary(
            name = "cross_publish_{}".format(rid),
            binary = "//dotnet/private/tests/publish/app_to_publish",
            runtime_identifier = rid,
            self_contained = True,
            target_framework = "net6.0",
        )

        native.sh_test(
            name = "cross_publish_test_{}".format(rid),
            srcs = ["test.sh"],
            args = [
                "$(rootpath :cross_publish_{})".format(rid),
                expected_file_type,
                expected_arch,
            ],
            data = [
                ":cross_publish_{}".format(rid),
            ],
            target_compatible_with = select({
                # Disable on remote runners because the `file` binary does not exist on the RBE runners
                "@bazel_tools//tools/cpp:gcc": ["@platforms//:incompatible"],
                "//conditions:default": [],
            }),
        )
