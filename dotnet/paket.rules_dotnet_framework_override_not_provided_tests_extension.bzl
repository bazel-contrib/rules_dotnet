"Generated"

load(":paket.rules_dotnet_framework_override_not_provided_tests.bzl", _rules_dotnet_framework_override_not_provided_tests = "rules_dotnet_framework_override_not_provided_tests")

def _rules_dotnet_framework_override_not_provided_tests_impl(module_ctx):
    _rules_dotnet_framework_override_not_provided_tests()
    return module_ctx.extension_metadata(reproducible = True)

rules_dotnet_framework_override_not_provided_tests_extension = module_extension(
    implementation = _rules_dotnet_framework_override_not_provided_tests_impl,
)
