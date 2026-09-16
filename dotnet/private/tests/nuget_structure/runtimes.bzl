"NuGet structure tests"

load("//dotnet/private/tests/nuget_structure:common.bzl", "nuget_structure_test", "nuget_test_wrapper")

# buildifier: disable=unnamed-macro
def runtimes_structure():
    "Test for the `runtimes` folder"

    # x64
    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.linux-x64",
        target_framework = "net8.0",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.osx-x64",
        target_framework = "net8.0",
        runtime_identifier = "osx-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.win-x64",
        target_framework = "net8.0",
        runtime_identifier = "win-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.alpine-x64",
        target_framework = "net8.0",
        runtime_identifier = "alpine-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_linux_x64",
        target_under_test = ":libgit2sharp.nativebinaries.linux-x64",
        expected_native = ["runtimes/linux-x64/native/libgit2-b7bad55.so"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_osx_x64",
        target_under_test = ":libgit2sharp.nativebinaries.osx-x64",
        expected_native = ["runtimes/osx-x64/native/libgit2-b7bad55.dylib"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_win_x64",
        target_under_test = ":libgit2sharp.nativebinaries.win-x64",
        expected_native = ["runtimes/win-x64/native/git2-b7bad55.dll"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_alpine_x64",
        target_under_test = ":libgit2sharp.nativebinaries.alpine-x64",
        expected_native = ["runtimes/linux-musl-x64/native/libgit2-b7bad55.so"],
    )

    # x86
    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.linux-x86",
        target_framework = "net8.0",
        runtime_identifier = "linux-x86",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.win-x86",
        target_framework = "net8.0",
        runtime_identifier = "win-x86",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_linux_x86",
        target_under_test = ":libgit2sharp.nativebinaries.linux-x86",
        expected_native = [],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_win_x86",
        target_under_test = ":libgit2sharp.nativebinaries.win-x86",
        expected_native = ["runtimes/win-x86/native/git2-b7bad55.dll"],
    )

    # arm64
    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.linux-arm64",
        target_framework = "net8.0",
        runtime_identifier = "linux-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.osx-arm64",
        target_framework = "net8.0",
        runtime_identifier = "osx-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.win-arm64",
        target_framework = "net8.0",
        runtime_identifier = "win-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.alpine-arm64",
        target_framework = "net8.0",
        runtime_identifier = "alpine-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_linux_arm64",
        target_under_test = ":libgit2sharp.nativebinaries.linux-arm64",
        expected_native = ["runtimes/linux-arm64/native/libgit2-b7bad55.so"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_osx_arm64",
        target_under_test = ":libgit2sharp.nativebinaries.osx-arm64",
        expected_native = ["runtimes/osx-arm64/native/libgit2-b7bad55.dylib"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_win_arm64",
        target_under_test = ":libgit2sharp.nativebinaries.win-arm64",
        expected_native = ["runtimes/win-arm64/native/git2-b7bad55.dll"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_alpine_arm64",
        target_under_test = ":libgit2sharp.nativebinaries.alpine-arm64",
        expected_native = ["runtimes/linux-musl-arm64/native/libgit2-b7bad55.so"],
    )

    # arm
    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.linux-arm",
        target_framework = "net8.0",
        runtime_identifier = "linux-arm",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.win-arm",
        target_framework = "net8.0",
        runtime_identifier = "win-arm",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.alpine-arm",
        target_framework = "net8.0",
        runtime_identifier = "alpine-arm",
        package = "@paket.rules_dotnet_dev_nuget_packages//libgit2sharp.nativebinaries",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_linux_arm",
        target_under_test = ":libgit2sharp.nativebinaries.linux-arm",
        expected_native = ["runtimes/linux-arm/native/libgit2-b7bad55.so"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_win_arm",
        target_under_test = ":libgit2sharp.nativebinaries.win-arm",
        expected_native = [],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_alpine_arm",
        target_under_test = ":libgit2sharp.nativebinaries.alpine-arm",
        expected_native = ["runtimes/linux-musl-arm/native/libgit2-b7bad55.so"],
    )

    # This package only has the `unix` and `win` RIDs so we want
    # to see that the right RID is chosen if we choose a parent of
    # those RIDs
    nuget_test_wrapper(
        name = "system.security.principal.windows.net8.0.linux-x64",
        target_framework = "net8.0",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_net6_0_linux_x64",
        target_under_test = ":system.security.principal.windows.net8.0.linux-x64",
        expected_libs = [],
        expected_refs = ["ref/netcoreapp3.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.net8.0.linux-arm64",
        target_framework = "net8.0",
        runtime_identifier = "linux-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_net6_0_linux_arm64",
        target_under_test = ":system.security.principal.windows.net8.0.linux-arm64",
        expected_libs = [],
        expected_refs = ["ref/netcoreapp3.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.net8.0.osx-x64",
        target_framework = "net8.0",
        runtime_identifier = "osx-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_net6_0_osx_x64",
        target_under_test = ":system.security.principal.windows.net8.0.osx-x64",
        expected_libs = [],
        expected_refs = ["ref/netcoreapp3.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.net8.0.osx-arm64",
        target_framework = "net8.0",
        runtime_identifier = "osx-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_net6_0_osx_arm64",
        target_under_test = ":system.security.principal.windows.net8.0.osx-arm64",
        expected_libs = [],
        expected_refs = ["ref/netcoreapp3.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.net8.0.win-x64",
        target_framework = "net8.0",
        runtime_identifier = "win-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_net6_0_win_x64",
        target_under_test = ":system.security.principal.windows.net8.0.win-x64",
        expected_libs = [],
        expected_refs = ["ref/netcoreapp3.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.net8.0.win-arm64",
        target_framework = "net8.0",
        runtime_identifier = "win-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_net6_0_win_arm64",
        target_under_test = ":system.security.principal.windows.net8.0.win-arm64",
        expected_libs = [],
        expected_refs = ["ref/netcoreapp3.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.netstandard2.1.linux-x64",
        target_framework = "netstandard2.1",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_netstandard_2_1_linux_x64",
        target_under_test = ":system.security.principal.windows.netstandard2.1.linux-x64",
        expected_libs = ["lib/netstandard2.0/System.Security.Principal.Windows.dll"],
        expected_refs = ["ref/netstandard2.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.netstandard2.1.linux-arm64",
        target_framework = "netstandard2.1",
        runtime_identifier = "linux-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_netstandard_2_1_linux_arm64",
        target_under_test = ":system.security.principal.windows.netstandard2.1.linux-arm64",
        expected_libs = ["lib/netstandard2.0/System.Security.Principal.Windows.dll"],
        expected_refs = ["ref/netstandard2.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.netstandard2.1.osx-x64",
        target_framework = "netstandard2.1",
        runtime_identifier = "osx-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_netstandard_2_1_osx_x64",
        target_under_test = ":system.security.principal.windows.netstandard2.1.osx-x64",
        expected_libs = ["lib/netstandard2.0/System.Security.Principal.Windows.dll"],
        expected_refs = ["ref/netstandard2.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.netstandard2.1.osx-arm64",
        target_framework = "netstandard2.1",
        runtime_identifier = "osx-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_netstandard_2_1_osx_arm64",
        target_under_test = ":system.security.principal.windows.netstandard2.1.osx-arm64",
        expected_libs = ["lib/netstandard2.0/System.Security.Principal.Windows.dll"],
        expected_refs = ["ref/netstandard2.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.netstandard2.1.win-x64",
        target_framework = "netstandard2.1",
        runtime_identifier = "win-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_netstandard_2_1_win_x64",
        target_under_test = ":system.security.principal.windows.netstandard2.1.win-x64",
        expected_libs = ["lib/netstandard2.0/System.Security.Principal.Windows.dll"],
        expected_refs = ["ref/netstandard2.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "system.security.principal.windows.netstandard2.1.win-arm64",
        target_framework = "netstandard2.1",
        runtime_identifier = "win-arm64",
        package = "@paket.rules_dotnet_dev_nuget_packages//system.security.principal.windows",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtime_unix_correctly_netstandard_2_1_win_arm64",
        target_under_test = ":system.security.principal.windows.netstandard2.1.win-arm64",
        expected_libs = ["lib/netstandard2.0/System.Security.Principal.Windows.dll"],
        expected_refs = ["ref/netstandard2.0/System.Security.Principal.Windows.dll"],
    )

    nuget_test_wrapper(
        name = "magick.net.core.netstandard21.linux-x64",
        target_framework = "net8.0",
        runtime_identifier = "linux-x64",
        package = "@paket.rules_dotnet_dev_nuget_packages//magick.net.core",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_libs_folder_correctly_netstandard21",
        target_under_test = ":magick.net.core.netstandard21.linux-x64",
        expected_libs = ["lib/netstandard21/Magick.NET.Core.dll"],
        expected_refs = ["lib/netstandard21/Magick.NET.Core.dll"],
    )
