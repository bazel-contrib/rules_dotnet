"""
Rules for compiling and running xUnit tests.

This rule is a macro that has the same attributes as `csharp_test`
"""

load("//dotnet/private/rules/common:embed_sources.bzl", "embed_sources_or_flag")
load("//dotnet/private/rules/csharp:test.bzl", "csharp_test")

def csharp_xunit_test(**kwargs):
    # TODO: This should be user configurable
    deps = kwargs.pop("deps", []) + [
        Label("@paket.rules_dotnet_nuget_packages//xunit.v3.assert"),
        Label("@paket.rules_dotnet_nuget_packages//xunit.v3.core"),
        Label("@paket.rules_dotnet_nuget_packages//xunit.v3.extensibility.core"),
        Label("@paket.rules_dotnet_nuget_packages//xunit.v3.runner.inproc.console"),
    ]

    srcs = kwargs.pop("srcs", []) + [
        Label("//dotnet/private/rules/common/xunit:shim.cs"),
    ]

    csharp_test(
        embed_sources = embed_sources_or_flag(kwargs.pop("embed_sources", None)),
        srcs = srcs,
        deps = deps,
        **kwargs
    )
