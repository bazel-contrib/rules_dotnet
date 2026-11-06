"Tests for windowsdesktop project_sdk and winexe target."

load("//dotnet:defs.bzl", "csharp_binary", "csharp_nunit_test", "fsharp_binary", "publish_binary")
load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=function-docstring
# buildifier: disable=unnamed-macro
def windowsdesktop_tests():
    csharp_binary(
        name = "winexe_csharp_app",
        srcs = ["Program.cs"],
        project_sdk = "windowsdesktop",
        target_frameworks = ["net10.0"],
        winexe = True,
        tags = ["manual"],
    )

    publish_binary(
        name = "winexe_csharp_publish",
        binary = ":winexe_csharp_app",
        runtime_identifier = "win-x64",
        self_contained = False,
        target_framework = "net10.0",
        tags = ["manual"],
    )

    csharp_nunit_test(
        name = "windowsdesktop_test",
        srcs = ["WindowsDesktopTest.cs"],
        data = [":winexe_csharp_publish"],
        project_sdk = "windowsdesktop",
        target_compatible_with = ["@platforms//os:windows"],
        target_frameworks = ["net10.0"],
        deps = ["//tools/runfiles"],
    )

    action_args_test(
        name = "winexe_csharp_compile_args_test",
        target_under_test = ":winexe_csharp_app",
        action_mnemonic = "CSharpCompile",
        expected_partial_args = ["/target:winexe"],
        expected_nonexistent_partial_args = ["/target:exe"],
        expected_args_containing = ["WindowsBase.dll", "System.Windows.Forms.dll"],
    )

    fsharp_binary(
        name = "winexe_fsharp_app",
        srcs = ["Program.fs"],
        target_frameworks = ["net10.0"],
        winexe = True,
        tags = ["manual"],
    )

    action_args_test(
        name = "winexe_fsharp_compile_args_test",
        target_under_test = ":winexe_fsharp_app",
        action_mnemonic = "FSharpCompile",
        expected_partial_args = ["--target:winexe"],
        expected_nonexistent_partial_args = ["--target:exe"],
    )
