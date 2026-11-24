"The attributes of the C# and F# binary, library and test rules."

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load("//dotnet/private:providers.bzl", "DotnetAssemblyCompileInfo", "DotnetAssemblyRuntimeInfo")
load("//dotnet/private/rules/common:static_web_assets.bzl", "STATIC_WEB_ASSETS_ATTRS")
load("//dotnet/private/rules/ready_to_run:ready_to_run.bzl", "READY_TO_RUN_ATTRS")
load("//dotnet/private/sdk:packs.bzl", "USER_PACKS", "USER_PROJECT_SDKS")
load("//dotnet/private/sdk/apphost_packs:apphost_pack_transition.bzl", "apphost_pack_transition")
load("//dotnet/private/sdk/runtime_packs:runtime_pack_transition.bzl", "runtime_pack_transition")
load("//dotnet/private/sdk/targeting_packs:targeting_pack_transition.bzl", "targeting_pack_transition")
load("//dotnet/private/transitions:default_transition.bzl", "default_transition")

# The attributes of every binary, library and test rule. Those that take files
# transition to the default configuration, so that a .NET target producing one
# is not built for this target's framework.
COMMON_ATTRS = {
    "embed_sources": attr.bool(
        doc = """Whether the PDB embeds the source files. Unset, follows `//dotnet/settings:embed_all_sources`.""",
        mandatory = False,
        default = False,
    ),
    "deps": attr.label_list(
        doc = "The libraries, binaries and imported assemblies this target compiles against and runs with.",
        providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
    ),
    "data": attr.label_list(
        doc = "Files the assembly reads at run time from its runfiles. Read them with the `@rules_dotnet//tools/runfiles` library.",
        allow_files = True,
        default = [],
        allow_empty = True,
        cfg = default_transition,
    ),
    "compile_data": attr.label_list(
        doc = "Additional files the compiler needs.",
        allow_files = True,
        default = [],
        allow_empty = True,
        cfg = default_transition,
    ),
    "content_files": attr.label_list(
        doc = """Data files copied next to the assembly, where the app finds them relative to `AppContext.BaseDirectory`.

        Each file keeps its path relative to this target's package; a file from another package
        keeps only its file name. To choose the destination paths, list a
        [`dotnet_content_files`](#dotnet_content_files) target instead.

        A library's content files are also copied next to every binary, test and publish that
        depends on it, at the same paths. The build fails if two different files would land on
        the same path.""",
        allow_files = True,
        default = [],
        allow_empty = True,
        cfg = default_transition,
    ),
    "keyfile": attr.label(
        doc = "The key file used to sign the assembly with a strong name.",
        allow_single_file = True,
        cfg = default_transition,
    ),
    "langversion": attr.string(
        doc = "The language version to compile with. Unset, C# uses the version the .NET SDK picks for the target framework, and F# the compiler's default.",
    ),
    "resources": attr.label_list(
        doc = """Files to embed in the assembly.

        A file is embedded as `<assembly name>.<path>`, where `<path>` is its path relative to this
        target's package with `/` replaced by `.`; a file from another package keeps only its file
        name. `.resx` files are compiled, and culture ones (`Strings.fr.resx`) go into satellite
        assemblies, as in MSBuild.""",
        allow_files = True,
        cfg = default_transition,
    ),
    "root_namespace": attr.string(
        doc = "MSBuild's `RootNamespace`, which prefixes `.resx` resource names and Razor component namespaces. Defaults to the target name.",
    ),
    "_resx_tool": attr.label(
        doc = "Compiles `.resx` files with the SDK's GenerateResource task.",
        default = "//dotnet/private/tools/resx",
        cfg = "exec",
    ),
    "_csharp_compiler_worker": attr.label(
        doc = """The persistent worker that runs the C# compiler, keeping Roslyn's build server alive between compilations.

        Resolves to nothing unless `//dotnet/settings:use_compiler_worker` is
        set, so that a workspace that does not use the worker never analyses
        it.""",
        default = "//dotnet/settings:csharp_compiler_worker",
        cfg = "exec",
    ),
    "out": attr.string(
        doc = "The name of the assembly, which is also its file name without the extension. Defaults to the target name.",
    ),
    "version": attr.string(
        doc = """The version of the assembly, as a NuGet version string: `1.2.3`,
        `1.2.3-beta.1` or `1.2.3-beta.1+sha.abcdef`.

        The assembly's `AssemblyVersion` and `AssemblyFileVersion` are the numeric part padded to
        four components (`1.2.3` becomes `1.2.3.0`), and its `AssemblyInformationalVersion` is the
        whole string.

        Unset, the assembly carries none of these attributes, and is versioned `1.0.0` in the
        `.deps.json` of the applications that use it.""",
        default = "",
    ),
    "user_secrets_id": attr.string(
        doc = """The user secrets ID of the assembly, MSBuild's `UserSecretsId`.

        When set, the assembly carries a `UserSecretsIdAttribute`, which `AddUserSecrets` and the
        default host builder read to find the secrets file:
        `$HOME/.microsoft/usersecrets/<id>/secrets.json`, or
        `%APPDATA%\\Microsoft\\UserSecrets\\<id>\\secrets.json` on Windows.

        The target must reference `Microsoft.Extensions.Configuration.UserSecrets`, through
        `project_sdk = "web"` or the NuGet package in `deps`, or the compile fails.

        `bazel run` finds the user's secrets. `bazel test` does not, as it points `HOME` at an
        empty directory: user secrets are optional, so their values are silently missing.
        `--test_env=HOME` (`--test_env=APPDATA` on Windows) restores them for local runs, at the
        cost of hermeticity; it cannot work under remote execution.""",
        default = "",
    ),
    "target_frameworks": attr.string_list(
        doc = """The target frameworks the target supports, such as `net8.0` or `netstandard2.0`.
        See https://learn.microsoft.com/en-us/dotnet/standard/frameworks

        The target is built for one of them. As a dependency, it is the one NuGet would pick for
        the depending target: the nearest compatible framework, or, for a .NET (Core) target with
        none compatible, a .NET Framework one (`AssetTargetFallback`). Built on its own, it is the
        newest, with .NET ahead of .NET Framework ahead of .NET Standard.""",
        mandatory = True,
        allow_empty = False,
    ),
    "project_sdk": attr.string(
        doc = "The MSBuild project SDK the target is built like: `default` (`Microsoft.NET.Sdk`), " +
              "`web` (ASP.NET Core), `razor` (a Razor class library) or `blazorwasm` (Blazor WebAssembly). " +
              "See https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview",
        default = "default",
        values = USER_PROJECT_SDKS,
    ),
    "framework_references": attr.string_list(
        doc = """Shared frameworks the target references besides Microsoft.NETCore.App, like MSBuild's `<FrameworkReference>` items.

        * `Microsoft.AspNetCore.App`: ASP.NET Core, implied by `project_sdk = "web"`.
        * `Microsoft.WindowsDesktop.App.WPF`: WPF, like `<UseWPF>`.
        * `Microsoft.WindowsDesktop.App.WindowsForms`: Windows Forms, like `<UseWindowsForms>`.
        * `Microsoft.WindowsDesktop.App`: both.

        Windows Forms and WPF need a `-windows` target framework, such as
        `net8.0-windows`. A self-contained publish only bundles the frameworks
        the binary itself lists, so it must list those its dependencies need.""",
        default = [],
    ),
    "defines": attr.string_list(
        doc = "Preprocessor symbols to define, besides the ones the .NET SDK defines for the target framework, such as `NET8_0_OR_GREATER`.",
        default = [],
        allow_empty = True,
    ),
    "static_web_assets": attr.label_list(
        doc = """Files the target serves over HTTP, such as a `wwwroot` tree.

        Each file is served at its path relative to the `wwwroot` directory
        it sits under. A library's assets are served under
        `_content/<assembly name>`.""",
        allow_files = True,
        default = [],
        allow_empty = True,
        cfg = default_transition,
    ),
    "internals_visible_to": attr.string_list(
        doc = "The names of the assemblies that can see this assembly's internal symbols, as with " +
              "`InternalsVisibleTo`. Prefer this to the attribute: other dependents then do not " +
              "recompile when only internals change.",
    ),
    "treat_warnings_as_errors": attr.bool(
        doc = "Treat all compiler warnings as errors. Cannot be combined with `warnings_as_errors`.",
        mandatory = False,
        default = False,
    ),
    "warnings_as_errors": attr.string_list(
        doc = "Compiler warning codes to treat as errors. Cannot be combined with `treat_warnings_as_errors`.",
        mandatory = False,
        default = [],
    ),
    "warnings_not_as_errors": attr.string_list(
        doc = "Compiler warning codes that stay warnings under `treat_warnings_as_errors`, which this requires.",
        mandatory = False,
        default = [],
    ),
    "warning_level": attr.int(
        doc = "The compiler's warning level.",
        mandatory = False,
        default = 3,
    ),
    "generate_documentation_file": attr.bool(
        doc = "Whether to generate an XML documentation file from the documentation comments.",
        default = True,
    ),
    "compiler_options": attr.string_list(
        doc = "Additional compiler options, for those that no attribute covers.",
        mandatory = False,
        default = [],
    ),
    "_target_framework": attr.label(
        default = "//dotnet:target_framework",
    ),
    "_windows_constraint": attr.label(default = "@platforms//os:windows"),
    "_compiler_wrapper_sh": attr.label(
        default = "//dotnet/private:compiler_wrapper.sh",
        executable = True,
        cfg = "exec",
        allow_single_file = True,
    ),
    "_compiler_wrapper_bat": attr.label(
        default = "//dotnet/private:compiler_wrapper.bat",
        executable = True,
        cfg = "exec",
        allow_single_file = True,
    ),
    "_pack_set": attr.string(
        doc = "The reference packs to compile against, set by the rule to match the toolchain type it resolves.",
        default = USER_PACKS,
    ),
    "_targeting_pack": attr.label(
        default = "//dotnet/private/sdk/targeting_packs:targeting_pack",
        cfg = targeting_pack_transition,
    ),
}

