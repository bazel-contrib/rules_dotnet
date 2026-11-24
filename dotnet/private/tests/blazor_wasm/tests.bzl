"""Asserts which copy of an assembly a Blazor WebAssembly site ships when a dependency and the runtime pack both carry it."""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("@rules_testing//lib:truth.bzl", "matching")
load("//dotnet:defs.bzl", "csharp_binary", "publish_binary")

def _file_from(description, repository, basename):
    return matching.custom(
        description,
        lambda file: file.basename == basename and repository in file.path,
    )

def _assembly_older_than_the_pack_test(name):
    csharp_binary(
        name = name + "_app",
        srcs = [
            "App.razor",
            "Program.cs",
            "_Imports.razor",
        ],
        project_sdk = "blazorwasm",
        root_namespace = "BlazorApp",
        # Analysis is all the test needs.
        tags = ["manual"],
        target_frameworks = ["net10.0"],
        deps = [
            "@paket.rules_dotnet_static_web_assets_tests//microsoft.aspnetcore.components.webassembly",
            # Older than the runtime pack's own System.Text.Json, as a package a
            # library asks for is once the framework has moved on.
            "@paket.rules_dotnet_dev_nuget_packages//system.text.json",
        ],
    )

    publish_binary(
        name = name + "_publish",
        binary = name + "_app",
        tags = ["manual"],
        target_framework = "net10.0",
        wasm = True,
    )

    analysis_test(name = name, impl = _assembly_older_than_the_pack_test_impl, target = name + "_publish")

def _assembly_older_than_the_pack_test_impl(env, target):
    # The framework's own assemblies are built against the pack's copy, and
    # fail to load an older one in its place.
    inputs = env.expect.that_target(target).action_named("BlazorWasmAssemble").inputs()
    inputs.contains_predicate(_file_from(
        "the runtime pack's System.Text.Json.dll",
        "runtime.mono.browser-wasm",
        "System.Text.Json.dll",
    ))
    inputs.not_contains_predicate(_file_from(
        "the package's System.Text.Json.dll",
        "nuget.system.text.json.",
        "System.Text.Json.dll",
    ))

def blazor_wasm_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _assembly_older_than_the_pack_test,
        ],
    )
