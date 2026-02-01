"extensions for bzlmod"

load("//dotnet/private/rules/dotnet_projects:dotnet_projects_repo.bzl", "dotnet_projects_repo")
load(":repositories.bzl", "dotnet_register_toolchains")

_DEFAULT_NAME = "dotnet"

# buildifier: disable=unsorted-dict-items
_TOOLCHAIN_ATTRS = {
    "name": attr.string(
        doc = "Base name for generated repositories",
        default = _DEFAULT_NAME,
    ),
    "dotnet_version": attr.string(
        doc = "Version of the .Net SDK",
    ),
}

# buildifier: disable=unsorted-dict-items
_SCAN_PROJECTS_ATTRS = {
    "exclude_patterns": attr.string_list(
        doc = """Glob patterns for paths to exclude from scanning.
        
Default patterns exclude bin/, obj/, .git/, .jj/, and bazel-* directories.""",
    ),
    "nuget_repo_name": attr.string(
        default = "dotnet_projects.nuget",
        doc = """Name of the NuGet repository to generate.
            
Packages can be referenced as @{nuget_repo_name}//PackageName.""",
    ),
    "auto_register_toolchains": attr.bool(
        default = False,
        doc = """If true, automatically register toolchains for discovered TFMs.
        
When enabled, the extension will analyze target frameworks from all discovered
.csproj/.fsproj files and register any missing toolchains needed to build them.""",
    ),
    "fail_on_missing_toolchain": attr.bool(
        default = True,
        doc = """If true, fail when a project targets a TFM not covered by registered toolchains.
        
Set to false to only emit warnings instead of failing.""",
    ),
}

def _toolchain_extension(module_ctx):
    # Collect registered toolchains
    registrations = {}
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            if toolchain.name in registrations.keys():
                if toolchain.name == _DEFAULT_NAME:
                    # Prioritize the root-most registration of the default dotnet toolchain version and
                    # ignore any further registrations (modules are processed breadth-first)
                    continue
                if toolchain.dotnet_version == registrations[toolchain.name]:
                    # No problem to register a matching toolchain twice
                    continue
                fail("Multiple conflicting toolchains declared for name {} ({} and {})".format(
                    toolchain.name,
                    toolchain.dotnet_version,
                    registrations[toolchain.name],
                ))
            else:
                registrations[toolchain.name] = toolchain.dotnet_version

    # Collect scan_projects configuration
    scan_config = None
    for mod in module_ctx.modules:
        for config in mod.tags.scan_projects:
            if scan_config != None:
                # Only use first scan_projects configuration (from root module)
                continue
            scan_config = config

    # Register toolchains
    for name, dotnet_version in registrations.items():
        dotnet_register_toolchains(
            name = name,
            dotnet_version = dotnet_version,
            register = False,
        )

    # Handle project scanning if enabled
    repos_to_return = []
    if scan_config != None:
        # Configure exclude patterns
        exclude_patterns = ["**/bin/**", "**/obj/**", "**/.git/**", "**/.jj/**", "**/bazel-*/**"]
        if scan_config.exclude_patterns:
            exclude_patterns = exclude_patterns + list(scan_config.exclude_patterns)

        nuget_repo_name = scan_config.nuget_repo_name if scan_config.nuget_repo_name else "dotnet_projects.nuget"

        # Create the csproj repository
        # The repository rule will use @@//:MODULE.bazel to find the workspace root
        dotnet_projects_repo(
            name = "dotnet_projects",
            exclude_patterns = exclude_patterns,
            nuget_repo_name = nuget_repo_name,
            # Pass registered toolchains for validation
            registered_toolchains = json.encode(registrations),
            auto_register_toolchains = scan_config.auto_register_toolchains,
            fail_on_missing_toolchain = scan_config.fail_on_missing_toolchain,
        )
        repos_to_return.append("dotnet_projects")

    return module_ctx.extension_metadata(
        reproducible = False if scan_config else True,
        root_module_direct_deps = repos_to_return if repos_to_return else "all",
        root_module_direct_dev_deps = [],
    )

dotnet = module_extension(
    implementation = _toolchain_extension,
    # buildifier: disable=unsorted-dict-items
    tag_classes = {
        "toolchain": tag_class(attrs = _TOOLCHAIN_ATTRS),
        "scan_projects": tag_class(
            attrs = _SCAN_PROJECTS_ATTRS,
            doc = """Enable automatic scanning of .csproj and .fsproj files.

When enabled, the extension will:
1. Scan the workspace for .csproj and .fsproj files
2. Parse each file to extract properties, sources, and dependencies
3. Generate a @dotnet_projects repository with .bzl files for each project
4. Validate that registered toolchains cover all discovered target frameworks

Usage in MODULE.bazel:
    dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
    dotnet.toolchain(dotnet_version = "10.0.100")
    dotnet.scan_projects()
    use_repo(dotnet, "dotnet_toolchains", "dotnet_projects")

Usage in BUILD files:
    load("@dotnet_projects//path/to:MyProject.csproj.bzl", "auto_dotnet_targets")
    auto_dotnet_targets(name = "MyProject")

File Change Detection:
    Changes to existing .csproj/.fsproj files are automatically detected.
    New files in existing project directories are also detected.
    
    However, new project files in entirely new directories require manual sync:
        bazel sync --only=@dotnet_projects

Requirements:
    Bazel 7.1 or later is required for the scan_projects feature.
""",
        ),
    },
    doc = """Extension for .NET toolchains and project scanning.

This extension provides two main features:
1. Toolchain registration via dotnet.toolchain()
2. Project scanning via dotnet.scan_projects()

The extension will validate that registered toolchains can build all discovered
target frameworks, and optionally auto-register missing toolchains.
""",
)
