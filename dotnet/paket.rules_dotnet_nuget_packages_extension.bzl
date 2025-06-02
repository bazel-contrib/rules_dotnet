"Generated"

load(":paket.rules_dotnet_nuget_packages.bzl", _rules_dotnet_nuget_packages = "rules_dotnet_nuget_packages")

def _rules_dotnet_nuget_packages_impl(module_ctx):
    _rules_dotnet_nuget_packages()
    return module_ctx.extension_metadata(reproducible = True)

rules_dotnet_nuget_packages_extension = module_extension(
    implementation = _rules_dotnet_nuget_packages_impl,
)
