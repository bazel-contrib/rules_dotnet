# The .NET SDK and its packs

What changes with every .NET release is looked up when a build needs it; what
changes once a year at most is kept here.

| File | What it holds | Changes |
|---|---|---|
| `releases.bzl` | Reads SDKs and runtime releases from Microsoft's release metadata | never, for a release |
| `global_json.bzl` | Reads the SDK version a `global.json` pins | never |
| `frameworks.bzl` | The target frameworks, and the C# version and compatibility of each | once a decade |
| `pack_bands.bzl` | Which packs each .NET release shipped, and for which runtime identifiers | when a release ships a new kind of pack |
| `packs.bzl` | The pack ids of each framework and runtime identifier, and the tables the pack transitions read | when a release ships a new kind of pack |
| `pack_repos.bzl` | Picks each band's version for the SDK and declares the pack repositories | rarely |
| `rids.bzl` | NuGet's runtime identifier graph, frozen upstream since .NET 8 | never |

## What is looked up, and when

The `dotnet` extension looks an SDK version up in the release metadata the first
time it meets it: the archive for each platform and its SHA-512, the runtime it
ships, and its C# and F# versions. It then picks the version of each pack band
(`net6.0` onwards) for that SDK: its own band at its own runtime, every other
band at the newest patch the metadata dates on or before the SDK's release,
stepping back where NuGet never got a patch's reference packs or ilc.

That is what the SDK bundles in `Microsoft.NETCoreSdk.BundledVersions.props`,
except where the metadata dates a release later than it shipped: SDK 9.0.300
bundles 8.0.16, which the metadata dates nine days after 9.0.300, so its
`net8.0` band is at 8.0.15. Reading the props file instead would mean
downloading the whole SDK to evaluate the extension.

The SDK's details, its band versions and the hashes of the packs are handed back
to Bazel as module extension facts, keyed by the SDK version. They land in
`MODULE.bazel.lock`, and an evaluation that finds them there reads neither the
release metadata nor NuGet.

That only holds because a fact's key alone decides its value. Do not add a fact
that a later release could change, such as the newest patch of a band. For the
same reason an SDK whose metadata lacks an archive or a hash is not remembered,
and nor is a band that stepped back past a patch until a later patch shows it is
never coming: both may just be a feed that has not caught up yet.

## A new .NET release

Nothing here changes for one. `frameworks.bzl` declares the .NET releases up to
`_NEWEST_DECLARED_MAJOR` ahead of time, each taken to ship the packs the newest
in `_PACKS_SINCE` does, so an SDK of a new release, previews included, works the
day it ships: register it with `dotnet.toolchain` and build for its framework.

The registered SDK knows the bands up to its own release. The pack repositories
hold a stand-in for each newer one (`sdk_too_old.bzl`), so building for a
framework newer than the SDK fails saying which SDK it needs.
`DEFAULT_TARGET_FRAMEWORK` is the newest declared framework, so a target builds
for the newest of its `target_frameworks` that nothing asks it to go below.

rules_dotnet's own tools are compiled with the bootstrap SDK in `MODULE.bazel`,
for its framework. A tool runs on the bootstrap SDK's runtime, or on the
registered SDK's when that is of a newer release, since some tools load
assemblies from the registered SDK.

Only these need a release of rules_dotnet:

1. A release that ships a kind of pack the earlier ones did not, or stops
   needing one: `_PACKS_SINCE` and `_PACKS_DROPPED` in `pack_bands.bzl`, and the
   tests under `dotnet/private/tests/packs`.
2. A release that changes what a feature reads out of a pack. .NET 11, for one,
   moved `blazor.webassembly.js` from `Microsoft.AspNetCore.App.Internal.Assets`
   into the application's own `Microsoft.AspNetCore.Components.WebAssembly`, and
   changed the tasks that write a Blazor WebAssembly application's boot
   configuration. `e2e/net11.0` builds one, which is where such a change shows.
3. Moving `_NEWEST_DECLARED_MAJOR` on, once a decade.

To move rules_dotnet itself onto a newer SDK, change the `dotnet_version` of
`dotnet.toolchain` and `dotnet.bootstrap_toolchain` in `MODULE.bazel`, the
`target_frameworks` of the tools in `dotnet/private/tools` to its framework,
and `examples/` and `e2e/` as wanted.

## References

* https://github.com/dotnet/designs/blob/main/accepted/2019/targeting-packs-and-runtime-packs.md
* https://github.com/dotnet/designs/blob/main/accepted/2020/targeting-packs/targeting-packs.md
