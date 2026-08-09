"NuGet package structure tests using a local package artifact."

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_file")
load("@rules_dotnet//dotnet:defs.bzl", "nuget_repo")
load(":common.bzl", "nuget_structure_test", "nuget_test_wrapper")

def _local_package_artifact_impl(module_ctx):
    _ = module_ctx  # @unused
    http_file(
        name = "local_nuget_package_artifact",
        urls = ["https://www.nuget.org/api/v2/package/FSharp.Core/9.0.300"],
        integrity = "sha512-VmGyQ5hzaEvOHR2NnSlGHeGJzDH8j/GAil0pVAVxFv1YhQO6/OSLab7MWN5adsB7GYWsDVhU4YiSMDy+rA/2EQ==",
    )
    return module_ctx.extension_metadata(reproducible = True)

local_package_artifact = module_extension(
    implementation = _local_package_artifact_impl,
)

def _local_package_test_impl(module_ctx):
    _ = module_ctx  # @unused
    nuget_repo(
        name = "local_nuget_package_test",
        packages = [
            {
                "name": "LocalNuGetPackage",
                "id": "LocalNuGetPackage",
                "version": "1.0.0",
                "sha512": "sha512-VmGyQ5hzaEvOHR2NnSlGHeGJzDH8j/GAil0pVAVxFv1YhQO6/OSLab7MWN5adsB7GYWsDVhU4YiSMDy+rA/2EQ==",
                "local_package": Label("@local_nuget_package_artifact//file"),
                "dependencies": {},
                "targeting_pack_overrides": [],
                "framework_list": [],
                "tools": {},
            },
        ],
    )
    return module_ctx.extension_metadata(reproducible = True)

local_package_test = module_extension(
    implementation = _local_package_test_impl,
)

# buildifier: disable=function-docstring
def local_package_structure():
    nuget_test_wrapper(
        name = "local_package",
        target_framework = "netstandard2.1",
        runtime_identifier = "linux-x64",
        package = "@local_nuget_package_test//localnugetpackage",
    )

    nuget_structure_test(
        name = "should_parse_local_package",
        target_under_test = ":local_package",
        expected_libs = ["lib/netstandard2.1/FSharp.Core.dll"],
        expected_refs = ["lib/netstandard2.1/FSharp.Core.dll"],
        expected_resource_assemblies = [
            "lib/netstandard2.1/cs/FSharp.Core.resources.dll",
            "lib/netstandard2.1/de/FSharp.Core.resources.dll",
            "lib/netstandard2.1/es/FSharp.Core.resources.dll",
            "lib/netstandard2.1/fr/FSharp.Core.resources.dll",
            "lib/netstandard2.1/it/FSharp.Core.resources.dll",
            "lib/netstandard2.1/ja/FSharp.Core.resources.dll",
            "lib/netstandard2.1/ko/FSharp.Core.resources.dll",
            "lib/netstandard2.1/pl/FSharp.Core.resources.dll",
            "lib/netstandard2.1/pt-BR/FSharp.Core.resources.dll",
            "lib/netstandard2.1/ru/FSharp.Core.resources.dll",
            "lib/netstandard2.1/tr/FSharp.Core.resources.dll",
            "lib/netstandard2.1/zh-Hans/FSharp.Core.resources.dll",
            "lib/netstandard2.1/zh-Hant/FSharp.Core.resources.dll",
        ],
    )
