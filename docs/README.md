# Getting started

## Usage

### Installation

The minimal supported Bazel version is 9.0.0.

From the release you wish to use: https://github.com/bazel-contrib/rules_dotnet/releases copy the WORKSPACE snippet into your WORKSPACE file.

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
`rollForward` does not apply.

```starlark
dotnet.toolchain(global_json = "//:global.json")
```


## Design

### Dependency resolution

These rules try their best to follow the conventions that are used in the
project files that MSBuild uses. MSBuild is not used behind the scenes
but the compilers and tools that are part of the .Net toolchain are
used directly instead.

The biggest change compared to MSBuild out of the box is that by default
these rules do not propagate transitive dependencies to compilation actions.
This is similar to setting `<DisableTransitiveProjectReferences>true</DisableTransitiveProjectReferences>`
in MSBuild.

This behaviour can be overridden by using the following flag when invoking bazel:
```
--@rules_dotnet//dotnet/settings:strict_deps=false
```
You can add this flag to your `.bazelrc` file to make it the default.

### Debug/Release configurations
These rules follow the Bazel idiomatic way of handling compilation modes by reading the `--compilation_mode` flag.
If the flag is set to either `dbg` or `fastbuild` the rules will compile with relase optimizations disabled.
If the flag is set to `opt` the rules will compile with the release optimizations enabled.

By default Bazel sets the compilation mode to `fastbuild`.

If you want to e.g. enable optimizations in CI you can add `common --compilation_mode=opt` to your CI `.bazelrc` file.

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
    target_frameworks = ["net9.0"],
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
application. Both compile Razor and resolve the ASP.NET Core reference pack,
because `Microsoft.NET.Sdk.Web` imports `Microsoft.NET.Sdk.Razor`.

A component's namespace and its `@page` route come from `root_namespace` plus
the source's path relative to the package that compiles it, so a Razor source
has to live in that package or below it.

### Scoped CSS

A `Foo.razor.css` beside `Foo.razor` styles only that component. It goes in
`srcs` next to the component, mirroring how MSBuild picks it up from beside the
`.razor`:

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
under. A library's assets are served below `_content/<assembly name>`, matching
the base path MSBuild gives a Razor class library, so two libraries shipping
`site.css` do not collide. A binary's own assets sit at the root.

The tree is laid out next to the binary the way a published application expects
it, with the endpoint manifest beside the assembly, so `app.MapStaticAssets()`
works under `bazel run` with no further setup.

Assets that arrive inside a NuGet package are picked up too. A packed Razor
class library ships them in a `staticwebassets` folder, and they are served from
`_content/<package id>` just like a library target's `wwwroot`, so referencing
the package is all that is needed.

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

`net10.0` or later is required: the WebAssembly toolchain only ships as NuGet
packages from .NET 10 onwards.

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
of all its dependencies, NuGet packages included. A self-contained
`publish_binary` only bundles the frameworks the binary lists, and fails if a
dependency needs another one.

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

Windows Forms and WPF code builds on any host, but running and publishing it
needs Windows: `publish_binary` needs a `win-*` `runtime_identifier`. They do
not support trimming, so `native_aot` cannot publish them.

`winexe = True` builds a GUI application, MSBuild's
`<OutputType>WinExe</OutputType>`, which starts without a console window. As in
MSBuild, referencing Windows Forms or WPF does not imply it.

### XAML

`.xaml` files in `srcs` are compiled as in MSBuild. `App.xaml` at the root of
the package is the application definition, and every other `.xaml` file is a
page. `wpf_resources` are MSBuild's `<Resource>` items. Pages and resources are
addressed by their path relative to the package, including generated ones, and
by their file name when they come from another package.

Only C# targets compile XAML, and the generated `.xaml` files of a target need
distinct file names.

## Unsupported workloads

The following workloads are not supported by these rules at this given time:

- VisualBasic
- AOT compilation and native relinking for Blazor WebAssembly
- Workloads that require Mono outside Blazor WebAssembly

