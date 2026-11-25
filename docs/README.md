# Getting started

## Usage

### Installation

The minimal supported Bazel version is 9.0.0.

Add `rules_dotnet` to your `MODULE.bazel`, using the version from the
[release](https://github.com/bazel-contrib/rules_dotnet/releases) you want:

```starlark
bazel_dep(name = "rules_dotnet", version = "<version>")
```

If you are using Windows you need to make sure that symlinks and runfiles are enabled.
You can do that by adding the following snippet to your `.bazelrc` file:

```
startup --windows_enable_symlinks
build --enable_runfiles
```

More information on these flags can be found here:

[--windows_enable_symlinks](https://bazel.build/reference/command-line-reference#param-no-windows-enable-symlinks)

[--enable_runfiles](https://bazel.build/reference/command-line-reference#param-no-enable-runfiles)

Various examples of how each rule can be used are in the [examples](../examples) folder.

### Choosing the .NET SDK

Register the SDK to build with in `MODULE.bazel`:

```starlark
dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
dotnet.toolchain(dotnet_version = "11.0.100")
use_repo(dotnet, "dotnet_toolchains")

register_toolchains("@dotnet_toolchains//:all")
```

To pin the SDK in one place for Bazel and for the `dotnet` CLI and IDEs, read
the version from a `global.json` instead. Bazel uses exactly its `sdk.version`;
`rollForward` and `allowPrerelease` do not apply. Comments and trailing commas
are allowed, as they are for the `dotnet` CLI.

```starlark
dotnet.toolchain(global_json = "//:global.json")
```

## Design

### Dependency resolution

These rules follow the conventions of MSBuild project files, but call the
compilers and tools of the .NET SDK directly instead of running MSBuild.

The biggest difference from MSBuild's defaults is that transitive dependencies
are not passed to the compiler: a target can only use the assemblies it lists
in `deps`. This is the same as setting
`<DisableTransitiveProjectReferences>true</DisableTransitiveProjectReferences>`
in MSBuild.

To compile against transitive dependencies as well, use the following flag, or
add it to your `.bazelrc` to make it the default:

```
--@rules_dotnet//dotnet/settings:strict_deps=false
```

### Debug/Release configurations

The rules follow Bazel's `--compilation_mode` flag. With `dbg` or `fastbuild`
(Bazel's default) assemblies are compiled without optimizations, as in a Debug
build; with `opt` they are compiled with optimizations, as in a Release build.

To build optimized assemblies in CI, for example, add
`common --compilation_mode=opt` to your CI `.bazelrc` file.

### Embedded sources

Sources are not embedded by default. To embed all sources into your `.pdb` files you can
set the following flag for global application:

```
build --@rules_dotnet//dotnet/settings:embed_all_sources=true
```

Or per target, overriding the flag:

```python
csharp_library(
    name = "lib",
    embed_sources = True,
    ...
)
```

## Resources and localization

`resources` works like MSBuild's `EmbeddedResource`. `.resx` files are compiled,
and culture ones (`Strings.fr.resx`) go into satellite assemblies
(`fr/<assembly>.resources.dll`):

```starlark
csharp_library(
    name = "greeter",
    srcs = ["Greeter.cs"],
    resources = glob(["**/*.resx"]),
    root_namespace = "Localization",  # Strings.resx -> Localization.Strings
    target_frameworks = ["net11.0"],
)
```

Use `resx_resource` to set a logical name or culture, or to provide files
referenced by `ResXFileRef`. See [`examples/localization`](../examples/localization).

## Razor

`.razor` and `.cshtml` files go in `srcs` alongside `.cs`, and `project_sdk`
picks the SDK that compiles them:

```python
csharp_library(
    name = "components",
    srcs = glob(["**/*.cs", "**/*.razor"]),
    project_sdk = "razor",
    root_namespace = "MyApp.Components",
    target_frameworks = ["net11.0"],
)
```

Use `"razor"` for a Razor class library and `"web"` for an ASP.NET Core
application. Both compile Razor and reference ASP.NET Core.

A component's namespace and its `@page` route come from `root_namespace` plus
the source's path relative to the package that compiles it, so a Razor source
has to live in that package or below it.

### Scoped CSS

A `Foo.razor.css` beside `Foo.razor` styles only that component. List it in
`srcs` next to the component:

```python
csharp_library(
    name = "components",
    srcs = glob(["**/*.cs", "**/*.razor", "**/*.razor.css"]),
    project_sdk = "razor",
    target_frameworks = ["net11.0"],
)
```

Only `<component>.razor.css` belongs in `srcs`; any other stylesheet is a static
web asset.

## Static web assets

Files a target serves over HTTP go in `static_web_assets`:

```python
csharp_library(
    name = "components",
    static_web_assets = glob(["wwwroot/**"]),
    ...
)
```

Each file is served at its path relative to the `wwwroot` directory it sits
under. A library's assets are served below `_content/<assembly name>`, as MSBuild
does for a Razor class library, so two libraries shipping `site.css` do not
collide. A binary's own assets are served from the root.

`app.MapStaticAssets()` finds them under `bazel run` with no further setup.

Static web assets that come with a NuGet package, such as a packed Razor class
library, are served from `_content/<package id>`, unless the package declares a
base path of its own. Referencing the package is all that is needed.

## Blazor WebAssembly

`publish_binary` turns a Blazor WebAssembly application into a static site:

```python
csharp_binary(
    name = "app",
    srcs = glob(["**/*.cs", "**/*.razor"]),
    project_sdk = "blazorwasm",
    static_web_assets = glob(["wwwroot/**"]),
    target_frameworks = ["net11.0"],
    deps = ["@paket.main//microsoft.aspnetcore.components.webassembly"],
)

publish_binary(
    name = "publish",
    binary = ":app",
    target_framework = "net11.0",
    wasm = True,
)
```

The output is a `wwwroot` directory, ready to serve from anything that serves
files.

Running the binary starts the development server:

```
bazel run //path/to:app
```

`blazor_devserver` serves anything that produces an application, so a publish
can be served exactly as it will be deployed - trimmed, compressed and
fingerprinted - rather than as the development build:

```python
blazor_devserver(
    name = "serve",
    app = ":publish",
)
```

Blazor WebAssembly requires `net10.0` or later.

## Shared frameworks

Every target references Microsoft.NETCore.App. `framework_references` adds
other shared frameworks, like MSBuild's `<FrameworkReference>`:

```python
csharp_library(
    name = "middleware",
    srcs = glob(["**/*.cs"]),
    framework_references = ["Microsoft.AspNetCore.App"],
    target_frameworks = ["net11.0"],
)
```

| `framework_references` | MSBuild |
| --- | --- |
| `Microsoft.AspNetCore.App` | `<FrameworkReference Include="Microsoft.AspNetCore.App" />`, implied by `project_sdk = "web"` |
| `Microsoft.WindowsDesktop.App.WPF` | `<UseWPF>true</UseWPF>` |
| `Microsoft.WindowsDesktop.App.WindowsForms` | `<UseWindowsForms>true</UseWindowsForms>` |
| `Microsoft.WindowsDesktop.App` | `<UseWPF>` and `<UseWindowsForms>` together |

A target only compiles against the frameworks it lists itself, so list a
framework on every target whose code uses it. A binary runs on the frameworks
of all its dependencies, NuGet packages included.

A self-contained or ReadyToRun `publish_binary` only takes the runtime packs of
the frameworks the binary lists itself, and fails if a dependency needs another
one. This is stricter than MSBuild, where a `FrameworkReference` flows through
project and package references unless
`<DisableTransitiveFrameworkReferences>true</DisableTransitiveFrameworkReferences>`
is set. To publish the frameworks of dependencies as well, use the following
flag, or add it to your `.bazelrc` to make it the default:

```
--@rules_dotnet//dotnet/settings:strict_framework_references=false
```

`nuget_pack` records a library's framework references in the package, so that
its consumers get them too.

## Windows Forms and WPF

Windows Forms and WPF need a Windows specific target framework, such as
`net11.0-windows`:

```python
csharp_binary(
    name = "app",
    srcs = glob(["**/*.cs", "**/*.xaml"]),
    framework_references = ["Microsoft.WindowsDesktop.App.WPF"],
    target_frameworks = ["net11.0-windows"],
    winexe = True,
    wpf_resources = glob(["Assets/**"]),
)
```

As in MSBuild, a `-windows` target can depend on targets and NuGet packages
built for the plain framework, defines the `WINDOWS` preprocessor symbol, and
cannot be a dependency of a plain framework target. Target frameworks for a
specific Windows version, such as `net8.0-windows10.0.19041.0`, are not
supported.

Windows Forms and WPF code builds and publishes on any host, but only runs on
Windows, so `publish_binary` needs a `win-*` `runtime_identifier`. They do not
support trimming, so `native_aot` cannot publish them.

`winexe = True` builds a GUI application, MSBuild's
`<OutputType>WinExe</OutputType>`, which starts without a console window. As in
MSBuild, referencing Windows Forms or WPF does not imply it.

### XAML

`.xaml` files in `srcs` are compiled as in MSBuild. `App.xaml` at the root of
the package is the application definition, and every other `.xaml` file is a
page. `wpf_resources` are MSBuild's `<Resource>` items. Pages and resources are
addressed by their path relative to the package's directory, generated ones
included, and by their file name when they are outside it, as the files of a
parent or sibling package are. Two that would get the same address, compared
case-insensitively, fail the build.

Only C# targets compile XAML. A `.xaml` file that is generated, or outside the
package's directory, is compiled by its file name alone, which must not be that
of another such file or of a `.xaml` file at the root of the package.

## Unsupported workloads

The following workloads are not supported by these rules at this given time:

- VisualBasic
- AOT compilation and native relinking for Blazor WebAssembly
- Workloads that require Mono outside Blazor WebAssembly

Contributions to add the missing workloads are welcomed and the maintainers
will do their best to guide if needed.

## NativeAOT and the C/C++ toolchain

`publish_binary(native_aot = True)` compiles the application ahead of time to a
single native executable. The binary has to be built for .NET 10 or later.

NativeAOT links native code, so it needs a registered **C/C++ toolchain**.
Builds that do not publish with NativeAOT do not need one.

### Recommended: a hermetic toolchain

The [`llvm`](https://registry.bazel.build/modules/llvm) module supplies a
hermetic LLVM toolchain and downloads Apple's official SDK for Apple targets, so
NativeAOT builds the same way on Linux and macOS and can cross-compile — a
`linux-x64` binary from macOS, say, with nothing installed on the host.

```starlark
bazel_dep(name = "llvm", version = "0.8.19")

register_toolchains("@llvm//toolchain:all")

# Apple targets only: the frameworks the .NET runtime links against. Listing
# frameworks replaces the module's default set, so list all of them.
osx_sysroot = use_extension("@llvm//extensions:osx.bzl", "osx")
osx_sysroot.frameworks(names = [
    "CoreFoundation",
    "CryptoKit",
    "Foundation",
    "GSS",
    "Kernel",
    "Network",
    "OSLog",
    "Security",
    "SystemConfiguration",
])
```

### Otherwise: host toolchains

Any registered C/C++ toolchain works, including the one Bazel auto-configures
from the host compiler. That needs a working toolchain on every machine that
publishes NativeAOT — Xcode's command line tools on macOS, clang or gcc on
Linux, or Visual Studio's C++ build tools on Windows — and it cannot
cross-compile, because a host toolchain only targets its own platform.

On Windows the toolchain has to link with `link.exe` or `lld-link`, so use MSVC
or clang-cl; MinGW is not supported. The executable links the C runtime
statically and needs no Visual C++ redistributable.

## Single-file executables

`publish_binary(single_file = True)` bundles a self-contained publish into one
executable, as `dotnet publish -p:PublishSingleFile=true` does:

```python
publish_binary(
    name = "publish",
    binary = ":app",
    self_contained = True,
    single_file = True,
    target_framework = "net11.0",
)
```

Two attributes mirror the MSBuild properties of the same name:

- `include_native_libraries_for_self_extract` bundles the native libraries as
  well.
- `enable_compression_in_single_file` compresses what is bundled.

`single_file` needs `self_contained`, and cannot be combined with `native_aot`,
which produces a single executable already.

## .NET Framework

Binaries and tests can target .NET Framework (`net48`, `net472`, ...). They
compile to an `.exe` that runs on the .NET Framework installed in Windows, with
no apphost, `deps.json` or `runtimeconfig.json`. With `winexe = True` it starts
without a console window.

As with MSBuild, the application's dependencies are copied next to the `.exe`:
assemblies with their PDBs, satellite assemblies and native libraries. When
several dependencies ship the same assembly, the highest version is used.
NuGet packages contribute their Windows native libraries and runtime-specific
assemblies for the target architecture.

### Configuration file

`app_config` is MSBuild's `App.config`. It is copied next to the executable as
`<assembly>.exe.config`, and the build adds:

- a `<supportedRuntime>` for the target framework, unless one is present;
- a binding redirect for each strong-named assembly that is referenced at a
  different version than the one shipped, as MSBuild's
  `AutoGenerateBindingRedirects` does. Redirects already in `app_config` are
  kept.

A reference to a newer version of an assembly than the application ships fails
the build, as the application could not load it. Depend on a newer version, or
add a `<bindingRedirect>` that covers it to `app_config`. Set
`auto_generate_binding_redirects = False` to write all redirects yourself.

### Publishing

`publish_binary` publishes the output directory, without PDBs, to
`publish/<runtime_identifier>`. The runtime identifier defaults to Windows on
the target platform's architecture, such as `win-x64` on x64 Linux.
`self_contained`, `single_file`, `ready_to_run` and `native_aot` don't apply to
.NET Framework.

### Running

Only Windows runs .NET Framework executables, but any platform can build them.
Mark .NET Framework tests with
`target_compatible_with = ["@platforms//os:windows"]` to skip them elsewhere.

### Differences from MSBuild

- .NET Framework 4.6.1 to 4.7.1 applications that depend on .NET Standard
  libraries need facade assemblies, which are not added. Target `net472` or
  later instead.
- The executable is always AnyCPU, so it runs as a 64-bit process on 64-bit
  Windows. The .NET SDK defaults to x86 when NuGet packages have native
  libraries.
- NuGet packages' copies of assemblies that .NET Framework provides, such as
  `System.Net.Http`, are copied next to the executable but not redirected to,
  so the framework's copy is used. The .NET SDK leaves them out.
- A binding redirect written in `app_config` is kept even when it does not
  cover the version the application references. MSBuild replaces it with the
  one it generates and warns (MSB3836).

## Container images

The output from `publish_binary` can easily be used to build container images.
See the [container image example](../examples/container_image) for how to do this with `rules_img`.

## IDE Support

Currently the rules do not support IDE support out of the box so for
proper IDE support the MSBuild project files need to be manually maintained.

## NuGet packages

NuGet packages are resolved with [Paket](https://fsprojects.github.io/Paket/),
whose lock file pins an exact version for every package.

### Setting Paket up

Declare your packages in `paket.dependencies`:

```
source https://api.nuget.org/v3/index.json
framework: net11.0

nuget FSharp.Core 11.0.101
nuget Argu 6.2.3
```

Generate `paket.lock` by running Paket in the directory that holds
`paket.dependencies`. `rules_dotnet` ships the Paket CLI, so no local .NET
install is needed:

```
bazel run @rules_dotnet//tools/paket -- install
```

Every other Paket command (`update`, `outdated`, `why`, ...) works the same way.

Then add the following snippet to your `MODULE.bazel` file:

```starlark
paket = use_extension("@rules_dotnet//dotnet:paket.bzl", "paket")
paket.parse(
    dependencies = "//:paket.dependencies",
    lock = "//:paket.lock",
)
use_repo(paket, "paket.main")
```

### Referring to packages

Each [dependency group](https://fsprojects.github.io/Paket/groups.html) becomes
a repository named `paket.<group>`, holding one lower cased target per package.
For example, with this `paket.dependencies`:

```text
source https://api.nuget.org/v3/index.json
framework: net11.0

nuget System.Text.Json 11.0.0

group iaac
    source https://api.nuget.org/v3/index.json

    nuget Pulumi 3.101.2
```

the top-level group becomes `@paket.main` and the `iaac` group becomes
`@paket.iaac`. Refer to a package as `@paket.<group>//<package>` in `deps`:

```starlark
csharp_binary(
    name = "app",
    srcs = ["Program.cs"],
    target_frameworks = ["net11.0"],
    deps = ["@paket.main//system.text.json"],
)
```

Do not mix groups in one target. Paket resolves each group separately, so two
groups can hold incompatible versions of the same transitive dependency.

A package that ships a [dotnet tool](https://learn.microsoft.com/en-us/dotnet/core/tools/global-tools)
also exposes it as an executable, at `@paket.<group>//<package>/tools:<tool>`.

## Producing NuGet packages

`nuget_pack` builds a `.nupkg` from a library, or a .NET tool package from a
binary, and `nuget_push` publishes it. See
[examples/nuget_pack](../examples/nuget_pack).

## Remote execution

The rules support remote execution out of the box. The remote runners do need to have the required .NET
system dependencies installed though. A common missing system dependency in existing RBE images is `libicu`;
[Globalization and ICU](#globalization-and-icu) covers how to build without it.

## Globalization and ICU

On Linux the .NET runtime takes its culture data from the system `libicu`, and a process fails to start
without it:

```
Couldn't find a valid ICU package installed on the system.
```

There are two ways to work around this:

1. Run everything in [globalization-invariant mode](https://learn.microsoft.com/dotnet/core/runtime-config/globalization#invariant-mode) by setting the `invariant_globalization` flag:

   ```
   build --@rules_dotnet//dotnet/settings:invariant_globalization=true
   ```

2. Use the hermetic ICU from the [`icu`](https://registry.bazel.build/modules/icu) module:

   ```
   build --@rules_dotnet//dotnet/settings:icu=@rules_dotnet//dotnet/settings:hermetic_icu
   ```

   It needs a C++ toolchain, the auto-configured one or a hermetic one, and the first build spends a
   few minutes compiling ICU. The flag has no effect on macOS and Windows, where the runtime uses the
   ICU the operating system ships.

   The hermetic ICU is only used for building, running and testing inside Bazel; a published
   application does not carry it.

## Persistent workers

The C# and F# compile actions can run in a [Bazel persistent worker](https://bazel.build/remote/persistent).
It is off by default, so turn it on with:

```
build --@rules_dotnet//dotnet/settings:use_compiler_worker=true
```

You can control the number of worker instances with:

```
build --worker_max_instances=CSharpCompile=HOST_CPUS
build --worker_max_instances=FSharpCompile=HOST_CPUS
```

### Remote persistent workers

The workers also run as persistent workers on remote executors that support them. Enable it with:

```
build --experimental_remote_mark_tool_inputs
```

## Path mapping

The compile actions support
[path mapping](https://bazel.build/reference/command-line-reference#flag--experimental_output_paths),
so the *same* compilation reached through two different configurations is cached once instead of
twice.

You also need to have disk/remote caching enabled for Bazel to take full advantage of path mapping.

```
common --experimental_output_paths=strip
common --disk_cache=path/to/cache
```

### It cannot be used on Windows

Path mapping requires sandboxing, which Bazel
[does not have on Windows](https://github.com/bazelbuild/bazel/discussions/18401), so every compile
action fails there when it is enabled. Use platform-specific configuration to enable path mapping only
on the platforms that support it:

```
common --enable_platform_specific_config
build:linux --experimental_output_paths=strip
build:macos --experimental_output_paths=strip
```
