"""Every NuGet resolution test.

A test is one declaration: the files a package ships, the framework and runtime
identifier to build at, and what should come out. Each one carries its own
layout and gets its own package in the fixture repository, so nothing has to be
published to add a case.

Everything that turns these into targets lives in `internal/`.
"""

load("//dotnet/private/tests/nuget_resolution/internal:declaration.bzl", "nuget_resolution_test")

TESTS = [
    nuget_resolution_test(
        name = "a_rid_assembly_replaces_the_lib_group_on_linux",
        files = [
            "lib/netstandard2.0/A.dll",
            "ref/netstandard2.0/A.dll",
            "ref/netcoreapp3.0/A.dll",
            "runtimes/unix/lib/netcoreapp2.1/A.dll",
            "runtimes/win/lib/netcoreapp2.1/A.dll",
        ],
        target_framework = "net6.0",
        runtime_identifier = "linux-x64",
        # The compile group and the runtime group are resolved independently:
        # one lands on the netcoreapp3.0 reference assembly, the other on the
        # unix specific implementation.
        expected_libs = ["runtimes/unix/lib/netcoreapp2.1/A.dll"],
        expected_refs = ["ref/netcoreapp3.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_rid_assembly_replaces_the_lib_group_on_windows",
        files = [
            "lib/netstandard2.0/A.dll",
            "ref/netstandard2.0/A.dll",
            "ref/netcoreapp3.0/A.dll",
            "runtimes/unix/lib/netcoreapp2.1/A.dll",
            "runtimes/win/lib/netcoreapp2.1/A.dll",
        ],
        target_framework = "net6.0",
        runtime_identifier = "win-x64",
        expected_libs = ["runtimes/win/lib/netcoreapp2.1/A.dll"],
        expected_refs = ["ref/netcoreapp3.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "the_lib_group_stands_when_no_rid_assembly_fits_the_framework",
        files = [
            "lib/netstandard2.0/A.dll",
            "ref/netstandard2.0/A.dll",
            "runtimes/unix/lib/netcoreapp2.1/A.dll",
            "runtimes/win/lib/netcoreapp2.1/A.dll",
        ],
        # Nothing under `runtimes` is consumable from netstandard2.1, so the
        # portable assembly is what is left.
        target_framework = "netstandard2.1",
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["ref/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "an_older_rid_assembly_still_replaces_a_newer_lib_one",
        files = [
            "lib/netstandard2.0/A.dll",
            "ref/netstandard2.0/A.dll",
            "runtimes/win/lib/netstandard1.3/A.dll",
        ],
        target_framework = "netstandard2.1",
        runtime_identifier = "win-x64",
        expected_libs = ["runtimes/win/lib/netstandard1.3/A.dll"],
        expected_refs = ["ref/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_mixed_case_framework_folder_is_matched",
        # `HtmlAgilityPack` ships `lib/Net45`. NuGet matches folder names case
        # insensitively and a case sensitive lookup drops it.
        files = [
            "lib/Net45/A.dll",
            "lib/netstandard2.0/A.dll",
        ],
        target_framework = "net472",
        expected_libs = ["lib/Net45/A.dll"],
        expected_refs = ["lib/Net45/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_mixed_case_folder_does_not_shadow_a_nearer_one",
        files = [
            "lib/Net45/A.dll",
            "lib/netstandard2.0/A.dll",
        ],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_rid_placeholder_brings_nothing_on_its_own_rid",
        # `_._` says the package brings nothing on that RID, which is not the
        # same as saying nothing about it.
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/win/lib/netstandard2.0/_._",
        ],
        runtime_identifier = "win-x64",
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_rid_placeholder_does_not_apply_off_its_rid",
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/win/lib/netstandard2.0/_._",
        ],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "the_ref_folder_beats_a_nearer_lib_folder",
        files = [
            "ref/netstandard2.0/A.dll",
            "lib/net8.0/A.dll",
            "lib/netstandard2.0/A.dll",
        ],
        expected_libs = ["lib/net8.0/A.dll"],
        expected_refs = ["ref/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "the_ref_folder_is_used_when_it_fits",
        files = [
            "ref/net8.0/R.dll",
            "lib/net8.0/M.dll",
            "lib/netstandard2.0/A.dll",
        ],
        expected_libs = ["lib/net8.0/M.dll"],
        expected_refs = ["ref/net8.0/R.dll"],
    ),
    nuget_resolution_test(
        name = "the_ref_folder_falls_back_to_lib_when_nothing_fits",
        files = [
            "ref/net8.0/R.dll",
            "lib/net8.0/M.dll",
            "lib/netstandard2.0/A.dll",
        ],
        # `ref` is preferred as a group, but net6.0 cannot use the only entry
        # in it, so the compile group comes from `lib` after all.
        target_framework = "net6.0",
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "an_architecture_qualified_rid_beats_a_libc_qualified_one",
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/linux-musl/lib/netstandard2.0/Musl.dll",
            "runtimes/linux-x64/lib/netstandard2.0/LinuxX64.dll",
        ],
        # Neither RID is a specialisation of the other and both apply here.
        runtime_identifier = "linux-musl-x64",
        expected_libs = ["runtimes/linux-x64/lib/netstandard2.0/LinuxX64.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "an_architecture_qualified_rid_beats_an_os_qualified_one",
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/unix-x64/lib/netstandard2.0/UnixX64.dll",
            "runtimes/linux/lib/netstandard2.0/Linux.dll",
        ],
        expected_libs = ["runtimes/unix-x64/lib/netstandard2.0/UnixX64.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "the_most_specific_rid_wins_where_it_applies",
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/win/lib/netstandard2.0/Win.dll",
            "runtimes/win-x64/lib/netstandard2.0/WinX64.dll",
        ],
        runtime_identifier = "win-x64",
        expected_libs = ["runtimes/win-x64/lib/netstandard2.0/WinX64.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_less_specific_rid_covers_the_rest",
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/win/lib/netstandard2.0/Win.dll",
            "runtimes/win-x64/lib/netstandard2.0/WinX64.dll",
        ],
        runtime_identifier = "win-arm64",
        expected_libs = ["runtimes/win/lib/netstandard2.0/Win.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "the_nearest_runtimes_framework_is_chosen_before_the_rid",
        # `win` ships net8.0 and `win-x64` ships netstandard2.0, so the
        # framework and the RID pull in opposite directions. The framework wins.
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/win/lib/net8.0/Win80.dll",
            "runtimes/win-x64/lib/netstandard2.0/WinX64.dll",
        ],
        runtime_identifier = "win-x64",
        expected_libs = ["runtimes/win/lib/net8.0/Win80.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "the_search_continues_when_the_nearest_runtimes_framework_is_too_new",
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/win/lib/net8.0/Win80.dll",
            "runtimes/win-x64/lib/netstandard2.0/WinX64.dll",
        ],
        target_framework = "net6.0",
        runtime_identifier = "win-x64",
        expected_libs = ["runtimes/win-x64/lib/netstandard2.0/WinX64.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_package_of_only_rid_assemblies_resolves_on_a_covered_platform",
        # `Microsoft.Management.Infrastructure.Runtime.Unix` is shaped like
        # this: RID specific assemblies and nothing portable to fall back on.
        files = ["runtimes/unix/lib/netstandard1.6/Unix.dll"],
        expected_libs = ["runtimes/unix/lib/netstandard1.6/Unix.dll"],
    ),
    nuget_resolution_test(
        name = "a_package_of_only_rid_assemblies_brings_nothing_elsewhere",
        files = ["runtimes/unix/lib/netstandard1.6/Unix.dll"],
        runtime_identifier = "win-x64",
    ),
    nuget_resolution_test(
        name = "rid_assemblies_split_across_platforms_resolve_on_a_covered_one",
        files = [
            "runtimes/linux/lib/netstandard1.6/Linux.dll",
            "runtimes/osx/lib/netstandard1.6/Osx.dll",
        ],
        expected_libs = ["runtimes/linux/lib/netstandard1.6/Linux.dll"],
    ),
    nuget_resolution_test(
        name = "rid_assemblies_split_across_platforms_bring_nothing_elsewhere",
        files = [
            "runtimes/linux/lib/netstandard1.6/Linux.dll",
            "runtimes/osx/lib/netstandard1.6/Osx.dll",
        ],
        runtime_identifier = "win-x64",
    ),
    nuget_resolution_test(
        name = "build_reference_assemblies_add_to_the_packages_own",
        # What `NETStandard.Library` ships. The SDK adds these alongside a
        # package's own assemblies rather than in place of them.
        files = [
            "lib/netstandard2.0/A.dll",
            "build/net8.0/ref/R.dll",
        ],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["build/net8.0/ref/R.dll", "lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "analyzers_are_split_by_language",
        files = [
            "lib/netstandard2.0/A.dll",
            "analyzers/dotnet/Any.dll",
            "analyzers/dotnet/cs/Csharp.dll",
            "analyzers/dotnet/fs/Fsharp.dll",
            "analyzers/dotnet/vb/Vb.dll",
        ],
        expected_analyzers = ["analyzers/dotnet/Any.dll"],
        expected_analyzers_csharp = ["analyzers/dotnet/cs/Csharp.dll"],
        expected_analyzers_fsharp = ["analyzers/dotnet/fs/Fsharp.dll"],
        expected_analyzers_vb = ["analyzers/dotnet/vb/Vb.dll"],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "the_lowest_roslyn_analyzers_are_used_whole",
        # An analyzer folder can be qualified by the Roslyn it was built
        # against. The lowest is the one every compiler can load, and all of
        # its assemblies are needed, not just the first.
        files = [
            "lib/netstandard2.0/A.dll",
            "analyzers/dotnet/roslyn3.8/cs/One.dll",
            "analyzers/dotnet/roslyn3.8/cs/Two.dll",
            "analyzers/dotnet/roslyn4.0/cs/One.dll",
        ],
        expected_analyzers_csharp = [
            "analyzers/dotnet/roslyn3.8/cs/One.dll",
            "analyzers/dotnet/roslyn3.8/cs/Two.dll",
        ],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "roslyn_folders_are_ordered_by_version_not_by_name",
        # `roslyn10.0` sorts before `roslyn4.0` as a string, and `roslyn4.10`
        # before `roslyn4.9`. Neither is the lower version.
        files = [
            "lib/netstandard2.0/A.dll",
            "analyzers/dotnet/roslyn10.0/cs/Ten.dll",
            "analyzers/dotnet/roslyn4.10/cs/FourTen.dll",
            "analyzers/dotnet/roslyn4.9/cs/FourNine.dll",
        ],
        expected_analyzers_csharp = ["analyzers/dotnet/roslyn4.9/cs/FourNine.dll"],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_roslyn_folder_naming_no_language_brings_no_analyzers",
        # `analyzers/dotnet/<roslyn version>/<assembly>.dll` has the shape of a
        # language qualified path without naming a language.
        files = [
            "lib/netstandard2.0/A.dll",
            "analyzers/dotnet/roslyn4.0/A.dll",
        ],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "type_providers_are_referenced_and_shipped",
        # F# design time components live outside `lib` and the compiler loads
        # them, so they belong to both groups.
        files = [
            "lib/netstandard2.0/A.dll",
            "typeproviders/fsharp41/netstandard2.0/TP.dll",
        ],
        expected_libs = [
            "lib/netstandard2.0/A.dll",
            "typeproviders/fsharp41/netstandard2.0/TP.dll",
        ],
        expected_refs = [
            "lib/netstandard2.0/A.dll",
            "typeproviders/fsharp41/netstandard2.0/TP.dll",
        ],
    ),
    nuget_resolution_test(
        name = "satellite_assemblies_are_their_own_group",
        files = [
            "lib/netstandard2.0/A.dll",
            "lib/netstandard2.0/de/A.resources.dll",
            "lib/netstandard2.0/it/A.resources.dll",
        ],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
        expected_resource_assemblies = [
            "lib/netstandard2.0/de/A.resources.dll",
            "lib/netstandard2.0/it/A.resources.dll",
        ],
    ),
    nuget_resolution_test(
        name = "native_libraries_are_keyed_by_rid_alone_on_linux",
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/linux-x64/native/libx.so",
            "runtimes/win-x64/native/x.dll",
        ],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_native = ["runtimes/linux-x64/native/libx.so"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "native_libraries_are_keyed_by_rid_alone_on_windows",
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/linux-x64/native/libx.so",
            "runtimes/win-x64/native/x.dll",
        ],
        runtime_identifier = "win-x64",
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_native = ["runtimes/win-x64/native/x.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_native_placeholder_is_not_shipped",
        # `_._` marks a RID the package deliberately brings nothing for. It is
        # a marker, not a library to copy next to the binary.
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/linux-x64/native/_._",
        ],
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_targeting_pack_declares_its_metadata",
        # No assemblies of its own: what it contributes is the assembly
        # versions it declares and the packages it supersedes.
        files = [
            "lib/net48/_._",
            "data/FrameworkList.xml",
            "data/PackageOverrides.txt",
        ],
        target_framework = "net48",
        contents = {
            "data/FrameworkList.xml": """<?xml version="1.0" encoding="utf-8"?>
<FileList Name="Fixture">
  <File Type="Managed" AssemblyName="System.Fixture" AssemblyVersion="4.0.0.0" />
  <File Type="Managed" AssemblyName="System.Fixture.Extra" AssemblyVersion="4.1.0.0" />
  <File Type="Native" AssemblyName="Native.Fixture" AssemblyVersion="1.0.0.0" />
</FileList>
""",
            "data/PackageOverrides.txt": "System.Fixture|4.0.0\nSystem.Fixture.Extra|4.1.0\n",
        },
        expected_framework_list = {
            "system.fixture": "4.0.0.0",
            "system.fixture.extra": "4.1.0.0",
        },
        expected_targeting_pack_overrides = {
            "system.fixture": "4.0.0",
            "system.fixture.extra": "4.1.0",
        },
    ),
    nuget_resolution_test(
        name = "a_lib_placeholder_brings_nothing_at_its_own_framework",
        # `lib/<tfm>/_._` says the package supports the framework and has
        # nothing to ship for it, which is not the same as not supporting it.
        files = [
            "lib/netstandard2.0/A.dll",
            "lib/net8.0/_._",
        ],
    ),
    nuget_resolution_test(
        name = "a_bare_lib_placeholder_is_not_an_unsupported_framework",
        # `lib/_._` names no framework at all: the package supports everything
        # and ships nothing, which must not read as supporting nothing.
        files = ["lib/_._"],
    ),
    nuget_resolution_test(
        name = "a_lib_placeholder_does_not_shadow_a_lower_framework",
        files = [
            "lib/netstandard2.0/A.dll",
            "lib/net8.0/_._",
        ],
        target_framework = "net6.0",
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_version_qualified_rid_folds_onto_its_portable_one",
        # rules_dotnet configures on portable RIDs only, so assets under a
        # distribution release fold onto the nearest portable ancestor.
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/ubuntu.16.04-x64/lib/netstandard2.0/Ubuntu.dll",
        ],
        runtime_identifier = "ubuntu-x64",
        expected_libs = ["runtimes/ubuntu.16.04-x64/lib/netstandard2.0/Ubuntu.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_version_qualified_rid_does_not_apply_below_its_portable_one",
        files = [
            "lib/netstandard2.0/A.dll",
            "runtimes/ubuntu.16.04-x64/lib/netstandard2.0/Ubuntu.dll",
        ],
        runtime_identifier = "linux-x64",
        expected_libs = ["lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "build_lib_assemblies_add_to_the_packages_own",
        files = [
            "lib/netstandard2.0/A.dll",
            "build/net8.0/lib/L.dll",
        ],
        expected_libs = ["build/net8.0/lib/L.dll", "lib/netstandard2.0/A.dll"],
        expected_refs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_non_standard_netstandard_spelling_is_rewritten",
        # Some packages ship `netstandard20` rather than `netstandard2.0`.
        files = ["lib/netstandard20/A.dll"],
        expected_libs = ["lib/netstandard20/A.dll"],
        expected_refs = ["lib/netstandard20/A.dll"],
    ),
    nuget_resolution_test(
        name = "content_files_are_exposed",
        files = [
            "lib/netstandard2.0/A.dll",
            "contentFiles/any/any/config.json",
        ],
        expected_content_files = ["contentFiles/any/any/config.json"],
    ),
    nuget_resolution_test(
        name = "tools_are_grouped_by_framework",
        # A tool folder holds a whole payload, not just assemblies, and a
        # package can offer the tool for more than one framework.
        files = [
            "tools/net8.0/any/Tool.dll",
            "tools/net8.0/any/Tool.runtimeconfig.json",
            "tools/net8.0/any/DotnetToolSettings.xml",
            "tools/netcoreapp3.1/any/Tool.dll",
            "tools/netcoreapp3.1/any/DotnetToolSettings.xml",
        ],
        expected_tools = {
            "net8.0": [
                "tools/net8.0/any/Tool.dll",
                "tools/net8.0/any/Tool.runtimeconfig.json",
                "tools/net8.0/any/DotnetToolSettings.xml",
            ],
            "netcoreapp3.1": [
                "tools/netcoreapp3.1/any/Tool.dll",
                "tools/netcoreapp3.1/any/DotnetToolSettings.xml",
            ],
        },
    ),
    nuget_resolution_test(
        name = "a_mixed_case_tools_folder_is_keyed_by_the_framework_it_names",
        # The folder spelling is the package's; the key is the framework, the
        # same way `lib/Net45` resolves.
        files = [
            "tools/NetCoreApp3.1/any/Tool.dll",
            "tools/NetCoreApp3.1/any/DotnetToolSettings.xml",
        ],
        expected_tools = {
            "netcoreapp3.1": [
                "tools/NetCoreApp3.1/any/Tool.dll",
                "tools/NetCoreApp3.1/any/DotnetToolSettings.xml",
            ],
        },
    ),
    nuget_resolution_test(
        name = "a_tools_folder_naming_no_targetable_framework_is_dropped",
        # Nothing could ever resolve to it, so it is not offered at all rather
        # than offered and failing when the tool is run.
        files = [
            "tools/net8.0/any/Tool.dll",
            "tools/net8.0-windows/any/Windows.dll",
        ],
        expected_tools = {"net8.0": ["tools/net8.0/any/Tool.dll"]},
    ),
    nuget_resolution_test(
        name = "only_the_any_tools_folder_is_collected",
        # `dotnet tool` runs portable assemblies, so `any` is the only RID
        # folder it looks at, and the payload always sits under one.
        files = [
            "tools/net8.0/any/Tool.dll",
            "tools/net8.0/win-x64/Tool.exe",
            "tools/net8.0/Stray.dll",
        ],
        expected_tools = {"net8.0": ["tools/net8.0/any/Tool.dll"]},
    ),
    nuget_resolution_test(
        name = "a_package_of_only_untargetable_frameworks_is_incompatible",
        files = ["lib/net8.0-windows/A.dll"],
        expect_incompatible = True,
    ),
    nuget_resolution_test(
        name = "a_package_resolves_in_the_default_configuration",
        files = [
            "lib/Net45/A.dll",
            "lib/netstandard2.0/A.dll",
        ],
        default_configuration = True,
        expected_libs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "build_transitive_assemblies_are_added_to_the_lib_group",
        # What `MSTest.TestFramework` looks like at one framework: its own
        # assembly under `lib/net8.0/` plus `TestFramework.Extensions.dll`
        # under `buildTransitive/net8.0/`. Both end up next to the binary and
        # the compile group falls back to both (same as the Task 3
        # workaround's refs = libs).
        files = [
            "lib/net8.0/A.dll",
            "buildTransitive/net8.0/T.dll",
        ],
        expected_libs = ["buildTransitive/net8.0/T.dll", "lib/net8.0/A.dll"],
        expected_refs = ["buildTransitive/net8.0/T.dll", "lib/net8.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_package_of_only_build_transitive_assemblies_resolves",
        # What `MSTest.TestAdapter` looks like: no `lib/` folder at all. The
        # assemblies are the package's payload, so the compile group falls
        # back to them the same way it falls back to `lib` assemblies.
        files = [
            "buildTransitive/netstandard2.0/A.dll",
            "buildTransitive/net8.0/A.dll",
        ],
        expected_libs = ["buildTransitive/net8.0/A.dll"],
        expected_refs = ["buildTransitive/net8.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "build_transitive_assemblies_resolve_by_framework_compatibility",
        # A net6.0 build cannot use the net8.0 assemblies and lands on
        # netstandard2.0, through the same nearest-compatible-framework walk
        # as every other group.
        files = [
            "buildTransitive/netstandard2.0/A.dll",
            "buildTransitive/net8.0/A.dll",
        ],
        target_framework = "net6.0",
        expected_libs = ["buildTransitive/netstandard2.0/A.dll"],
        expected_refs = ["buildTransitive/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "only_portable_build_transitive_assemblies_are_collected",
        # `MSTest.TestAdapter` ships `winui`/`uwp` subfolders and a
        # `_localization` folder under `buildTransitive/`; neither is a
        # portable framework folder.
        files = [
            "buildTransitive/net8.0/A.dll",
            "buildTransitive/net8.0/winui/W.dll",
            "buildTransitive/_localization/de/A.resources.dll",
        ],
        expected_libs = ["buildTransitive/net8.0/A.dll"],
        expected_refs = ["buildTransitive/net8.0/A.dll"],
    ),
]
