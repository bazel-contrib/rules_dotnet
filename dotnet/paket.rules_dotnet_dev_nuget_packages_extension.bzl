"Generated"

load(":paket.rules_dotnet_dev_nuget_packages.bzl", _rules_dotnet_dev_nuget_packages = "rules_dotnet_dev_nuget_packages")

def _rules_dotnet_dev_nuget_packages_impl(_ctx):
    _rules_dotnet_dev_nuget_packages()

rules_dotnet_dev_nuget_packages_extension = module_extension(
    implementation = _rules_dotnet_dev_nuget_packages_impl,
)
