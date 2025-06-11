"NuGet structure tests"

load("//dotnet/private/tests/nuget_structure:common.bzl", "nuget_structure_test", "nuget_test_wrapper")

# buildifier: disable=unnamed-macro
def resource_assemblies():
    "Tests for resolution of resource assemblies"

    # The Microsoft.Data.SqlClient package only has resource assemblies for the net462 TFM.
    nuget_test_wrapper(
        name = "microsoft.data.sqlclient.netstandard2.0",
        target_framework = "netstandard2.0",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_nuget_resource_assemblies_tests//microsoft.data.sqlclient",
    )

    nuget_structure_test(
        name = "should_resolve_microsoft.data.sqlclient_netstandard2.0_linux-x64_correctly",
        target_under_test = ":microsoft.data.sqlclient.netstandard2.0",
        expected_libs = ["runtimes/unix/lib/netstandard2.0/Microsoft.Data.SqlClient.dll"],
        expected_refs = ["ref/netstandard2.0/Microsoft.Data.SqlClient.dll"],
        expected_resource_assemblies = [
        ],
    )

    nuget_test_wrapper(
        name = "microsoft.data.sqlclient.net462",
        target_framework = "net462",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_nuget_resource_assemblies_tests//microsoft.data.sqlclient",
    )

    nuget_structure_test(
        name = "should_resolve_microsoft.data.sqlclient_net462_linux-x64_correctly",
        target_under_test = ":microsoft.data.sqlclient.net462",
        expected_libs = ["lib/net462/Microsoft.Data.SqlClient.dll"],
        expected_refs = ["ref/net462/Microsoft.Data.SqlClient.dll"],
        expected_resource_assemblies = [
            "lib/net462/de/Microsoft.Data.SqlClient.resources.dll",
            "lib/net462/es/Microsoft.Data.SqlClient.resources.dll",
            "lib/net462/fr/Microsoft.Data.SqlClient.resources.dll",
            "lib/net462/it/Microsoft.Data.SqlClient.resources.dll",
            "lib/net462/ja/Microsoft.Data.SqlClient.resources.dll",
            "lib/net462/ko/Microsoft.Data.SqlClient.resources.dll",
            "lib/net462/pt-BR/Microsoft.Data.SqlClient.resources.dll",
            "lib/net462/ru/Microsoft.Data.SqlClient.resources.dll",
            "lib/net462/zh-Hans/Microsoft.Data.SqlClient.resources.dll",
            "lib/net462/zh-Hant/Microsoft.Data.SqlClient.resources.dll",
        ],
    )

    nuget_test_wrapper(
        name = "humanizer.core.de.net6.0",
        target_framework = "net6.0",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_nuget_resource_assemblies_tests//humanizer.core.de",
    )