# These are attributes that are common across all library rules
LIBRARY_COMMON_ATTRS = {
    "exports": attr.label_list(
        doc = """Targets that the dependents of this target compile against as if they depended on them directly.

        Use this sparingly, as it weakens the precision of the build graph. It only matters with
        strict dependencies (`//dotnet/settings:strict_deps`, on by default).""",
        default = [],
        providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
    ),
}

WINEXE_ATTRS = {
    "winexe": attr.bool(
        doc = """Build a Windows GUI application, MSBuild's `<OutputType>WinExe</OutputType>`,
        which starts without a console window.""",
        default = False,
    ),
}

# These are attributes that are common across all binary/test rules
BINARY_COMMON_ATTRS = dicts.add(STATIC_WEB_ASSETS_ATTRS, {
    # Binaries override this with `WINEXE_ATTRS`; tests are always console executables.
    "winexe": attr.bool(
        doc = "Has no effect on tests.",
        default = False,
    ),
    "roll_forward_behavior": attr.string(
        doc = "How the app picks a runtime when the one it was built for is not installed, MSBuild's `RollForward`. " +
              "See https://learn.microsoft.com/en-us/dotnet/core/versions/selection#control-roll-forward-behavior",
        default = "Major",
        values = ["Minor", "Major", "LatestPatch", "LatestMinor", "LatestMajor", "Disable"],
    ),
    "app_config": attr.label(
        doc = """The application configuration file, MSBuild's `App.config`.

It is copied next to the assembly as `<assembly>.exe.config` for .NET Framework,
with `<supportedRuntime>` and generated binding redirects added, or as
`<assembly>.dll.config` for .NET.""",
        allow_single_file = [".config"],
    ),
    "auto_generate_binding_redirects": attr.bool(
        doc = """Add binding redirects to a .NET Framework executable's configuration file, as
MSBuild's `AutoGenerateBindingRedirects` does. When false, write them in `app_config`.
Has no effect on .NET.""",
        default = True,
    ),
    "appsetting_files": attr.label_list(
        doc = "Files, such as `appsettings.json`, copied next to the assembly under their file name. " +
              "Unlike `content_files`, directories are not kept.",
        allow_files = True,
        default = [],
        allow_empty = True,
        cfg = default_transition,
    ),
    "envs": attr.string_dict(
        doc = "Environment variables to set when the binary is run with `bazel run` or `bazel test`. " +
              "Values support `$(location)` expansion of `data` targets and make variables.",
        default = {},
    ),
    "env_inherit": attr.string_list(
        doc = "Names of environment variables to pass through from the environment that " +
              "`bazel run` or `bazel test` is invoked in.",
        default = [],
    ),
    "_bash_runfiles": attr.label(
        default = "@rules_shell//shell/runfiles",
    ),
    "_launcher_sh": attr.label(
        doc = "A template file for the launcher on Linux/MacOS",
        default = "//dotnet/private:launcher.sh.tpl",
        allow_single_file = True,
    ),
    "_launcher_bat": attr.label(
        doc = "A template file for the launcher on Windows",
        default = "//dotnet/private:launcher.bat.tpl",
        allow_single_file = True,
    ),
    "_launcher_netfx_sh": attr.label(
        doc = "A template file for the launcher of a .NET Framework executable on Linux/MacOS",
        default = "//dotnet/private:launcher_netfx.sh.tpl",
        allow_single_file = True,
    ),
    "_launcher_netfx_bat": attr.label(
        doc = "A template file for the launcher of a .NET Framework executable on Windows",
        default = "//dotnet/private:launcher_netfx.bat.tpl",
        allow_single_file = True,
    ),
    "_apphost_pack": attr.label(
        default = "//dotnet/private/sdk/apphost_packs:apphost_pack",
        cfg = apphost_pack_transition,
    ),
    "_runtime_pack": attr.label(
        default = "//dotnet/private/sdk/runtime_packs:runtime_pack",
        cfg = runtime_pack_transition,
    ),
    "_native_tools": attr.label(
        doc = """The native compiler a ReadyToRun or NativeAOT publish of the binary asks for, for the binary's framework.

Resolves to nothing unless a publish asked, so that no other build analyses the packs.""",
        default = "//dotnet/private/rules/publish_binary:native_tools",
    ),
    "_netfx_config_tool": attr.label(
        doc = "Lays out a .NET Framework executable's dependencies and writes its `<exe>.config`.",
        default = "//dotnet/private/tools/netfx_config",
        cfg = "exec",
    ),
})

