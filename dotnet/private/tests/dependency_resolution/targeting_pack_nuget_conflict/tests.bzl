load("@aspect_bazel_lib//lib:run_binary.bzl", "run_binary")
load("@aspect_bazel_lib//lib:testing.bzl", "assert_contains")
load(
    "//dotnet:defs.bzl",
    "csharp_binary",
    "publish_binary",
)

EXPECTED_VERSION_PER_TFM = {
    "net6.0": "7.0.0.0",
    "net7.0": "7.0.0.0",
    "net8.0": "8.0.0.0",
}

def tests():
    """Returns a list of test targets."""
    for tfm, expected_version in EXPECTED_VERSION_PER_TFM.items():
        csharp_binary(
            name = "{tfm}".format(tfm = tfm),
            srcs = ["Main.cs"],
            target_frameworks = ["{tfm}".format(tfm = tfm)],
            deps = [
                "@paket.rules_dotnet_dev_nuget_packages//system.text.json",
            ],
        )

        publish_binary(
            name = "publish_{tfm}".format(tfm = tfm),
            binary = ":{tfm}".format(tfm = tfm),
            self_contained = True,
            target_framework = "{tfm}".format(tfm = tfm),
        )

        run_binary(
            name = "run_{tfm}".format(tfm = tfm),
            outs = ["version_{tfm}".format(tfm = tfm)],
            args = ["$@"],
            tool = ":publish_{tfm}".format(tfm = tfm),
        )

        assert_contains(
            name = "assert_{tfm}".format(tfm = tfm),
            actual = ":run_{tfm}".format(tfm = tfm),
            expected = expected_version,
        )
