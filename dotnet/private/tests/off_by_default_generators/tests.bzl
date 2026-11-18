"""Asserts which of the .NET SDK's own source generators a compilation runs, and which interceptors namespaces it allows.

The expectations are what MSBuild resolves for the same project (`dotnet msbuild
-getItem:Analyzer -getProperty:InterceptorsPreviewNamespaces`).
"""

load("@rules_testing//lib:analysis_test.bzl", "analysis_test", "test_suite")
load("//dotnet:defs.bzl", "csharp_binary", "csharp_library", "publish_binary")
load("//dotnet/private/tests:utils.bzl", "published_binary")

_REQUEST_DELEGATE_GENERATOR = "Microsoft.AspNetCore.Http.RequestDelegateGenerator.dll"
_CONFIGURATION_BINDING_GENERATOR = "Microsoft.Extensions.Configuration.Binder.SourceGeneration.dll"
_VALIDATIONS_GENERATOR = "Microsoft.Extensions.Validation.ValidationsGenerator.dll"
_GENERATORS = [_REQUEST_DELEGATE_GENERATOR, _CONFIGURATION_BINDING_GENERATOR, _VALIDATIONS_GENERATOR]

_HTTP_NAMESPACE = "Microsoft.AspNetCore.Http.Generated"
_BINDER_NAMESPACE = "Microsoft.Extensions.Configuration.Binder.SourceGeneration"
_VALIDATION_NAMESPACE = "Microsoft.Extensions.Validation.Generated"

_INTERCEPTORS_FEATURE = "/features:InterceptorsNamespaces="

_SRCS = ["Sample.cs"]

# The linker for NativeAOT only drives Unix toolchains.
_NOT_WINDOWS = select({
    "@platforms//os:windows": ["@platforms//:incompatible"],
    "//conditions:default": [],
})

def _compile_action(target):
    compiles = [action for action in target.actions if action.mnemonic == "CSharpCompile"]
    if len(compiles) != 1:
        fail("Expected one CSharpCompile action in {}, found {}".format(target.label, len(compiles)))
    return compiles[0]

def _expect_generators(env, target, generators, namespaces):
    argv = _compile_action(target).argv
    analyzers = [arg.rpartition("/")[2].strip("\"") for arg in argv if arg.startswith("/analyzer:")]
    env.expect.that_collection([dll for dll in analyzers if dll in _GENERATORS]).contains_exactly(generators)

    features = [arg[len(_INTERCEPTORS_FEATURE):].split(";") for arg in argv if arg.startswith(_INTERCEPTORS_FEATURE)]
    env.expect.that_collection(features[0] if features else []).contains_exactly(namespaces).in_order()

def _library(name, project_sdk = "web", target_framework = "net10.0", **kwargs):
    csharp_library(
        name = name,
        srcs = _SRCS,
        project_sdk = project_sdk,
        target_frameworks = [target_framework],
        tags = ["manual"],
        **kwargs
    )

def _published(name, native_aot, **kwargs):
    csharp_binary(
        name = name + "_binary",
        srcs = _SRCS,
        project_sdk = "web",
        target_frameworks = ["net10.0"],
        tags = ["manual"],
        **kwargs
    )

    publish_binary(
        name = name + "_publish",
        binary = name + "_binary",
        native_aot = native_aot,
        self_contained = native_aot,
        tags = ["manual"],
        target_compatible_with = _NOT_WINDOWS if native_aot else [],
        target_framework = "net10.0",
    )

def _web_default_test(name):
    _library(name + "_lib")
    analysis_test(name = name, impl = _web_default_test_impl, target = name + "_lib")

def _web_default_test_impl(env, target):
    # Off unless the project opts in, as `ResolveOffByDefaultAnalyzers` leaves them.
    _expect_generators(env, target, [_VALIDATIONS_GENERATOR], [_VALIDATION_NAMESPACE])

def _web_enabled_test(name):
    _library(
        name + "_lib",
        enable_configuration_binding_generator = "true",
        enable_request_delegate_generator = "true",
    )
    analysis_test(name = name, impl = _web_enabled_test_impl, target = name + "_lib")

