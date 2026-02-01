"Tests for csproj parser utilities"

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/rules/dotnet_projects:parser.bzl", "extract_additional_attrs", "get_bazel_rule_name", "get_project_sdk_attr", "get_project_type", "parse_project_file")

# Test XML content for a simple C# library
_CSHARP_LIBRARY_CSPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <EnableDefaultItems>false</EnableDefaultItems>
    <Nullable>enable</Nullable>
    <LangVersion>12</LangVersion>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="lib.cs" />
    <Compile Include="helper.cs" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
  </ItemGroup>
</Project>
"""

# Test XML content for a C# binary
_CSHARP_BINARY_CSPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Program.cs" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="../lib/lib.csproj" />
  </ItemGroup>
</Project>
"""

# Test XML content for a web SDK project
_WEB_SDK_CSPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <OutputType>Exe</OutputType>
  </PropertyGroup>
</Project>
"""

# Test XML content with multi-targeting
_MULTI_TARGET_CSPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net8.0;net9.0;netstandard2.0</TargetFrameworks>
  </PropertyGroup>
</Project>
"""

# Test XML content for F# project
_FSHARP_CSPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
    <EnableDefaultItems>false</EnableDefaultItems>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="Lib.fs" />
    <Compile Include="Main.fs" />
  </ItemGroup>
</Project>
"""

# Test XML content with additional properties
_PROPERTIES_CSPROJ = """<?xml version="1.0" encoding="utf-8"?>
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <WarningLevel>5</WarningLevel>
    <AllowUnsafeBlocks>true</AllowUnsafeBlocks>
  </PropertyGroup>
</Project>
"""

def _parse_csharp_library_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_CSHARP_LIBRARY_CSPROJ)

    asserts.equals(env, "Microsoft.NET.Sdk", parsed.sdk)
    asserts.equals(env, ["net9.0"], parsed.target_frameworks)
    asserts.equals(env, "Library", parsed.output_type)
    asserts.equals(env, ["lib.cs", "helper.cs"], parsed.sources)
    asserts.equals(env, False, parsed.enable_default_items)
    asserts.equals(env, 1, len(parsed.package_references))
    asserts.equals(env, "Newtonsoft.Json", parsed.package_references[0].id)
    asserts.equals(env, "13.0.3", parsed.package_references[0].version)
    asserts.equals(env, "enable", parsed.properties.get("Nullable"))
    asserts.equals(env, "12", parsed.properties.get("LangVersion"))
    asserts.equals(env, [], parsed.errors)

    return unittest.end(env)

parse_csharp_library_test = unittest.make(_parse_csharp_library_test_impl)

def _parse_csharp_binary_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_CSHARP_BINARY_CSPROJ)

    asserts.equals(env, "Microsoft.NET.Sdk", parsed.sdk)
    asserts.equals(env, ["net8.0"], parsed.target_frameworks)
    asserts.equals(env, "Exe", parsed.output_type)
    asserts.equals(env, ["Program.cs"], parsed.sources)
    asserts.equals(env, 1, len(parsed.project_references))
    asserts.equals(env, "../lib/lib.csproj", parsed.project_references[0].path)
    asserts.equals(env, [], parsed.errors)

    return unittest.end(env)

parse_csharp_binary_test = unittest.make(_parse_csharp_binary_test_impl)

def _parse_web_sdk_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_WEB_SDK_CSPROJ)

    asserts.equals(env, "Microsoft.NET.Sdk.Web", parsed.sdk)
    asserts.equals(env, ["net9.0"], parsed.target_frameworks)
    asserts.equals(env, "Exe", parsed.output_type)

    return unittest.end(env)

parse_web_sdk_test = unittest.make(_parse_web_sdk_test_impl)

def _parse_multi_target_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_MULTI_TARGET_CSPROJ)

    asserts.equals(env, ["net8.0", "net9.0", "netstandard2.0"], parsed.target_frameworks)

    return unittest.end(env)

parse_multi_target_test = unittest.make(_parse_multi_target_test_impl)

def _parse_fsharp_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_FSHARP_CSPROJ)

    # F# source order matters - verify order is preserved
    asserts.equals(env, ["Lib.fs", "Main.fs"], parsed.sources)
    asserts.equals(env, "Exe", parsed.output_type)

    return unittest.end(env)

parse_fsharp_test = unittest.make(_parse_fsharp_test_impl)

def _get_project_type_test_impl(ctx):
    env = unittest.begin(ctx)

    library_parsed = parse_project_file(_CSHARP_LIBRARY_CSPROJ)
    binary_parsed = parse_project_file(_CSHARP_BINARY_CSPROJ)

    asserts.equals(env, "library", get_project_type(library_parsed))
    asserts.equals(env, "binary", get_project_type(binary_parsed))

    return unittest.end(env)

get_project_type_test = unittest.make(_get_project_type_test_impl)

def _get_bazel_rule_name_test_impl(ctx):
    env = unittest.begin(ctx)

    library_parsed = parse_project_file(_CSHARP_LIBRARY_CSPROJ)
    binary_parsed = parse_project_file(_CSHARP_BINARY_CSPROJ)

    asserts.equals(env, "csharp_library", get_bazel_rule_name(library_parsed, False))
    asserts.equals(env, "csharp_binary", get_bazel_rule_name(binary_parsed, False))
    asserts.equals(env, "fsharp_library", get_bazel_rule_name(library_parsed, True))
    asserts.equals(env, "fsharp_binary", get_bazel_rule_name(binary_parsed, True))

    return unittest.end(env)

get_bazel_rule_name_test = unittest.make(_get_bazel_rule_name_test_impl)

def _get_project_sdk_attr_test_impl(ctx):
    env = unittest.begin(ctx)

    regular_parsed = parse_project_file(_CSHARP_LIBRARY_CSPROJ)
    web_parsed = parse_project_file(_WEB_SDK_CSPROJ)

    asserts.equals(env, None, get_project_sdk_attr(regular_parsed))
    asserts.equals(env, "web", get_project_sdk_attr(web_parsed))

    return unittest.end(env)

get_project_sdk_attr_test = unittest.make(_get_project_sdk_attr_test_impl)

def _extract_additional_attrs_test_impl(ctx):
    env = unittest.begin(ctx)

    parsed = parse_project_file(_PROPERTIES_CSPROJ)
    attrs = extract_additional_attrs(parsed)

    asserts.equals(env, True, attrs.get("treat_warnings_as_errors"))
    asserts.equals(env, 5, attrs.get("warning_level"))
    asserts.equals(env, True, attrs.get("allow_unsafe_blocks"))

    # Test nullable extraction
    nullable_parsed = parse_project_file(_CSHARP_LIBRARY_CSPROJ)
    nullable_attrs = extract_additional_attrs(nullable_parsed)
    asserts.equals(env, "enable", nullable_attrs.get("nullable"))
    asserts.equals(env, "12", nullable_attrs.get("langversion"))

    return unittest.end(env)

extract_additional_attrs_test = unittest.make(_extract_additional_attrs_test_impl)

def parser_test_suite(name):
    unittest.suite(
        name,
        parse_csharp_library_test,
        parse_csharp_binary_test,
        parse_web_sdk_test,
        parse_multi_target_test,
        parse_fsharp_test,
        get_project_type_test,
        get_bazel_rule_name_test,
        get_project_sdk_attr_test,
        extract_additional_attrs_test,
    )
