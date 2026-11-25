"""
Rules for importing assemblies for .NET frameworks.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(
    "//dotnet/private:common.bzl",
    "collect_compile_info",
    "collect_transitive_runfiles",
    "get_toolchain",
)
load(
    "//dotnet/private:providers.bzl",
    "DotnetAssemblyCompileInfo",
    "DotnetAssemblyRuntimeInfo",
    "NuGetInfo",
    "NuGetPortableAssetsInfo",
)
load(
    "//dotnet/private/rules/common:static_web_assets.bzl",
    "PACKAGE_CONTENT_ROOT",
    "collect_static_web_assets",
)
load(
    "//dotnet/private/rules/ready_to_run:ready_to_run.bzl",
    "READY_TO_RUN_ATTRS",
    "compile_ready_to_run_images",
    "get_ready_to_run_tools",
)
load("//dotnet/private/transitions:native_transition.bzl", "native_transition")

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
        transitive_internals,
    ) = collect_compile_info(
        ctx.label.name,
        ctx.attr.deps,
        None,
        [],
        get_toolchain(ctx).strict_deps[BuildSettingInfo].value,
    )

    nuget_info = NuGetInfo(
        targeting_pack_overrides = ctx.attr.targeting_pack_overrides,
        framework_list = ctx.attr.framework_list,
        framework_list_file_versions = ctx.attr.framework_list_file_versions,
        framework_list_profiles = ctx.attr.framework_list_profiles,
        framework_list_analyzer_profiles = ctx.attr.framework_list_analyzer_profiles,
        sha512 = ctx.attr.sha512,
        nupkg = ctx.file.nupkg,
        portable_assets = ctx.attr.portable_assets[NuGetPortableAssetsInfo] if ctx.attr.portable_assets else None,
    )

    dotnet_assembly_compile_info = DotnetAssemblyCompileInfo(
        name = ctx.attr.library_name,
        version = ctx.attr.version,
        project_sdk = "default",
        target_framework = None,
        refs = ctx.files.refs,
        irefs = ctx.files.refs,
        analyzers = ctx.files.analyzers,
        analyzers_csharp = ctx.files.analyzers_csharp,
        analyzers_fsharp = ctx.files.analyzers_fsharp,
        analyzers_vb = ctx.files.analyzers_vb,
        compile_data = ctx.files.typeproviders,
        exports = [],
        transitive_compile_data = depset([]),
        transitive_refs = prefs,
        transitive_internals = transitive_internals,
        transitive_analyzers = analyzers,
        transitive_analyzers_csharp = analyzers_csharp,
        transitive_analyzers_fsharp = analyzers_fsharp,
        transitive_analyzers_vb = analyzers_vb,
        internals_visible_to = [],
    )

    runtime_deps = depset([dep[DotnetAssemblyRuntimeInfo] for dep in ctx.attr.deps], transitive = [dep[DotnetAssemblyRuntimeInfo].deps for dep in ctx.attr.deps])

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
        content_files = [],
        nuget_info = nuget_info,
        framework_references = ctx.attr.framework_references,
        deps = runtime_deps,
        direct_deps_depsjson_fragment = {dep[DotnetAssemblyRuntimeInfo].name: dep[DotnetAssemblyRuntimeInfo].version for dep in ctx.attr.deps},
        ready_to_run = compile_ready_to_run_images(ctx.actions, get_ready_to_run_tools(ctx), ctx.label, ctx.files.libs, runtime_deps, ctx.attr.framework_references),
    )

    return [
        DefaultInfo(
            runfiles = collect_transitive_runfiles(ctx, dotnet_assembly_runtime_info, ctx.attr.deps),
        ),
        dotnet_assembly_compile_info,
        dotnet_assembly_runtime_info,
        # A packed Razor class library serves its files from
        # `_content/<package id>`, the same base path a library target uses,
        # unless its manifest says otherwise.
        collect_static_web_assets(
            label = ctx.label,
            assembly_name = ctx.attr.library_name,
            files = ctx.files.static_web_assets,
            deps = ctx.attr.deps,
            is_application = False,
            content_root = PACKAGE_CONTENT_ROOT,
            declared_base_path = ctx.attr.static_web_assets_base_path,
        ),
        nuget_info,
    ]

import_library = rule(
    _import_library,
    doc = """Imports prebuilt assemblies, such as the contents of a NuGet package, as a dependency of .NET targets.

