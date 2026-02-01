# Automatic .csproj/.fsproj Integration

This module provides automatic Bazel integration for existing .NET projects by scanning
`.csproj` and `.fsproj` files and generating corresponding Bazel targets.

## Quick Start

Add to your `MODULE.bazel`:

```starlark
dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
dotnet.toolchain(dotnet_version = "10.0.100")
dotnet.scan_projects()
use_repo(dotnet, "dotnet_toolchains", "dotnet_projects")

register_toolchains("@dotnet_toolchains//:all")
```

Then in your `BUILD.bazel` files:

```starlark
load("@dotnet_projects//path/to:MyProject.csproj.bzl", "auto_dotnet_targets")

auto_dotnet_targets(
    name = "MyProject",
    visibility = ["//visibility:public"],
)
```

## How It Works

1. **Scanning**: The extension scans your workspace for all `.csproj` and `.fsproj` files
2. **Parsing**: Each project file is parsed to extract:
   - Target framework(s)
   - Output type (library, executable, test)
   - Source files (explicit or SDK-style defaults)
   - Project references (converted to Bazel labels)
   - Package references (NuGet dependencies)
3. **Generation**: A `.bzl` file is generated for each project containing an
   `auto_dotnet_targets()` macro that creates the appropriate Bazel rule

## Configuration

### Exclude Patterns

You can exclude certain paths from scanning:

```starlark
dotnet.scan_projects(
    exclude_patterns = [
        "**/tests/**",      # Exclude test directories
        "**/legacy/**",     # Exclude legacy code
    ],
)
```

Default exclusions: `**/bin/**`, `**/obj/**`, `**/.git/**`, `**/.jj/**`, `**/bazel-*/**`

### Toolchain Validation

By default, the extension validates that your registered toolchains can build all
discovered target frameworks:

```starlark
dotnet.scan_projects(
    fail_on_missing_toolchain = True,  # Default: fail if TFM not covered
)
```

Set to `False` to only emit warnings instead of failing.

## File Change Detection

### Automatic Detection

Bazel will automatically re-scan and regenerate when:

- Any existing `.csproj` or `.fsproj` file is modified
- New project files are added to directories that already contain projects

### Manual Sync Required

Bazel will **NOT** automatically detect:

- New project files in entirely new directories
- New top-level project directories

To pick up changes in these cases, run:

```bash
bazel sync --only=@dotnet_projects
```

## Requirements

- **Bazel 7.1 or later** - Required for `repository_ctx.workspace_root` support
- **xml.bzl** - Used for parsing XML project files

## Generated Files

The `@dotnet_projects` repository contains:

- `<path>/<project>.csproj.bzl` - Generated macro for each project
- `nuget/packages.bzl` - Consolidated NuGet package references
- `nuget/paket.dependencies.generated` - Paket-compatible dependency file
- `TOOLCHAIN_COVERAGE.md` - Summary of TFM coverage by registered toolchains
- `CONFLICTS.md` - NuGet version conflicts (if any)

## Limitations

1. **NuGet packages**: Package references are extracted but SHA512 hashes are not
   available from project files. Consider using Paket for full dependency management.

2. **Conditional properties**: MSBuild conditions in project files are not fully
   evaluated. The parser extracts a best-effort interpretation.

3. **Custom targets**: Custom MSBuild targets and imports are not processed.

4. **Source generators**: While source generator references are detected, the
   generated sources are not automatically included.

## Overriding Generated Targets

The `auto_dotnet_targets()` macro accepts `**kwargs` to override any generated
attribute:

```starlark
auto_dotnet_targets(
    name = "MyProject",
    visibility = ["//visibility:public"],
    # Override the generated deps
    deps = ["//other:dependency"],
    # Add additional compiler options
    compiler_options = ["/warnaserror"],
)
```

## IDE Support for Bazel-Generated Code

When you have Bazel-generated source files (e.g., from protobuf, gRPC, or OpenAPI),
your IDE won't see them by default because they don't exist until Bazel runs.

Use `dotnet_generated_props` to generate a `.props` file that tells the IDE about
these files:

### Setup

```starlark
# BUILD.bazel
load("@rules_dotnet//dotnet:defs.bzl", "dotnet_generated_props")

# Your code generation rule
proto_csharp_library(
    name = "my_protos",
    protos = ["//proto:services"],
)

# Generate a .props file for IDE integration
dotnet_generated_props(
    name = "sync_ide",
    generated_srcs = [":my_protos"],
    out = "MyProject.Generated.props",
)
```

### Add Import to .csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  
  <!-- Import Bazel-generated sources for IDE support -->
  <Import Project="MyProject.Generated.props" 
          Condition="Exists('MyProject.Generated.props')" />
</Project>
```

### Sync the .props File

```bash
# Update the .props file when generated sources change
bazel run //:sync_ide

# Build will fail if .props is out of date (for CI)
bazel build //:sync_ide
```

### Generated .props Content

The generated file looks like:

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- DO NOT EDIT - Generated by Bazel. Run 'bazel run //:sync_ide' to update. -->
<Project>
  <ItemGroup Label="Bazel Generated Sources">
    <Compile Include="$(MSBuildThisFileDirectory)bazel-bin/proto/MyService.cs">
      <Link>Generated/MyService.cs</Link>
    </Compile>
  </ItemGroup>
</Project>
```

This gives you full IntelliSense and Go to Definition support in your IDE for
Bazel-generated code.
