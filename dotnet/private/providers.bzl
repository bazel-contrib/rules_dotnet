"Providers"
DotnetAssemblyCompileInfo = provider(
    doc = "Compilation information for a .Net assembly.",
    fields = {
        "name": "string: The name of the assembly",
        "version": "string: The version of the assembly",
        "project_sdk": "string: The SDK being targeted",
        "target_framework": "string: The target framework moniker the assembly was compiled for. None for an imported assembly, whose files are chosen per framework and so name no single one.",
        "refs": "list[File]: Reference-only assemblies containing only public symbols.",
        "irefs": "list[File]: Reference-only assemblies containing public and internal symbols, which only the `internals_visible_to` assemblies compile against.",
        "analyzers": "list[File]: Common language analyzer dlls",
        "analyzers_csharp": "list[File]: C# analyzer dlls",
        "analyzers_fsharp": "list[File]: F# analyzer dlls",
        "analyzers_vb": "list[File]: VB analyzer dlls",
        "internals_visible_to": "list[string]: The assemblies that compile against `irefs` rather than `refs`.",
        "compile_data": "list[File]: Compile data files",
        "exports": "list[File]: The reference assemblies of the target's `exports`, which its dependents compile against as if they were their own dependencies.",
        "transitive_refs": "depset[File]: Transitive reference-only assemblies containing only public symbols. Only used when strict deps are off.",
        "transitive_internals": "depset[tuple[File, File, tuple[string]]]: `(ref, iref, internals_visible_to)` for each assembly in `transitive_refs` or `exports` that grants its internals to others.",
        "transitive_compile_data": "depset[File]: Transitive compile data files. Only used when strict deps are off.",
        "transitive_analyzers": "depset[File]: Transitive analyzer dlls. Only used when strict deps are off.",
        "transitive_analyzers_csharp": "depset[File]: Transitive C# analyzer dlls. Only used when strict deps are off.",
        "transitive_analyzers_fsharp": "depset[File]: Transitive F# analyzer dlls. Only used when strict deps are off.",
        "transitive_analyzers_vb": "depset[File]: Transitive VB analyzer dlls. Only used when strict deps are off.",
    },
)

DotnetAssemblyRuntimeInfo = provider(
    doc = "What a .Net assembly needs at run time.",
    fields = {
        "name": "string: The name of the assembly",
        "version": "string: The version of the assembly",
        "libs": "list[File]: Runtime DLLs",
        "pdbs": "list[File]: The PDBs of the assembly",
        "xml_docs": "list[File]: The XML documentation files of the assembly",
        "native": "list[File]: Native runtime files",
        "data": "list[File]: Runtime data files",
        "resource_assemblies": "list[File]: Resource assemblies",
        "appsetting_files": "depset[File]: Appsetting files staged next to the assembly, flattened to their basename.",
        "content_files": "list[struct(file, dest, src)]: Content files staged next to the assembly, where `dest` is each file's path relative to the output directory and `src` is the file it was staged from. Consumers reproduce this layout (e.g. in runfiles or the publish folder).",
        "nuget_info": "NuGetInfo: The package the assembly comes from, or None.",
        "framework_references": "list[string]: The framework references of the assembly itself, such as `Microsoft.AspNetCore.App`.",
        "deps": "depset[DotnetAssemblyRuntimeInfo]: The direct and transitive runtime dependencies of the assembly",
        "direct_deps_depsjson_fragment": "dict[string, string]: The name and version of each direct runtime dependency: the `dependencies` of the assembly's deps.json entry.",
        "ready_to_run": """list[struct]: The ReadyToRun images of `libs`, when a publish asked for them, or None. Each carries

  * `assembly`: the File that was compiled.
  * `image`: its ReadyToRun image.
  * `framework`: the `key` of the framework it was compiled against.
  * `references`: the tuple of Files it was compiled against besides that.""",
    },
)

DotnetContentFilesInfo = provider(
    doc = "Content files with explicit destination paths, from `dotnet_content_files`.",
    fields = {
        "mappings": "list[struct]: `struct(src = File, dest = string)` pairs, where `dest` is the destination path (relative to the assembly output directory) at which `src` should be staged.",
    },
)

DotnetResxInfo = provider(
    doc = "`.resx` files from a `resx_resource`.",
    fields = {
        "resources": "list[struct]: `file`, `culture` (None if neutral), `neutral_path` and `logical_name`.",
        "data": "depset[File]: Files referenced by `ResXFileRef` entries.",
    },
)

StaticWebAssetsInfo = provider(
    doc = "The web-servable files a target contributes, and those of its dependencies.",
    fields = {
        "assets": """depset[struct]: the transitive assets. Each carries

  * `file`: the `File` to serve.
  * `serving_path`: where it is served from, relative to `wwwroot`.
  * `scoped_css_bundle`: whether the file is the target's scoped CSS bundle,
    which an application's own bundle has to `@import`.""",
    },
)