# These are attributes that are common across all the binary/library/test C# rules
CSHARP_COMMON_ATTRS = dicts.add(
    COMMON_ATTRS,
    READY_TO_RUN_ATTRS,
    {
        "srcs": attr.label_list(
            doc = "The source files: C#; with a `project_sdk` that compiles Razor, Razor components " +
                  "and pages (`.razor`, `.cshtml`) and their scoped CSS (`.razor.css`); and with WPF " +
                  "in `framework_references`, XAML (`.xaml`), where `App.xaml` at the root of the " +
                  "package is the application definition.",
            allow_files = [".cs", ".razor", ".cshtml", ".css", ".xaml"],
            cfg = default_transition,
        ),
        "additionalfiles": attr.label_list(
            doc = "Files handed to analyzers and source generators as `AdditionalFiles`.",
            allow_files = True,
            cfg = default_transition,
        ),
        "allow_unsafe_blocks": attr.bool(
            doc = "Allow `unsafe` code, MSBuild's `AllowUnsafeBlocks`.",
            mandatory = False,
            default = False,
        ),
        "nullable": attr.string(
            doc = "The nullable context, MSBuild's `Nullable`.",
            mandatory = False,
            default = "disable",
            values = ["disable", "enable", "warnings", "annotations"],
        ),
        "run_analyzers": attr.bool(
            doc = "Whether the compiler runs analyzers and source generators.",
            mandatory = False,
            default = True,
        ),
        "enable_net_analyzers": attr.string(
            doc = """Run the .NET SDK's built-in code quality analyzers (`CAxxxx`), matching MSBuild's `EnableNETAnalyzers`.

            For `project_sdk = "web"` this also adds the ASP.NET Core analyzers. `"default"` takes
            `//dotnet/settings:enable_net_analyzers`, which is false unless set.""",
            default = "default",
            values = ["default", "true", "false"],
        ),
        "enforce_code_style_in_build": attr.string(
            doc = """Run the .NET SDK's built-in C# code style analyzers (`IDExxxx`), matching MSBuild's `EnforceCodeStyleInBuild`.

            `"default"` takes `//dotnet/settings:enforce_code_style_in_build`, which is false unless set.""",
            default = "default",
            values = ["default", "true", "false"],
        ),
        "analysis_mode": attr.string(
            doc = """Rule severity preset for the .NET SDK's code quality analyzers, matching MSBuild's `AnalysisMode`.

            Like MSBuild, it only applies to .NET 5 and later, where it selects the SDK's
            `analysislevel_<version>_<mode>.globalconfig`.""",
            default = "default",
            values = ["default", "none", "minimum", "recommended", "all"],
        ),
        "nowarn": attr.string_list(
            doc = "Compiler warning codes to suppress.",
            mandatory = False,
            default = ["CS1701", "CS1702"],
        ),
        "analyzer_configs": attr.label_list(
            doc = "Analyzer configuration files (`.globalconfig`, `.editorconfig`). " +
                  "See https://learn.microsoft.com/en-us/dotnet/fundamentals/code-analysis/configuration-files",
            allow_files = True,
            allow_empty = True,
            cfg = default_transition,
        ),
        "_scoped_css_tool": attr.label(
            doc = "Rewrites `.razor.css` by running the SDK's own scoped CSS tasks.",
            default = "//dotnet/private/tools/scoped_css",
            cfg = "exec",
        ),
        "wpf_resources": attr.label_list(
            doc = """WPF resources, such as images: MSBuild's `<Resource>` items.

            Each is addressed by its path relative to the package. Needs WPF in
            `framework_references`.""",
            allow_files = True,
            default = [],
            # We transition to the default configuration because the end user might have resources
            # that are generated by a dotnet binary
            cfg = default_transition,
        ),
        "_xaml_tool": attr.label(
            doc = "Compiles WPF XAML.",
            default = "//dotnet/private/tools/xaml",
            cfg = "exec",
        ),
        "_enable_net_analyzers": attr.label(
            doc = "The default for `enable_net_analyzers`.",
            default = "//dotnet/settings:enable_net_analyzers",
        ),
        "_enforce_code_style_in_build": attr.label(
            doc = "The default for `enforce_code_style_in_build`.",
            default = "//dotnet/settings:enforce_code_style_in_build",
        ),
        "interceptors_namespaces": attr.string_list(
            doc = """List of namespaces that are allowed to contain interceptors.

            Mirrors MSBuild's `InterceptorsNamespaces`. The namespaces of the SDK's own generators are
            already allowed: see `enable_request_delegate_generator` and
            `enable_configuration_binding_generator`, and `Microsoft.Extensions.Validation.Generated` for
            .NET 10 and later.
            """,
            mandatory = False,
            default = [],
        ),
        "excluded_analyzers": attr.string_list(
            doc = """File names of analyzer and source generator DLLs to leave out of the compilation.

            Mirrors MSBuild's `<Analyzer Remove="..." />`. Only this target's compilation drops them, not the
            targets that depend on it.
            """,
            mandatory = False,
            default = [],
        ),
        "enable_request_delegate_generator": attr.string(
            doc = """Run ASP.NET Core's Request Delegate Generator, which generates the minimal API endpoints at compile time, matching MSBuild's `EnableRequestDelegateGenerator`.

            `"default"` follows the .NET SDK: on for a binary that `publish_binary` publishes with `native_aot`, and
            for `project_sdk = "blazorwasm"`, which always trims; off otherwise. While it is on, its
            interceptors namespace, `Microsoft.AspNetCore.Http.Generated`, is allowed.""",
            default = "default",
            values = ["default", "true", "false"],
        ),
        "enable_configuration_binding_generator": attr.string(
            doc = """Run the configuration binding source generator from `Microsoft.Extensions.Configuration.Binder`, matching MSBuild's `EnableConfigurationBindingGenerator`.

            `"default"` follows the .NET SDK: on for a binary that `publish_binary` publishes with `native_aot`, and
            off otherwise, `project_sdk = "blazorwasm"` included. While it is on, its interceptors namespace,
            `Microsoft.Extensions.Configuration.Binder.SourceGeneration`, is allowed.""",
            default = "default",
            values = ["default", "true", "false"],
        ),
    },
)