`nuget_repo` and the `paket` module extension declare one per package; the
file groups are expected to already be resolved for the target framework and
runtime identifier being built.""",
    attrs = dicts.add(READY_TO_RUN_ATTRS, {
        "library_name": attr.string(
            doc = "The package id. Names the library in the `deps.json` of a binary that depends on it.",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "The package version.",
        ),
        "typeproviders": attr.label_list(
            doc = "The design time assemblies of any F# type providers the package ships.",
            allow_files = True,
            allow_empty = True,
            default = [],
        ),
        "static_web_assets": attr.label_list(
            doc = "Files the package serves over HTTP, from its `staticwebassets` folder.",
            allow_files = True,
            allow_empty = True,
            default = [],
        ),
        "static_web_assets_base_path": attr.string(
            doc = """Where `static_web_assets` are served from, as the package's manifest declares it.

`/` is the root, which is where .NET 11 serves a framework's own scripts from.
Empty for `_content/<library_name>`, MSBuild's default.""",
        ),
        "libs": attr.label_list(
            doc = "The assemblies a binary that depends on this import loads at run time.",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "native": attr.label_list(
            doc = "The native libraries a binary that depends on this import loads at run time.",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
            cfg = native_transition,
        ),
        "analyzers": attr.label_list(
            doc = "Analyzers and source generators for every language.",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "analyzers_csharp": attr.label_list(
            doc = "Analyzers and source generators for C# only.",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "analyzers_fsharp": attr.label_list(
            doc = "Analyzers for F# only.",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "analyzers_vb": attr.label_list(
            doc = "Analyzers and source generators for Visual Basic only.",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "refs": attr.label_list(
            doc = "The assemblies the compiler references.",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "resource_assemblies": attr.label_list(
            doc = "Localized satellite assemblies, each in a folder named after its culture.",
            allow_files = True,  # [".dll"] currently does not work with empty file groups
            allow_empty = True,
        ),
        "deps": attr.label_list(
            doc = "The imports and libraries this import depends on.",
            providers = [DotnetAssemblyRuntimeInfo, DotnetAssemblyCompileInfo],
        ),
        "data": attr.label_list(
            doc = "Other files needed at run time.",
            allow_files = True,
            cfg = native_transition,
        ),
        "targeting_pack_overrides": attr.string_dict(
            doc = """For a targeting pack: the packages the framework provides itself.

Maps a lower cased package id to the newest version the framework supersedes.
A dependency on that package at or below that version is not referenced.""",
            default = {},
        ),
        "framework_list": attr.string_dict(
            doc = """For a targeting pack: the assemblies the framework provides.

Maps a lower cased assembly name to the version the framework ships. A
dependency on an assembly of the same name is only referenced when it is
newer.""",
            default = {},
        ),
        "framework_list_file_versions": attr.string_dict(
            doc = "The file version of each assembly in `framework_list`.",
            default = {},
        ),
        "framework_list_profiles": attr.string_dict(
            doc = "The `;` separated profiles of each assembly in `framework_list` that is in any.",
            default = {},
        ),
        "framework_list_analyzer_profiles": attr.string_dict(
            doc = "The `;` separated profiles of each analyzer the pack's FrameworkList.xml lists, keyed by its path inside the package.",
            default = {},
        ),
        "framework_references": attr.string_list(
            doc = """The shared frameworks the package needs, from the `<frameworkReferences>` of its `.nuspec`.""",
            default = [],
        ),
        "sha512": attr.string(
            doc = "The subresource integrity of the `.nupkg`, written to the `deps.json` of binaries that depend on this import.",
        ),
        "nupkg": attr.label(
            doc = "The `.nupkg` this import was unpacked from, if any.",
            allow_single_file = True,
        ),
        "portable_assets": attr.label(
            doc = """Every runtime's assets of the package, for an app that runs on any runtime.

A .NET tool package ships these. Without them, a tool package that depends on
this import ships `libs` as they are and cannot ship `native`.""",
            providers = [NuGetPortableAssetsInfo],
        ),
    }),
    toolchains = [
        "//dotnet/toolchain:toolchain_type",
    ],
    executable = False,
)

def _import_dll(ctx):
    assembly_compile_info = DotnetAssemblyCompileInfo(
        name = ctx.file.dll.basename[:-4],
        version = ctx.attr.version,
        project_sdk = "default",
        target_framework = None,
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
        transitive_internals = depset([]),
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
        content_files = [],
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
    doc = "Imports a single prebuilt assembly, which is both referenced at compile time and loaded at run time.",
    attrs = {
        "dll": attr.label(
            doc = "The assembly. Its file name, less `.dll`, is the assembly name.",
            mandatory = True,
            allow_single_file = True,
        ),
        "version": attr.string(
            doc = "The version of the assembly.",
        ),
        "data": attr.label_list(
            doc = "Other files needed at run time.",
            allow_files = True,
            cfg = native_transition,
        ),
    },
    executable = False,
)