NuGetInfo = provider(
    doc = "Information about a NuGet package.",
    fields = {
        "targeting_pack_overrides": "map[string, string]: Targeting packs like e.g. Microsoft.NETCore.App.Ref have a PackageOverride.txt that includes a list of NuGet packages that should be omitted in a compiliation because they are included in the targeting pack",
        "framework_list": "map[string, string]: Targeting packs like e.g. Microsoft.NETCore.App.Ref have a FrameworkList.xml that includes a list of the DLLs in the targeting pack, and runtime packs a RuntimeList.xml that does the same. This is used for selecting the correct DLL versions during compilation and runtime.",
        "framework_list_file_versions": "map[string, string]: The file version of each assembly in `framework_list`, for breaking ties in assembly version.",
        "framework_list_profiles": "map[string, string]: The `;` separated profiles of each assembly in `framework_list` that is in any, such as `WPF` or `WindowsForms`.",
        "framework_list_analyzer_profiles": "map[string, string]: The `;` separated profiles of each analyzer the FrameworkList.xml lists, keyed by its path inside the package.",
        "sha512": "string: the SHA512 SRI string for the package",
        "nupkg": "File: the underlying `.nupkg` file which provides this package",
        "portable_assets": "NuGetPortableAssetsInfo: The package's assets for an app that runs on any runtime, or None if the import has none.",
    },
)

NuGetPortableAssetsInfo = provider(
    doc = """A NuGet package's assets for an app that runs on any runtime, such as a .NET tool.

`DotnetAssemblyRuntimeInfo.libs` and `.native` hold the configured runtime's
assets. This holds every runtime's, for the configured target framework, as a
RID-less `dotnet publish` lists them.""",
    fields = {
        "libs": "list[File]: The RID-agnostic assemblies under `lib/<tfm>/`, the deps.json `runtime` assets.",
        "runtime_targets": """list[struct]: The deps.json `runtimeTargets`, sorted by `path`. Each has

  * `path`: the file's path in the package, which is also its deps.json key
    and its path in a publish.
  * `file`: the File.
  * `rid`: the RID folder, as the package spells it.
  * `asset_type`: `native` or `runtime`.""",
    },
)

NuGetPackInfo = provider(
    doc = "A NuGet package built by `nuget_pack`.",
    fields = {
        "label": "Label: The `nuget_pack` target, for messages.",
        "package_id": "string: The package id, in the casing it was given.",
        "version": "string: The normalized package version, or None when it is read from `version_file` when the package is built.",
        "version_file": "File: The file the version is read from, or None.",
        "nupkg": "File: The package.",
        "snupkg": "File: The symbol package, or None.",
        "target_frameworks": "list[string]: The frameworks the package ships assets for.",
        "bundled_assemblies": "list[string]: The names of the assemblies the package ships under lib/, runtimes/ or analyzers/, across every framework, its own included. Empty for a tool package. A package that depends on one of these depends on this package.",
        "is_tool": "bool: Whether this is a .NET tool package, which nothing can depend on.",
    },
)

BlazorWasmSiteInfo = provider(
    doc = """A built Blazor WebAssembly application, as the development server wants it.

Carried by anything that produces one - a development build or a publish - so
that `blazor_devserver` can serve either.""",
    fields = {
        "wwwroot": "File: the served directory.",
        "manifest": "File: the endpoint manifest describing it.",
        "assembly": "File: the application's own assembly.",
    },
)

BlazorWasmInfo = provider(
    doc = """Marks a target as a Blazor WebAssembly application.

Carried only by a binary built with `project_sdk = "blazorwasm"`, so that the
choice of SDK and the choice of publish cannot disagree.""",
    fields = {},
)

