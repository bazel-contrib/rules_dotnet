"""
Rules for compiling and running MSTest tests.

This rule is a macro that has the same attributes as `csharp_test`
"""

load("//dotnet/private/rules/common:embed_sources.bzl", "embed_sources_or_flag")
load("//dotnet/private/rules/csharp:test.bzl", "csharp_test")

def csharp_mstest_test(**kwargs):
    # TODO: This should be user configurable
    deps = kwargs.pop("deps", []) + [
        Label("@paket.rules_dotnet_nuget_packages//microsoft.testing.platform"),
        Label("@paket.rules_dotnet_nuget_packages//mstest.testadapter"),
        Label("@paket.rules_dotnet_nuget_packages//mstest.testframework"),
    ]

    srcs = kwargs.pop("srcs", []) + [
        Label("//dotnet/private/rules/common/mstest:shim.cs"),
    ]

    csharp_test(
        embed_sources = embed_sources_or_flag(kwargs.pop("embed_sources", None)),
        srcs = srcs,
        deps = deps,
        **kwargs
    )