Contributions to add the missing workloads are welcomed and the maintainers
will do their best to guide if needed.

## NativeAOT and the C/C++ toolchain

`publish_binary(native_aot = True)` compiles the application ahead of time to a
single native executable. It is the only publish model that links native code,
so unlike every other rule in `rules_dotnet` it needs a **C/C++ toolchain**. The
toolchain is resolved through Bazel's standard mechanism and requested
optionally, so a build that never publishes NativeAOT does not need one to
exist.

The binary has to be built for .NET 10 or later.

### Recommended: a hermetic toolchain

The [`llvm`](https://registry.bazel.build/modules/llvm) module supplies a
hermetic LLVM toolchain and downloads Apple's official SDK for Apple targets, so
NativeAOT builds the same way on Linux and macOS and can cross-compile — a
`linux-x64` binary from macOS, say, with nothing installed on the host. It is
what `rules_dotnet` uses for its own test suite on Unix.

```starlark
bazel_dep(name = "llvm", version = "0.8.19")

register_toolchains("@llvm//toolchain:all")

# Apple targets only. The .NET runtime links against CryptoKit, GSS and Network,
# which the module's minimal sysroot leaves out, and naming any framework
# replaces the default set rather than extending it.
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

A Windows publish is linked the way the .NET SDK links it, so the toolchain has
to link with `link.exe` or `lld-link`: MSVC or clang-cl, not MinGW. The
executable links the C runtime statically and needs no Visual C++
redistributable, whichever compilation mode Bazel builds in.

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

Binaries and tests can target .NET Framework (`net48`, `net472`, ...) as well.
They compile to an `.exe` (or a `winexe` with `winexe = True`) that starts
itself on the framework installed in Windows, so they need no apphost, no
`deps.json` and no `runtimeconfig.json`, and they run without the toolchain's
.NET runtime.

.NET Framework only loads assemblies from the GAC or from beside the
executable, so, as MSBuild's copy-local does, everything the application
depends on is laid out next to the `.exe`: assemblies with their PDBs,
satellite assemblies in a folder per culture, and native libraries. Where
several dependencies ship the same assembly, the highest version is the one
laid out, as MSBuild's `ResolveAssemblyReference` picks it, wherever each comes
in the dependency graph.

Beside the executable goes its `<assembly>.exe.config`. It starts from
`app_config`, MSBuild's `App.config`, when there is one, and gains:

- a `<supportedRuntime>` for the target framework, unless it names one, as the
  .NET SDK's `GenerateSupportedRuntime` target adds;
- a binding redirect for each strong-named assembly that is referenced at a
  version other than the one laid out, as MSBuild's
  `AutoGenerateBindingRedirects` writes them. A redirect `app_config` has
  already is kept. An assembly the framework itself provides at that version or
  later is not redirected: the CLR uses the framework's copy.

A reference to a version newer than any the application ships fails the build,
where MSBuild warns (MSB3277) and the application fails when it loads the
assembly. Depend on a version recent enough, or write the redirect in
`app_config`. `auto_generate_binding_redirects = False` leaves every redirect
to `app_config`.

`publish_binary` publishes the same directory, less the PDBs.
`self_contained`, `single_file`, `ready_to_run` and `native_aot` describe how a
.NET application is hosted, so they do not apply.

Only Windows runs .NET Framework executables, although every platform can
build them. Elsewhere `bazel run` and `bazel test` report that instead, so mark
tests that target .NET Framework with
`target_compatible_with = ["@platforms//os:windows"]` to skip them there.

Differences from MSBuild that remain:

- From .NET Framework 4.6.1 to 4.7.1, a library built for .NET Standard needs
  the facades MSBuild adds beside the executable (`netstandard.dll` and the
  `System.*` facades of `Microsoft.NET.Build.Extensions`). They are not added,
  so target `net472` or later when depending on .NET Standard libraries.
- The executable is always AnyCPU. The .NET SDK compiles an executable with
  native NuGet dependencies for x86 by default, choosing `win-x86` assets to
  match; here the native libraries are the ones for `//dotnet:rid`, which comes
  from the target platform, and an AnyCPU process on 64-bit Windows runs as
  64-bit.
- A NuGet package's copy of an assembly the framework provides, such as
  `System.Net.Http`, is still laid out beside the executable. The .NET SDK
  leaves it out; here it is not redirected to, so the CLR uses the framework's
  copy all the same.

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

Run `@rules_dotnet//tools/paket -- install` in the same directory as the 
`paket.dependencies` file to generate the `paket.lock` file.

Add the following snippet to your MODULE.bazel file:

```starlark
paket = use_extension("@rules_dotnet//dotnet:paket.bzl", "paket")
paket.parse(
    dependencies = "//:paket.dependencies",
    lock = "//:paket.lock",
)
use_repo(paket, "paket.main")
```

`@rules_dotnet//tools/paket`. Every Paket command works (`update`,
`outdated`, `why`), and it runs in the directory you invoke it from.

### Referring to packages

Each [dependency group](https://fsprojects.github.io/Paket/groups.html) becomes
a repository named after it, holding one lower cased target per package:

Example:
If you have the following `paket.dependencies`:

```text
source https://api.nuget.org/v3/index.json
framework: net11.0

nuget System.Text.Json 11.0.0

group iaac
    source https://api.nuget.org/v3/index.json

    nuget Pulumi 3.101.2
```

The top-level group becomes `@paket.main`, and the `iaac` group becomes `@paket.iaac`.
and you can refer to them in your Bazel targets using the `@paket.<group>//<package>` syntax
in the `deps` attribute of your Bazel targets.

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

The rules support remote execution out of the box. The remote runners do need to have the required .Net
system dependencies installed though. A common missing system dependency in existing RBE images is `libicu`;
[Globalization and ICU](#globalization-and-icu) covers how to build without it.

## Globalization and ICU

On Linux the .NET runtime takes its culture data from the system `libicu`, and a process fails to start
without it:

```
Couldn't find a valid ICU package installed on the system.
```

There are two ways to work around this:

1. Run everything in [globalization-invariant mode](https://learn.microsoft.com/dotnet/core/runtime-config/globalization#invariant-mode) by setting the `invariant_globalization` flag.

```
build --@rules_dotnet//dotnet/settings:invariant_globalization=true
```

2. Use the hermetic ICU provided by rules_dotnet

This pulls a hermetic ICU into the build using [icu module](https://registry.bazel.build/modules/icu) from the Bazel registry.

```
build --@rules_dotnet//dotnet/settings:icu=@rules_dotnet//dotnet/settings:hermetic_icu
```

It needs a C++ toolchain, the auto-configured one or a hermetic one, and the first build spends a few minutes
compiling ICU. The flag has no effect on macOS and Windows, whose runtime uses the ICU the operating system
ships.

A published application do not carry this ICU. This is purely for the build and test environment within Bazel.

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

The workers also run as persistent workers on remote executors that support them, over either the
JSON or the protobuf worker protocol. Enable it with:

```
build --experimental_remote_mark_tool_inputs
```

## Path mapping

The rules_dotnet compile actions support
[path mapping](https://bazel.build/reference/command-line-reference#flag--experimental_output_paths),
which strips the configuration segment out of the paths a compile action sees, so the *same*
compilation reached through two different configurations produces one cache **key** instead of two.

You also need to have disk/remote caching enabled for Bazel to take full advantage of path mapping.

```
common --experimental_output_paths=strip
common --disk_cache=path/to/cache
```

### It cannot be used on Windows

Bazel has [no sandboxing on Windows](https://github.com/bazelbuild/bazel/discussions/18401), so
there is no strategy there that can satisfy the requirement and *every* compile fails with the
error above. You can use platform specific configuration to enable path mapping only on supported platforms:

```
common --enable_platform_specific_config
build:linux --experimental_output_paths=strip
build:macos --experimental_output_paths=strip
```