DotnetBinaryInfo = provider(
    doc = "Information about a .Net binary",
    fields = {
        "dll": "File: The main binary dll",
        "deps_json": """File: The `.deps.json` the binary runs with, or None when the
target framework has none (.NET Framework). It describes the runfiles layout - its paths
are relative to the runfiles root - so it is only valid next to the binary inside a
runfiles tree. Something that is packaged or deployed takes the one `publish_binary`
writes instead.""",
        "runtimeconfig_json": """File: The `.runtimeconfig.json` the binary runs with, or
None when the target framework has none (.NET Framework). Its probing paths point into the
runfiles tree, so the same caveat as `deps_json` applies.""",
        "static_web_files": """list[struct]: The servable tree, as structs of a `file` and
the `publish_path` it takes inside a publish directory. Already materialized by the
binary, so a publish copies these rather than laying the tree out a second time.""",
        "transitive_runtime_deps": "list[DotnetAssemblyRuntimeInfo]: The transitive runtime dependencies of the binary",
        "apphost_pack_info": "DotnetApphostPackInfo: The apphost pack for the binary",
        "runtime_pack_info": "DotnetRuntimePackInfo: The runtime pack for the binary: the shared frameworks it references itself, or every shared framework when a publish ships or compiles against the runtime.",
        "framework_version": "string: The version of the shared frameworks the binary asks for when it is not self-contained",
        "runtime_frameworks": "list[string]: The shared frameworks beyond Microsoft.NETCore.App that the binary and its dependencies reference.",
        "winexe": "bool: True if the binary is a Windows GUI executable (Subsystem.WindowsGui)",
        "app_config": "File: The `app_config` of a .NET binary, as `<assembly>.dll.config`, or None.",
        "netfx_layout": "list[(string, File)]: The files a .NET Framework binary publishes, with their paths in the publish directory. None for other binaries.",
    },
)

DotnetTargetingPackInfo = provider(
    doc = "Information about a .Net targeting pack.",
    fields = {
        "assembly_runtime_infos": "list[DotnetAssemblyRuntimeInfo]: The runtime infos of the assemblies in the targeting pack",
        "assembly_compile_infos": "list[DotnetAssemblyCompileInfo]: The compile infos of the assemblies in the targeting pack",
        "targeting_pack_overrides": "map[string, string]: The merged `PackageOverride.txt` entries of every pack.",
        "framework_list": "map[string, dict]: The merged `FrameworkList.xml` entries of every pack, by lower-cased assembly name. Each is a dict of the assembly's `version` and the ref `file` that provides it, or None.",
        "framework_files": "list[File]: The irefs of packs that do not ship a `FrameworkList.xml`.",
        "framework_files_depset": "depset[File]: `framework_files` plus the resolved files of `framework_list`, for targets that do not narrow the pack.",
        "analyzers": "list[File]: The merged common language analyzers of every pack.",
        "analyzers_csharp": "list[File]: The merged C# analyzers of every pack.",
        "analyzers_fsharp": "list[File]: The merged F# analyzers of every pack.",
        "analyzers_vb": "list[File]: The merged VB analyzers of every pack.",
        "compile_data": "list[File]: The merged compile data of every pack.",
        "nuget_infos": "list[NuGetInfo]: The NuGet infos of the assemblies in the targeting pack",
    },
)

DotnetRuntimePackInfo = provider(
    doc = "Information about a .Net runtime pack.",
    fields = {
        "runtime_identifier": "string: The runtime identifier of the runtime pack",
        "assembly_runtime_infos": "list[DotnetAssemblyRuntimeInfo]: The runtime infos of the assemblies in the runtime pack",
        "nuget_infos": "list[NuGetInfo]: The NuGet infos of the assemblies in the runtime pack",
        "all_assembly_runtime_infos": "list[DotnetAssemblyRuntimeInfo]: `assembly_runtime_infos` before the assemblies another pack shadows are dropped, for `runtime_pack_of_frameworks`.",
    },
)

DotnetToolPackInfo = provider(
    doc = "A native SDK tool, such as crossgen2 or ilc.",
    fields = {
        "tool": "File: The tool's executable.",
        "files": "depset[File]: Everything the tool needs at runtime.",
    },
)

DotnetNativeAotPackInfo = provider(
    doc = "The framework a NativeAOT publish compiles and links against.",
    fields = {
        "libs": "list[File]: The framework assemblies ilc compiles against.",
        "link_inputs": "map[string, File]: The static libraries and objects the native link consumes, by basename.",
        "direct_pinvoke_lists": "list[File]: Lists of the platform's own APIs that ilc may bind directly, as the SDK ships them. Empty except on Windows.",
    },
)

DotnetNativeToolsInfo = provider(
    doc = "The native compiler a ReadyToRun or NativeAOT publish asks its binary for.",
    fields = {
        "crossgen2": "DotnetToolPackInfo: crossgen2, for a ReadyToRun publish, or None.",
        "ilcompiler": "DotnetToolPackInfo: ilc, for a NativeAOT publish, or None.",
        "nativeaot_pack": "DotnetNativeAotPackInfo: The framework ilc compiles and links against, or None.",
        "cc_link_toolchain": "The resolved `@bazel_tools//tools/cpp:toolchain_type` a NativeAOT publish links with, or None for any other publish or where none is registered.",
    },
)

DotnetApphostPackInfo = provider(
    doc = "Information about a .Net apphost pack.",
    fields = {
        "apphost": "File: The apphost file",
        "singlefilehost": "File: The singlefilehost file",
    },
)
