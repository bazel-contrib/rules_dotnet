# Getting started

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

## Razor

`.razor` and `.cshtml` files go in `srcs` alongside `.cs`, and `project_sdk`
picks the SDK that compiles them:

```python
csharp_library(
    name = "components",
    srcs = glob(["**/*.cs", "**/*.razor"]),
    project_sdk = "razor",
    root_namespace = "MyApp.Components",
    target_frameworks = ["net10.0"],
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
    target_frameworks = ["net10.0"],
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
    target_frameworks = ["net10.0"],
    deps = ["@paket.main//microsoft.aspnetcore.components.webassembly"],
)

publish_binary(
    name = "publish",
    binary = ":app",
    target_framework = "net10.0",
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

Windows AOT is not supported yet.

### Recommended: a hermetic toolchain

The [`llvm`](https://registry.bazel.build/modules/llvm) module supplies a
hermetic LLVM toolchain and downloads Apple's official SDK for Apple targets, so
NativeAOT builds the same way on every machine and can cross-compile — a
`linux-x64` binary from macOS, say, with nothing installed on the host. It is
what `rules_dotnet` uses for its own test suite.

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
Linux — and it cannot cross-compile, because a host toolchain only targets its
own platform.

## Usage

### Installation

The minimal supported Bazel version is 7.0.0 and bzlmod has to enabled.

From the release you wish to use: https://github.com/bazel-contrib/rules_dotnet/releases copy the WORKSPACE snippet into your WORKSPACE file.

If you are using Windows you need to make sure that symlinks and runfiles are enabled.
You can do that by adding the following snippet to your `.bazelrc` file:

```
startup --windows_enable_symlinks
build --enable_runfiles
```

More information on these flags can be found here:

[--windows_enable_symlinks](https://docs.bazel.build/versions/main/command-line-reference.html#flag--windows_enable_symlinks)

[--enable_runfiles](https://docs.bazel.build/versions/main/command-line-reference.html#flag--enable_runfiles)

Various examples of how each rule can be used are in the [examples](../examples) folder.

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
framework: net10.0

nuget FSharp.Core 10.1.401
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
framework: net10.0

nuget System.Text.Json 10.1.201

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
    target_frameworks = ["net10.0"],
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

### Versioning assemblies

Libraries, binaries and tests take a `version`, a NuGet version string such as
`1.2.3`, `1.2.3-beta.1` or `1.2.3-beta.1+sha.abcdef`:

```starlark
csharp_library(
    name = "greeter",
    srcs = ["Greeter.cs"],
    target_frameworks = ["netstandard2.0", "net9.0"],
    version = "1.2.3",
)
```

### nuget_pack

```starlark
nuget_pack(
    name = "greeter_pack",
    library = ":greeter",
    target_frameworks = ["netstandard2.0", "net9.0"],
    package_id = "Example.Greeter",
    authors = ["Example"],
    description = "Greets people.",
    license_expression = "Apache-2.0",
    readme = "README.md",
    symbols = "snupkg",
)
```

The library is built once per framework in `target_frameworks` (each has to be
one the library itself lists) and the package gets `lib/<tfm>/` with the
assembly and its XML documentation, `ref/<tfm>/` with the reference assembly,
and one dependency group per framework. The output is
`<name>/<package_id>.<version>.nupkg`, with `<package_id>.<version>.snupkg`
beside it when `symbols = "snupkg"`. Both are deterministic: the same inputs
give the same bytes on the same .NET runtime version and OS family, wherever
and whenever they are built.

The version is the packed target's unless `version` overrides it. `version`
overrides the package alone: the assembly keeps the version it was compiled
with, so `version = "2.0.0-rc.1"` on a library built as 1.0.0 publishes a
release candidate of that same assembly.

A version that is only known when the package is built - one that comes from a
stamp - goes in `version_file` instead, a file whose first non-empty line is the
version. The package is then named `<name>/<name>.nupkg`, since its version
cannot name it, and the packed assemblies again keep the version they were
compiled with. The file is usually a `genrule` over the workspace status:

```starlark
genrule(
    name = "package_version",
    outs = ["package_version.txt"],
    cmd = "sed -n 's/^STABLE_PACKAGE_VERSION //p' bazel-out/stable-status.txt > $@",
    stamp = 1,
)

