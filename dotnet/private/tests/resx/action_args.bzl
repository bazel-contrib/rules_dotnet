"""Unit tests asserting the compiler args emitted for `resx` resources.

These verify that neutral `.resx` resources are embedded under their manifest name
(including the `logical_names` override) in the main assembly, and that per-culture
resources are compiled into a satellite assembly under a culture-qualified manifest name.
"""

load("//dotnet/private/tests:utils.bzl", "action_args_test")

# buildifier: disable=unnamed-macro
def resx_action_args_tests():
    # Neutral resources are embedded in the main C# assembly under their manifest names.
    action_args_test(
        name = "csharp_neutral_manifest_args_test",
        target_under_test = ":greeter_cs",
        action_mnemonic = "CSharpCompile",
        expected_args_containing = [
            ",ResxCsTest.Strings.resources",
            ",MyApp.Messages.resources",
        ],
    )

    # Culture resources are emitted into a satellite assembly, not the main C# assembly.
    action_args_test(
        name = "csharp_satellite_manifest_args_test",
        target_under_test = ":greeter_cs",
        action_mnemonic = "ResxSatellite",
        expected_args_containing = [
            ",ResxCsTest.Strings.fr.resources",
            ",MyApp.Messages.fr.resources",
        ],
    )

    # Neutral resources are embedded in the main F# assembly under their manifest names.
    action_args_test(
        name = "fsharp_neutral_manifest_args_test",
        target_under_test = ":greeter_fs",
        action_mnemonic = "FSharpCompile",
        expected_args_containing = [
            ",ResxFsTest.Strings.resources",
            ",MyApp.Messages.resources",
        ],
    )

    # Culture resources are emitted into a satellite assembly, not the main F# assembly.
    action_args_test(
        name = "fsharp_satellite_manifest_args_test",
        target_under_test = ":greeter_fs",
        action_mnemonic = "ResxSatellite",
        expected_args_containing = [
            ",ResxFsTest.Strings.fr.resources",
            ",MyApp.Messages.fr.resources",
        ],
    )
