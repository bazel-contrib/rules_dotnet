"""Analysis tests of publishing the shared frameworks a binary's dependencies reference."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("@rules_testing//lib:util.bzl", "TestingAspectInfo")
load("//dotnet:defs.bzl", "csharp_binary", "csharp_library", "publish_binary")
load("//dotnet/private:providers.bzl", "DotnetBinaryInfo")
load("//dotnet/private/tests:utils.bzl", "published_binary")

def _strict_publish_fails(name):
    publish_binary(
        name = name + "_publish",
        binary = ":app",
        self_contained = True,
        strict_framework_references = 1,
        tags = ["manual"],
        target_framework = "net10.0",
    )

    analysis_test(
        name = name,
        impl = _strict_publish_fails_impl,
        target = name + "_publish",
        expect_failure = True,
    )

def _strict_publish_fails_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*runs on Microsoft.AspNetCore.App, which one of its dependencies references*"),
    )

def _missing_runtime_pack(name):
    # .NET Core 3.1 only shipped Microsoft.WindowsDesktop.App for win-x64, so
    # there is no pack to take for win-arm64 even when the publish takes the
    # frameworks of dependencies.
    csharp_library(
        name = name + "_lib",
        srcs = ["DesktopLib.cs"],
        framework_references = ["Microsoft.WindowsDesktop.App"],
        tags = ["manual"],
        target_frameworks = ["netcoreapp3.1"],
    )

    csharp_binary(
        name = name + "_app",
        srcs = ["Main.cs"],
        tags = ["manual"],
        target_frameworks = ["netcoreapp3.1"],
        deps = [name + "_lib"],
    )

    publish_binary(
        name = name + "_publish",
        binary = name + "_app",
        runtime_identifier = "win-arm64",
        self_contained = True,
        strict_framework_references = 0,
        tags = ["manual"],
        target_framework = "netcoreapp3.1",
    )

    analysis_test(
        name = name,
        impl = _missing_runtime_pack_impl,
        target = name + "_publish",
        expect_failure = True,
    )

def _missing_runtime_pack_impl(env, target):
    env.expect.that_target(target).failures().contains_predicate(
        matching.str_matches("*runs on Microsoft.WindowsDesktop.App, which has no runtime pack for netcoreapp3.1 and runtime identifier win-arm64*"),
    )

def _strict_publish_shares_binary(name):
    publish_binary(
        name = name + "_publish",
        binary = ":plain_app",
        self_contained = True,
        strict_framework_references = 1,
        tags = ["manual"],
        target_framework = "net10.0",
    )

    analysis_test(
        name = name,
        impl = _strict_publish_shares_binary_impl,
        targets = {
            "binary": ":plain_app",
            "publish": name + "_publish",
        },
    )

def _strict_publish_shares_binary_impl(env, targets):
    # The same configuration, so the binary is built once.
    env.expect.that_str(published_binary(targets.publish)[DotnetBinaryInfo].dll.path).equals(
        targets.binary[DotnetBinaryInfo].dll.path,
    )

# What a ReadyToRun publish of a web application puts in the configuration of
# the targets below its binary.
_READY_TO_RUN_SETTINGS = {
    str(Label("//dotnet/private/rules/ready_to_run:framework")): "net10.0",
    str(Label("//dotnet/private/rules/ready_to_run:shared_frameworks")): "aspnetcore",
}

def _ready_to_run_references(name):
    analysis_test(
        name = name,
        impl = _ready_to_run_references_impl,
        targets = {
            "plain": ":plain_lib",
            "web": ":lib",
        },
        config_settings = _READY_TO_RUN_SETTINGS,
    )

def _crossgen2_inputs(target):
    return [
        file.basename
        for action in target[TestingAspectInfo].actions
        if action.mnemonic == "Crossgen2"
        for file in action.inputs.to_list()
    ]

def _ready_to_run_references_impl(env, targets):
    # Each image is compiled against the shared frameworks its assembly runs
    # on, not every one the publish's runtime pack carries.
    web = _crossgen2_inputs(targets.web)
    env.expect.that_collection(web).contains("System.Private.CoreLib.dll")
    env.expect.that_collection(web).contains("Microsoft.AspNetCore.Http.Abstractions.dll")

    plain = _crossgen2_inputs(targets.plain)
    env.expect.that_collection(plain).contains("System.Private.CoreLib.dll")
    env.expect.that_collection([file for file in plain if file.startswith("Microsoft.AspNetCore.")]).contains_exactly([])

def dependency_frameworks_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _strict_publish_fails,
            _missing_runtime_pack,
            _strict_publish_shares_binary,
            _ready_to_run_references,
        ],
    )
