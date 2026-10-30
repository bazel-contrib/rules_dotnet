# SDK Generation
This program generates the Bazel targets required for rules_dotnet to work with the upstream .Net SDK.

It does the following:

1. Updates the available .Net SDK versions so that the end user of rules_dotnet can choose the SDK version they want to use.
2. Updates the avilable runtime identifiers (RIDs) so that the end user of rules_dotnet can choose the RID they want to when publishing.
3. Updates and creates the Bazel targest for the targeting/runtime/apphost packs that are fetched by rules_dotnet when building.
4. Updates the supported framework lists and the per-framework C# language version cap that rules_dotnet uses to reproduce the SDK's implicit preprocessor defines (`frameworks.bzl`).

## Usage

```
./update-sdk.sh [versions|rids|packs|frameworks|paket ...]
```

The script is a wrapper around `bazel run //dotnet/private/sdk/gen`, so the
generator's own dependencies come from `paket.lock` through Bazel and no local
`dotnet` install is involved. Naming a subset matters because the generators
download release metadata and take minutes.

### frameworks.bzl

This one reads an SDK rather than the release feed: the framework lists come
from `Microsoft.NET.SupportedTargetFrameworks.props`, and the language versions
are probed out of MSBuild one framework at a time, because that mapping lives
inside Roslyn rather than in any targets file. The SDK is downloaded by the
generator and the generated file records which version it was read from.

### gen.fsproj

Only for IDE support, like every other project file in this repo. It restores
through `Paket.Restore.targets`, so keep `dotnet-tools.json` pinned to the same
paket as the `paket_cli` group in `paket.dependencies`: the targets file is
format-versioned against paket, and an older one writes resolved lines with
fewer fields than it reads, so every `PackageReference` condition evaluates
false and restore silently produces a `project.assets.json` with **zero**
libraries. The failure that follows points at missing `NuGet.*` namespaces and
says nothing about paket.

# References
* https://github.com/dotnet/designs/blob/main/accepted/2019/targeting-packs-and-runtime-packs.md
* https://github.com/dotnet/designs/blob/main/accepted/2020/targeting-packs/targeting-packs.md

## Upgrading to a new .NET release

```
./update-sdk.sh
```

That is the whole procedure. There is no channel list to extend, no default
target framework to bump, and no compatibility entry to add by hand: every
table is derived from the release feed and from an SDK the generator downloads
itself.

Then review the diff, and check the parity harness:

```
bazel run //dotnet/private/tests/harness:update_goldens
./dotnet/private/tests/harness/capture.sh
```

A new SDK legitimately moves things -- new analyzers, new implicit defines, a
new C# version -- and the harness is what tells you whether rules_dotnet moved
the same way. `dotnet/private/tests/harness/FINDINGS.md` lists the divergences
that are known and expected, so anything outside that list is new.

### Preview support does not change the default

The generator includes every available release channel, including previews and
release candidates. For prerelease channels it resolves prerelease packs from
NuGet; generally-available channels continue to use stable packs only. SDK,
framework, and pack tables therefore describe the same set of releases.

`DEFAULT_TFM` remains the newest **generally-available** framework. Using a
preview is explicit: register its SDK and request its target framework. For
example, .NET 11 RC3 uses
`dotnet.toolchain(dotnet_version = "11.0.100-rc.3.26522.148")` and
`target_frameworks = ["net11.0"]`, with
`--@rules_dotnet//dotnet:target_framework=net11.0` selecting the framework.
This does not change the stable SDK used to build rules_dotnet's own tools.

Run `./update-sdk.sh versions packs frameworks` when updating a preview. Once
the release goes GA, regeneration also advances the default framework.

### Things that still need a human

- **Servicing bumps ripple into tests.** `pack_bands.bzl` pins an exact pack
  version per band, and `dotnet/private/tests/packs/packs_test.bzl` asserts on
  those strings. A routine patch release will fail it until the expectations
  are updated.
- **`MODULE.bazel` still pins the SDK by hand.** The generator adds the new
  version to `versions.bzl`; choosing to move `dotnet.toolchain(dotnet_version)`
  onto it is a deliberate decision, not an automatic one.

### What the generator produces

| File | Source | Needs network |
|---|---|---|
| `versions.bzl` | the release feed | yes |
| `rids.bzl` | the runtime graph | yes |
| `pack_bands.bzl` | NuGet pack metadata | yes |
| `frameworks.bzl` | an SDK it downloads | yes |
| `paket.dependencies`, `dotnet-tools.json` | the newest Paket on NuGet | yes |

Run a subset with e.g. `./update-sdk.sh frameworks` while iterating.