# These are attributes that are common across all the library C# rules
CSHARP_LIBRARY_COMMON_ATTRS = dicts.add(
    CSHARP_COMMON_ATTRS,
    LIBRARY_COMMON_ATTRS,
    {
        "is_analyzer": attr.bool(
            doc = "Whether this library is an analyzer or source generator, which dependents run in the " +
                  "compiler rather than reference.",
            default = False,
        ),
        "is_language_specific_analyzer": attr.bool(
            doc = "Whether this library is an analyzer or source generator for C# only. Set it for a " +
                  "source generator.",
            default = False,
        ),
        "analyzer_runtime_deps": attr.label_list(
            doc = """Only for an analyzer or source generator: the NuGet packages it loads
            when it runs that the compiler does not bring, such as `Humanizer.Core`.

            They are compiled against like `deps`, handed to the compiler beside the
            analyzer, and packed beside it by `nuget_pack`. A listed package's own
            dependencies are not followed, so list each one the analyzer loads.
            Libraries built in this workspace need not be listed.""",
            providers = [DotnetAssemblyCompileInfo, DotnetAssemblyRuntimeInfo],
        ),
    },
)

# These are attributes that are common across all the binary C# rules
CSHARP_BINARY_COMMON_ATTRS = dicts.add(
    CSHARP_COMMON_ATTRS,
    BINARY_COMMON_ATTRS,
)

