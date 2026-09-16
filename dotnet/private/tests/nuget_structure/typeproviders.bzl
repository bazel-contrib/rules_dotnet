"NuGet structure tests"

load("//dotnet/private/tests/nuget_structure:common.bzl", "nuget_structure_test", "nuget_test_wrapper")

# buildifier: disable=unnamed-macro
def typeproviders_structure():
    "Tests for the typeproviders folder"
    nuget_test_wrapper(
        name = "fsharp.data",
        target_framework = "net8.0",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//fsharp.data",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_typeprovider_folder_correctly",
        target_under_test = ":fsharp.data",
        expected_libs = ["lib/netstandard2.0/FSharp.Data.dll", "typeproviders/fsharp41/netstandard2.0/FSharp.Data.DesignTime.dll"],
        expected_refs = ["lib/netstandard2.0/FSharp.Data.dll", "typeproviders/fsharp41/netstandard2.0/FSharp.Data.DesignTime.dll"],
    )
