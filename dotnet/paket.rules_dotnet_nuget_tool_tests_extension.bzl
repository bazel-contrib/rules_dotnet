"Generated"

load(":paket.rules_dotnet_nuget_tool_tests.bzl", _rules_dotnet_nuget_tool_tests = "rules_dotnet_nuget_tool_tests")

def _rules_dotnet_nuget_tool_tests_impl(module_ctx):
    _rules_dotnet_nuget_tool_tests()
    return module_ctx.extension_metadata(reproducible = True)

rules_dotnet_nuget_tool_tests_extension = module_extension(
    implementation = _rules_dotnet_nuget_tool_tests_impl,
)
