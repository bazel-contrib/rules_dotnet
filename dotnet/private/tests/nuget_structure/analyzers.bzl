"NuGet structure tests"

load("//dotnet/private/tests/nuget_structure:common.bzl", "nuget_structure_test", "nuget_test_wrapper")

# buildifier: disable=unnamed-macro
def analyzers_structure():
    "Tests for the analyzers folder"
    nuget_test_wrapper(
        name = "system.text.json",
        target_framework = "net8.0",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.text.json",
    )

    nuget_test_wrapper(
        name = "microsoft.codeanalysis.analyzers",
        target_framework = "net8.0",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//microsoft.codeanalysis.analyzers",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_version_specific_analyzers",
        target_under_test = ":system.text.json",
        expected_libs = ["lib/net7.0/System.Text.Json.dll"],
        expected_refs = ["lib/net7.0/System.Text.Json.dll"],
        expected_analyzers = [],
        expected_analyzers_csharp = ["analyzers/dotnet/roslyn3.11/cs/System.Text.Json.SourceGeneration.dll"],
        expected_analyzers_fsharp = [],
        expected_analyzers_vb = [],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_non_version_specific_analyzers",
        target_under_test = ":microsoft.codeanalysis.analyzers",
        expected_libs = [],
        expected_refs = [],
        expected_analyzers = [],
        expected_analyzers_csharp = ["analyzers/dotnet/cs/Microsoft.CodeAnalysis.Analyzers.dll", "analyzers/dotnet/cs/Microsoft.CodeAnalysis.CSharp.Analyzers.dll"],
        expected_analyzers_fsharp = [],
        expected_analyzers_vb = ["analyzers/dotnet/vb/Microsoft.CodeAnalysis.Analyzers.dll", "analyzers/dotnet/vb/Microsoft.CodeAnalysis.VisualBasic.Analyzers.dll"],
    )
