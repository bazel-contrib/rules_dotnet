"Providers"
DotnetAssemblyCompileInfo = provider(
    doc = "Compilation information for a .Net assembly.",
    fields = {
        "name": "string: The name of the assembly",
        "version": "string: The version of the assembly",
        "project_sdk": "string: The SDK being targeted",
        "refs": "list[File]: Reference-only assemblies containing only public symbols. See docs/ReferenceAssemblies.md for more info.",
        "irefs": "list[File]: Reference-only assemblies containing public and internal symbols. See docs/ReferenceAssemblies.md for more info.",
        "analyzers": "list[File]: Common language analyzer dlls",
        "analyzers_csharp": "list[File]: C# analyzer dlls",
        "analyzers_fsharp": "list[File]: F# analyzer dlls",
        "analyzers_vb": "list[File]: VB analyzer dlls",
        "internals_visible_to": "list[string]: A list of assemblies that can use the assemblies listed in iref for compilation. See docs/ReferenceAssemblies.md for more info.",
        "compile_data": "list[File]: Compile data files",
        "exports": "list[File]",
        "transitive_refs": "depset[File]: Transitive reference-only assemblies containing only public symbols. Only used when strict deps are off.",
        "transitive_compile_data": "depset[File]: Transitive compile data files. Only used when strict deps are off.",
        "transitive_analyzers": "depset[File]: Transitive analyzer dlls. Only used when strict deps are off.",
        "transitive_analyzers_csharp": "depset[File]: Transitive C# analyzer dlls. Only used when strict deps are off.",
        "transitive_analyzers_fsharp": "depset[File]: Transitive F# analyzer dlls. Only used when strict deps are off.",
        "transitive_analyzers_vb": "depset[File]: Transitive VB analyzer dlls. Only used when strict deps are off.",
    },
)

DotnetAssemblyRuntimeInfo = provider(
    doc = "A DLL or exe.",
    fields = {
        "name": "string: The name of the assembly",
        "version": "string: The version of the assembly",
        "libs": "list[File]: Runtime DLLs",
        "pdbs": "list[File]: The PDBs of the assembly",
        "xml_docs": "list[File]: The XML documentation files of the assembly",
        "native": "list[File]: Native runtime files",
        "data": "list[File]: Runtime data files",
        "resource_assemblies": "list[File]: Resource assemblies",
        "appsetting_files": "list[File]: Appsetting files",
        "nuget_info": "NugetInfo",
        "deps": "depset[DotnetAssemblyRuntimeInfo]: The direct and transitive runtime dependencies of the assembly",
        "direct_deps_depsjson_fragment": "struct: A struct containing the direct deps of the target. This is used during deps.json generation and is generated in the provider to avoid making the provider too bloated and thus making analysis slower.",
    },
)

StaticWebAssetsInfo = provider(
    doc = "The web-servable files a target contributes, and those of its dependencies.",
    fields = {
        "assets": """depset[struct]: the transitive assets. Each carries

  * `file`: the `File` to serve.
  * `serving_path`: where it is served from, relative to `wwwroot`. A library's
    assets are prefixed with `_content/<assembly name>`, matching the base path
    MSBuild gives a Razor class library; an application's sit at the root.
  * `scoped_css_bundle`: whether the file is the target's scoped CSS bundle,
    which an application's own bundle has to `@import`.""",
    },
)

DotnetDepVariantInfo = provider(
    doc = "A wrapper provider for a dependency. The dependency can be a project " +
          "dependency, in which case the `assembly_runtime_info` will be populated" +
          "or a NuGet dependency, in which case `assembly_runtime_info` and `nuget_info` will be populated.",
    fields = {
        "label": "Label: The label of the dependency",
        "assembly_runtime_info": "DotnetAssemblyRuntimeInfo: The DotnetAssemblyRuntimeInfo provider of a dependency",
        "nuget_info": "NuGetInfo: The NuGet info of a dependency",
    },
)

NuGetInfo = provider(
    doc = "Information about a NuGet package.",
    fields = {
        "targeting_pack_overrides": "map[string, string]: Targeting packs like e.g. Microsoft.NETCore.App.Ref have a PackageOverride.txt that includes a list of NuGet packages that should be omitted in a compiliation because they are included in the targeting pack",
        "framework_list": "map[string, string]: Targeting packs like e.g. Microsoft.NETCore.App.Ref have a FrameworkList.xml that includes a list of the DLLs in the targeting pack. This is used for selecting the correct DLL versions during compilation and runtime.",
        "sha512": "string: the SHA512 SRI string for the package",
        "nupkg": "File: the underlying `.nupkg` file which provides this package",
    },
)

DotnetBinaryInfo = provider(
    doc = "Information about a .Net binary",
    fields = {
        "dll": "File: The main binary dll",
        "static_web_files": """list[struct]: The servable tree, as structs of a `file` and
the `publish_path` it takes inside a publish directory. Already materialized by the
binary, so a publish copies these rather than laying the tree out a second time.""",
        "transitive_runtime_deps": "list[DotnetAssemblyRuntimeInfo]: The transitive runtime dependencies of the binary",
        "apphost_pack_info": "DotnetApphostPackInfo: The apphost pack for the binary",
        "runtime_pack_info": "DotnetRuntimePackInfo: The runtime pack for the binary",
    },
)

DotnetTargetingPackInfo = provider(
    doc = "Information about a .Net targeting pack.",
    fields = {
        "assembly_runtime_infos": "list[DotnetAssemblyRuntimeInfo]: The runtime infos of the assemblies in the targeting pack",
        "assembly_compile_infos": "list[DotnetAssemblyCompileInfo]: The compile infos of the assemblies in the targeting pack",
        "targeting_pack_overrides": "map[string, string]: The merged `PackageOverride.txt` entries of every pack.",
        "framework_list": "map[string, struct]: The merged `FrameworkList.xml` entries of every pack, resolved to the ref File that provides each assembly.",
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
        "assembly_runtime_infos": "list[DotnetAssemblyRuntimeInfo]: The runtime infos of the assemblies in the targeting pack",
        "nuget_infos": "list[NuGetInfo]: The NuGet infos of the assemblies in the targeting pack",
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
    },
)

DotnetApphostPackInfo = provider(
    doc = "Information about a .Net runtime pack.",
    fields = {
        "apphost": "File: The apphost file",
    },
)