# These are attributes that are common across all the binary/library/test F# rules
FSHARP_COMMON_ATTRS = dicts.add(
    COMMON_ATTRS,
    READY_TO_RUN_ATTRS,
    {
        "_fsharp_compiler_worker": attr.label(
            doc = """The persistent worker that runs the F# compiler, keeping it warm between compilations.

            Resolves to nothing unless `//dotnet/settings:use_compiler_worker` is
            set, so that a workspace that does not use the worker never analyses
            it.""",
            default = "//dotnet/settings:fsharp_compiler_worker",
            cfg = "exec",
        ),
        "srcs": attr.label_list(
            doc = "The F# source and signature files, in compilation order.",
            allow_files = [".fs", ".fsi"],
            cfg = default_transition,
        ),
        "nowarn": attr.string_list(
            doc = "Compiler warning codes to suppress.",
            mandatory = False,
            default = [],
        ),
        "nullable": attr.string(
            doc = """Whether the compiler checks nullness, MSBuild's `Nullable`. `enable` needs F# 9 (the .NET 9 SDK) or newer.""",
            mandatory = False,
            default = "disable",
            values = ["disable", "enable"],
        ),
    },
)

# These are attributes that are common across all the library F# rules
FSHARP_LIBRARY_COMMON_ATTRS = dicts.add(
    FSHARP_COMMON_ATTRS,
    LIBRARY_COMMON_ATTRS,
)

# These are attributes that are common across all the binary F# rules
FSHARP_BINARY_COMMON_ATTRS = dicts.add(
    FSHARP_COMMON_ATTRS,
    BINARY_COMMON_ATTRS,
)
