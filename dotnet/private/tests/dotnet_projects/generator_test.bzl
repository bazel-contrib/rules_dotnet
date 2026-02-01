"Tests for .bzl generator utilities"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/rules/dotnet_projects:generator.bzl", "generate_defs_bzl", "generate_project_bzl", "generate_root_build_bazel", "generate_subdir_build_bazel")
load("//dotnet/private/rules/dotnet_projects:parser.bzl", "parse_project_file")

# Test project content
_TEST_LIBRARY_CSPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <EnableDefaultItems>false</EnableDefaultItems>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="lib.cs" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
  </ItemGroup>
</Project>
"""

_TEST_BINARY_CSPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <EnableDefaultItems>false</EnableDefaultItems>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Program.cs" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../lib/lib.csproj" />
  </ItemGroup>
</Project>
"""

_TEST_WEB_CSPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
</Project>
"""

def _generate_library_bzl_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_TEST_LIBRARY_CSPROJ)
    bzl_content = generate_project_bzl(
        parsed,
        "my/path/lib.csproj",
        "my/path",
        False,  # is_fsharp
        "csproj.nuget",
        "",
    )

    # Check that the generated content contains expected elements
    asserts.true(env, "csharp_library" in bzl_content)
    asserts.true(env, 'load("@rules_dotnet//dotnet:defs.bzl"' in bzl_content)
    asserts.true(env, "auto_dotnet_targets" in bzl_content)
    asserts.true(env, '"lib.cs"' in bzl_content)
    asserts.true(env, 'target_frameworks = ["net9.0"]' in bzl_content)
    asserts.true(env, "@csproj.nuget//newtonsoft.json" in bzl_content)
    asserts.true(env, 'nullable = "enable"' in bzl_content)

    return unittest.end(env)

generate_library_bzl_test = unittest.make(_generate_library_bzl_test_impl)

def _generate_binary_bzl_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_TEST_BINARY_CSPROJ)
    bzl_content = generate_project_bzl(
        parsed,
        "app/Program.csproj",
        "app",
        False,  # is_fsharp
        "csproj.nuget",
        "",
    )

    # Check that the generated content uses csharp_binary
    asserts.true(env, "csharp_binary" in bzl_content)
    asserts.true(env, '"Program.cs"' in bzl_content)

    # Check project reference conversion
    asserts.true(env, "//lib:lib" in bzl_content)

    return unittest.end(env)

generate_binary_bzl_test = unittest.make(_generate_binary_bzl_test_impl)

def _generate_web_sdk_bzl_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_TEST_WEB_CSPROJ)
    bzl_content = generate_project_bzl(
        parsed,
        "web/Web.csproj",
        "web",
        False,  # is_fsharp
        "csproj.nuget",
        "",
    )

    # Check that web SDK is properly set
    asserts.true(env, 'project_sdk = "web"' in bzl_content)

    return unittest.end(env)

generate_web_sdk_bzl_test = unittest.make(_generate_web_sdk_bzl_test_impl)

def _generate_fsharp_bzl_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_TEST_LIBRARY_CSPROJ)
    bzl_content = generate_project_bzl(
        parsed,
        "fs/Lib.fsproj",
        "fs",
        True,  # is_fsharp
        "csproj.nuget",
        "",
    )

    # Check that F# rule is used
    asserts.true(env, "fsharp_library" in bzl_content)

    return unittest.end(env)

generate_fsharp_bzl_test = unittest.make(_generate_fsharp_bzl_test_impl)

def _generate_defs_bzl_test_impl(ctx):
    env = unittest.begin(ctx)

    content = generate_defs_bzl()

    # Basic structure check
    asserts.true(env, len(content) > 0)
    asserts.true(env, "Common utilities" in content)

    return unittest.end(env)

generate_defs_bzl_test = unittest.make(_generate_defs_bzl_test_impl)

def _generate_root_build_bazel_test_impl(ctx):
    env = unittest.begin(ctx)

    content = generate_root_build_bazel()

    # Check for exports_files
    asserts.true(env, "exports_files" in content)
    asserts.true(env, "*.bzl" in content)

    return unittest.end(env)

generate_root_build_bazel_test = unittest.make(_generate_root_build_bazel_test_impl)

def _generate_subdir_build_bazel_test_impl(ctx):
    env = unittest.begin(ctx)

    # With bzl files
    content_with_files = generate_subdir_build_bazel(["foo.csproj.bzl", "bar.fsproj.bzl"])
    asserts.true(env, "exports_files" in content_with_files)
    asserts.true(env, "foo.csproj.bzl" in content_with_files)
    asserts.true(env, "bar.fsproj.bzl" in content_with_files)

    # Without bzl files
    content_empty = generate_subdir_build_bazel([])
    asserts.true(env, "No .bzl files" in content_empty)

    return unittest.end(env)

generate_subdir_build_bazel_test = unittest.make(_generate_subdir_build_bazel_test_impl)

def _kwargs_passthrough_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_TEST_LIBRARY_CSPROJ)
    bzl_content = generate_project_bzl(
        parsed,
        "my/path/lib.csproj",
        "my/path",
        False,
        "csproj.nuget",
        "",
    )

    # Check that **kwargs is passed through
    asserts.true(env, "**kwargs" in bzl_content)

    return unittest.end(env)

kwargs_passthrough_test = unittest.make(_kwargs_passthrough_test_impl)

def generator_test_suite(name):
    unittest.suite(
        name,
        generate_library_bzl_test,
        generate_binary_bzl_test,
        generate_web_sdk_bzl_test,
        generate_fsharp_bzl_test,
        generate_defs_bzl_test,
        generate_root_build_bazel_test,
        generate_subdir_build_bazel_test,
        kwargs_passthrough_test,
    )
