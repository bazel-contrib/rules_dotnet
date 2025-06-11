"Generated"

load(":paket.rules_dotnet_nuget_resource_assemblies_tests.bzl", _rules_dotnet_nuget_resource_assemblies_tests = "rules_dotnet_nuget_resource_assemblies_tests")

def _rules_dotnet_nuget_resource_assemblies_tests_impl(module_ctx):
    _rules_dotnet_nuget_resource_assemblies_tests()
    return module_ctx.extension_metadata(reproducible = True)

rules_dotnet_nuget_resource_assemblies_tests_extension = module_extension(
    implementation = _rules_dotnet_nuget_resource_assemblies_tests_impl,
)
