"""
Rules for compiling and running NUnit tests.

This rule is a macro that has the same attributes as `csharp_test`
"""

load("//dotnet/private/rules/common:embed_sources.bzl", "embed_sources_or_flag")
load("//dotnet/private/rules/csharp:test.bzl", "csharp_test")

def csharp_nunit_test(**kwargs):
    # TODO: This should be user configurable
    deps = kwargs.pop("deps", []) + [
        Label("@paket.rules_dotnet_nuget_packages//nunitlite"),
        Label("@paket.rules_dotnet_nuget_packages//nunit"),
    ]

    srcs = kwargs.pop("srcs", []) + [
        Label("//dotnet/private/rules/common/nunit:shim.cs"),
    ]

    csharp_test(
        embed_sources = embed_sources_or_flag(kwargs.pop("embed_sources", None)),
        srcs = srcs,
        deps = deps,
        **kwargs
    )
