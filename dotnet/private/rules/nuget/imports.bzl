"""
Rules for importing assemblies for .NET frameworks.
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:common.bzl",
    "collect_compile_info",
    "collect_transitive_runfiles",
)
load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo", "NuGetInfo")

def _import_library(ctx):
    (
        _irefs,
        prefs,
        analyzers,
        analyzers_csharp,
        analyzers_fsharp,
        analyzers_vb,
        _compile_data,
        _framework_files,
        _exports,
    ) = collect_compile_info(
        ctx.label.name,
        ctx.attr.deps,
        None,
        [],
        ctx.toolchains["//dotnet:toolchain_type"].strict_deps[BuildSettingInfo].value,
    )

    nuget_info = NuGetInfo(
        targeting_pack_overrides = ctx.attr.targeting_pack_overrides,
        framework_list = ctx.attr.framework_list,
        sha512 = ctx.attr.sha512,
        nupkg = ctx.file.nupkg,
    )

    dotnet_assembly_compile_info = DotnetAssemblyCompileInfo(
        name = ctx.attr.library_name,
        version = ctx.attr.version,
        project_sdk = "default",
        refs = ctx.files.refs,
        irefs = ctx.files.refs,
        analyzers = ctx.files.analyzers,
        analyzers_csharp = ctx.files.analyzers_csharp,
        analyzers_fsharp = ctx.files.analyzers_fsharp,
        analyzers_vb = ctx.files.analyzers_vb,
        compile_data = [],
        exports = [],
        transitive_compile_data = depset([]),
        transitive_refs = prefs,
        transitive_analyzers = analyzers,
        transitive_analyzers_csharp = analyzers_csharp,
        transitive_analyzers_fsharp = analyzers_fsharp,
        transitive_analyzers_vb = analyzers_vb,
        internals_visible_to = [],
    )

    dotnet_assembly_runtime_info = DotnetAssemblyRuntimeInfo(
        name = ctx.attr.library_name,
        version = ctx.attr.version,
        libs = ctx.files.libs,
        resource_assemblies = ctx.files.resource_assemblies,
        # TODO: PDBs from nuget packages should also be forwarded
        pdbs = [],
        xml_docs = [],
        native = ctx.files.native,
        data = ctx.files.data,
        nuget_info = nuget_info,
        deps = depset([dep[DotnetAssemblyRuntimeInfo] for dep in ctx.attr.deps], transitive = [dep[DotnetAssemblyRuntimeInfo].deps for dep in ctx.attr.deps]),
        direct_deps_depsjson_fragment = {dep[DotnetAssemblyRuntimeInfo].name: dep[DotnetAssemblyRuntimeInfo].version for dep in ctx.attr.deps},
    )

    return [
        DefaultInfo(
            runfiles = collect_transitive_runfiles(ctx, dotnet_assembly_runtime_info, ctx.attr.deps),
        ),
        dotnet_assembly_compile_info,
        dotnet_assembly_runtime_info,
        nuget_info,
    ]

import_library = rule(
    _import_library,
    doc = "Creates a target for a static DLL for a specific target framework",
    attrs = {
        "library_name": attr.string(
            doc = "The name of the library",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "The version of the library",
        ),
        "libs": attr.label_list(
            doc = "Static runtime DLLs",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "native": attr.label_list(
            doc = "Native runtime DLLs",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "analyzers": attr.label_list(
            doc = "Static analyzer DLLs",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "analyzers_csharp": attr.label_list(
            doc = "Static C# analyzer DLLs",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "analyzers_fsharp": attr.label_list(
            doc = "Static F# analyzer DLLs",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "analyzers_vb": attr.label_list(
            doc = "Static VB analyzer DLLs",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "refs": attr.label_list(
            doc = "Compile time DLLs",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "resource_assemblies": attr.label_list(
            doc = "Resource assemblies",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "deps": attr.label_list(
            doc = "Other DLLs that this DLL depends on.",
            providers = [DotnetAssemblyRuntimeInfo, DotnetAssemblyCompileInfo],
        ),
        "data": attr.label_list(
            doc = "Other files that this DLL depends on at runtime",
            allow_files = True,
        ),
        "targeting_pack_overrides": attr.string_dict(
            doc = "Targeting packs like e.g. Microsoft.NETCore.App.Ref have a PackageOverride.txt that includes a list of NuGet packages that should be omitted in a compiliation because they are included in the targeting pack",
            default = {},
        ),
        "framework_list": attr.string_dict(
            doc = "Targeting packs like e.g. Microsoft.NETCore.App.Ref have a PlatformManifest.txt that includes all the DLLs that are included in the targeting pack. This is used to determine which version of a DLL should be used during compilation or runtime.",
            default = {},
        ),
        "sha512": attr.string(
            doc = "The SHA512 sum of the NuGet package",
        ),
        "nupkg": attr.label(
            doc = "The `.nupkg` file providing this import",
            allow_single_file = True,
        ),
    },
    toolchains = [
        "//dotnet:toolchain_type",
    ],
    executable = False,
)

def _import_dll(ctx):
    assembly_compile_info = DotnetAssemblyCompileInfo(
        name = ctx.file.dll.basename[:-4],
        version = ctx.attr.version,
        project_sdk = "default",
        refs = [ctx.file.dll],
        irefs = [],
        analyzers = [],
        analyzers_csharp = [],
        analyzers_fsharp = [],
        analyzers_vb = [],
        compile_data = [],
        exports = [],
        transitive_compile_data = depset([]),
        transitive_refs = depset([]),
        transitive_analyzers = depset([]),
        transitive_analyzers_csharp = depset([]),
        transitive_analyzers_fsharp = depset([]),
        transitive_analyzers_vb = depset([]),
        internals_visible_to = [],
    )
    assembly_runtime_info = DotnetAssemblyRuntimeInfo(
        name = ctx.file.dll.basename[:-4],
        version = ctx.attr.version,
        libs = [ctx.file.dll],
        resource_assemblies = [],
        pdbs = [],
        xml_docs = [],
        native = [],
        data = ctx.files.data,
        deps = depset([]),
        nuget_info = None,
        direct_deps_depsjson_fragment = {},
    )
    return [
        DefaultInfo(
            runfiles = collect_transitive_runfiles(ctx, assembly_runtime_info, []),
        ),
        assembly_compile_info,
        assembly_runtime_info,
    ]

import_dll = rule(
    _import_dll,
    doc = "Imports a DLL",
    attrs = {
        "dll": attr.label(
            doc = "The name of the library",
            mandatory = True,
            allow_single_file = True,
        ),
        "version": attr.string(
            doc = "The version of the library",
        ),
        "data": attr.label_list(
            doc = "Other files that this DLL depends on at runtime",
            allow_files = True,
        ),
    },
    executable = False,
)
