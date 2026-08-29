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

## Unsupported workloads

The following workloads are not supported by these rules at this given time:

- VisualBasic
- Razor
- Blazor/WebAssembly
- Workloads that require Mono

Contributions to add the missing workloads are welcomed and the maintainers
will do their best to guide if needed.

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

NuGet packages are fully supported by the rules in two ways

### NuGet packages with Paket

[Paket](https://fsprojects.github.io/Paket/) is a great choice for managing dependencies in .Net
and one of the reasons for Paket being a great fit with Bazel is that it supports a lock file
out of the box.

See the [paket2bazel](../tools/paket2bazel/README.md) docs for instructions on how to set Paket up with Bazel.

## Resources and localization

The `csharp_*` and `fsharp_*` rules can embed arbitrary files into an assembly through the
`resources` attribute, but `.resx` files require compilation into a binary `.resources`
stream before `System.Resources.ResourceManager` can read them. The `resx_resource` rule
does this compilation and the `resx` attribute wires the result into a compilation.

```starlark
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library", "resx_resource")

resx_resource(
    name = "strings",
    srcs = [
        "Strings.resx",      # neutral / culture-invariant
        "Strings.fr.resx",   # French
        "Strings.de.resx",   # German
    ],
)

csharp_library(
    name = "greeter",
    srcs = ["Greeter.cs"],
    out = "Localization",
    resx = [":strings"],
    target_frameworks = ["net9.0"],
)
```

The neutral `.resx` files are embedded into the assembly under their manifest name
(`<AssemblyName>.<path-with-dots>`, e.g. `Localization.Strings`). Each culture variant
(`*.<culture>.resx`) is compiled into a **satellite assembly**
(`<culture>/<AssemblyName>.resources.dll`, e.g. `fr/Localization.resources.dll`) that is
placed next to the main assembly, added to runfiles and `deps.json`, and copied into the
publish output — so `ResourceManager` resolves the right culture at runtime. The same
`resx` attribute is available on `csharp_binary`, `csharp_test`, `fsharp_library`,
`fsharp_binary` and `fsharp_test`; satellite assemblies are always built with the
toolchain's C# compiler because they contain no code.

By default the manifest resource name is derived from the assembly name and the `.resx`
file path (`<AssemblyName>.<path-with-dots>`). To pin an explicit manifest name instead —
for example so it matches a name the consuming code already looks up — override it with
`logical_names`:

```starlark
resx_resource(
    name = "messages",
    srcs = [
        "resources/Messages.resx",
        "resources/Messages.fr.resx",
    ],
    logical_names = {
        "resources/Messages.resx": "MyApp.Messages",
    },
)
```

The value is the exact name to construct `ResourceManager` with. Culture variants inherit
their neutral counterpart's logical name automatically. See the
[`examples/localization`](../examples/localization) example for a runnable end-to-end setup.

## Remote execution

The rules support remote execution out of the box. The remote runners do need to have the required .Net
system dependencies installed though. A common missing system dependency in existing RBE images is `libicu`.
