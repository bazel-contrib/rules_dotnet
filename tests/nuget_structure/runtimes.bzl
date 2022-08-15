"NuGet structure tests"

load("//tests/nuget_structure:common.bzl", "nuget_structure_test", "nuget_test_wrapper")

def runtimes_structure():
    "Test for the `runtimes` folder"

    # x64
    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.linux-x64",
        target_framework = "net6.0",
        runtime_identifier = "linux-x64",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.osx-x64",
        target_framework = "net6.0",
        runtime_identifier = "osx-x64",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.win-x64",
        target_framework = "net6.0",
        runtime_identifier = "win-x64",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.alpine-x64",
        target_framework = "net6.0",
        runtime_identifier = "alpine-x64",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_linux_x64",
        target_under_test = ":libgit2sharp.nativebinaries.linux-x64",
        expected_data = ["runtimes/linux-x64/native/libgit2-182d0d1.so"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_osx_x64",
        target_under_test = ":libgit2sharp.nativebinaries.osx-x64",
        expected_data = ["runtimes/osx-x64/native/libgit2-182d0d1.dylib"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_win_x64",
        target_under_test = ":libgit2sharp.nativebinaries.win-x64",
        expected_data = ["runtimes/win-x64/native/git2-182d0d1.dll", "runtimes/win-x64/native/libgit2_tests.exe"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_alpine_x64",
        target_under_test = ":libgit2sharp.nativebinaries.alpine-x64",
        expected_data = ["runtimes/linux-musl-x64/native/libgit2-182d0d1.so"],
    )

    # x86
    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.linux-x86",
        target_framework = "net6.0",
        runtime_identifier = "linux-x86",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.win-x86",
        target_framework = "net6.0",
        runtime_identifier = "win-x86",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_linux_x86",
        target_under_test = ":libgit2sharp.nativebinaries.linux-x86",
        expected_data = [],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_win_x86",
        target_under_test = ":libgit2sharp.nativebinaries.win-x86",
        expected_data = ["runtimes/win-x86/native/git2-182d0d1.dll", "runtimes/win-x86/native/libgit2_tests.exe"],
    )

    # arm64
    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.linux-arm64",
        target_framework = "net6.0",
        runtime_identifier = "linux-arm64",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.osx-arm64",
        target_framework = "net6.0",
        runtime_identifier = "osx-arm64",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.win-arm64",
        target_framework = "net6.0",
        runtime_identifier = "win-arm64",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.alpine-arm64",
        target_framework = "net6.0",
        runtime_identifier = "alpine-arm64",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_linux_arm64",
        target_under_test = ":libgit2sharp.nativebinaries.linux-arm64",
        expected_data = ["runtimes/linux-arm64/native/libgit2-182d0d1.so"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_osx_arm64",
        target_under_test = ":libgit2sharp.nativebinaries.osx-arm64",
        expected_data = ["runtimes/osx-arm64/native/libgit2-182d0d1.dylib"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_win_arm64",
        target_under_test = ":libgit2sharp.nativebinaries.win-arm64",
        expected_data = ["runtimes/win-arm64/native/git2-182d0d1.dll", "runtimes/win-arm64/native/libgit2_tests.exe"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_alpine_arm64",
        target_under_test = ":libgit2sharp.nativebinaries.alpine-arm64",
        expected_data = ["runtimes/linux-musl-arm64/native/libgit2-182d0d1.so"],
    )

    # arm
    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.linux-arm",
        target_framework = "net6.0",
        runtime_identifier = "linux-arm",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.win-arm",
        target_framework = "net6.0",
        runtime_identifier = "win-arm",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_test_wrapper(
        name = "libgit2sharp.nativebinaries.alpine-arm",
        target_framework = "net6.0",
        runtime_identifier = "alpine-arm",
        package = "@rules_dotnet_test_deps//libgit2sharp.nativebinaries",
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_linux_arm",
        target_under_test = ":libgit2sharp.nativebinaries.linux-arm",
        expected_data = ["runtimes/linux-arm/native/libgit2-182d0d1.so"],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_win_arm",
        target_under_test = ":libgit2sharp.nativebinaries.win-arm",
        expected_data = [],
    )

    nuget_structure_test(
        name = "nuget_structure_should_parse_runtimes_native_folder_correctly_alpine_arm",
        target_under_test = ":libgit2sharp.nativebinaries.alpine-arm",
        expected_data = ["runtimes/linux-musl-arm/native/libgit2-182d0d1.so"],
    )