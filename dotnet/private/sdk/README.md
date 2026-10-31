# The .NET SDK and its packs

Nothing in this directory is generated. What changes with every .NET release is
looked up when a build needs it; what changes once a year at most is kept here
by hand.

| File | What it holds | Changes |
|---|---|---|
| `releases.bzl` | Reads SDKs and runtime releases from Microsoft's release metadata | never, for a release |
| `frameworks.bzl` | The target frameworks, and the C# version and compatibility of each | once a year |
| `pack_bands.bzl` | Which packs each .NET release shipped, and for which runtime identifiers | once a year, if at all |
| `rids.bzl` | NuGet's runtime identifier graph, frozen upstream since .NET 8 | never |

## What is looked up, and when

The `dotnet` extension looks an SDK version up in the release metadata the first
time it meets it: the archive for each platform and its SHA-512, the runtime it
ships, and its C# and F# versions. It then works out the version of each pack
band (`net6.0` onwards) for that SDK: its own band at its own runtime, every
other band at the newest patch the metadata dates on or before the SDK's
release, stepping back where NuGet never got a patch's reference packs or ilc.

That is what the SDK bundles in its `Microsoft.NETCoreSdk.BundledVersions.props`
except where the metadata dates a release later than it shipped. SDK 9.0.300
bundles 8.0.16, for one, which the metadata dates nine days after 9.0.300's
release, so its `net8.0` band is at 8.0.15. Reading the props file itself would
mean downloading the whole SDK to evaluate the extension.

The SDK's details and its band versions are handed back to Bazel as module
extension facts, keyed by the SDK version, alongside the hashes of the packs
themselves. They land in
`MODULE.bazel.lock`, and an evaluation that finds them there reads neither the
release metadata nor NuGet's. That only holds because a fact's key alone
decides its value: an SDK's archives never change once released, and nor does
what had shipped by a given day. Do not add a fact that a later release could
change, such as the newest patch of a band. That is also why an SDK whose
metadata lacks an archive or a hash is not remembered, and nor is a band that
stepped back past a patch until a later patch shows it is never coming: both
may just be a feed that has not caught up yet.

## Supporting a new .NET release

Once it is generally available, not before: a preview's packs are not published
as stable versions, and `DEFAULT_TARGET_FRAMEWORK` is what every downstream
target builds for.

1. Append it to `SDK_NETCOREAPP_FRAMEWORKS` in `frameworks.bzl` and move
   `DEFAULT_TARGET_FRAMEWORK` onto it. Its C# version, its place in the
   compatibility graph and its pack band all follow from the list.
2. Add it to `_subsystem_version` in `dotnet/private/common.bzl`.
3. If the release ships a kind of pack the earlier ones did not, add it to
   `_PACKS_SINCE` in `pack_bands.bzl`.
4. Update the tests that enumerate the frameworks and bands, under
   `dotnet/private/tests/packs` and `dotnet/private/tests/frameworks`.

Until then an SDK of the new release is refused, since its runtime is a
framework `rules_dotnet` does not know.

Moving `rules_dotnet` itself onto a newer SDK is just a matter of changing
`dotnet_version` in `MODULE.bazel`, and in `examples/` and `e2e/` as wanted.

## The Paket CLI

The `paket_cli` group in `paket.dependencies` and `dotnet-tools.json` pin Paket
in two places, which must agree. The project files in this repository exist for
IDE support only and restore through `.paket/Paket.Restore.targets`, which is
format-versioned against Paket: an older Paket writes resolved lines with fewer
fields than the targets read, so every `PackageReference` condition is false
and restore silently produces a `project.assets.json` with no libraries at all.

## References

* https://github.com/dotnet/designs/blob/main/accepted/2019/targeting-packs-and-runtime-packs.md
* https://github.com/dotnet/designs/blob/main/accepted/2020/targeting-packs/targeting-packs.md