nuget_pack(
    name = "greeter_nightly",
    library = ":greeter",
    version_file = ":package_version",
    ...
)
```

`STABLE_PACKAGE_VERSION` comes from a `--workspace_status_command`, and the
`STABLE_` prefix is what makes Bazel rebuild the package when it changes.
[examples/nuget_pack](../examples/nuget_pack) has this wired up, with a
`version.sh` to run it with.

What a dependency of the library becomes in the package:

* a NuGet package is declared as a dependency, with its version as the minimum;
* an assembly shipped by a `nuget_pack` listed in `deps` is declared as a
  dependency on that package;
* any other library built in your workspace follows `first_party_deps`:
  `reference` (the default) declares a dependency on a package named after the
  assembly with the assembly's version, which is exactly what a `nuget_pack` of
  it produces by default, so a workspace that publishes every library as its
  own package needs no `deps` wiring; `bundle` copies the assembly into this
  package along with its dependencies, for one self-contained package; `error`
  fails, so that every such dependency has to be listed in `deps`.

Only direct dependencies are declared; NuGet resolves the rest.

Further metadata: `title`, `copyright`, `project_url`, `release_notes`,
`package_tags`, `license_expression` or `license_file`, `icon`,
`repository_url` with `repository_type`, `repository_branch` and
`repository_commit`, `require_license_acceptance`, `development_dependency`
and `min_client_version`. Arbitrary files go in through `files`, a dict of
target to in-package path (a path ending in `/` is a folder), which is how
`build/<tfm>/<package_id>.props` and the like are shipped; `content_files`
places files under `contentFiles/<language>/<framework>/` and describes them
for consuming projects.

A package whose assembly differs per runtime identifier - one that `select()`s
on `@rules_dotnet//dotnet:rid_<rid>` - sets `runtime_identifiers`:

```starlark
csharp_library(
    name = "platform",
    srcs = ["Platform.cs"] + select({
        "@rules_dotnet//dotnet:rid_linux-x64": ["PlatformLinux.cs"],
        "@rules_dotnet//dotnet:rid_win-x64": ["PlatformWindows.cs"],
        "//conditions:default": ["PlatformOther.cs"],
    }),
    target_frameworks = ["net9.0"],
)

nuget_pack(
    name = "platform_pack",
    library = ":platform",
    target_frameworks = ["net9.0"],
    runtime_identifiers = ["linux-x64", "win-x64"],
    ...
)
```

The library is built once per runtime identifier and shipped under
`runtimes/<rid>/lib/<tfm>/`. Nothing is left under `lib/` to compile against, so
the package always carries one `ref/<tfm>/`, and NuGet picks the implementation
that matches the consuming project's own runtime identifier at restore time.
Native libraries of the assemblies go under `runtimes/<rid>/native/`. Every
runtime identifier builds the whole dependency graph again, so keep this to the
packages that need it.

Not supported yet: `data` files and stamping the assembly version
(`version_file` stamps the package version alone).

### Analyzer and source generator packages

A library built with `is_analyzer` packs as an analyzer package. Nothing goes
under `lib/`, because a consumer hands it to the compiler rather than compiling
against it:

```starlark
csharp_library(
    name = "greeting_generator",
    srcs = ["GreetingGenerator.cs"],
    is_analyzer = True,
    is_language_specific_analyzer = True,
    out = "Example.Greeter.Generator",
    target_frameworks = ["netstandard2.0"],
    deps = [
        "@paket.main//microsoft.codeanalysis.common",
        "@paket.main//microsoft.codeanalysis.csharp",
    ],
)

nuget_pack(
    name = "greeting_generator_pack",
    library = ":greeting_generator",
    target_frameworks = ["netstandard2.0"],
    package_id = "Example.Greeter.Generator",
    development_dependency = True,
    authors = ["Example"],
    description = "Generates a greeting constant.",
)
```

The assembly goes under `analyzers/dotnet/cs/`, or `analyzers/dotnet/` when
`is_language_specific_analyzer` is off, along with every other assembly this
workspace built that the compiler was handed with it. Assemblies out of a NuGet
package do not travel: the compiler running the analyzer brings Roslyn itself,
which is what an analyzer project's `PrivateAssets="all"` says in MSBuild. An
analyzer that needs one anyway ships it through `files`:

```starlark
    files = {"@paket.main//some.package:libs": "analyzers/dotnet/cs/"},
```

For the same reason an analyzer package declares no dependencies of its own,
only the packages listed in `deps`. `development_dependency = True` marks a
package a consuming project needs at build time alone: the SDK sets it for an
analyzer project, and `nuget_pack` leaves the choice to you.

Analyzers target `netstandard2.0` and nothing else, so `target_frameworks` is
that one framework and `runtime_identifiers` does not apply.

### Razor class libraries