def _web_enabled_test_impl(env, target):
    _expect_generators(env, target, _GENERATORS, [_HTTP_NAMESPACE, _BINDER_NAMESPACE, _VALIDATION_NAMESPACE])

def _default_sdk_test(name):
    _library(name + "_lib", project_sdk = "default")
    analysis_test(name = name, impl = _default_sdk_test_impl, target = name + "_lib")

def _default_sdk_test_impl(env, target):
    # The SDK allows the validation namespace for every project on .NET 10.
    _expect_generators(env, target, [], [_VALIDATION_NAMESPACE])

def _before_net10_test(name):
    _library(name + "_lib", target_framework = "net8.0")
    analysis_test(name = name, impl = _before_net10_test_impl, target = name + "_lib")

def _before_net10_test_impl(env, target):
    _expect_generators(env, target, [], [])

def _blazorwasm_test(name):
    _library(name + "_lib", project_sdk = "blazorwasm")
    analysis_test(name = name, impl = _blazorwasm_test_impl, target = name + "_lib")

def _blazorwasm_test_impl(env, target):
    # The Blazor WebAssembly SDK always trims, which turns the request delegate
    # generator on, and then turns the binding generator back off.
    _expect_generators(env, target, [_REQUEST_DELEGATE_GENERATOR, _VALIDATIONS_GENERATOR], [_HTTP_NAMESPACE, _VALIDATION_NAMESPACE])

def _native_aot_publish_test(name):
    _published(name, native_aot = True)
    analysis_test(name = name, impl = _native_aot_publish_test_impl, target = name + "_publish")

def _native_aot_publish_test_impl(env, target):
    # `PublishAot` turns both on.
    _expect_generators(env, published_binary(target), _GENERATORS, [_HTTP_NAMESPACE, _BINDER_NAMESPACE, _VALIDATION_NAMESPACE])

def _native_aot_publish_respects_attributes_test(name):
    _published(
        name,
        native_aot = True,
        enable_configuration_binding_generator = "false",
        enable_request_delegate_generator = "false",
    )
    analysis_test(name = name, impl = _native_aot_publish_respects_attributes_test_impl, target = name + "_publish")

def _native_aot_publish_respects_attributes_test_impl(env, target):
    _expect_generators(env, published_binary(target), [_VALIDATIONS_GENERATOR], [_VALIDATION_NAMESPACE])

def _framework_dependent_publish_test(name):
    _published(name, native_aot = False)
    analysis_test(name = name, impl = _framework_dependent_publish_test_impl, target = name + "_publish")

def _framework_dependent_publish_test_impl(env, target):
    _expect_generators(env, published_binary(target), [_VALIDATIONS_GENERATOR], [_VALIDATION_NAMESPACE])

def _trimmed_only_reaches_the_published_binary_test(name):
    csharp_binary(
        name = name + "_binary",
        srcs = _SRCS,
        project_sdk = "web",
        target_frameworks = ["net10.0"],
        tags = ["manual"],
    )
    analysis_test(
        name = name,
        impl = _trimmed_only_reaches_the_published_binary_test_impl,
        target = name + "_binary",
        # Seen by a binary that is not the one being published, which drops it.
        config_settings = {str(Label("//dotnet/private/rules/publish_binary:trimmed")): True},
    )

def _trimmed_only_reaches_the_published_binary_test_impl(env, target):
    _expect_generators(env, target, [_VALIDATIONS_GENERATOR], [_VALIDATION_NAMESPACE])

def off_by_default_generators_test_suite(name):
    test_suite(
        name = name,
        tests = [
            _web_default_test,
            _web_enabled_test,
            _default_sdk_test,
            _before_net10_test,
            _blazorwasm_test,
            _native_aot_publish_test,
            _native_aot_publish_respects_attributes_test,
            _framework_dependent_publish_test,
            _trimmed_only_reaches_the_published_binary_test,
        ],
    )