A library with Razor sources packs like any other - its assembly under
`lib/<tfm>/` and its reference assembly under `ref/<tfm>/` - and the files it
serves go under `staticwebassets/`: the `static_web_assets` it declares and the
bundle its scoped CSS compiles to. Beside them the package gets
`build/Microsoft.AspNetCore.StaticWebAssets.props`, the file the SDK writes
when it packs one, so that a consuming project finds them whether or not it is
built with Bazel. A Razor class library also declares a framework reference on
`Microsoft.AspNetCore.App`, which is what it compiled against.

```starlark
csharp_library(
    name = "components",
    srcs = ["Badge.razor", "Badge.razor.css", "_Imports.razor"],
    out = "Example.Components",
    project_sdk = "razor",
    static_web_assets = glob(["wwwroot/**"]),
    target_frameworks = ["net10.0"],
)

nuget_pack(
    name = "components_pack",
    library = ":components",
    target_frameworks = ["net10.0"],
    package_id = "Example.Components",
    authors = ["Example"],
    description = "A badge component.",
)
```

A library serves its files under `_content/<assembly name>` in a Bazel build and
under `_content/<package id>` out of a package, so the two have to agree or the
same `_content/...` path would mean two things; `out` is how an assembly takes
the package's name. Only the packed library's own files travel: a dependency's
belong to that dependency's package, so a library that serves files cannot be
copied in with `first_party_deps = "bundle"`.

### Tool packages

A `csharp_binary` or `fsharp_binary` packs as a .NET tool, the kind
`dotnet tool install` installs:

```starlark
nuget_pack(
    name = "greet_tool",
    binary = ":greet",
    command_name = "greet",
    target_frameworks = ["net9.0"],
    package_id = "Example.Greet",
    authors = ["Example"],
    description = "Greets from the command line.",
)
```

The package carries the binary's framework-dependent publish under
`tools/<tfm>/any/` - every managed dependency, NuGet packages included, native
libraries under `runtimes/<rid>/native/`, a `deps.json` and a
`runtimeconfig.json` (`roll_forward_behavior` sets its policy) - and a
`DotnetToolSettings.xml` naming the command. The SDK allows exactly one command
per tool package, so each tool is its own `nuget_pack`.

The managed assemblies run anywhere, but the native libraries are only those of
the runtime identifier the package was built for, so a tool that pulls in native
dependencies installs on that platform alone.

### nuget_push

```starlark
nuget_push(
    name = "push",
    packages = [":greeter_pack", ":greet_tool"],
    source = "https://api.nuget.org/v3/index.json",
)
```

```sh
bazel run //:push                                  # the target's source, NUGET_API_KEY for the key
bazel run //:push -- --api-key <key>               # an explicit key
bazel run //:push -- --source ./local-feed         # a folder, no network
```

`bazel run` runs `dotnet nuget push` from the toolchain's SDK once per package,
and a `.snupkg` built beside a package is pushed along with it. Arguments after
`--` go to `dotnet nuget push`; an explicit `--source` or `--api-key` there wins
over the target's `source` and over the `NUGET_API_KEY` environment variable
(`NUGET_SYMBOL_API_KEY` for `--symbol-api-key`). Failing both, credentials come
from your `NuGet.Config` as for any `dotnet nuget push`, so feeds that
authenticate through it - GitHub Packages, Azure Artifacts - work as usual;
`nuget_config` names a `NuGet.Config` to use instead of yours. `skip_duplicate`
(on by default) makes a version the feed already has a warning rather than an
error. `RULES_DOTNET_NUGET_PUSH_DRY_RUN=1` prints the commands instead of
running them. On Windows, spell an explicit source or key as separate words:
`--source <feed>`, not `--source=<feed>`.

## Remote execution

The rules support remote execution out of the box. The remote runners do need to have the required .Net
system dependencies installed though. A common missing system dependency in existing RBE images is `libicu`.

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

### Pruning unused references

When using the compiler worker an additional optimization becomes possible for C#: pruning unused references.
What this does is track which references are actually used by the compiler and if they are unused
they will be ignored by Bazel in subsequent builds. This can lead to better cache reuse.

To enable this optimization, set the following flags:

```
build --@rules_dotnet//dotnet/settings:use_compiler_worker=true
build --@rules_dotnet//dotnet/settings:prune_unused_references=true
```

## Path mapping

The rules_dotnet compile actions support
[path mapping](https://bazel.build/reference/command-line-reference#flag--experimental_output_paths),
which strips the configuration segment out of the paths a compile action sees, so the *same*
compilation reached through two different configurations produces one cache **key** instead of two.

```
common --experimental_output_paths=strip
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
