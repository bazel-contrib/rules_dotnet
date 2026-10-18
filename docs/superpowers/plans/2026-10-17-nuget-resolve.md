# `nuget.resolve` — NuGet-resolutie en pinning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-subagent-driven-development (recommended) or superpowers-executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bouw een nieuwe bzlmod-module-extensie `nuget` met een `resolve`-tag die NuGet-afhankelijkheden transitief resolveert (naar het model van `maven_install` + `maven_install.json` uit rules_jvm_external), met een eigen C#-resolver-tool, een eigen lockbestand `nuget_resolve.json` met sha512-integriteit en input-hash — en verwijder de bestaande `packages_lock`-extensie volledig terwijl de twee resterende gebruikers migreren.

**Architecture:** Vier componenten. (1) Een C#-console-tool `tools/nuget_resolver/` op de gepubliceerde `NuGet.Protocol` 7.0.1- en `NuGet.DependencyResolver.Core` 7.0.1-packages. (2) Een interne repository `nuget_resolver_tool` die de tool bij fetch-tijd offline bouwt uit een gepinde `.nupkg`-folder-feed met de bootstrap-.NET-SDK. (3) Hub/spoke-repository-generatie die de bestaande `nuget_repo.bzl`/`nuget_archive.bzl`-machinery hergebruikt: gepind via `nuget_archive`-spokes + gepinde hubs, ongepind via monolithische hubs die `unpinned_<name>//:nuget_resolve.json` lezen. (4) Pinning naar rules_jvm_external: `unpinned_<name>` resolveert en heeft een `:pin`-run-target; gepinde hubs valideren de in Starlark berekende input-hash (`fail_if_repin_required`, `REPIN=1` waarschuwt) en aliassen `:pin`.

**Tech Stack:** Bazel 9 (bzlmod), Starlark, C# / .NET (bootstrap-SDK 10.0.401, tool-TFM net10.0), NuGet.Protocol 7.0.1, NuGet.DependencyResolver.Core 7.0.1, NUnit (tool-tests via `csharp_nunit_test`), skylib `unittest` (Starlark-tests), Go 1.24 (Gazelle-indexmigratie).

**Spec:** `docs/superpowers/specs/2026-10-17-nuget-resolve-design.md` (goedgekeurd). Referentie-implementaties: `private/rules/coursier.bzl` in `/home/jhobert/Projects/Gazelle/rules_jvm_external` (pinning-model), NuGet.Client-checkout `/home/jhobert/Projects/Gazelle/NuGet.Client` (alleen API-referentie).

---

## Environment notes (read before running any command)

These workarounds are required in this development environment. Run the exports in **every new shell** before running `bazel` or `go` commands:

```bash
# Bazel fails inside the sandbox with "invalid registered toolchain
# '@local_jdk//:bootstrap_runtime_toolchain_definition' ... (Permission denied)"
# because /etc/java-openjdk is not readable. Point JAVA_HOME at Bazel's own JDK:
export JAVA_HOME="$(bazel info java-home 2>/dev/null)"

# ~/go is not writable in this sandbox. The module cache is already primed
# under /tmp/opencode/gopath; proxy.golang.org is reachable for anything missing.
export GOPATH=/tmp/opencode/gopath
export GOCACHE=/tmp/opencode/gocache
```

Other environment facts:

- Work from the repo root: `/home/jhobert/Projects/Gazelle/rules_dotnet` (branch `feature/gazelle`).
- `bazel` is bazelisk; `.bazelversion` pins Bazel 9.1.1. Local `go` is 1.27 (only used for `go test`; Bazel builds use the rules_go 1.24.12 SDK). A local `dotnet` exists but is used in this plan only as a sanity check in Task 4 — the build itself never uses it. NOTE: as of Task 4 the sandbox does NOT grant `$HOME/.dotnet`; the opencode-with-nuget nono profile must be re-promoted (v1.1.0 adds `$HOME/.dotnet` and `$HOME/.local/share/Nuget`) and the session restarted before running any `dotnet` CLI command (Task 4 Step 5, Task 8).
- **Pre-existing gazelle drift:** running `bazel run //:gazelle` on the unmodified repo adds `bzl_library` targets in `dotnet/BUILD.bazel` and various `dotnet/private/tests/**/BUILD.bazel` files. That drift is unrelated to this feature. After every root gazelle run, revert it:

```bash
git diff --name-only -- dotnet/BUILD.bazel dotnet/private | xargs -r git checkout --
```

- Commit style in this repo: imperative, "Add X". Commit at the end of every task with `git add` of exactly the files listed in that task's commit step.
- e2e directories are independent Bazel modules; run their commands with the e2e directory as working directory. They download from nuget.org at fetch time — network is required (and available in CI, as the former `e2e/net10.0_packages_lock` already did).

## Normative design decisions (fixed by the spec, restated for the implementer)

- Publieke API: één module-extensie `nuget` uit `@rules_dotnet//dotnet:nuget.bzl` met één tag `resolve`; alle repository-rules blijven private. Adressering: `@<name>.<tfm>//<package-id-lowercase>`.
- `resolve`-attributen: `name` (verplicht), `packages` (string_dict, verplicht, niet-leeg), `frameworks` (string_list, verplicht, niet-leeg), `sources` (default `["https://api.nuget.org/v3/index.json"]`), `lock_file` (label, optioneel), `fail_if_repin_required` (bool, default `True`), `netrc` (label, optioneel).
- Repository-namen: hub per framework `<name>.<tfm>`, resolve-repository `unpinned_<name>`, tool-repository `nuget_resolver_tool`.
- De input-hash wordt **in Starlark** berekend (`hash()` over een canonieke JSON van gesorteerde frameworks, gesorteerde packages-dict, sources in opgegeven volgorde) en aan de tool meegegeven; de tool stempelt hem ongemoeid in het lockbestand. De extensie berekent hem opnieuw bij elke evaluatie en geeft hem als attribuut aan de gepinde hub, die hem met het lockbestand vergelijkt — een attribuutwijziging triggert refetch, dus dit is equivalent aan "de hub berekent hem opnieuw".
- De gepinde hub valideert bij fetch: mismatch + `fail_if_repin_required` + geen `REPIN` in de environment → `fail()` met repin-instructies (`REPIN=1 bazel run @<name>.<tfm>//:pin`); mismatch + `REPIN` gezet of attribuut `False` → waarschuwing en doorbouwen met het bestaande lockbestand. Een lockbestand-hash uit de lijst vervangen algoritmen waarschuwt altijd.
- Repin-commando: `REPIN=1 bazel run @<name>.<tfm>//:pin`. Zowel de gepinde als de ongepinde hub krijgt `alias(name = "pin", actual = "@unpinned_<name>//:pin")` — de gepinde zodat het commando werkt ongeacht welke hub in `use_repo` staat, de ongepinde zodat de **eerste** pin (wanneer `lock_file` nog niet gezet is) via hetzelfde commando ontstaat.
- De tool bouwt offline: `dotnet publish` met een `NuGet.config` die alleen de lokale folder-feed `feed/` als bron heeft; de volledige transitieve `.nupkg`-sluiting van de tool staat gepind met sha512 in `TOOL_PACKAGES` in `dotnet/private/nuget_resolve/tool.bzl`.
- De bootstrap-SDK wordt gelabeld als `@dotnet_sdk.<versie>_<platform>//:dotnet` (`.exe` op Windows); rules_dotnet's eigen `MODULE.bazel` neemt de zes per-platform bootstrap-SDK-repository's op in `use_repo(dotnet, ...)` zodat die apparent names zichtbaar zijn vanuit de door de extensie gedeclareerde repository's. `dotnet/repositories.bzl` exporteert het `dotnet`-binaire met `exports_files` zodat het label bestaat.
- Cross-repository labels tussen door dezelfde extensie gedeclareerde repo's (`@unpinned_<name>//:pin` vanuit de hub, `@nuget_resolver_tool//:publish/NuGetResolver.dll` vanuit `unpinned_<name>`) werken omdat door één extensie gegenereerde repo's elkaars apparent names in hun repo-mapping hebben.
- Lockbestandformaat `nuget_resolve.json`: `version` (1), `inputHash` (decimale string), `frameworks` → tfm → `packages`: gesorteerde lijst van `{id, version, sha512 ("sha512-<base64>"), urls[]}`. Deterministisch geserialiseerd (gesorteerde keys, twee spaties indentatie). Geen dependency-edges — die leest de hub/spoke-machinery uit de `.nuspec`, zoals bij `paket`.

## File structure

Nieuwe bestanden (Starlark):

| File | Responsibility |
|---|---|
| `dotnet/nuget.bzl` | Publieke ingang: docstring + re-export van de extensie |
| `dotnet/private/nuget_resolve/BUILD.bazel` | `bzl_library`s + `tool_version_test` (sh_test SDK-versieguard) |
| `dotnet/private/nuget_resolve/extension.bzl` | tag-class, `claimed`-check, declaratie van alle repository's, `extension_metadata` |
| `dotnet/private/nuget_resolve/lock.bzl` | Parser + validator voor `nuget_resolve.json` |
| `dotnet/private/nuget_resolve/input_hash.bzl` | Canonieke input-hash + lijst vervangen algoritmen |
| `dotnet/private/nuget_resolve/tool.bzl` | `TOOL_PACKAGES`-pin, `BOOTSTRAP_SDK_VERSION`, tool-build-repository-rule, host-platform-mapping |
| `dotnet/private/nuget_resolve/resolve.bzl` | Ongepinde resolve-repository-rule (voert tool uit, schrijft lockbestand, `:pin`-script) |
| `dotnet/private/nuget_resolve/pinned_hub.bzl` | Gepinde hub-repository-rule (hash-validatie, `environ = ["REPIN"]`, `:pin`-alias) |
| `dotnet/private/nuget_resolve/unpinned_hub.bzl` | Monolithische ongepinde hub-repository-rule |
| `dotnet/private/nuget_resolve/tool_version_test.sh` | Guard: `BOOTSTRAP_SDK_VERSION` == bootstrap-versie in `MODULE.bazel` |
| `dotnet/private/tests/nuget_resolve/{BUILD.bazel,lock_test.bzl,input_hash_test.bzl,extension_test.bzl}` | Starlark-unittests |

Nieuwe bestanden (tool):

| File | Responsibility |
|---|---|
| `tools/nuget_resolver/NuGetResolver.csproj` | Fetch-tijd-build (net10.0, NuGet.Protocol + NuGet.DependencyResolver.Core 7.0.1) |
| `tools/nuget_resolver/{Program,ResolveSpec,ResolveException,Resolver,FeedDependencyProvider,LockFile,Netrc}.cs` | De resolver-tool |
| `tools/nuget_resolver/BUILD.bazel` | `csharp_library` voor de repo-tests |
| `tools/nuget_resolver/tests/{BUILD.bazel,FeedFixture.cs,SpecTests.cs,LockFileTests.cs,ResolverTests.cs,ProgramTests.cs,NetrcTests.cs}` | NUnit-tests met folder-feed-fixture |

Nieuwe bestanden (examples/e2e):

| File | Responsibility |
|---|---|
| `examples/nuget_resolve/**` | Voorbeeld: Serilog met een sink, ingecheckt `nuget_resolve.json` |
| `e2e/nuget_resolve_basic/**` | Ongepind, één package, build + run |
| `e2e/nuget_resolve_transitive/**` | Gepind, diepe keten (Http → Logging → DI → DI.Abstractions) + diamond (Serilog-unificatie) |
| `e2e/nuget_resolve_multi_framework/**` | Gepind, net8.0 + net10.0 uit één tag |
| `e2e/nuget_resolve_pinning/**` | Gepind + `test.sh` dat repin-detectie en de repin-flow bewijst |

Gewijzigde bestanden:

| File | Change |
|---|---|
| `paket.dependencies`, `paket.lock` | NuGet.Protocol/NuGet.DependencyResolver.Core 7.0.1 in group `rules_dotnet_nuget_packages` (voor de Bazel-build van de tool-tests) |
| `dotnet/private/rules/nuget/nuget_archive.bzl` | Nieuw optioneel attribuut `urls`; publieke helper `fetch_package_into` |
| `dotnet/private/rules/nuget/nuget_repo.bzl` | Hub-BUILD-generatie geëxtraheerd naar publieke `write_hub_files`; `nuget_archives` geeft `urls` door |
| `dotnet/repositories.bzl` | `exports_files` voor het `dotnet`-binaire in de SDK-repository-BUILD |
| `MODULE.bazel` | Zes per-platform bootstrap-SDK-repository's in `use_repo(dotnet, ...)` |
| `dotnet/BUILD.bazel` | `nuget`-`bzl_library` erbij (Task 11); `packages_lock`-`bzl_library` weg (Task 20) |
| `dotnet/gazelle/private/nuget/nuget.go` (+ test) | Index leest `nuget_resolve.json` |
| `dotnet/gazelle/dotnetconfig/config.go` (+ test), `dotnet/gazelle/configure.go`, `dotnet/gazelle/lang.go`, `dotnet/gazelle/resolve_test.go`, `dotnet/gazelle/testdata/**` | Default lockbestand en fixtures naar `nuget_resolve.json` |
| `examples/MODULE.bazel`, `examples/gazelle_csharp/` | Migratie naar `nuget.resolve` |
| `e2e/gazelle_net10.0/MODULE.bazel` | Migratie naar `nuget.resolve` |
| `.bazelci/presubmit.yml` | Vier nieuwe e2e-mappen in `e2e_working_directory` |

Verwijderd (Task 20): `dotnet/packages_lock.bzl`, `dotnet/private/packages_lock/`, `dotnet/private/tests/packages_lock/`, `e2e/net10.0_packages_lock/`, `examples/packages_json/`, de `packages_lock`-`bzl_library` in `dotnet/BUILD.bazel`.

---

### Task 1: NuGet-packages voor de tool aan paket toevoegen

De Bazel-build van de tool en zijn tests halen hun NuGet-afhankelijkheden uit de paket-group `rules_dotnet_nuget_packages` (framework net9.0). Voeg `NuGet.Protocol` en `NuGet.DependencyResolver.Core` 7.0.1 toe en regenereer `paket.lock`.

**Files:**
- Modify: `paket.dependencies` (group `rules_dotnet_nuget_packages`)
- Modify: `paket.lock` (regenerated)

- [x] **Step 1: Add the packages to paket.dependencies**

In `paket.dependencies`, group `rules_dotnet_nuget_packages`. Old:

```
group rules_dotnet_nuget_packages
    framework: net9.0
    source https://api.nuget.org/v3/index.json

    nuget NUnit 3.14.0
    nuget NUnitLite 3.14.0
```

New:

```
group rules_dotnet_nuget_packages
    framework: net9.0
    source https://api.nuget.org/v3/index.json

    nuget NuGet.DependencyResolver.Core 7.0.1
    nuget NuGet.Protocol 7.0.1
    nuget NUnit 3.14.0
    nuget NUnitLite 3.14.0
```

- [x] **Step 2: Regenerate paket.lock**

Run: `bazel run //tools/paket -- install`
Expected: exit 0; `git status` toont een gewijzigde `paket.lock` waarin `NuGet.Protocol` en `NuGet.DependencyResolver.Core` (plus hun transitieve sluiting) in group `rules_dotnet_nuget_packages` staan.

- [x] **Step 3: Verify the new packages resolve in Bazel**

Run: `bazel build @paket.rules_dotnet_nuget_packages//nuget.protocol @paket.rules_dotnet_nuget_packages//nuget.dependencyresolver.core`
Expected: `INFO: Build completed successfully`, beide targets gebouwd.

- [x] **Step 4: Commit**

```bash
git add paket.dependencies paket.lock
git commit -m "Add NuGet.Protocol and NuGet.DependencyResolver.Core to the nuget packages group"
```

---

### Task 2: Tool — ResolveSpec, ResolveException en LockFile met tests (TDD)

Pure logica zonder NuGet-API's: de spec-invoer lezen en het lockbestand deterministisch schrijven. Eerst de falende tests, dan de implementatie. Deze task zet ook de csproj en BUILD-scaffolding neer waar latere tasks op voortbouwen.

**Files:**
- Create: `tools/nuget_resolver/NuGetResolver.csproj`
- Create: `tools/nuget_resolver/ResolveSpec.cs`
- Create: `tools/nuget_resolver/ResolveException.cs`
- Create: `tools/nuget_resolver/LockFile.cs`
- Create: `tools/nuget_resolver/BUILD.bazel`
- Test: `tools/nuget_resolver/tests/BUILD.bazel`
- Test: `tools/nuget_resolver/tests/SpecTests.cs`
- Test: `tools/nuget_resolver/tests/LockFileTests.cs`

- [x] **Step 1: Write the failing tests**

Create `tools/nuget_resolver/tests/SpecTests.cs`:

```csharp
using NUnit.Framework;
using NuGetResolver;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class SpecTests
{
    [Test]
    public void LoadReadsPackagesFrameworksAndSources()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "spec.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, """
            {
              "packages": { "Newtonsoft.Json": "13.0.3", "Serilog": "4.0.*" },
              "frameworks": ["net8.0", "net10.0"],
              "sources": ["https://api.nuget.org/v3/index.json", "https://pkgs.example.com/v3/index.json"]
            }
            """);

        var spec = ResolveSpec.Load(path);

        Assert.That(spec.Packages, Is.EqualTo(new[]
        {
            new PackageRequest("Newtonsoft.Json", "13.0.3"),
            new PackageRequest("Serilog", "4.0.*"),
        }));
        Assert.That(spec.Frameworks, Is.EqualTo(new[] { "net8.0", "net10.0" }));
        Assert.That(spec.Sources, Is.EqualTo(new[]
        {
            "https://api.nuget.org/v3/index.json",
            "https://pkgs.example.com/v3/index.json",
        }));
    }

    [Test]
    public void LoadMissingFileThrowsResolveException()
    {
        var ex = Assert.Throws<ResolveException>(() => ResolveSpec.Load("/does/not/exist/spec.json"));
        Assert.That(ex!.Message, Does.Contain("/does/not/exist/spec.json"));
    }
}
```

Create `tools/nuget_resolver/tests/LockFileTests.cs`:

```csharp
using NUnit.Framework;
using NuGetResolver;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class LockFileTests
{
    private static readonly Dictionary<string, List<ResolvedPackage>> Frameworks = new()
    {
        ["net10.0"] = new List<ResolvedPackage>
        {
            new("Serilog", "4.0.0", "sha512-AAAA", new[] { "https://feed/serilog.4.0.0.nupkg" }),
            new("Newtonsoft.Json", "13.0.3", "sha512-BBBB", new[]
            {
                "https://feed1/newtonsoft.json.13.0.3.nupkg",
                "https://feed2/newtonsoft.json.13.0.3.nupkg",
            }),
        },
        ["net8.0"] = new List<ResolvedPackage>
        {
            new("Newtonsoft.Json", "13.0.3", "sha512-BBBB", new[] { "https://feed1/newtonsoft.json.13.0.3.nupkg" }),
        },
    };

    [Test]
    public void RenderIsDeterministicAndSorted()
    {
        const string expected = """
            {
              "version": 1,
              "inputHash": "737269301",
              "frameworks": {
                "net10.0": {
                  "packages": [
                    {
                      "id": "Newtonsoft.Json",
                      "version": "13.0.3",
                      "sha512": "sha512-BBBB",
                      "urls": [
                        "https://feed1/newtonsoft.json.13.0.3.nupkg",
                        "https://feed2/newtonsoft.json.13.0.3.nupkg"
                      ]
                    },
                    {
                      "id": "Serilog",
                      "version": "4.0.0",
                      "sha512": "sha512-AAAA",
                      "urls": [
                        "https://feed/serilog.4.0.0.nupkg"
                      ]
                    }
                  ]
                },
                "net8.0": {
                  "packages": [
                    {
                      "id": "Newtonsoft.Json",
                      "version": "13.0.3",
                      "sha512": "sha512-BBBB",
                      "urls": [
                        "https://feed1/newtonsoft.json.13.0.3.nupkg"
                      ]
                    }
                  ]
                }
              }
            }
            """;

        var rendered = LockFile.Render("737269301", Frameworks);

        Assert.That(rendered, Is.EqualTo(expected.Replace("\r\n", "\n")));
        Assert.That(LockFile.Render("737269301", Frameworks), Is.EqualTo(rendered), "second render must be identical");
    }
}
```

Let op: de invoer-dict zet `net10.0` vóór `net8.0`, en de verwachte output ook — de test pint dus **ordinale sortering van framework-keys** ("net10.0" sorteert ordinaal vóór "net8.0" want "1" < "8"). Packages sorteren ordinal-ignore-case: `Newtonsoft.Json` vóór `Serilog`.

Create `tools/nuget_resolver/tests/BUILD.bazel`:

```python
load(
    "//dotnet:defs.bzl",
    "csharp_nunit_test",
)

csharp_nunit_test(
    name = "nuget_resolver_test",
    srcs = glob(["*.cs"]),
    target_frameworks = ["net10.0"],
    deps = [
        "//tools/nuget_resolver",
        "@paket.rules_dotnet_nuget_packages//nuget.dependencyresolver.core",
        "@paket.rules_dotnet_nuget_packages//nuget.protocol",
    ],
)
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bazel test //tools/nuget_resolver/tests:nuget_resolver_test`
Expected: FAIL — `no such package 'tools/nuget_resolver'` (de library bestaat nog niet).

- [x] **Step 3: Write the implementation**

Create `tools/nuget_resolver/NuGetResolver.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <AssemblyName>NuGetResolver</AssemblyName>
    <!--
      Only the tool's own sources: the default glob would also pick up
      tests/*.cs, which reference NUnit and only compile in the Bazel test.
      The offline tool build (tool.bzl) copies exactly the tool's sources next
      to the csproj, so `*.cs` covers everything there.
    -->
    <EnableDefaultCompileItems>false</EnableDefaultCompileItems>
  </PropertyGroup>
  <ItemGroup>
    <Compile Include="*.cs" />
  </ItemGroup>
  <ItemGroup>
    <PackageReference Include="NuGet.Protocol" Version="7.0.1" />
    <PackageReference Include="NuGet.DependencyResolver.Core" Version="7.0.1" />
  </ItemGroup>
</Project>
```

Create `tools/nuget_resolver/ResolveException.cs`:

```csharp
namespace NuGetResolver;

/// <summary>
/// A resolution failure whose message is shown to the user verbatim.
/// </summary>
public sealed class ResolveException : Exception
{
    public ResolveException(string message)
        : base(message)
    {
    }
}
```

Create `tools/nuget_resolver/ResolveSpec.cs`:

```csharp
using System.Text.Json;

namespace NuGetResolver;

/// <summary>One requested package: an id and a PackageReference-style version range.</summary>
public sealed record PackageRequest(string Id, string Range);

/// <summary>The JSON specification the repository rule hands to the resolver.</summary>
public sealed record ResolveSpec(
    IReadOnlyList<PackageRequest> Packages,
    IReadOnlyList<string> Frameworks,
    IReadOnlyList<string> Sources)
{
    public static ResolveSpec Load(string path)
    {
        JsonDocument doc;
        try
        {
            doc = JsonDocument.Parse(File.ReadAllText(path));
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException)
        {
            throw new ResolveException($"Could not read resolve spec {path}: {e.Message}");
        }

        using (doc)
        {
            var root = doc.RootElement;
            var packages = new List<PackageRequest>();
            foreach (var package in root.GetProperty("packages").EnumerateObject())
            {
                packages.Add(new PackageRequest(package.Name, package.Value.GetString()!));
            }

            var frameworks = root.GetProperty("frameworks").EnumerateArray()
                .Select(e => e.GetString()!).ToList();
            var sources = root.GetProperty("sources").EnumerateArray()
                .Select(e => e.GetString()!).ToList();
            return new ResolveSpec(packages, frameworks, sources);
        }
    }
}
```

Create `tools/nuget_resolver/LockFile.cs`:

```csharp
using System.Text;
using System.Text.Json;

namespace NuGetResolver;

/// <summary>One resolved package in the lock file.</summary>
public sealed record ResolvedPackage(string Id, string Version, string Sha512, IReadOnlyList<string> Urls);

/// <summary>
/// Writes nuget_resolve.json deterministically: keys in fixed order, packages
/// sorted by id (ordinal-ignore-case), frameworks sorted ordinal, two-space
/// indentation. Diffs between runs are minimal and stable.
/// </summary>
public static class LockFile
{
    public const int FormatVersion = 1;

    public static string Render(string inputHash, IReadOnlyDictionary<string, List<ResolvedPackage>> frameworks)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true, IndentSize = 2 }))
        {
            writer.WriteStartObject();
            writer.WriteNumber("version", FormatVersion);
            writer.WriteString("inputHash", inputHash);
            writer.WriteStartObject("frameworks");
            foreach (var (tfm, packages) in frameworks.OrderBy(kv => kv.Key, StringComparer.Ordinal))
            {
                writer.WriteStartObject(tfm);
                writer.WriteStartArray("packages");
                foreach (var package in packages.OrderBy(p => p.Id, StringComparer.OrdinalIgnoreCase))
                {
                    writer.WriteStartObject();
                    writer.WriteString("id", package.Id);
                    writer.WriteString("version", package.Version);
                    writer.WriteString("sha512", package.Sha512);
                    writer.WriteStartArray("urls");
                    foreach (var url in package.Urls)
                    {
                        writer.WriteStringValue(url);
                    }

                    writer.WriteEndArray();
                    writer.WriteEndObject();
                }

                writer.WriteEndArray();
                writer.WriteEndObject();
            }

            writer.WriteEndObject();
            writer.WriteEndObject();
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }
}
```

Create `tools/nuget_resolver/BUILD.bazel`:

```python
load(
    "//dotnet:defs.bzl",
    "csharp_library",
)

csharp_library(
    name = "nuget_resolver",
    srcs = glob(
        ["*.cs"],
        allow_empty = False,
    ),
    target_frameworks = ["net10.0"],
    visibility = ["//tools:__subpackages__"],
    deps = [
        "@paket.rules_dotnet_nuget_packages//nuget.dependencyresolver.core",
        "@paket.rules_dotnet_nuget_packages//nuget.protocol",
    ],
)
```

- [x] **Step 4: Run the test to verify it passes**

Run: `bazel test //tools/nuget_resolver/tests:nuget_resolver_test`
Expected: PASS — `//tools/nuget_resolver/tests:nuget_resolver_test PASSED`.

- [x] **Step 5: Commit**

```bash
git add tools/nuget_resolver/NuGetResolver.csproj tools/nuget_resolver/ResolveSpec.cs tools/nuget_resolver/ResolveException.cs tools/nuget_resolver/LockFile.cs tools/nuget_resolver/BUILD.bazel tools/nuget_resolver/tests/BUILD.bazel tools/nuget_resolver/tests/SpecTests.cs tools/nuget_resolver/tests/LockFileTests.cs
git commit -m "Add resolve spec parsing and lock file rendering for the NuGet resolver tool"
```

---

### Task 3: Tool — FeedDependencyProvider en Resolver met folder-feed-tests (TDD)

De kern: graafresolutie met `RemoteDependencyWalker` uit `NuGet.DependencyResolver.Core`, met een eigen `IRemoteDependencyProvider` bovenop `NuGet.Protocol`-resources. De tests draaien tegen een lokale folder-feed-fixture (geen netwerk).

**Files:**
- Create: `tools/nuget_resolver/FeedDependencyProvider.cs`
- Create: `tools/nuget_resolver/Resolver.cs`
- Create: `tools/nuget_resolver/Netrc.cs`
- Test: `tools/nuget_resolver/tests/FeedFixture.cs`
- Test: `tools/nuget_resolver/tests/ResolverTests.cs`

- [x] **Step 1: Write the failing tests**

Create `tools/nuget_resolver/tests/FeedFixture.cs`:

```csharp
using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

namespace NuGetResolver.Tests;

/// <summary>
/// Builds a flat (V2-layout) local folder feed of fabricated .nupkg files.
/// Repository.Factory.GetCoreV3 treats a flat folder of nupkgs as a local feed.
/// </summary>
public static class FeedFixture
{
    public static string Create(params (string Id, string Version, (string Id, string Range)[] Dependencies)[] packages)
    {
        var dir = Path.Combine(Path.GetTempPath(), "nuget-resolver-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        foreach (var (id, version, dependencies) in packages)
        {
            WriteNupkg(dir, id, version, dependencies);
        }

        return dir;
    }

    /// <summary>The SRI hash of the fixture nupkg's bytes, as the resolver must record it.</summary>
    public static string ExpectedSha512(string feedDir, string id, string version)
    {
        var bytes = File.ReadAllBytes(Path.Combine(feedDir, $"{id}.{version}.nupkg"));
        return "sha512-" + Convert.ToBase64String(SHA512.HashData(bytes));
    }

    private static void WriteNupkg(string dir, string id, string version, (string Id, string Range)[] dependencies)
    {
        var nuspec = new StringBuilder();
        nuspec.Append("""
            <?xml version="1.0" encoding="utf-8"?>
            <package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
              <metadata>
            """);
        nuspec.Append($"\n    <id>{id}</id>\n    <version>{version}</version>\n    <description>fixture</description>\n    <authors>fixture</authors>");
        if (dependencies.Length > 0)
        {
            nuspec.Append("\n    <dependencies>\n      <group targetFramework=\"netstandard2.0\">");
            foreach (var (depId, range) in dependencies)
            {
                nuspec.Append($"\n        <dependency id=\"{depId}\" version=\"{range}\" />");
            }

            nuspec.Append("\n      </group>\n    </dependencies>");
        }

        nuspec.Append("\n  </metadata>\n</package>\n");

        var path = Path.Combine(dir, $"{id}.{version}.nupkg");
        using var archive = ZipFile.Open(path, ZipArchiveMode.Create);
        WriteEntry(archive, "[Content_Types].xml", """
            <?xml version="1.0" encoding="utf-8"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="nuspec" ContentType="application/octet-stream" />
              <Default Extension="dll" ContentType="application/octet-stream" />
            </Types>
            """);
        WriteEntry(archive, $"{id}.nuspec", nuspec.ToString());
        WriteEntry(archive, $"lib/netstandard2.0/{id}.dll", "fixture");
    }

    private static void WriteEntry(ZipArchive archive, string name, string content)
    {
        var entry = archive.CreateEntry(name);
        using var writer = new StreamWriter(entry.Open());
        writer.Write(content);
    }
}
```

Create `tools/nuget_resolver/tests/ResolverTests.cs`:

```csharp
using NUnit.Framework;
using NuGetResolver;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class ResolverTests
{
    private static ResolveSpec Spec(string feed, string[] frameworks, params (string Id, string Range)[] packages)
        => new(packages.Select(p => new PackageRequest(p.Id, p.Range)).ToList(), frameworks, new[] { feed });

    [Test]
    public async Task MinimumVersionResolvesToLowestApplicable()
    {
        var feed = FeedFixture.Create(
            ("Widget.Core", "1.0.0", []),
            ("Widget.Core", "1.2.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "1.0.0")), null, default);

        var packages = result["net8.0"];
        Assert.That(packages.Select(p => p.Id), Is.EqualTo(new[] { "Widget.Core" }));
        Assert.That(packages[0].Version, Is.EqualTo("1.0.0"), "a plain version is a minimum; lowest applicable wins");
    }

    [Test]
    public async Task ExactVersionResolvesExactly()
    {
        var feed = FeedFixture.Create(
            ("Widget.Core", "1.0.0", []),
            ("Widget.Core", "1.2.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "[1.2.0]")), null, default);

        Assert.That(result["net8.0"][0].Version, Is.EqualTo("1.2.0"));
    }

    [Test]
    public async Task FloatingVersionResolvesToHighestMatch()
    {
        var feed = FeedFixture.Create(
            ("Widget.Core", "4.0.1", []),
            ("Widget.Core", "4.0.3", []),
            ("Widget.Core", "4.1.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "4.0.*")), null, default);

        Assert.That(result["net8.0"][0].Version, Is.EqualTo("4.0.3"));
    }

    [Test]
    public async Task TransitiveDeepChainIsFullyResolved()
    {
        var feed = FeedFixture.Create(
            ("App.A", "1.0.0", [("Lib.B", "1.0.0")]),
            ("Lib.B", "1.0.0", [("Lib.C", "1.0.0")]),
            ("Lib.C", "1.0.0", [("Lib.D", "1.0.0")]),
            ("Lib.D", "1.0.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("App.A", "1.0.0")), null, default);

        Assert.That(
            result["net8.0"].Select(p => p.Id),
            Is.EqualTo(new[] { "App.A", "Lib.B", "Lib.C", "Lib.D" }));
    }

    [Test]
    public async Task DiamondUnifiesToTheHigherMinimum()
    {
        var feed = FeedFixture.Create(
            ("App.A", "1.0.0", [("Widget.Core", "1.0.0")]),
            ("App.B", "1.0.0", [("Widget.Core", "1.1.0")]),
            ("Widget.Core", "1.0.0", []),
            ("Widget.Core", "1.1.0", []));

        var result = await Resolver.ResolveAsync(
            Spec(feed, ["net8.0"], ("App.A", "1.0.0"), ("App.B", "1.0.0")), null, default);

        var packages = result["net8.0"];
        Assert.That(packages.Select(p => p.Id), Is.EqualTo(new[] { "App.A", "App.B", "Widget.Core" }));
        Assert.That(
            packages.Single(p => p.Id == "Widget.Core").Version,
            Is.EqualTo("1.1.0"),
            "two paths to Widget.Core unify to one version: the highest minimum");
    }

    [Test]
    public async Task EveryFrameworkIsResolvedSeparately()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0", "net9.0"], ("Widget.Core", "1.0.0")), null, default);

        Assert.That(result.Keys.OrderBy(k => k, StringComparer.Ordinal), Is.EqualTo(new[] { "net8.0", "net9.0" }));
        Assert.That(result["net8.0"][0].Id, Is.EqualTo("Widget.Core"));
        Assert.That(result["net9.0"][0].Id, Is.EqualTo("Widget.Core"));
    }

    [Test]
    public async Task Sha512MatchesTheDownloadedBytes()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));

        var result = await Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "1.0.0")), null, default);

        Assert.That(result["net8.0"][0].Sha512, Is.EqualTo(FeedFixture.ExpectedSha512(feed, "Widget.Core", "1.0.0")));
    }

    [Test]
    public void UnknownPackageFails()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));

        var ex = Assert.ThrowsAsync<ResolveException>(
            () => Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Ghost.Package", "1.0.0")), null, default));
        Assert.That(ex!.Message, Does.Contain("Ghost.Package"));
    }

    [Test]
    public void UnsatisfiableRangeFails()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));

        var ex = Assert.ThrowsAsync<ResolveException>(
            () => Resolver.ResolveAsync(Spec(feed, ["net8.0"], ("Widget.Core", "[2.0.0]")), null, default));
        Assert.That(ex!.Message, Does.Contain("Widget.Core"));
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bazel test //tools/nuget_resolver/tests:nuget_resolver_test`
Expected: FAIL — compile error: `The type or namespace name 'Resolver' could not be found`.

- [x] **Step 3: Write the implementation**

Create `tools/nuget_resolver/FeedDependencyProvider.cs`:

```csharp
using NuGet.Common;
using NuGet.Configuration;
using NuGet.DependencyResolver;
using NuGet.Frameworks;
using NuGet.LibraryModel;
using NuGet.Packaging;
using NuGet.Packaging.Core;
using NuGet.Protocol.Core.Types;
using NuGet.Versioning;

namespace NuGetResolver;

/// <summary>
/// Adapts a NuGet.Protocol source repository to the IRemoteDependencyProvider
/// the graph walker resolves through. Mirrors what NuGet.Commands'
/// SourceRepositoryDependencyProvider does, but stays within NuGet.Protocol.
/// </summary>
public sealed class FeedDependencyProvider : IRemoteDependencyProvider
{
    private readonly FindPackageByIdResource _findPackageById;
    private readonly DependencyInfoResource _dependencyInfo;

    public FeedDependencyProvider(SourceRepository repository)
    {
        SourceRepository = repository;
        Source = repository.PackageSource;
        _findPackageById = repository.GetResourceAsync<FindPackageByIdResource>().GetAwaiter().GetResult();
        _dependencyInfo = repository.GetResourceAsync<DependencyInfoResource>().GetAwaiter().GetResult();
    }

    public bool IsHttp =>
        Uri.TryCreate(Source.Source, UriKind.Absolute, out var uri) &&
        (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps);

    public PackageSource Source { get; }

    public SourceRepository SourceRepository { get; }

    public async Task<LibraryIdentity?> FindLibraryAsync(
        LibraryRange libraryRange,
        NuGetFramework targetFramework,
        SourceCacheContext cacheContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var versions = await _findPackageById.GetAllVersionsAsync(
            libraryRange.Name, cacheContext, logger, cancellationToken);
        var best = libraryRange.VersionRange?.FindBestMatch(versions ?? Enumerable.Empty<NuGetVersion>());
        return best == null ? null : new LibraryIdentity(libraryRange.Name, best, LibraryType.Package);
    }

    public async Task<LibraryDependencyInfo> GetDependenciesAsync(
        LibraryIdentity libraryIdentity,
        NuGetFramework targetFramework,
        SourceCacheContext cacheContext,
        ILogger logger,
        CancellationToken cancellationToken)
    {
        var info = await _dependencyInfo.ResolvePackage(
            new PackageIdentity(libraryIdentity.Name, libraryIdentity.Version),
            targetFramework, cacheContext, logger, cancellationToken);
        if (info == null)
        {
            return LibraryDependencyInfo.CreateUnresolved(libraryIdentity, targetFramework);
        }

        var group = NuGetFrameworkUtility.GetNearest(info.DependencyGroups, targetFramework);
        var dependencies = (group?.Packages ?? Enumerable.Empty<PackageDependency>())
            .Select(d => new LibraryDependency
            {
                LibraryRange = new LibraryRange(d.Id, d.VersionRange, LibraryDependencyTarget.Package),
            });
        return LibraryDependencyInfo.Create(libraryIdentity, targetFramework, dependencies);
    }

    public Task<IPackageDownloader> GetPackageDownloaderAsync(
        PackageIdentity packageIdentity,
        SourceCacheContext cacheContext,
        ILogger logger,
        CancellationToken cancellationToken)
        => throw new NotSupportedException(
            "The resolver downloads through FindPackageByIdResource, never through the walker's providers.");

    public async Task<IEnumerable<NuGetVersion>?> GetAllVersionsAsync(
        string id,
        SourceCacheContext cacheContext,
        ILogger logger,
        CancellationToken token)
        => await _findPackageById.GetAllVersionsAsync(id, cacheContext, logger, token);
}
```

Create `tools/nuget_resolver/Netrc.cs`:

```csharp
using System.Net;
using NuGet.Configuration;

namespace NuGetResolver;

/// <summary>
/// Reads per-host credentials from a netrc file and applies them to the
/// package sources the resolver talks to.
/// </summary>
public static class Netrc
{
    private static string? _netrcPath;

    /// <summary>Returns the source with netrc credentials applied, when the netrc covers its host.</summary>
    public static PackageSource ApplyCredentials(string source, string? netrcPath)
    {
        var packageSource = new PackageSource(source);
        if (netrcPath == null)
        {
            return packageSource;
        }

        _netrcPath = netrcPath;
        var credential = CredentialsFor(new Uri(source));
        if (credential != null)
        {
            packageSource.Credentials = new PackageSourceCredential(
                source,
                credential.UserName,
                credential.Password,
                isClearTextPassword: true,
                validAuthenticationTypesText: null);
        }

        return packageSource;
    }

    /// <summary>The credentials the netrc records for the host of url, or null.</summary>
    public static NetworkCredential? CredentialsFor(Uri url)
    {
        if (_netrcPath == null || !File.Exists(_netrcPath))
        {
            return null;
        }

        string? machine = null, login = null, password = null;
        foreach (var rawLine in File.ReadLines(_netrcPath))
        {
            var parts = rawLine.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            for (var i = 0; i + 1 < parts.Length; i += 2)
            {
                switch (parts[i])
                {
                    case "machine":
                        machine = parts[i + 1];
                        break;
                    case "login":
                        login = parts[i + 1];
                        break;
                    case "password":
                        password = parts[i + 1];
                        break;
                }
            }

            if (machine != null &&
                string.Equals(machine, url.Host, StringComparison.OrdinalIgnoreCase) &&
                login != null)
            {
                return new NetworkCredential(login, password ?? string.Empty);
            }
        }

        return null;
    }
}
```

Create `tools/nuget_resolver/Resolver.cs`:

```csharp
using System.Security.Cryptography;
using System.Text.Json;
using NuGet.Common;
using NuGet.Configuration;
using NuGet.DependencyResolver;
using NuGet.Frameworks;
using NuGet.LibraryModel;
using NuGet.Packaging.Core;
using NuGet.Protocol;
using NuGet.Protocol.Core.Types;
using NuGet.RuntimeModel;
using NuGet.Versioning;

namespace NuGetResolver;

/// <summary>
/// Resolves the full transitive graph of a resolve spec, per framework, with
/// the same walker dotnet restore uses.
/// </summary>
public static class Resolver
{
    public static async Task<IReadOnlyDictionary<string, List<ResolvedPackage>>> ResolveAsync(
        ResolveSpec spec,
        string? netrcPath,
        CancellationToken cancellationToken)
    {
        var providers = spec.Sources
            .Select(source => new FeedDependencyProvider(
                Repository.Factory.GetCoreV3(Netrc.ApplyCredentials(source, netrcPath))))
            .ToList();

        var result = new Dictionary<string, List<ResolvedPackage>>(StringComparer.Ordinal);
        foreach (var tfm in spec.Frameworks)
        {
            NuGetFramework framework;
            try
            {
                framework = NuGetFramework.Parse(tfm);
            }
            catch (ArgumentException e)
            {
                throw new ResolveException($"Invalid target framework '{tfm}': {e.Message}");
            }

            result[tfm] = await ResolveFrameworkAsync(spec, framework, providers, cancellationToken);
        }

        return result;
    }

    private static async Task<List<ResolvedPackage>> ResolveFrameworkAsync(
        ResolveSpec spec,
        NuGetFramework framework,
        List<FeedDependencyProvider> providers,
        CancellationToken cancellationToken)
    {
        var cacheContext = new SourceCacheContext();
        var walkContext = new RemoteWalkContext(
            cacheContext,
            PackageSourceMapping.GetPackageSourceMapping(NullSettings.Instance),
            NullLogger.Instance);
        foreach (var provider in providers)
        {
            walkContext.RemoteLibraryProviders.Add(provider);
        }

        var walker = new RemoteDependencyWalker(walkContext);

        // One synthetic root holding every requested package, so version
        // conflicts across the requests are detected exactly like restore does.
        var root = new GraphNode<RemoteResolveResult>(new LibraryRange(
            "nuget_resolver_root",
            new VersionRange(new NuGetVersion(0, 0, 0)),
            LibraryDependencyTarget.Project));
        foreach (var package in spec.Packages)
        {
            VersionRange range;
            try
            {
                range = VersionRange.Parse(package.Range);
            }
            catch (ArgumentException e)
            {
                throw new ResolveException($"Invalid version range '{package.Range}' for {package.Id}: {e.Message}");
            }

            root.InnerNodes.Add(await walker.WalkAsync(
                new LibraryRange(package.Id, range, LibraryDependencyTarget.Package),
                framework,
                runtimeIdentifier: null,
                runtimeGraph: RuntimeGraph.Empty,
                recursive: true));
        }

        // Analyze marks nodes accepted/rejected (nearest-wins) and reports
        // cycles and version conflicts over the whole tree.
        var analysis = root.Analyze();
        if (analysis.Cycles.Count > 0)
        {
            throw new ResolveException(
                "Dependency cycle detected: " +
                string.Join(", ", analysis.Cycles.Select(c => c.Cycle.GetPath())));
        }

        if (analysis.VersionConflicts.Count > 0)
        {
            throw new ResolveException(
                "Version conflict detected: " +
                string.Join(", ", analysis.VersionConflicts.Select(c => c.Conflicting.GetPath())));
        }

        var accepted = new Dictionary<string, GraphNode<RemoteResolveResult>>(StringComparer.OrdinalIgnoreCase);
        var unresolved = new List<string>();
        CollectAccepted(root, accepted, unresolved);
        if (unresolved.Count > 0)
        {
            throw new ResolveException(
                $"Unable to resolve for {framework.GetShortFolderName()}: " + string.Join(", ", unresolved));
        }

        var packages = new List<ResolvedPackage>();
        foreach (var node in accepted.Values)
        {
            packages.Add(await DescribeAsync(node, cacheContext, cancellationToken));
        }

        return packages;
    }

    private static void CollectAccepted(
        GraphNode<RemoteResolveResult> node,
        Dictionary<string, GraphNode<RemoteResolveResult>> accepted,
        List<string> unresolved)
    {
        foreach (var child in node.InnerNodes)
        {
            if (child.Disposition == Disposition.Rejected)
            {
                continue;
            }

            if (child.Item == null)
            {
                unresolved.Add(child.Key.Name);
                continue;
            }

            // On a conflict-free graph each package id has exactly one accepted node.
            accepted[child.Item.Key.Name] = child;
            CollectAccepted(child, accepted, unresolved);
        }
    }

    /// <summary>
    /// Downloads the nupkg of a resolved package, hashes the bytes, verifies
    /// the hash against the feed's registration metadata when the feed
    /// publishes one, and records the download URL.
    /// </summary>
    private static async Task<ResolvedPackage> DescribeAsync(
        GraphNode<RemoteResolveResult> node,
        SourceCacheContext cacheContext,
        CancellationToken cancellationToken)
    {
        var identity = node.Item!.Key;
        var provider = (FeedDependencyProvider)node.Item.Data.Match.Provider!;
        var version = identity.Version.ToNormalizedString();

        string? metadataHash = null;
        var urls = new List<string>();
        if (provider.IsHttp)
        {
            var serviceIndex = await provider.SourceRepository.GetResourceAsync<ServiceIndexResourceV3>(cancellationToken);
            var registrationBases = serviceIndex?.GetServiceEntryUris("RegistrationsBaseUrl/3.6.0") ?? Array.Empty<Uri>();
            if (registrationBases.Count == 0)
            {
                registrationBases = serviceIndex?.GetServiceEntryUris("RegistrationsBaseUrl") ?? Array.Empty<Uri>();
            }

            if (registrationBases.Count > 0)
            {
                var baseAddress = registrationBases[0].AbsoluteUri.TrimEnd('/') + "/";
                var leafUrl = $"{baseAddress}{identity.Id.ToLowerInvariant()}/{version.ToLowerInvariant()}.json";
                var leaf = await GetJsonAsync(leafUrl, cancellationToken);
                if (leaf != null)
                {
                    urls.Add(leaf.RootElement.GetProperty("packageContent").GetString()!);
                    if (leaf.RootElement.TryGetProperty("catalogEntry", out var catalogEntry) &&
                        catalogEntry.ValueKind == JsonValueKind.Object &&
                        catalogEntry.TryGetProperty("packageHash", out var packageHash))
                    {
                        metadataHash = packageHash.GetString();
                    }
                }
            }

            if (urls.Count == 0)
            {
                // A V2 feed (or a V3 feed whose registration leaf did not
                // resolve): the package content lives at a fixed location.
                urls.Add($"{provider.Source.Source.TrimEnd('/')}/package/{identity.Id}/{version}");
            }
        }
        else
        {
            // A local folder feed. Flat (V2) layout: <dir>/<id>.<version>.nupkg.
            var localPath = Path.GetFullPath(
                Path.Combine(provider.Source.Source, $"{identity.Id}.{version}.nupkg"));
            if (!File.Exists(localPath))
            {
                // Hierarchical (V3) layout: <dir>/<id>/<version>/<id>.<version>.nupkg.
                localPath = Path.GetFullPath(Path.Combine(
                    provider.Source.Source,
                    identity.Id.ToLowerInvariant(),
                    version.ToLowerInvariant(),
                    $"{identity.Id.ToLowerInvariant()}.{version.ToLowerInvariant()}.nupkg"));
            }

            urls.Add(new Uri(localPath).AbsoluteUri);
        }

        var findPackageById = await provider.SourceRepository
            .GetResourceAsync<FindPackageByIdResource>(cancellationToken);
        using var stream = new MemoryStream();
        var copied = await findPackageById.CopyNupkgToStreamAsync(
            identity.Id, identity.Version, stream, cacheContext, NullLogger.Instance, cancellationToken);
        if (!copied)
        {
            throw new ResolveException(
                $"Could not download {identity.Id} {version} from {provider.Source.Source}.");
        }

        var sha512 = Convert.ToBase64String(SHA512.HashData(stream.ToArray()));
        if (metadataHash != null && !string.Equals(metadataHash, sha512, StringComparison.Ordinal))
        {
            throw new ResolveException(
                $"Hash mismatch for {identity.Id} {version}: the feed publishes {metadataHash} " +
                $"but the downloaded bytes hash to {sha512}.");
        }

        return new ResolvedPackage(identity.Id, version, "sha512-" + sha512, urls);
    }

    private static async Task<JsonDocument?> GetJsonAsync(string url, CancellationToken cancellationToken)
    {
        try
        {
            var handler = new HttpClientHandler();
            var credentials = Netrc.CredentialsFor(new Uri(url));
            if (credentials != null)
            {
                handler.Credentials = credentials;
            }

            using var http = new HttpClient(handler);
            return JsonDocument.Parse(await http.GetStringAsync(url, cancellationToken));
        }
        catch (Exception e) when (e is HttpRequestException or JsonException or TaskCanceledException)
        {
            // Feeds without registration metadata (or a hiccup reading it)
            // fall back to the constructed URL and the bytes-only hash.
            return null;
        }
    }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `bazel test //tools/nuget_resolver/tests:nuget_resolver_test`
Expected: PASS — alle negen ResolverTests plus de eerdere tests slagen; `//tools/nuget_resolver/tests:nuget_resolver_test PASSED`.

Als de tests falen met `Unable to resolve` óók voor bestaande packages, levert de folder-feed geen `DependencyInfoResource`; de stack trace wijst dan naar `FeedDependencyProvider`. Los dat niet op door de tests af te zwakken — `Repository.Factory.GetCoreV3` op een folder levert wel degelijk dependency-info (dat is hoe restore met folder-sources werkt).

- [x] **Step 5: Commit**

```bash
git add tools/nuget_resolver/FeedDependencyProvider.cs tools/nuget_resolver/Resolver.cs tools/nuget_resolver/Netrc.cs tools/nuget_resolver/tests/FeedFixture.cs tools/nuget_resolver/tests/ResolverTests.cs
git commit -m "Add graph resolution to the NuGet resolver tool"
```

---

### Task 4: Tool — Program.cs CLI met exitcode- en netrc-tests (TDD)

Het entrypoint: argumentenparsen, de resolver aanroepen, het lockbestand schrijven, niet-nul exitcodes met de foutmelding op stderr.

**Files:**
- Create: `tools/nuget_resolver/Program.cs`
- Test: `tools/nuget_resolver/tests/ProgramTests.cs`
- Test: `tools/nuget_resolver/tests/NetrcTests.cs`

- [x] **Step 1: Write the failing tests**

Create `tools/nuget_resolver/tests/ProgramTests.cs`:

```csharp
using System.Text.Json;
using NUnit.Framework;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class ProgramTests
{
    private static string WriteSpec(string dir, string feed, params (string Id, string Range)[] packages)
    {
        var specPath = Path.Combine(dir, "spec.json");
        File.WriteAllText(specPath, JsonSerializer.Serialize(new
        {
            packages = packages.ToDictionary(p => p.Id, p => p.Range),
            frameworks = new[] { "net8.0" },
            sources = new[] { feed },
        }));
        return specPath;
    }

    [Test]
    public async Task ResolvesAndStampsTheInputHash()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));
        var specPath = WriteSpec(feed, feed, ("Widget.Core", "1.0.0"));
        var output = Path.Combine(feed, "nuget_resolve.json");

        var stderr = new StringWriter();
        var code = await NuGetResolver.Program.RunAsync(
            new[] { "--spec", specPath, "--input-hash", "737269301", "--output", output },
            new StringWriter(), stderr);

        Assert.That(code, Is.EqualTo(0), stderr.ToString());
        using var doc = JsonDocument.Parse(File.ReadAllText(output));
        Assert.That(doc.RootElement.GetProperty("version").GetInt32(), Is.EqualTo(1));
        Assert.That(doc.RootElement.GetProperty("inputHash").GetString(), Is.EqualTo("737269301"));
        var packages = doc.RootElement.GetProperty("frameworks").GetProperty("net8.0").GetProperty("packages");
        Assert.That(packages.GetArrayLength(), Is.EqualTo(1));
        Assert.That(packages[0].GetProperty("id").GetString(), Is.EqualTo("Widget.Core"));
        Assert.That(
            packages[0].GetProperty("sha512").GetString(),
            Is.EqualTo(FeedFixture.ExpectedSha512(feed, "Widget.Core", "1.0.0")));
        Assert.That(packages[0].GetProperty("urls")[0].GetString(), Does.StartWith("file://"));
    }

    [Test]
    public async Task UnknownPackageExitsNonZeroWithMessageOnStderr()
    {
        var feed = FeedFixture.Create(("Widget.Core", "1.0.0", []));
        var specPath = WriteSpec(feed, feed, ("Ghost.Package", "1.0.0"));

        var stderr = new StringWriter();
        var code = await NuGetResolver.Program.RunAsync(
            new[] { "--spec", specPath, "--input-hash", "0", "--output", Path.Combine(feed, "out.json") },
            new StringWriter(), stderr);

        Assert.That(code, Is.Not.EqualTo(0));
        Assert.That(stderr.ToString(), Does.Contain("Ghost.Package"));
    }

    [Test]
    public async Task MissingArgumentsExitNonZero()
    {
        var code = await NuGetResolver.Program.RunAsync(Array.Empty<string>(), new StringWriter(), new StringWriter());
        Assert.That(code, Is.Not.EqualTo(0));
    }
}
```

Create `tools/nuget_resolver/tests/NetrcTests.cs`:

```csharp
using NUnit.Framework;
using NuGetResolver;

namespace NuGetResolver.Tests;

[TestFixture]
public sealed class NetrcTests
{
    [Test]
    public void CredentialsMatchTheHostCaseInsensitively()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "netrc");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "machine pkgs.example.com\nlogin build\npassword s3cret\n");

        var source = Netrc.ApplyCredentials("https://PKGS.example.com/v3/index.json", path);

        Assert.That(source.Credentials, Is.Not.Null);
        Assert.That(source.Credentials!.Username, Is.EqualTo("build"));
        Assert.That(source.Credentials.Password, Is.EqualTo("s3cret"));
    }

    [Test]
    public void UnknownHostGetsNoCredentials()
    {
        var path = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"), "netrc");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "machine pkgs.example.com\nlogin build\npassword s3cret\n");

        var source = Netrc.ApplyCredentials("https://other.example.com/v3/index.json", path);

        Assert.That(source.Credentials, Is.Null);
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bazel test //tools/nuget_resolver/tests:nuget_resolver_test`
Expected: FAIL — compile error: `The type or namespace name 'Program' does not exist in the namespace 'NuGetResolver'`.

- [x] **Step 3: Write the implementation**

Create `tools/nuget_resolver/Program.cs`:

```csharp
namespace NuGetResolver;

public static class Program
{
    /// <summary>Split out from Main so tests can drive it with in-memory streams.</summary>
    public static async Task<int> RunAsync(string[] args, TextWriter stdout, TextWriter stderr)
    {
        string? specPath = null, inputHash = null, output = null, netrc = null;
        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--spec" when i + 1 < args.Length:
                    specPath = args[++i];
                    break;
                case "--input-hash" when i + 1 < args.Length:
                    inputHash = args[++i];
                    break;
                case "--output" when i + 1 < args.Length:
                    output = args[++i];
                    break;
                case "--netrc" when i + 1 < args.Length:
                    netrc = args[++i];
                    break;
                default:
                    await stderr.WriteLineAsync($"Unknown or incomplete argument: {args[i]}");
                    return 2;
            }
        }

        if (specPath == null || inputHash == null || output == null)
        {
            await stderr.WriteLineAsync(
                "Usage: NuGetResolver --spec <spec.json> --input-hash <hash> --output <nuget_resolve.json> [--netrc <path>]");
            return 2;
        }

        try
        {
            var spec = ResolveSpec.Load(specPath);
            var resolved = await Resolver.ResolveAsync(spec, netrc, CancellationToken.None);
            File.WriteAllText(output, LockFile.Render(inputHash, resolved));
            await stdout.WriteLineAsync(
                $"Resolved {spec.Packages.Count} package(s) for {spec.Frameworks.Count} framework(s) into {output}.");
            return 0;
        }
        catch (ResolveException e)
        {
            await stderr.WriteLineAsync(e.Message);
            return 1;
        }
        catch (Exception e)
        {
            // Feed/auth failures surface their NuGet message verbatim.
            await stderr.WriteLineAsync(e.ToString());
            return 1;
        }
    }

    public static int Main(string[] args)
        => RunAsync(args, Console.Out, Console.Error).GetAwaiter().GetResult();
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `bazel test //tools/nuget_resolver/tests:nuget_resolver_test`
Expected: PASS — `//tools/nuget_resolver/tests:nuget_resolver_test PASSED`.

- [x] **Step 5: Sanity-check the csproj (de offline-publish volgt in Task 12)**

De csproj wordt pas in Task 12 echt offline gepubliceerd; controleer hier alvast dat hij met netwerk herstelt en compileert (de pins voor de offline variant volgen in Task 8):

Run: `cd tools/nuget_resolver && dotnet restore NuGetResolver.csproj && dotnet build NuGetResolver.csproj -c Release --no-restore -v:minimal`
Expected: `Build succeeded.` en `0 Error(s)`. Verwijder daarna de gegenereerde artefacten: `rm -rf obj bin`.

- [x] **Step 6: Commit**

```bash
git add tools/nuget_resolver/Program.cs tools/nuget_resolver/tests/ProgramTests.cs tools/nuget_resolver/tests/NetrcTests.cs
git commit -m "Add the resolver tool entrypoint"
```

---

### Task 5: Starlark — input_hash.bzl met tests (TDD)

**Files:**
- Create: `dotnet/private/nuget_resolve/input_hash.bzl`
- Create: `dotnet/private/nuget_resolve/BUILD.bazel`
- Test: `dotnet/private/tests/nuget_resolve/input_hash_test.bzl`
- Test: `dotnet/private/tests/nuget_resolve/BUILD.bazel`

- [x] **Step 1: Write the failing test**

Create `dotnet/private/tests/nuget_resolve/input_hash_test.bzl`:

```python
"""Tests for the nuget.resolve input hash."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/nuget_resolve:input_hash.bzl",
    "classify_input_hash",
    "compute_input_hash",
)

_PACKAGES = {"Newtonsoft.Json": "13.0.3", "Serilog": "4.0.*"}
_FRAMEWORKS = ["net10.0", "net8.0"]
_SOURCES = ["https://api.nuget.org/v3/index.json", "https://pkgs.example.com/v3/index.json"]

def _stable_test_impl(ctx):
    env = unittest.begin(ctx)

    first = compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES)
    second = compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES)

    asserts.equals(env, first, second, "the same inputs hash the same")
    asserts.true(env, first.isdigit(), "the hash is a decimal string: %s" % first)

    return unittest.end(env)

_stable_test = unittest.make(_stable_test_impl)

def _canonicalization_test_impl(ctx):
    env = unittest.begin(ctx)

    canonical = compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES)

    asserts.equals(
        env,
        canonical,
        compute_input_hash({"Serilog": "4.0.*", "Newtonsoft.Json": "13.0.3"}, _FRAMEWORKS, _SOURCES),
        "package dict order does not matter",
    )
    asserts.equals(
        env,
        canonical,
        compute_input_hash(_PACKAGES, ["net8.0", "net10.0"], _SOURCES),
        "framework order does not matter",
    )

    return unittest.end(env)

_canonicalization_test = unittest.make(_canonicalization_test_impl)

def _sensitivity_test_impl(ctx):
    env = unittest.begin(ctx)

    canonical = compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES)

    asserts.false(
        env,
        canonical == compute_input_hash(
            {"Newtonsoft.Json": "13.0.3", "Serilog": "4.0.0"},
            _FRAMEWORKS,
            _SOURCES,
        ),
        "a changed version range changes the hash",
    )
    asserts.false(
        env,
        canonical == compute_input_hash(_PACKAGES, ["net10.0"], _SOURCES),
        "a removed framework changes the hash",
    )
    asserts.false(
        env,
        canonical == compute_input_hash(
            _PACKAGES,
            _FRAMEWORKS,
            ["https://pkgs.example.com/v3/index.json", "https://api.nuget.org/v3/index.json"],
        ),
        "source order matters (lookup order is semantically significant)",
    )
    asserts.false(
        env,
        canonical == compute_input_hash(_PACKAGES, _FRAMEWORKS, _SOURCES[:1]),
        "a removed source changes the hash",
    )

    return unittest.end(env)

_sensitivity_test = unittest.make(_sensitivity_test_impl)

def _classify_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, "current", classify_input_hash("123", "123"))
    asserts.equals(env, "mismatch", classify_input_hash("123", "456"))
    asserts.equals(
        env,
        "legacy",
        classify_input_hash("999", "456", legacy = ["999"]),
        "a hash from a superseded algorithm is recognised",
    )

    return unittest.end(env)

_classify_test = unittest.make(_classify_test_impl)

def input_hash_test_suite(name):
    unittest.suite(
        name,
        _stable_test,
        _canonicalization_test,
        _sensitivity_test,
        _classify_test,
    )
```

Create `dotnet/private/tests/nuget_resolve/BUILD.bazel`:

```python
load(":input_hash_test.bzl", "input_hash_test_suite")

input_hash_test_suite(name = "input_hash_test")
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bazel test //dotnet/private/tests/nuget_resolve:input_hash_test`
Expected: FAIL — `no such package 'dotnet/private/nuget_resolve'`.

- [x] **Step 3: Write the implementation**

Create `dotnet/private/nuget_resolve/input_hash.bzl`:

```python
"""The canonical input hash of a `nuget.resolve` tag.

The hash is computed in Starlark — never in the resolver tool — so the
unpinned and pinned sides are guaranteed to agree (the pattern of
`compute_dependency_inputs_signature` in rules_jvm_external). It is a
staleness detector, not a security boundary: integrity comes from the
per-package sha512 in the lock file.
"""

# Hashes produced by superseded algorithms. A lock file stamped with one of
# these warns ("run repin") instead of failing, the same trade-off
# rules_jvm_external makes with `old_hashes`. Empty: the current algorithm is
# the first.
LEGACY_INPUT_HASHES = []

def compute_input_hash(packages, frameworks, sources):
    """Returns the canonical hash of the tag inputs as a decimal string.

    Args:
      packages: The `packages` dict of the tag (package id to version range).
      frameworks: The `frameworks` list of the tag.
      sources: The `sources` list of the tag, in lookup order.

    Returns:
      `hash()` over a canonical JSON encoding, as a decimal string.
    """
    canonical = json.encode({
        "frameworks": sorted(frameworks),
        "packages": {id: packages[id] for id in sorted(packages)},
        "sources": sources,
    })
    # Starlark hash() is signed; mask to non-negative so the stamped value is
    # always a decimal string of digits.
    return str(hash(canonical) & 0x7fffffff)

def classify_input_hash(lock_hash, computed_hash, legacy = LEGACY_INPUT_HASHES):
    """Compares the hash in the lock file with the freshly computed one.

    Args:
      lock_hash: The `inputHash` recorded in the lock file.
      computed_hash: The hash of the current tag inputs.
      legacy: Hashes produced by superseded algorithms.

    Returns:
      "current" when they match, "legacy" when the lock file carries a
      superseded algorithm, "mismatch" otherwise.
    """
    if lock_hash == computed_hash:
        return "current"
    if lock_hash in legacy:
        return "legacy"
    return "mismatch"
```

Create `dotnet/private/nuget_resolve/BUILD.bazel`:

```python
load("@bazel_lib//:bzl_library.bzl", "bzl_library")

bzl_library(
    name = "input_hash",
    srcs = ["input_hash.bzl"],
    visibility = ["//dotnet:__subpackages__"],
)
```

- [x] **Step 4: Run the test to verify it passes**

Run: `bazel test //dotnet/private/tests/nuget_resolve:input_hash_test`
Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add dotnet/private/nuget_resolve/input_hash.bzl dotnet/private/nuget_resolve/BUILD.bazel dotnet/private/tests/nuget_resolve/input_hash_test.bzl dotnet/private/tests/nuget_resolve/BUILD.bazel
git commit -m "Add the nuget.resolve input hash"
```

---

### Task 6: Starlark — lock.bzl (parser en validator) met tests (TDD)

**Files:**
- Create: `dotnet/private/nuget_resolve/lock.bzl`
- Modify: `dotnet/private/nuget_resolve/BUILD.bazel`
- Test: `dotnet/private/tests/nuget_resolve/lock_test.bzl`
- Modify: `dotnet/private/tests/nuget_resolve/BUILD.bazel`

- [x] **Step 1: Write the failing test**

Create `dotnet/private/tests/nuget_resolve/lock_test.bzl`:

```python
"""Tests for the nuget_resolve.json parser and validator."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//dotnet/private/nuget_resolve:lock.bzl", "parse_lock", "validate_lock")

_LOCK = """\
{
  "version": 1,
  "inputHash": "737269301",
  "frameworks": {
    "net10.0": {
      "packages": [
        {
          "id": "Newtonsoft.Json",
          "version": "13.0.3",
          "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
          "urls": [
            "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg"
          ]
        },
        {
          "id": "Serilog",
          "version": "4.0.0",
          "sha512": "sha512-AAAA",
          "urls": ["https://feed/serilog.4.0.0.nupkg"]
        }
      ]
    },
    "net8.0": {
      "packages": [
        {
          "id": "Newtonsoft.Json",
          "version": "13.0.3",
          "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
          "urls": ["https://feed/newtonsoft.json.13.0.3.nupkg"]
        }
      ]
    }
  }
}
"""

def _parse_lock_test_impl(ctx):
    env = unittest.begin(ctx)

    lock = parse_lock(_LOCK, "nuget_resolve.json")

    asserts.equals(env, "737269301", lock.input_hash)
    asserts.equals(env, ["net10.0", "net8.0"], lock.frameworks.keys(), "insertion order is preserved")
    packages = lock.frameworks["net10.0"]
    asserts.equals(env, ["Newtonsoft.Json", "Serilog"], [p.id for p in packages])
    asserts.equals(env, "13.0.3", packages[0].version)
    asserts.equals(
        env,
        "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
        packages[0].sha512,
    )
    asserts.equals(
        env,
        ["https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg"],
        packages[0].urls,
    )

    return unittest.end(env)

_parse_lock_test = unittest.make(_parse_lock_test_impl)

def _validate_test_impl(ctx):
    env = unittest.begin(ctx)

    asserts.equals(env, [], validate_lock(_LOCK), "the valid lock file has no problems")

    errors = validate_lock('{"version": 2, "inputHash": "1", "frameworks": {"net10.0": {"packages": []}}}')
    asserts.true(env, len(errors) == 1, "one error for the unknown version: %s" % errors)
    asserts.true(env, errors[0].find("version") != -1, "the error names the version field: %s" % errors[0])
    asserts.true(env, errors[0].find("REPIN") != -1, "the error points at repinning: %s" % errors[0])

    errors = validate_lock('{"version": 1, "frameworks": {"net10.0": {"packages": []}}}')
    asserts.true(env, len(errors) == 1, "one error for the missing inputHash: %s" % errors)
    asserts.true(env, errors[0].find("inputHash") != -1, "the error names inputHash: %s" % errors[0])

    errors = validate_lock('{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [{"id": "A", "version": "1.0.0"}]}}}')
    asserts.true(env, len(errors) == 2, "missing sha512 and urls are both reported: %s" % errors)

    errors = validate_lock('{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [{"id": "A", "version": "1.0.0", "sha512": "md5-AAAA", "urls": []}]}}}')
    asserts.true(env, len(errors) == 2, "a non-SRI sha512 and empty urls are both reported: %s" % errors)

    errors = validate_lock('{"version": 1, "inputHash": "1"}')
    asserts.true(env, len(errors) == 1, "one error for the missing frameworks map: %s" % errors)

    return unittest.end(env)

_validate_test = unittest.make(_validate_test_impl)

def lock_test_suite(name):
    unittest.suite(
        name,
        _parse_lock_test,
        _validate_test,
    )
```

Modify `dotnet/private/tests/nuget_resolve/BUILD.bazel`. Old:

```python
load(":input_hash_test.bzl", "input_hash_test_suite")

input_hash_test_suite(name = "input_hash_test")
```

New:

```python
load(":input_hash_test.bzl", "input_hash_test_suite")
load(":lock_test.bzl", "lock_test_suite")

input_hash_test_suite(name = "input_hash_test")

lock_test_suite(name = "lock_test")
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bazel test //dotnet/private/tests/nuget_resolve:lock_test`
Expected: FAIL — `cannot load '//dotnet/private/nuget_resolve:lock.bzl'`.

- [x] **Step 3: Write the implementation**

Create `dotnet/private/nuget_resolve/lock.bzl`:

```python
"""Parser and validator for `nuget_resolve.json` lock files."""

_FORMAT_VERSION = 1

_REPIN_HINT = "Do not edit nuget_resolve.json by hand; regenerate it with `REPIN=1 bazel run @<name>.<tfm>//:pin`."

def _error(path, message):
    return "%s: %s %s" % (path, message, _REPIN_HINT)

def validate_lock(content, path = "nuget_resolve.json"):
    """Validates lock file contents without failing.

    Args:
      content: The file contents. Must be valid JSON — malformed JSON fails in
        json.decode before validation runs.
      path: The path reported in error messages.

    Returns:
      A list of problems; empty when the file is valid.
    """
    lock = json.decode(content)
    if type(lock) != "dict":
        return [_error(path, "expected a JSON object at the top level.")]

    errors = []

    version = lock.get("version")
    if version != _FORMAT_VERSION:
        errors.append(_error(path, "unsupported version %s; this rules_dotnet version reads version %d." % (
            json.encode(version),
            _FORMAT_VERSION,
        )))

    if type(lock.get("inputHash")) != "string":
        errors.append(_error(path, "missing or invalid \"inputHash\" (a decimal string)."))

    frameworks = lock.get("frameworks")
    if type(frameworks) != "dict" or len(frameworks) == 0:
        errors.append(_error(path, "missing or empty \"frameworks\" map."))
    else:
        for (tfm, group) in frameworks.items():
            packages = group.get("packages") if type(group) == "dict" else None
            if type(packages) != "list":
                errors.append(_error(path, "framework \"%s\" has no \"packages\" list." % tfm))
                continue
            for package in packages:
                if type(package) != "dict":
                    errors.append(_error(path, "framework \"%s\" has a non-object package entry." % tfm))
                    continue
                for field in ("id", "version", "sha512", "urls"):
                    if field not in package:
                        errors.append(_error(path, "package %s in framework \"%s\" has no \"%s\"." % (
                            package.get("id", "<unknown>"),
                            tfm,
                            field,
                        )))
                if "sha512" in package and not str(package["sha512"]).startswith("sha512-"):
                    errors.append(_error(path, "package %s in framework \"%s\" has a sha512 that is not an SRI string (\"sha512-<base64>\")." % (
                        package.get("id", "<unknown>"),
                        tfm,
                    )))
                if "urls" in package and (type(package["urls"]) != "list" or len(package["urls"]) == 0):
                    errors.append(_error(path, "package %s in framework \"%s\" has no download urls." % (
                        package.get("id", "<unknown>"),
                        tfm,
                    )))

    return errors

def parse_lock(content, path = "nuget_resolve.json"):
    """Parses and validates a `nuget_resolve.json` file.

    Args:
      content: The file contents.
      path: The path reported in error messages.

    Returns:
      A struct with `input_hash` (string) and `frameworks` (a dict of TFM to a
      list of structs with `id`, `version`, `sha512` and `urls` fields, in
      file order).
    """
    errors = validate_lock(content, path)
    if errors:
        fail("\n".join(errors))

    lock = json.decode(content)
    frameworks = {}
    for (tfm, group) in lock["frameworks"].items():
        frameworks[tfm] = [
            struct(
                id = package["id"],
                version = package["version"],
                sha512 = package["sha512"],
                urls = package["urls"],
            )
            for package in group["packages"]
        ]

    return struct(input_hash = lock["inputHash"], frameworks = frameworks)
```

Modify `dotnet/private/nuget_resolve/BUILD.bazel`. Old:

```python
bzl_library(
    name = "input_hash",
    srcs = ["input_hash.bzl"],
    visibility = ["//dotnet:__subpackages__"],
)
```

New:

```python
bzl_library(
    name = "input_hash",
    srcs = ["input_hash.bzl"],
    visibility = ["//dotnet:__subpackages__"],
)

bzl_library(
    name = "lock",
    srcs = ["lock.bzl"],
    visibility = ["//dotnet:__subpackages__"],
)
```

- [x] **Step 4: Run the test to verify it passes**

Run: `bazel test //dotnet/private/tests/nuget_resolve/...`
Expected: PASS — `input_hash_test` en `lock_test` slagen.

- [x] **Step 5: Commit**

```bash
git add dotnet/private/nuget_resolve/lock.bzl dotnet/private/nuget_resolve/BUILD.bazel dotnet/private/tests/nuget_resolve/lock_test.bzl dotnet/private/tests/nuget_resolve/BUILD.bazel
git commit -m "Add the nuget_resolve.json parser and validator"
```

---

### Task 7: Refactor nuget_archive.bzl (`urls`-attribuut + `fetch_package_into`) en nuget_repo.bzl (`write_hub_files`)

Twee hergebruik-ingrepen, beide gedekt door bestaande tests (gedrag mag niet veranderen):

1. `nuget_archive` krijgt een optioneel attribuut `urls`: als het gezet is, wordt de feed-index-URL-afleiding overgeslagen en dient `sources` alleen nog voor auth. De download/extractie-logica wordt een publieke functie `fetch_package_into` met een `prefix`-parameter, zodat de ongepinde hub hem per package in zijn eigen repository kan aanroepen.
2. De hub-BUILD-generatie in `nuget_repo.bzl` wordt een publieke functie `write_hub_files` met een `archive_and_info`-functor, zodat zowel de spoke-hub (archieven als `@<spoke>//`-labels) als de ongepinde monolithische hub (archieven als `//<id>/<version>`-labels in de eigen repo) hem gebruiken.

**Files:**
- Modify: `dotnet/private/rules/nuget/nuget_archive.bzl`
- Modify: `dotnet/private/rules/nuget/nuget_repo.bzl`

- [x] **Step 1: Modify nuget_archive.bzl**

In `dotnet/private/rules/nuget/nuget_archive.bzl`, vervang `_nuget_archive_impl`. Old:

```python
def _nuget_archive_impl(ctx):
    # First get the auth dict for the package sources since the sources can be different than the
    # package base url when using NuGet V3 feeds.
    auth = _get_auth_dict(ctx, ctx.attr.sources)
    urls = _get_package_urls(ctx, ctx.attr.sources, auth, ctx.attr.id, ctx.attr.version)

    # Then get the auth dict for the package base urls
    auth = _get_auth_dict(ctx, urls)

    # We download it as .zip because ctx.extract reads the file extension to determine the archive type
    file_name = "%s.zip" % ctx.name
    nupkg_name = "%s.%s.nupkg" % (ctx.attr.id, ctx.attr.version)

    ctx.download(urls, output = file_name, integrity = ctx.attr.sha512, auth = auth)
    ctx.extract(archive = file_name)
    ctx.symlink(file_name, nupkg_name)

    all_files = sorted(_read_dir(ctx, ".").replace(str(ctx.path(".")) + "/", "").splitlines())

    _write_repository(ctx, ctx.attr.id, nupkg_name, all_files)
```

New:

```python
def fetch_package_into(ctx, id, version, urls, integrity, prefix):
    """Downloads a .nupkg and extracts it under `prefix` in the repository.

    Args:
      ctx: The repository context. When it has a `netrc` attribute it is used
        for authentication, otherwise the user's netrc.
      id: The package id.
      version: The normalized package version.
      urls: The download URLs of the `.nupkg`, tried in order.
      integrity: The expected sha512 as an SRI string, or "" to skip the check.
      prefix: The directory to extract into, relative to the repository root,
        with a trailing slash; "" for the root itself.

    Returns:
      A struct with `nupkg` (the name of the `.nupkg` inside `prefix`) and
      `files` (every extracted path, relative to `prefix`, sorted).
    """
    auth = _get_auth_dict(ctx, urls)

    # We download it as .zip because ctx.extract reads the file extension to determine the archive type
    file_name = "%s.%s.zip" % (id, version)
    # The nupkg name must be the lowercased id: the hub's nuget_package targets
    # address it as `<library_name.lower()>.<version>.nupkg` (package.bzl), and
    # the unpinned hub calls this with the lock file's original-casing id.
    nupkg_name = "%s.%s.nupkg" % (id.lower(), version)

    ctx.download(urls, output = prefix + file_name, integrity = integrity, auth = auth)
    ctx.extract(archive = prefix + file_name, output = prefix)
    ctx.symlink(prefix + file_name, prefix + nupkg_name)

    base = str(ctx.path(prefix if prefix else ".")) + "/"
    all_files = sorted(_read_dir(ctx, prefix if prefix else ".").replace(base, "").splitlines())

    return struct(nupkg = nupkg_name, files = all_files)

def _nuget_archive_impl(ctx):
    if ctx.attr.urls:
        # The urls are recorded in the lock file; no feed index download is
        # needed to derive them. `sources` still feeds auth resolution.
        urls = ctx.attr.urls
    else:
        # First get the auth dict for the package sources since the sources can be different than the
        # package base url when using NuGet V3 feeds.
        auth = _get_auth_dict(ctx, ctx.attr.sources)
        urls = _get_package_urls(ctx, ctx.attr.sources, auth, ctx.attr.id, ctx.attr.version)

    package = fetch_package_into(ctx, ctx.attr.id, ctx.attr.version, urls, ctx.attr.sha512, "")

    _write_repository(ctx, ctx.attr.id, package.nupkg, package.files)
```

NB: de oude code noemde de zip `%s.zip % ctx.name`; de nieuwe `%s.%s.zip % (id, version)`. De zip-naam is puur intern (hij komt wel in de `files`-filegroup terecht, maar niemand adresseert hem als label).

Voeg het attribuut toe. Old:

```python
nuget_archive = repository_rule(
    _nuget_archive_impl,
    attrs = {
        "sources": attr.string_list(),
        "netrc": attr.label(),
        "id": attr.string(),
        "version": attr.string(),
        "sha512": attr.string(),
    },
)
```

New:

```python
nuget_archive = repository_rule(
    _nuget_archive_impl,
    attrs = {
        "sources": attr.string_list(),
        "netrc": attr.label(),
        "id": attr.string(),
        "version": attr.string(),
        "sha512": attr.string(),
        "urls": attr.string_list(
            doc = "The download URLs of the .nupkg, e.g. recorded in a lock file. When set, no feed index is downloaded to derive URLs; `sources` then only feeds authentication.",
        ),
    },
)
```

- [x] **Step 2: Modify nuget_repo.bzl**

In `dotnet/private/rules/nuget/nuget_repo.bzl`, parametiseer de templates. Old (`_PACKAGE_TEMPLATE`, `_ALIAS_TEMPLATE` en `_TOOLS_TEMPLATE`):

```python
_PACKAGE_TEMPLATE = """\
"GENERATED"

load("@rules_dotnet//dotnet/private/rules/nuget:package.bzl", "nuget_package")
load(
    "@{archive}//:package_info.bzl",
    "DEPENDENCY_GROUPS",
    "FRAMEWORK_LIST",
    "TARGETING_PACK_OVERRIDES",
    "TOOLS",
)
load("//:packages.bzl", "PACKAGES")

package(default_visibility = ["//visibility:public"])

nuget_package(
    version = "{version}",
    library_name = "{library_name}",
    archive = "@{archive}//",
    packages = PACKAGES,
    sha512 = "{sha512}",
    dependency_groups = DEPENDENCY_GROUPS,
    framework_list = FRAMEWORK_LIST,
    targeting_pack_overrides = TARGETING_PACK_OVERRIDES,
    tools = TOOLS,
)
"""

_ALIAS_TEMPLATE = """\
"GENERATED"

package(default_visibility = ["//visibility:public"])

alias(name = "{name}", actual = "{package}")

alias(name = "content_files", actual = "@{archive}//:content_files")

alias(name = "files", actual = "@{archive}//:files")
"""

_TOOLS_TEMPLATE = """\
"GENERATED"

load("@rules_dotnet//dotnet/private/rules/nuget:package.bzl", "nuget_package_tools")
load("@{archive}//:package_info.bzl", "TOOLS")

package(default_visibility = ["//visibility:public"])

nuget_package_tools(
    package = "{package}",
    tools = TOOLS,
)
"""
```

New:

```python
_PACKAGE_TEMPLATE = """\
"GENERATED"

load("@rules_dotnet//dotnet/private/rules/nuget:package.bzl", "nuget_package")
load(
    "{package_info}",
    "DEPENDENCY_GROUPS",
    "FRAMEWORK_LIST",
    "TARGETING_PACK_OVERRIDES",
    "TOOLS",
)
load("//:packages.bzl", "PACKAGES")

package(default_visibility = ["//visibility:public"])

nuget_package(
    version = "{version}",
    library_name = "{library_name}",
    archive = "{archive}",
    packages = PACKAGES,
    sha512 = "{sha512}",
    dependency_groups = DEPENDENCY_GROUPS,
    framework_list = FRAMEWORK_LIST,
    targeting_pack_overrides = TARGETING_PACK_OVERRIDES,
    tools = TOOLS,
)
"""

_ALIAS_TEMPLATE = """\
"GENERATED"

package(default_visibility = ["//visibility:public"])

alias(name = "{name}", actual = "{package}")

alias(name = "content_files", actual = "{archive}:content_files")

alias(name = "files", actual = "{archive}:files")
"""

_TOOLS_TEMPLATE = """\
"GENERATED"

load("@rules_dotnet//dotnet/private/rules/nuget:package.bzl", "nuget_package_tools")
load("{package_info}", "TOOLS")

package(default_visibility = ["//visibility:public"])

nuget_package_tools(
    package = "{package}",
    tools = TOOLS,
)
"""
```

Vervang vervolgens `_nuget_repo_impl`. Old:

```python
def _nuget_repo_impl(ctx):
    packages = [json.decode(package) for package in ctx.attr.packages]

    for (path, content) in ctx.attr.extra_build_files.items():
        ctx.file(path, content)

    ctx.file("BUILD.bazel", """\
"GENERATED"

package(default_visibility = ["//visibility:public"])
""")

    # A dependency group resolves one version per id, so `name` is just the id.
    # The SDK's pack repositories hold several versions of an id and tell them
    # apart with `<id>.v<version>`; there a dependency edge naming that id is
    # ambiguous, so it resolves to nothing rather than to an arbitrary version.
    names = {}
    for package in packages:
        id = package["id"].lower()
        names[id] = None if id in names else package["name"].lower()

    ctx.file("packages.bzl", _PACKAGES_TEMPLATE.format(
        packages = json.encode({id: name for (id, name) in names.items() if name}),
    ))

    for package in packages:
        id = package["id"].lower()
        name = package["name"].lower()
        version = package["version"]
        archive = nuget_archive_name(package["id"], version)

        ctx.file("{}/{}/BUILD.bazel".format(id, version), _PACKAGE_TEMPLATE.format(
            archive = archive,
            library_name = package["id"],
            sha512 = package.get("sha512", ""),
            version = version,
        ))

        ctx.file("{}/BUILD.bazel".format(name), _ALIAS_TEMPLATE.format(
            archive = archive,
            name = name,
            package = nuget_package_label(id, version),
        ))

        ctx.file("{}/tools/BUILD.bazel".format(name), _TOOLS_TEMPLATE.format(
            archive = archive,
            package = nuget_package_label(id, version),
        ))
```

New:

```python
def _spoke_archive(id, version):
    """The archive of a package version as its own `nuget_archive` repository."""
    archive = "@{}//".format(nuget_archive_name(id, version))
    return struct(archive = archive, package_info = archive + ":package_info.bzl")

def write_hub_files(ctx, packages, archive_and_info, extra_build_files = {}, extra_root_build = ""):
    """Writes the hub repository files for one dependency group.

    Used by every hub-shaped repository rule: the classic `_nuget_repo` and
    the pinned hub (archives as cross-repository `@<spoke>//` labels) and the
    unpinned monolithic hub (archives extracted into the hub repository
    itself, addressed as `//<id>/<version>`).

    Args:
      ctx: The repository context.
      packages: Dicts with `id`, `version` and optionally `name` and `sha512`
        keys. `name` is the label the package is addressed by and defaults to
        its id.
      archive_and_info: A function `(id, version) -> struct(archive,
        package_info)`, where `archive` is the label prefix of the package's
        archive (`"@<spoke>//"` or `"//<id>/<version>"`) and `package_info`
        the label the generated package BUILD loads `package_info.bzl` from.
      extra_build_files: Additional BUILD files to write into the repository,
        keyed by path.
      extra_root_build: Extra content appended to the root BUILD.bazel (the
        `:pin` alias).
    """
    for (path, content) in extra_build_files.items():
        ctx.file(path, content)

    ctx.file("BUILD.bazel", """\
"GENERATED"

package(default_visibility = ["//visibility:public"])
""" + extra_root_build)

    # A dependency group resolves one version per id, so `name` is just the id.
    # The SDK's pack repositories hold several versions of an id and tell them
    # apart with `<id>.v<version>`; there a dependency edge naming that id is
    # ambiguous, so it resolves to nothing rather than to an arbitrary version.
    names = {}
    for package in packages:
        id = package["id"].lower()
        names[id] = None if id in names else package.get("name", package["id"]).lower()

    ctx.file("packages.bzl", _PACKAGES_TEMPLATE.format(
        packages = json.encode({id: name for (id, name) in names.items() if name}),
    ))

    for package in packages:
        id = package["id"].lower()
        name = package.get("name", package["id"]).lower()
        version = package["version"]
        archive = archive_and_info(package["id"], version)

        ctx.file("{}/{}/BUILD.bazel".format(id, version), _PACKAGE_TEMPLATE.format(
            archive = archive.archive,
            package_info = archive.package_info,
            library_name = package["id"],
            sha512 = package.get("sha512", ""),
            version = version,
        ))

        ctx.file("{}/BUILD.bazel".format(name), _ALIAS_TEMPLATE.format(
            archive = archive.archive,
            name = name,
            package = nuget_package_label(id, version),
        ))

        ctx.file("{}/tools/BUILD.bazel".format(name), _TOOLS_TEMPLATE.format(
            package_info = archive.package_info,
            package = nuget_package_label(id, version),
        ))

def _nuget_repo_impl(ctx):
    packages = [json.decode(package) for package in ctx.attr.packages]

    write_hub_files(
        ctx,
        packages,
        _spoke_archive,
        extra_build_files = ctx.attr.extra_build_files,
    )
```

Pas tenslotte `nuget_archives` aan om `urls` door te geven. Old:

```python
        declared[name] = True
        nuget_archive(
            name = name,
            id = package["id"].lower(),
            netrc = package.get("netrc", None),
            sha512 = package.get("sha512", ""),
            sources = package["sources"],
            version = package["version"].lower(),
        )
```

New:

```python
        declared[name] = True
        nuget_archive(
            name = name,
            id = package["id"].lower(),
            netrc = package.get("netrc", None),
            sha512 = package.get("sha512", ""),
            sources = package["sources"],
            urls = package.get("urls", []),
            version = package["version"].lower(),
        )
```

Werk ook de docstring van `nuget_archives` bij. Old:

```python
    Args:
      packages: Dicts with `id`, `version` and `sources` keys, and optionally
        `sha512` and `netrc`.
      declared: The names of the archives declared so far, which this call
        adds to. Pass the same dict across groups so that a package version
        shared between them is only declared once.
```

New:

```python
    Args:
      packages: Dicts with `id`, `version` and `sources` keys, and optionally
        `sha512`, `netrc` and `urls`. When `urls` is given the archive
        downloads those directly and never reads a feed index.
      declared: The names of the archives declared so far, which this call
        adds to. Pass the same dict across groups so that a package version
        shared between them is only declared once.
```

- [x] **Step 3: Verify no behavior changed**

Run: `bazel test //dotnet/private/tests/nuget_resolution/... //dotnet/private/tests/packages_lock/... //dotnet/private/tests/paket/...`
Expected: PASS — alle bestaande tests groen.

- [x] **Step 4: Commit**

```bash
git add dotnet/private/rules/nuget/nuget_archive.bzl dotnet/private/rules/nuget/nuget_repo.bzl
git commit -m "Make nuget hub and archive generation reusable for nuget.resolve"
```

---

### Task 8: Tool-bootstrap — tool.bzl, SDK-exports en de versieguard

De interne repository `nuget_resolver_tool` bouwt de tool offline: gepinde `.nupkg`-sluiting als folder-feed + `dotnet publish` uit de bootstrap-SDK. De `TOOL_PACKAGES`-pins hieronder zijn de echte, geverifieerde sha512's van de transitieve sluiting van `NuGet.Protocol` 7.0.1 + `NuGet.DependencyResolver.Core` 7.0.1 voor net10.0 (bepaald door de sluiting met `dotnet restore` op te lossen en elk `.nupkg` van nuget.org te downloaden en te hashen).

**Files:**
- Create: `dotnet/private/nuget_resolve/tool.bzl`
- Create: `dotnet/private/nuget_resolve/tool_version_test.sh`
- Modify: `dotnet/private/nuget_resolve/BUILD.bazel`
- Modify: `dotnet/repositories.bzl` (exports van het dotnet-binaire)
- Modify: `MODULE.bazel` (use_repo van de per-platform bootstrap-SDK-repo's)

- [x] **Step 1: Export the dotnet binary from the SDK repositories**

In `dotnet/repositories.bzl`, in `_dotnet_repo_impl`, voeg aan de `build_content`-template (vlak vóór `dotnet_toolchain(`) de export toe. Old:

```python
dotnet_toolchain(
    name = "dotnet_toolchain", 
    runtime = ":runtime",
```

New:

```python
# The SDK's own dotnet host, exported so repository rules (the nuget.resolve
# tool build) can execute the SDK without going through a toolchain.
exports_files(
    ["{dotnet_binary}"],
    visibility = ["//visibility:public"],
)

dotnet_toolchain(
    name = "dotnet_toolchain", 
    runtime = ":runtime",
```

En voeg de format-variabele toe. Old:

```python
""".format(
        os = PLATFORMS[repository_ctx.attr.platform].os,
        sdk_version = repository_ctx.attr.dotnet_version,
```

New:

```python
""".format(
        os = PLATFORMS[repository_ctx.attr.platform].os,
        dotnet_binary = "dotnet.exe" if PLATFORMS[repository_ctx.attr.platform].os == "windows" else "dotnet",
        sdk_version = repository_ctx.attr.dotnet_version,
```

- [x] **Step 2: Write tool.bzl**

Create `dotnet/private/nuget_resolve/tool.bzl`:

```python
"""Builds the NuGet resolver tool offline, with the bootstrap SDK.

The tool's full transitive .nupkg closure is pinned below with sha512
integrity, downloaded into a local folder feed, and restored against a
NuGet.config that names only that feed — no network access beyond the pinned
downloads, so Bazel's repository cache makes the tool repo hermetic.
"""

load("//dotnet/private:toolchains_repo.bzl", "PLATFORMS")

# Keep in step with the `dotnet.bootstrap_toolchain` version in
# //:MODULE.bazel. //dotnet/private/nuget_resolve:tool_version_test fails when
# they diverge.
BOOTSTRAP_SDK_VERSION = "10.0.401"

# The TFM band of the bootstrap SDK; the tool's csproj targets it.
TOOL_TFM = "net10.0"

# The complete transitive .nupkg closure of the tool: (id, version, sha512 of
# the .nupkg as an SRI string). Repin procedure: `dotnet restore
# tools/nuget_resolver/NuGetResolver.csproj`, read the closure from
# obj/project.assets.json, download each
# https://api.nuget.org/v3-flatcontainer/<id-lower>/<version-lower>/<id-lower>.<version-lower>.nupkg
# and hash it (`openssl dgst -sha512 -binary | base64`).
TOOL_PACKAGES = [
    ("Newtonsoft.Json", "13.0.3", "sha512-mbJSvHfRxfX3tR/U6n1WU+mWHXswYc+SB/hkOpx8yZZe68hNZGfymJu0cjsaJEkVzCMqePiU6LdIyogqfIn7kg=="),
    ("NuGet.Common", "7.0.1", "sha512-BYeB6hyPQjGydptqKbeSbeUHnN4ODGZecW8C69m/fxO+jzznUPq2aCFsfx0Zm49o3bnkZPxOFNDWdoyVYJIuhw=="),
    ("NuGet.Configuration", "7.0.1", "sha512-qRY2f312PqXN3aRjclFdXbuKDH7xggRzMnedMpx3jz3jTQzR5gV0De0EM+HxV23/OulsIywW78HD8kBY7exibw=="),
    ("NuGet.DependencyResolver.Core", "7.0.1", "sha512-BbjqES1Gz1MNtyy1vvymBmaKad+UmBCRFoa0ST1c1/Me8mL3uEE8QSuMGhO3iGm2FWw+izCT4mRbhaMQMhghcQ=="),
    ("NuGet.Frameworks", "7.0.1", "sha512-m4YoXx/qKDHfHDry5BfsEejx2xI933Cw8fiF36XmxyT1E2a+z2kkzjon+qxlUy3X0UGYvBjS0BQvicqVaNMHVg=="),
    ("NuGet.LibraryModel", "7.0.1", "sha512-NMrWbnGT+gZzursqycpq/82tyLOZ3+JtDlKKnxw582RLl7Ho5ZOflZgHcrq2s3esElAtIS10398Ttz8oeSp9Ag=="),
    ("NuGet.Packaging", "7.0.1", "sha512-083yADb1esNQ/qmA5KkE/518QS52KLBCVoer+J9cibgB89k9gBXOgvgdN7emNYyU+5DGPm5OVUtkc5Z6cdVtDA=="),
    ("NuGet.Protocol", "7.0.1", "sha512-1T2I6/E84eX6aq3bJ6rdxGwvpXxbNNxeUXctN8GACIBZtLml9JXH7hQXt5yrdbsGojk0NaxObf00IOf9OvziKg=="),
    ("NuGet.Versioning", "7.0.1", "sha512-ibGcrpgA8foidKNcnf+AQ4zEaVZu4OyWjcPITii6mNgwt2uhd8VFsEq7/Mb0KDxrEJaew+nWJQb7Ju166SAyzw=="),
    ("System.Security.Cryptography.Pkcs", "9.0.6", "sha512-wpqmzVYr3B4FKcRrcnA26VzNeGK0GNlsx5IH5GMFSG8VKILfDB2BRGqYK3VZxTJq9fjai6A+sAXRQXCZkkXqvA=="),
    ("System.Security.Cryptography.ProtectedData", "9.0.6", "sha512-POnou/8+TN15ItlBZn3SerIAAAQeCABZhb+Oeirym8BGB/TVk3YUi3zFR26AbxprRVt06hFALYtfU+bNZ+lnvw=="),
]

_TOOL_SRCS = [
    "FeedDependencyProvider.cs",
    "LockFile.cs",
    "Netrc.cs",
    "NuGetResolver.csproj",
    "Program.cs",
    "ResolveException.cs",
    "ResolveSpec.cs",
    "Resolver.cs",
]

_NUGET_CONFIG = """\
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="feed" />
  </packageSources>
</configuration>
"""

def _host_os(os_name):
    os_name = os_name.lower()
    if os_name.find("windows") != -1:
        return "windows"
    if os_name.find("mac") != -1 or os_name.find("darwin") != -1:
        return "osx"
    if os_name.find("linux") != -1:
        return "linux"
    fail("unsupported host OS: " + os_name)

def host_platform(os_name, os_arch):
    """Maps a Bazel host os/arch pair onto a key of PLATFORMS.

    Args:
      os_name: `repository_ctx.os.name` / `module_ctx.os.name`.
      os_arch: `repository_ctx.os.arch` / `module_ctx.os.arch`.

    Returns:
      The PLATFORMS key for the host, e.g. "x86_64-unknown-linux-gnu".
    """
    want_os = _host_os(os_name)
    if os_arch in ("aarch64", "arm64"):
        want_cpu = "@platforms//cpu:aarch64"
    elif os_arch in ("x86_64", "amd64"):
        want_cpu = "@platforms//cpu:x86_64"
    else:
        fail("unsupported host architecture: " + os_arch)

    for (key, meta) in PLATFORMS.items():
        if meta.os == want_os and want_cpu in meta.compatible_with:
            return key
    fail("no .NET SDK platform for %s/%s" % (os_name, os_arch))

def bootstrap_sdk_dotnet_label(os_name, os_arch):
    """The label of the pinned bootstrap SDK's dotnet binary on this host."""
    platform = host_platform(os_name, os_arch)
    binary = "dotnet.exe" if PLATFORMS[platform].os == "windows" else "dotnet"
    return "@dotnet_sdk.{}_{}//:{}".format(BOOTSTRAP_SDK_VERSION, platform, binary)

def _nuget_resolver_tool_impl(ctx):
    for (id, version, integrity) in TOOL_PACKAGES:
        lower_id = id.lower()
        lower_version = version.lower()
        ctx.download(
            url = "https://api.nuget.org/v3-flatcontainer/{}/{}/{}.{}.nupkg".format(
                lower_id,
                lower_version,
                lower_id,
                lower_version,
            ),
            output = "feed/{}.{}.nupkg".format(lower_id, lower_version),
            integrity = integrity,
        )

    for src in ctx.attr.srcs:
        ctx.file("src/" + src.name, ctx.read(src))

    ctx.file("NuGet.config", _NUGET_CONFIG)

    dotnet = str(ctx.path(ctx.attr.dotnet))
    home = str(ctx.path("home"))
    ctx.file("home/.keep", "")
    env = {
        "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
        "DOTNET_CLI_HOME": home,
        "DOTNET_NOLOGO": "1",
        "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
        "NUGET_PACKAGES": str(ctx.path("nuget_packages")),
        "NUGET_HTTP_CACHE_PATH": str(ctx.path("nuget_http_cache")),
    }
    if _host_os(ctx.os.name) == "windows":
        env["USERPROFILE"] = home
    else:
        env["HOME"] = home

    result = ctx.execute(
        [
            dotnet,
            "publish",
            "src/NuGetResolver.csproj",
            "-c",
            "Release",
            "-o",
            "publish",
            "--disable-build-servers",
            "/p:UseSharedCompilation=false",
            # Targeting packs the SDK does not bundle (Microsoft.AspNetCore.App.Ref
            # on distro-packaged SDKs) would otherwise be restored from NuGet,
            # which the offline folder feed cannot serve. The tool only compiles
            # against Microsoft.NETCore.App, which every SDK bundles.
            "/p:EnableTargetingPackDownload=false",
        ],
        environment = env,
        timeout = 1200,
    )
    if result.return_code != 0:
        fail("Building the NuGet resolver tool failed:\n" + result.stdout + result.stderr)

    ctx.file("BUILD.bazel", """\
"GENERATED"

package(default_visibility = ["//visibility:public"])

exports_files(glob(["publish/**"], allow_empty = False))
""")

nuget_resolver_tool = repository_rule(
    _nuget_resolver_tool_impl,
    doc = "Builds the NuGet resolver tool offline against a pinned .nupkg folder feed.",
    attrs = {
        "dotnet": attr.label(
            doc = "The dotnet binary of the bootstrap SDK: the label bootstrap_sdk_dotnet_label returns.",
            mandatory = True,
        ),
        "srcs": attr.label_list(
            doc = "The tool's sources, copied next to a NuGet.config that only names the pinned folder feed.",
            default = [
                "@rules_dotnet//tools/nuget_resolver:{}".format(src)
                for src in _TOOL_SRCS
            ],
        ),
    },
)
```

- [x] **Step 3: Write the version guard test**

Create `dotnet/private/nuget_resolve/tool_version_test.sh`:

```bash
#!/usr/bin/env bash
# Guards that the bootstrap SDK version the tool build pins matches the one
# rules_dotnet's MODULE.bazel pins via dotnet.bootstrap_toolchain.
set -euo pipefail

# The main repository's runfiles directory is "_main" under bzlmod on some
# Bazel versions and the module name on others; accept both.
root=""
for candidate in "$TEST_SRCDIR/rules_dotnet" "$TEST_SRCDIR/_main"; do
  if [[ -f "$candidate/MODULE.bazel" ]]; then
    root="$candidate"
    break
  fi
done
if [[ -z "$root" ]]; then
  echo "MODULE.bazel not found in the runfiles tree ($TEST_SRCDIR)" >&2
  exit 1
fi

module_bazel="$root/MODULE.bazel"
tool_bzl="$root/dotnet/private/nuget_resolve/tool.bzl"

module_version=$(sed -n 's/.*bootstrap_toolchain(dotnet_version = "\([^"]*\)").*/\1/p' "$module_bazel")
tool_version=$(sed -n 's/^BOOTSTRAP_SDK_VERSION = "\([^"]*\)".*/\1/p' "$tool_bzl")

if [[ -z "$module_version" ]]; then
  echo "no dotnet.bootstrap_toolchain version found in MODULE.bazel" >&2
  exit 1
fi
if [[ "$module_version" != "$tool_version" ]]; then
  echo "BOOTSTRAP_SDK_VERSION in dotnet/private/nuget_resolve/tool.bzl is $tool_version," >&2
  echo "but MODULE.bazel pins bootstrap_toolchain $module_version." >&2
  echo "Update both, and TOOL_TFM if the TFM band changed." >&2
  exit 1
fi
```

Modify `dotnet/private/nuget_resolve/BUILD.bazel`. Old (de bovenste load-regel):

```python
load("@bazel_lib//:bzl_library.bzl", "bzl_library")
```

New:

```python
load("@bazel_lib//:bzl_library.bzl", "bzl_library")
load("@rules_shell//shell:sh_test.bzl", "sh_test")
```

En voeg onderaan toe (`sh_test` komt uit rules_shell; de native variant bestaat niet meer in Bazel 9. `//:MODULE.bazel` is al zichtbaar: de root-package heeft `package(default_visibility = ["//visibility:public"])`):

```python
bzl_library(
    name = "tool",
    srcs = ["tool.bzl"],
    visibility = ["//dotnet:__subpackages__"],
    deps = ["//dotnet/private:toolchains_repo"],
)

sh_test(
    name = "tool_version_test",
    srcs = ["tool_version_test.sh"],
    data = [
        ":tool.bzl",
        "//:MODULE.bazel",
    ],
)
```

- [x] **Step 4: Run the guard test**

Run: `bazel test //dotnet/private/nuget_resolve:tool_version_test`
Expected: PASS (beide pinnen nu 10.0.401).

- [x] **Step 5: Add the bootstrap SDK repositories to MODULE.bazel's use_repo**

In `MODULE.bazel`. Old:

```python
use_repo(dotnet, "dotnet.apphost_packs", "dotnet.crossgen2_packs", "dotnet.ilcompiler_packs", "dotnet.nativeaot_packs", "dotnet.runtime_packs", "dotnet.targeting_packs", "dotnet.wasm_packs", "dotnet_bootstrap_toolchains", "dotnet_toolchains")
```

New:

```python
use_repo(
    dotnet,
    "dotnet.apphost_packs",
    "dotnet.crossgen2_packs",
    "dotnet.ilcompiler_packs",
    "dotnet.nativeaot_packs",
    "dotnet.runtime_packs",
    "dotnet.targeting_packs",
    "dotnet.wasm_packs",
    "dotnet_bootstrap_toolchains",
    # The per-platform bootstrap SDKs the nuget.resolve tool build labels.
    # Lazy: only fetched when a resolve actually builds the tool.
    "dotnet_sdk.10.0.401_aarch64-apple-darwin",
    "dotnet_sdk.10.0.401_arm64-pc-windows-msvc",
    "dotnet_sdk.10.0.401_arm64-unknown-linux-gnu",
    "dotnet_sdk.10.0.401_x86_64-apple-darwin",
    "dotnet_sdk.10.0.401_x86_64-pc-windows-msvc",
    "dotnet_sdk.10.0.401_x86_64-unknown-linux-gnu",
    "dotnet_toolchains",
)
```

- [x] **Step 6: Verify the SDK repo label exists**

Run (op Linux x86_64; op een ander host-platform de bijbehorende repo — zie `PLATFORMS` in `dotnet/private/toolchains_repo.bzl`):

`bazel build @dotnet_sdk.10.0.401_x86_64-unknown-linux-gnu//:dotnet`

Expected: `INFO: Build completed successfully` en het target resolveert naar het geëxporteerde `dotnet`-bestand.

- [x] **Step 7: Commit**

```bash
git add dotnet/private/nuget_resolve/tool.bzl dotnet/private/nuget_resolve/tool_version_test.sh dotnet/private/nuget_resolve/BUILD.bazel dotnet/repositories.bzl MODULE.bazel
git commit -m "Add the offline nuget resolver tool build"
```

---

### Task 9: Starlark — resolve.bzl (de ongepinde resolve-repository + `:pin`)

De repository-rule `nuget_resolve` voert de tool uit en schrijft `nuget_resolve.json` plus een `pin.sh` naar het rules_jvm_external-patroon. Integratieverificatie volgt in Task 12; hier is de verificatie dat de bzl-laag laadt en de bestaande tests groen blijven.

**Files:**
- Create: `dotnet/private/nuget_resolve/resolve.bzl`
- Modify: `dotnet/private/nuget_resolve/BUILD.bazel`

- [x] **Step 1: Write resolve.bzl**

Create `dotnet/private/nuget_resolve/resolve.bzl`:

```python
"""The unpinned resolve repository: runs the resolver tool and offers `:pin`.

Every `resolve` tag gets one of these, pinned or not: the pinned hubs only
read the checked-in lock file, so repinning always goes through this
repository, which resolves fresh.
"""

# A bash script after the rules_jvm_external pin.sh pattern: locate the
# generated lock file through the runfiles library and copy it into the
# workspace. {dest} is the workspace-relative destination, {message} the
# closing note.
_PIN_SH = """\
#!/usr/bin/env bash

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
source "${{RUNFILES_DIR:-/dev/null}}/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "${{RUNFILES_MANIFEST_FILE:-/dev/null}}" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$0.runfiles/$f" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \\
  {{ echo>&2 "ERROR: cannot find $f"; exit 1; }}; f=; set -e
# --- end runfiles.bash initialization v3 ---

set -euo pipefail
resolved_file=$(rlocation "${{1#external\\/}}")
if [[ ! -e $resolved_file ]]; then
  # for --experimental_sibling_repository_layout
  resolved_file="${{1#..\\/}}"
fi
if [[ ! -e $resolved_file ]]; then (echo >&2 "Failed to locate the resolved lock file: $1" && exit 1) fi
dest="$BUILD_WORKSPACE_DIRECTORY/{dest}"

cp "$resolved_file" "$dest"
echo "{message}"
"""

_BUILD = """\
"GENERATED"

# The native sh_binary no longer exists in Bazel 9; rules_shell is a non-dev
# dependency of rules_dotnet, so the label resolves in every consumer.
load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

package(default_visibility = ["//visibility:public"])

exports_files(["nuget_resolve.json"])

sh_binary(
    name = "pin",
    srcs = ["pin.sh"],
    args = ["$(rootpath :nuget_resolve.json)"],
    data = [":nuget_resolve.json"],
)
"""

def _is_windows(repository_ctx):
    return repository_ctx.os.name.lower().find("windows") != -1

def _nuget_resolve_impl(ctx):
    spec = {
        "frameworks": ctx.attr.frameworks,
        "packages": ctx.attr.packages,
        "sources": ctx.attr.sources,
    }
    ctx.file("spec.json", json.encode_indent(spec, prefix = "", indent = "  "))

    dotnet = str(ctx.path(ctx.attr.dotnet))
    tool = str(ctx.path(ctx.attr.tool))
    home = str(ctx.path("home"))
    ctx.file("home/.keep", "")
    env = {
        "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
        "DOTNET_CLI_HOME": home,
        "DOTNET_NOLOGO": "1",
        "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
        "NUGET_PACKAGES": str(ctx.path("nuget_packages")),
        "NUGET_HTTP_CACHE_PATH": str(ctx.path("nuget_http_cache")),
    }
    if _is_windows(ctx):
        env["USERPROFILE"] = home
    else:
        env["HOME"] = home

    args = [
        dotnet,
        "exec",
        tool,
        "--spec",
        "spec.json",
        "--input-hash",
        ctx.attr.input_hash,
        "--output",
        "nuget_resolve.json",
    ]
    if ctx.attr.netrc:
        args += ["--netrc", str(ctx.path(ctx.attr.netrc))]

    result = ctx.execute(args, environment = env, timeout = 1200)
    if result.return_code != 0:
        fail("NuGet resolution failed:\n" + result.stdout + result.stderr)

    if ctx.attr.lock_file:
        label = ctx.attr.lock_file
        dest = (label.package + "/" + label.name) if label.package else label.name
        message = "Updated {}.".format(dest)
    else:
        dest = "nuget_resolve.json"
        message = "Wrote {0}. Check it in and point the resolve tag at it with lock_file = \"//:{0}\".".format(dest)

    ctx.file("pin.sh", _PIN_SH.format(dest = dest, message = message), executable = True)
    ctx.file("BUILD.bazel", _BUILD)

nuget_resolve = repository_rule(
    _nuget_resolve_impl,
    doc = "Resolves the full transitive graph with the NuGet resolver tool and writes nuget_resolve.json.",
    attrs = {
        "packages": attr.string_dict(
            doc = "Package id to version range, in PackageReference syntax.",
            mandatory = True,
            allow_empty = False,
        ),
        "frameworks": attr.string_list(
            doc = "The target frameworks to resolve for.",
            mandatory = True,
            allow_empty = False,
        ),
        "sources": attr.string_list(
            doc = "The NuGet feeds, in lookup order.",
            mandatory = True,
            allow_empty = False,
        ),
        "input_hash": attr.string(
            doc = "The Starlark-computed hash of the resolve inputs, stamped into the lock file by the tool.",
            mandatory = True,
        ),
        "lock_file": attr.label(
            doc = "The checked-in lock file; determines where `:pin` writes.",
        ),
        "netrc": attr.label(
            doc = "A netrc file with the credentials for the feeds.",
        ),
        "dotnet": attr.label(
            doc = "The dotnet binary of the bootstrap SDK.",
            mandatory = True,
        ),
        "tool": attr.label(
            doc = "The published resolver dll, `@nuget_resolver_tool//:publish/NuGetResolver.dll`.",
            mandatory = True,
        ),
    },
)
```

- [x] **Step 2: Register the bzl_library**

Modify `dotnet/private/nuget_resolve/BUILD.bazel` — voeg onderaan toe:

```python
bzl_library(
    name = "resolve",
    srcs = ["resolve.bzl"],
    visibility = ["//dotnet:__subpackages__"],
)
```

- [x] **Step 3: Verify the layer loads**

Run: `bazel build //dotnet/private/nuget_resolve:all && bazel test //dotnet/private/tests/nuget_resolve/... //dotnet/private/nuget_resolve:tool_version_test`
Expected: build slaagt; alle tests PASS.

- [x] **Step 4: Commit**

```bash
git add dotnet/private/nuget_resolve/resolve.bzl dotnet/private/nuget_resolve/BUILD.bazel
git commit -m "Add the unpinned nuget resolve repository rule"
```

---

### Task 10: Starlark — pinned_hub.bzl en unpinned_hub.bzl

**Files:**
- Create: `dotnet/private/nuget_resolve/pinned_hub.bzl`
- Create: `dotnet/private/nuget_resolve/unpinned_hub.bzl`
- Modify: `dotnet/private/nuget_resolve/BUILD.bazel`

- [x] **Step 1: Write pinned_hub.bzl**

Create `dotnet/private/nuget_resolve/pinned_hub.bzl`:

```python
"""The pinned hub: reads the lock file, validates freshness, generates the hub.

The hub never resolves; it serves exactly what the lock file pins. Freshness
is the Starlark-computed input hash the extension passes in: the extension
re-evaluates whenever the tag changes, so a changed hash lands here as a
changed attribute, which refetches the hub and trips the comparison.
"""

load(
    "//dotnet/private/nuget_resolve:input_hash.bzl",
    "classify_input_hash",
)
load("//dotnet/private/nuget_resolve:lock.bzl", "parse_lock")
load(
    "//dotnet/private/rules/nuget:nuget_repo.bzl",
    "nuget_archive_name",
    "write_hub_files",
)

def _spoke_archive(id, version):
    archive = "@{}//".format(nuget_archive_name(id, version))
    return struct(archive = archive, package_info = archive + ":package_info.bzl")

def _repin_command(resolve_name, framework):
    return "REPIN=1 bazel run @{}.{}//:pin".format(resolve_name, framework)

def _pinned_hub_impl(ctx):
    path = str(ctx.attr.lock_file)
    lock = parse_lock(ctx.read(ctx.attr.lock_file), path)
    repin = _repin_command(ctx.attr.resolve_name, ctx.attr.framework)

    status = classify_input_hash(lock.input_hash, ctx.attr.input_hash)
    if status == "legacy":
        # buildifier: disable=print
        print("Warning: {} was written with a superseded input hash algorithm. Regenerate it with `{}`.".format(path, repin))
    elif status == "mismatch":
        message = "{} is out of date: its inputs no longer match the resolve tag in MODULE.bazel. Regenerate it with `{}`.".format(path, repin)
        if ctx.os.environ.get("REPIN") != None:
            # A repin is in flight: the pin target must build while the lock
            # file is stale.
            # buildifier: disable=print
            print("Warning: " + message)
        elif ctx.attr.fail_if_repin_required:
            fail(message)
        else:
            # buildifier: disable=print
            print("Warning: " + message)

    group = lock.frameworks.get(ctx.attr.framework)
    if group == None:
        fail("{} has no framework '{}'. It has: {}. Regenerate it with `{}`.".format(
            path,
            ctx.attr.framework,
            ", ".join(lock.frameworks.keys()),
            repin,
        ))

    packages = [
        {"id": package.id, "sha512": package.sha512, "version": package.version}
        for package in group
    ]
    write_hub_files(
        ctx,
        packages,
        _spoke_archive,
        extra_root_build = "\nalias(name = \"pin\", actual = \"@unpinned_{}//:pin\")\n".format(ctx.attr.resolve_name),
    )

pinned_hub = repository_rule(
    _pinned_hub_impl,
    doc = "Generates the hub for one framework of a pinned resolve tag.",
    attrs = {
        "lock_file": attr.label(
            doc = "The checked-in nuget_resolve.json.",
            mandatory = True,
        ),
        "input_hash": attr.string(
            doc = "The Starlark-computed hash of the resolve inputs.",
            mandatory = True,
        ),
        "fail_if_repin_required": attr.bool(
            doc = "Fail the fetch when the lock file's input hash no longer matches; otherwise warn and build on.",
            default = True,
        ),
        "framework": attr.string(
            doc = "The target framework this hub serves.",
            mandatory = True,
        ),
        "resolve_name": attr.string(
            doc = "The `name` of the resolve tag, used for the `:pin` alias and repin instructions.",
            mandatory = True,
        ),
    },
    environ = ["REPIN"],
)
```

- [x] **Step 2: Write unpinned_hub.bzl**

Create `dotnet/private/nuget_resolve/unpinned_hub.bzl`:

```python
"""The monolithic unpinned hub: downloads every package into the hub itself.

Without a lock file the extension cannot declare spokes (the resolved
versions are only known after `unpinned_<name>` has run), so this hub reads
the freshly resolved lock file, downloads and extracts every package under
`_archives/<id>/<version>/` in its own repository, and generates the same hub
targets the pinned hub does. Sharing and laziness come with pinning.
"""

load(
    "//dotnet/private/rules/nuget:nuget_archive.bzl",
    "fetch_package_into",
    "write_repository_for_testing",
)
load("//dotnet/private/rules/nuget:nuget_repo.bzl", "write_hub_files")
load("//dotnet/private/nuget_resolve:lock.bzl", "parse_lock")

def _in_repo_archive(id, version):
    # Packages are extracted under `_archives/`, not `<id>/<version>/`: the hub
    # generation writes its own package BUILD at `<id>/<version>/BUILD.bazel`
    # and would clobber the archive's BUILD there.
    prefix = "//_archives/{}/{}".format(id.lower(), version.lower())
    return struct(archive = prefix, package_info = prefix + ":package_info.bzl")

def _unpinned_hub_impl(ctx):
    lock = parse_lock(
        ctx.read(ctx.attr.lock),
        "@unpinned_{}//:nuget_resolve.json".format(ctx.attr.resolve_name),
    )

    group = lock.frameworks.get(ctx.attr.framework)
    if group == None:
        fail("@unpinned_{}//:nuget_resolve.json has no framework '{}'. It has: {}.".format(
            ctx.attr.resolve_name,
            ctx.attr.framework,
            ", ".join(lock.frameworks.keys()),
        ))

    packages = []
    for package in group:
        prefix = "_archives/{}/{}/".format(package.id.lower(), package.version.lower())
        extracted = fetch_package_into(ctx, package.id, package.version, package.urls, package.sha512, prefix)
        write_repository_for_testing(ctx, package.id, extracted.nupkg, extracted.files, prefix)
        packages.append({
            "id": package.id,
            "sha512": package.sha512,
            "version": package.version,
        })

    write_hub_files(
        ctx,
        packages,
        _in_repo_archive,
        extra_root_build = "\nalias(name = \"pin\", actual = \"@unpinned_{}//:pin\")\n".format(ctx.attr.resolve_name),
    )

unpinned_hub = repository_rule(
    _unpinned_hub_impl,
    doc = "Generates the hub for one framework of an unpinned resolve tag, downloading every package itself.",
    attrs = {
        "lock": attr.label(
            doc = "The freshly resolved lock file: `@unpinned_<name>//:nuget_resolve.json`.",
            mandatory = True,
        ),
        "framework": attr.string(
            doc = "The target framework this hub serves.",
            mandatory = True,
        ),
        "resolve_name": attr.string(
            doc = "The `name` of the resolve tag, used for the `:pin` alias and error messages.",
            mandatory = True,
        ),
        "netrc": attr.label(
            doc = "A netrc file with the credentials for the feeds.",
        ),
    },
)
```

- [x] **Step 3: Register the bzl_library targets**

Modify `dotnet/private/nuget_resolve/BUILD.bazel` — voeg onderaan toe:

```python
bzl_library(
    name = "pinned_hub",
    srcs = ["pinned_hub.bzl"],
    visibility = ["//dotnet:__subpackages__"],
    deps = [
        ":input_hash",
        ":lock",
        "//dotnet/private/rules/nuget:nuget_repo",
    ],
)

bzl_library(
    name = "unpinned_hub",
    srcs = ["unpinned_hub.bzl"],
    visibility = ["//dotnet:__subpackages__"],
    deps = [
        ":lock",
        "//dotnet/private/rules/nuget:nuget_archive",
        "//dotnet/private/rules/nuget:nuget_repo",
    ],
)
```

- [x] **Step 4: Verify the layer loads**

Run: `bazel build //dotnet/private/nuget_resolve:all`
Expected: `INFO: Build completed successfully` — alle bzl_library-targets laden zonder fouten.

- [x] **Step 5: Commit**

```bash
git add dotnet/private/nuget_resolve/pinned_hub.bzl dotnet/private/nuget_resolve/unpinned_hub.bzl dotnet/private/nuget_resolve/BUILD.bazel
git commit -m "Add the pinned and unpinned nuget hub repository rules"
```

---

### Task 11: Starlark — extension.bzl, publieke nuget.bzl en extensie-tests (TDD)

De extensie zelf, met de puur-functionele helpers (`resolve_repositories`, `claim`) apart testbaar. Dit is de eerste task die de extensie laadbaar maakt als `@rules_dotnet//dotnet:nuget.bzl`; de eerste echte fetch volgt in Task 12.

**Files:**
- Create: `dotnet/private/nuget_resolve/extension.bzl`
- Create: `dotnet/nuget.bzl`
- Modify: `dotnet/BUILD.bazel`
- Modify: `dotnet/private/nuget_resolve/BUILD.bazel`
- Test: `dotnet/private/tests/nuget_resolve/extension_test.bzl`
- Modify: `dotnet/private/tests/nuget_resolve/BUILD.bazel`

- [x] **Step 1: Write the failing test**

Create `dotnet/private/tests/nuget_resolve/extension_test.bzl`:

```python
"""Tests for the nuget module extension helpers."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/nuget_resolve:extension.bzl",
    "claim",
    "resolve_repositories",
)

def _repositories_test_impl(ctx):
    env = unittest.begin(ctx)

    tag = struct(name = "nuget", frameworks = ["net8.0", "net10.0"])

    asserts.equals(
        env,
        ["unpinned_nuget", "nuget.net8.0", "nuget.net10.0"],
        resolve_repositories(tag),
        "one resolve repository plus one hub per framework",
    )

    return unittest.end(env)

_repositories_test = unittest.make(_repositories_test_impl)

def _claim_test_impl(ctx):
    env = unittest.begin(ctx)

    claimed = {}
    asserts.equals(env, None, claim(claimed, "nuget.net10.0", "module 'a'"))
    asserts.equals(env, None, claim(claimed, "nuget.net8.0", "module 'a'"))

    error = claim(claimed, "nuget.net10.0", "module 'b'")
    asserts.true(env, error != None, "a double claim is an error")
    asserts.true(env, error.find("nuget.net10.0") != -1, "the error names the repository: %s" % error)
    asserts.true(env, error.find("module 'a'") != -1, "the error names the first claimant: %s" % error)
    asserts.true(env, error.find("name") != -1, "the error advises picking a different name: %s" % error)

    return unittest.end(env)

_claim_test = unittest.make(_claim_test_impl)

def extension_test_suite(name):
    unittest.suite(
        name,
        _repositories_test,
        _claim_test,
    )
```

Modify `dotnet/private/tests/nuget_resolve/BUILD.bazel`. Old:

```python
load(":input_hash_test.bzl", "input_hash_test_suite")
load(":lock_test.bzl", "lock_test_suite")

input_hash_test_suite(name = "input_hash_test")

lock_test_suite(name = "lock_test")
```

New:

```python
load(":extension_test.bzl", "extension_test_suite")
load(":input_hash_test.bzl", "input_hash_test_suite")
load(":lock_test.bzl", "lock_test_suite")

extension_test_suite(name = "extension_test")

input_hash_test_suite(name = "input_hash_test")

lock_test_suite(name = "lock_test")
```

- [x] **Step 2: Run the test to verify it fails**

Run: `bazel test //dotnet/private/tests/nuget_resolve:extension_test`
Expected: FAIL — `cannot load '//dotnet/private/nuget_resolve:extension.bzl'`.

- [x] **Step 3: Write the extension**

Create `dotnet/private/nuget_resolve/extension.bzl`:

```python
"""Implementation of the `nuget` module extension. See //dotnet:nuget.bzl."""

load(
    "//dotnet/private/nuget_resolve:input_hash.bzl",
    "compute_input_hash",
)
load("//dotnet/private/nuget_resolve:lock.bzl", "parse_lock")
load("//dotnet/private/nuget_resolve:pinned_hub.bzl", "pinned_hub")
load("//dotnet/private/nuget_resolve:resolve.bzl", "nuget_resolve")
load(
    "//dotnet/private/nuget_resolve:tool.bzl",
    "bootstrap_sdk_dotnet_label",
    "nuget_resolver_tool",
)
load("//dotnet/private/nuget_resolve:unpinned_hub.bzl", "unpinned_hub")
load(
    "//dotnet/private/rules/nuget:nuget_repo.bzl",
    "nuget_archives",
)

_DEFAULT_SOURCES = ["https://api.nuget.org/v3/index.json"]

_resolve = tag_class(
    doc = "Resolves a set of NuGet packages transitively, once per target framework.",
    attrs = {
        "name": attr.string(
            doc = "Prefix for the repositories: a hub per framework as `<name>.<tfm>`, the resolve repository as `unpinned_<name>`.",
            mandatory = True,
        ),
        "packages": attr.string_dict(
            doc = """Package id to version range, in NuGet's PackageReference syntax: `13.0.3` (minimum version, resolves to the lowest applicable), `[13.0.3]` (exact), `4.0.*` (floating). Semantics identical to `dotnet restore`.""",
            mandatory = True,
            allow_empty = False,
        ),
        "frameworks": attr.string_list(
            doc = "The target frameworks to resolve for. Each becomes its own hub repository, addressed as `@<name>.<tfm>//<package>`.",
            mandatory = True,
            allow_empty = False,
        ),
        "sources": attr.string_list(
            doc = "The NuGet feeds, in lookup order. V3 (`index.json`) and V2 are both supported.",
            default = _DEFAULT_SOURCES,
        ),
        "lock_file": attr.label(
            doc = "The checked-in `nuget_resolve.json`. Without it every fetch resolves fresh (unpinned mode).",
        ),
        "fail_if_repin_required": attr.bool(
            doc = """Fail the build when the inputs no longer match the lock file. Only meaningful with `lock_file`; without one it is inert. With `REPIN=1` in the environment a mismatch warns instead of failing, so the `:pin` target itself always builds.""",
            default = True,
        ),
        "netrc": attr.label(
            doc = "A netrc file with the credentials for the feeds. Defaults to the user's.",
        ),
    },
)

def resolve_repositories(tag):
    """The repository names one resolve tag claims.

    Args:
      tag: A struct or tag with `name` and `frameworks` fields.

    Returns:
      The resolve repository name followed by the hub names, one per
      framework.
    """
    return ["unpinned_" + tag.name] + [
        "{}.{}".format(tag.name, tfm)
        for tfm in tag.frameworks
    ]

def claim(claimed, repo, owner):
    """Records repo as claimed by owner.

    Args:
      claimed: The claim map, repository name to owner description.
      repo: The repository name being claimed.
      owner: A description of the claimant, for error messages.

    Returns:
      An error message when the repository was already claimed, else None.
    """
    existing = claimed.get(repo)
    if existing != None:
        return "The repository @{} is already provided by {}. Pick a different `name` for one of the resolve tags.".format(repo, existing)
    claimed[repo] = owner
    return None

def _collect(module_ctx):
    """Gathers every resolve tag across all modules, checking name collisions."""
    entries = []

    # Repository name to the module that claimed it, so that a collision
    # between two tags (also across modules) is reported rather than silently
    # resolved.
    claimed = {}

    for module in module_ctx.modules:
        for tag in module.tags.resolve:
            owner = "the resolve tag '{}' of module '{}'".format(tag.name, module.name)
            for repo in resolve_repositories(tag):
                error = claim(claimed, repo, owner)
                if error:
                    fail(error)

            entries.append(struct(
                tag = tag,
                is_dev = module_ctx.is_dev_dependency(tag),
                is_root = module.is_root,
            ))

    return entries

def _nuget_impl(module_ctx):
    entries = _collect(module_ctx)

    if not entries:
        return module_ctx.extension_metadata(reproducible = True)

    # One tool repository per extension instance, shared by every resolve tag.
    # The SDK label resolves through rules_dotnet's own repo mapping: its
    # MODULE.bazel lists the per-platform bootstrap SDKs in use_repo(dotnet).
    dotnet = bootstrap_sdk_dotnet_label(module_ctx.os.name, module_ctx.os.arch)
    nuget_resolver_tool(
        name = "nuget_resolver_tool",
        dotnet = dotnet,
    )

    archives = {}
    direct_deps = []
    direct_dev_deps = []
    all_pinned = True

    for entry in entries:
        tag = entry.tag
        input_hash = compute_input_hash(tag.packages, tag.frameworks, tag.sources)

        nuget_resolve(
            name = "unpinned_" + tag.name,
            packages = tag.packages,
            frameworks = tag.frameworks,
            sources = tag.sources,
            input_hash = input_hash,
            lock_file = tag.lock_file,
            netrc = tag.netrc,
            dotnet = dotnet,
            tool = "@nuget_resolver_tool//:publish/NuGetResolver.dll",
        )

        if tag.lock_file:
            lock = parse_lock(module_ctx.read(tag.lock_file), str(tag.lock_file))
            for tfm in tag.frameworks:
                group = lock.frameworks.get(tfm)
                if group == None:
                    fail("{} has no framework '{}'. It has: {}. Regenerate it with `REPIN=1 bazel run @{}.{}//:pin`.".format(
                        tag.lock_file,
                        tfm,
                        ", ".join(lock.frameworks.keys()),
                        tag.name,
                        tfm,
                    ))

                packages = [
                    {
                        "id": package.id,
                        "netrc": tag.netrc,
                        "sha512": package.sha512,
                        "sources": tag.sources,
                        "urls": package.urls,
                        "version": package.version,
                    }
                    for package in group
                ]
                nuget_archives(packages, archives)
                pinned_hub(
                    name = "{}.{}".format(tag.name, tfm),
                    lock_file = tag.lock_file,
                    input_hash = input_hash,
                    fail_if_repin_required = tag.fail_if_repin_required,
                    framework = tfm,
                    resolve_name = tag.name,
                )
        else:
            all_pinned = False
            for tfm in tag.frameworks:
                unpinned_hub(
                    name = "{}.{}".format(tag.name, tfm),
                    lock = "@unpinned_{}//:nuget_resolve.json".format(tag.name),
                    framework = tfm,
                    resolve_name = tag.name,
                    netrc = tag.netrc,
                )

        if entry.is_root:
            for tfm in tag.frameworks:
                if entry.is_dev:
                    direct_dev_deps.append("{}.{}".format(tag.name, tfm))
                else:
                    direct_deps.append("{}.{}".format(tag.name, tfm))

    return module_ctx.extension_metadata(
        root_module_direct_deps = direct_deps,
        root_module_direct_dev_deps = direct_dev_deps,
        reproducible = all_pinned,
    )

nuget = module_extension(
    implementation = _nuget_impl,
    doc = "Resolves NuGet packages transitively, with optional pinning.",
    tag_classes = {"resolve": _resolve},
    # The tool build and its SDK label depend on the host platform.
    os_dependent = True,
    arch_dependent = True,
)
```

Create `dotnet/nuget.bzl`:

```python
"""The `nuget` module extension.

Resolves NuGet packages transitively — the same graph resolution as
`dotnet restore` — and optionally pins the result in a checked-in
`nuget_resolve.json`:

```starlark
nuget = use_extension("@rules_dotnet//dotnet:nuget.bzl", "nuget")
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
        "Serilog": "4.0.0",
    },
    frameworks = ["net8.0", "net10.0"],
    lock_file = "//:nuget_resolve.json",
)
use_repo(nuget, "nuget.net8.0", "nuget.net10.0")
```

Each target framework becomes its own repository, so a package in the
`net10.0` framework is addressed as `@nuget.net10.0//<package-id-lowercase>`.

Without `lock_file` every fetch resolves fresh. Create or refresh the lock
file with `REPIN=1 bazel run @nuget.net10.0//:pin` and check it in.
"""

load("//dotnet/private/nuget_resolve:extension.bzl", _nuget = "nuget")

nuget = _nuget
```

Modify `dotnet/BUILD.bazel` — voeg direct na de `paket`-bzl_library toe. Old:

```python
bzl_library(
    name = "paket",
    srcs = ["paket.bzl"],
    visibility = ["//visibility:public"],
    deps = ["//dotnet/private/paket:extension"],
)
```

New:

```python
bzl_library(
    name = "paket",
    srcs = ["paket.bzl"],
    visibility = ["//visibility:public"],
    deps = ["//dotnet/private/paket:extension"],
)

bzl_library(
    name = "nuget",
    srcs = ["nuget.bzl"],
    visibility = ["//visibility:public"],
    deps = ["//dotnet/private/nuget_resolve:extension"],
)
```

Modify `dotnet/private/nuget_resolve/BUILD.bazel` — voeg onderaan toe:

```python
bzl_library(
    name = "extension",
    srcs = ["extension.bzl"],
    visibility = ["//dotnet:__subpackages__"],
    deps = [
        ":input_hash",
        ":lock",
        ":pinned_hub",
        ":resolve",
        ":tool",
        ":unpinned_hub",
        "//dotnet/private/rules/nuget:nuget_repo",
    ],
)
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `bazel test //dotnet/private/tests/nuget_resolve/... && bazel build //dotnet:nuget`
Expected: alle drie de test-suites PASS; de publieke `bzl_library` bouwt.

- [x] **Step 5: Commit**

```bash
git add dotnet/private/nuget_resolve/extension.bzl dotnet/nuget.bzl dotnet/BUILD.bazel dotnet/private/nuget_resolve/BUILD.bazel dotnet/private/tests/nuget_resolve/extension_test.bzl dotnet/private/tests/nuget_resolve/BUILD.bazel
git commit -m "Add the nuget module extension"
```

---

### Task 12: e2e/nuget_resolve_basic — ongepind, één package

De eerste end-to-end-verificatie van de hele keten: tool-build bij fetch-tijd, resolutie, monolithische ongepinde hub, build en run. Elke e2e-map is een eigen bazel-module.

**Files:**
- Create: `e2e/nuget_resolve_basic/MODULE.bazel`
- Create: `e2e/nuget_resolve_basic/.bazelrc`
- Create: `e2e/nuget_resolve_basic/.bazelversion`
- Create: `e2e/nuget_resolve_basic/internal_dev_deps.bzl`
- Create: `e2e/nuget_resolve_basic/BUILD.bazel`
- Create: `e2e/nuget_resolve_basic/src/hello/BUILD.bazel`
- Create: `e2e/nuget_resolve_basic/src/hello/hello.cs`

- [x] **Step 1: Create the module scaffolding**

Create `e2e/nuget_resolve_basic/.bazelversion`:

```
9.1.1
```

Create `e2e/nuget_resolve_basic/.bazelrc` (identiek aan `e2e/gazelle_net10.0/.bazelrc`):

```
startup --windows_enable_symlinks
common --enable_runfiles
common --incompatible_strict_action_env

# Enable C# persistent workers
build --@rules_dotnet//dotnet/settings:use_compiler_worker=true

# Give one cache key to a compilation reached through several configurations.
# Per platform because path mapping requires a sandbox and Bazel has none on
# Windows, where it would fail every compile. See ../../docs/README.md#path-mapping.
common --enable_platform_specific_config
common:linux --experimental_output_paths=strip
common:macos --experimental_output_paths=strip
```

Create `e2e/nuget_resolve_basic/internal_dev_deps.bzl` (identiek aan de andere e2e-modules):

```python
"""Module extension for internal dev_dependency=True setup."""

load("@bazel_ci_rules//:rbe_repo.bzl", "rbe_preconfig")

def _internal_dev_deps_impl(mctx):
    _ = mctx  # @unused

    rbe_preconfig(
        name = "buildkite_config",
        toolchain = "ubuntu2204",
    )

internal_dev_deps = module_extension(
    implementation = _internal_dev_deps_impl,
    doc = "This extension creates internal rules_dotnet dev dependencies.",
)
```

Create `e2e/nuget_resolve_basic/BUILD.bazel` (leeg package zodat `//...` de root dekt):

```python
package(default_visibility = ["//visibility:public"])
```

- [x] **Step 2: Create the module and the app**

Create `e2e/nuget_resolve_basic/MODULE.bazel`:

```python
"rules_dotnet nuget.resolve basic e2e (unpinned)"

module(
    name = "e2e_nuget_resolve_basic",
    version = "0.0.0",
    compatibility_level = 1,
)

bazel_dep(name = "rules_dotnet", version = "0.0.0")
local_path_override(
    module_name = "rules_dotnet",
    path = "../..",
)

dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
dotnet.toolchain(dotnet_version = "10.0.401")
use_repo(dotnet, "dotnet_toolchains")

register_toolchains("@dotnet_toolchains//:all")

# No lock_file: the graph is resolved fresh at fetch time.
nuget = use_extension("@rules_dotnet//dotnet:nuget.bzl", "nuget")
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
    },
    frameworks = ["net10.0"],
)
use_repo(nuget, "nuget.net10.0")

# Only needed to make the Bazel CI RBE config work. Not needed for using rules_dotnet.
bazel_dep(name = "bazel_ci_rules", version = "1.0.0", dev_dependency = True)
bazel_dep(name = "platforms", version = "0.0.10", dev_dependency = True)

internal_dev_deps = use_extension("//:internal_dev_deps.bzl", "internal_dev_deps", dev_dependency = True)
use_repo(internal_dev_deps, "buildkite_config")
```

Create `e2e/nuget_resolve_basic/src/hello/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary")

csharp_binary(
    name = "hello",
    srcs = ["hello.cs"],
    target_frameworks = ["net10.0"],
    deps = ["@nuget.net10.0//newtonsoft.json"],
)
```

Create `e2e/nuget_resolve_basic/src/hello/hello.cs`:

```csharp
using Newtonsoft.Json;

public static class Program
{
    public static void Main()
    {
        System.Console.WriteLine(JsonConvert.SerializeObject(new { hello = "world" }));
    }
}
```

- [x] **Step 3: Build and run (eerste integratieverificatie van de hele keten)**

Run (vanuit `e2e/nuget_resolve_basic`): `bazel run //src/hello`
Expected: de tool-repository bouwt offline (éénmalig traag: SDK-download + `dotnet publish`), de resolutie draait tegen nuget.org, en het programma print `{"hello":"world"}`.

Debug-aanknopingspunten als dit faalt:
- `bazel build @nuget_resolver_tool//...` isoleert de tool-build.
- `bazel build @unpinned_nuget//...` isoleert de resolutie.
- `bazel build @nuget.net10.0//newtonsoft.json` isoleert de ongepinde hub.

- [x] **Step 4: Verify the full module build**

Run: `bazel build //...`
Expected: `INFO: Build completed successfully`.

- [x] **Step 5: Commit**

```bash
git add e2e/nuget_resolve_basic
git commit -m "Add unpinned nuget.resolve e2e module"
```

---

### Task 13: e2e/nuget_resolve_transitive — gepind, diepe keten + diamond

Geverifieerde echte grafen op nuget.org:
- Diepe keten: `Microsoft.Extensions.Http` 8.0.0 → `Microsoft.Extensions.Logging` 8.0.0 → `Microsoft.Extensions.DependencyInjection` 8.0.0 → `Microsoft.Extensions.DependencyInjection.Abstractions` 8.0.0 (D, waarvan de app een type gebruikt).
- Diamond met versie-unificatie: `Serilog.Sinks.Async` 2.1.0 → `Serilog >= 4.1.0` én `Serilog.Sinks.File` 6.0.0 → `Serilog >= 4.0.0`; beide sinks direct gevraagd, Serilog unificeert naar 4.1.0.

**Files:**
- Create: `e2e/nuget_resolve_transitive/MODULE.bazel`
- Create: `e2e/nuget_resolve_transitive/.bazelrc`
- Create: `e2e/nuget_resolve_transitive/.bazelversion`
- Create: `e2e/nuget_resolve_transitive/internal_dev_deps.bzl`
- Create: `e2e/nuget_resolve_transitive/BUILD.bazel`
- Create: `e2e/nuget_resolve_transitive/src/app/BUILD.bazel`
- Create: `e2e/nuget_resolve_transitive/src/app/Program.cs`
- Create: `e2e/nuget_resolve_transitive/nuget_resolve.json` (gegenereerd via de pin-flow)

- [x] **Step 1: Create the module scaffolding**

De bestanden `.bazelrc`, `.bazelversion`, `internal_dev_deps.bzl` en `BUILD.bazel` zijn identiek aan die van Task 12 — kopieer ze:

```bash
cp e2e/nuget_resolve_basic/.bazelrc e2e/nuget_resolve_basic/.bazelversion e2e/nuget_resolve_basic/internal_dev_deps.bzl e2e/nuget_resolve_basic/BUILD.bazel e2e/nuget_resolve_transitive/
```

- [x] **Step 2: Create the module (nog zonder lock_file) en de app**

Create `e2e/nuget_resolve_transitive/MODULE.bazel`:

```python
"rules_dotnet nuget.resolve transitive e2e (pinned)"

module(
    name = "e2e_nuget_resolve_transitive",
    version = "0.0.0",
    compatibility_level = 1,
)

bazel_dep(name = "rules_dotnet", version = "0.0.0")
local_path_override(
    module_name = "rules_dotnet",
    path = "../..",
)

dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
dotnet.toolchain(dotnet_version = "10.0.401")
use_repo(dotnet, "dotnet_toolchains")

register_toolchains("@dotnet_toolchains//:all")

nuget = use_extension("@rules_dotnet//dotnet:nuget.bzl", "nuget")
nuget.resolve(
    name = "nuget",
    packages = {
        # Deep chain: Http -> Logging -> DependencyInjection -> DependencyInjection.Abstractions
        "Microsoft.Extensions.Http": "8.0.0",
        # Diamond: both sinks depend on Serilog with different minimums
        # (Async: >= 4.1.0, File: >= 4.0.0); Serilog unifies to 4.1.0.
        "Serilog.Sinks.Async": "2.1.0",
        "Serilog.Sinks.File": "6.0.0",
    },
    frameworks = ["net10.0"],
)
use_repo(nuget, "nuget.net10.0")

# Only needed to make the Bazel CI RBE config work. Not needed for using rules_dotnet.
bazel_dep(name = "bazel_ci_rules", version = "1.0.0", dev_dependency = True)
bazel_dep(name = "platforms", version = "0.0.10", dev_dependency = True)

internal_dev_deps = use_extension("//:internal_dev_deps.bzl", "internal_dev_deps", dev_dependency = True)
use_repo(internal_dev_deps, "buildkite_config")
```

Create `e2e/nuget_resolve_transitive/src/app/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary")

csharp_binary(
    name = "app",
    srcs = ["Program.cs"],
    target_frameworks = ["net10.0"],
    deps = [
        # A type from the deepest package of the chain (D).
        "@nuget.net10.0//microsoft.extensions.dependencyinjection.abstractions",
        # The package the diamond unifies on.
        "@nuget.net10.0//serilog",
    ],
)
```

Create `e2e/nuget_resolve_transitive/src/app/Program.cs`:

```csharp
using Microsoft.Extensions.DependencyInjection;
using Serilog;

public static class Program
{
    public static void Main()
    {
        // ServiceDescriptor lives in Microsoft.Extensions.DependencyInjection.Abstractions,
        // the deepest package of the Http -> Logging -> DependencyInjection -> Abstractions chain.
        ServiceDescriptor descriptor = ServiceDescriptor.Singleton<string>("hello");
        Log.Logger = new LoggerConfiguration().MinimumLevel.Debug().CreateLogger();
        Log.Information("deep chain type: {Type}", descriptor.ServiceType.FullName);
    }
}
```

- [x] **Step 3: Generate the lock file via the pin flow**

Run (vanuit `e2e/nuget_resolve_transitive`): `bazel run @nuget.net10.0//:pin`
Expected: `Wrote nuget_resolve.json. Check it in and point the resolve tag at it with lock_file = "//:nuget_resolve.json".`

Verify de gegenereerde inhoud:

```bash
python3 - <<'EOF'
import json
lock = json.load(open("nuget_resolve.json"))
assert lock["version"] == 1
assert isinstance(lock["inputHash"], str) and lock["inputHash"].isdigit()
pkgs = {p["id"]: p["version"] for p in lock["frameworks"]["net10.0"]["packages"]}
assert pkgs["Microsoft.Extensions.Http"] == "8.0.0", pkgs
assert pkgs["Microsoft.Extensions.Logging"] == "8.0.0", pkgs
assert pkgs["Microsoft.Extensions.DependencyInjection"] == "8.0.0", pkgs
assert pkgs["Microsoft.Extensions.DependencyInjection.Abstractions"] == "8.0.0", pkgs
assert pkgs["Serilog"] == "4.1.0", ("diamond unification", pkgs)
assert pkgs["Serilog.Sinks.Async"] == "2.1.0", pkgs
assert pkgs["Serilog.Sinks.File"] == "6.0.0", pkgs
for p in lock["frameworks"]["net10.0"]["packages"]:
    assert p["sha512"].startswith("sha512-"), p
    assert p["urls"], p
print("lock file OK:", len(pkgs), "packages")
EOF
```

Expected: `lock file OK: N packages` (N is de volledige transitieve sluiting, groter dan 7 — de Microsoft.Extensions-keten trekt o.a. `Microsoft.Bcl.AsyncInterfaces` en `Microsoft.Extensions.Options` mee).

- [x] **Step 4: Pin the module**

In `e2e/nuget_resolve_transitive/MODULE.bazel`, voeg `lock_file` toe aan de tag. Old:

```python
    packages = {
        # Deep chain: Http -> Logging -> DependencyInjection -> DependencyInjection.Abstractions
        "Microsoft.Extensions.Http": "8.0.0",
        # Diamond: both sinks depend on Serilog with different minimums
        # (Async: >= 4.1.0, File: >= 4.0.0); Serilog unifies to 4.1.0.
        "Serilog.Sinks.Async": "2.1.0",
        "Serilog.Sinks.File": "6.0.0",
    },
    frameworks = ["net10.0"],
)
```

New:

```python
    packages = {
        # Deep chain: Http -> Logging -> DependencyInjection -> DependencyInjection.Abstractions
        "Microsoft.Extensions.Http": "8.0.0",
        # Diamond: both sinks depend on Serilog with different minimums
        # (Async: >= 4.1.0, File: >= 4.0.0); Serilog unifies to 4.1.0.
        "Serilog.Sinks.Async": "2.1.0",
        "Serilog.Sinks.File": "6.0.0",
    },
    frameworks = ["net10.0"],
    lock_file = "//:nuget_resolve.json",
)
```

- [x] **Step 5: Build and run pinned**

Run: `bazel run //src/app && bazel build //...`
Expected: `INFO: Build completed successfully`; het programma print `deep chain type: System.String` (met Serilog-consolevrije logger-output op stderr/stdout — het exacte formaat maakt niet uit, de exitcode is 0).

- [x] **Step 6: Commit**

```bash
git add e2e/nuget_resolve_transitive
git commit -m "Add pinned transitive nuget.resolve e2e module"
```

---

### Task 14: e2e/nuget_resolve_multi_framework — gepind, net8.0 + net10.0

Eén tag, twee frameworks, per-framework-hubs geadresseerd via een `select` op de tfm-config-settings.

**Files:**
- Create: `e2e/nuget_resolve_multi_framework/MODULE.bazel`
- Create: `e2e/nuget_resolve_multi_framework/.bazelrc`
- Create: `e2e/nuget_resolve_multi_framework/.bazelversion`
- Create: `e2e/nuget_resolve_multi_framework/internal_dev_deps.bzl`
- Create: `e2e/nuget_resolve_multi_framework/BUILD.bazel`
- Create: `e2e/nuget_resolve_multi_framework/src/lib/BUILD.bazel`
- Create: `e2e/nuget_resolve_multi_framework/src/lib/Json.cs`
- Create: `e2e/nuget_resolve_multi_framework/nuget_resolve.json` (gegenereerd via de pin-flow)

- [x] **Step 1: Create the module scaffolding**

```bash
cp e2e/nuget_resolve_basic/.bazelrc e2e/nuget_resolve_basic/.bazelversion e2e/nuget_resolve_basic/internal_dev_deps.bzl e2e/nuget_resolve_basic/BUILD.bazel e2e/nuget_resolve_multi_framework/
```

- [x] **Step 2: Create the module (nog zonder lock_file) en de library**

Create `e2e/nuget_resolve_multi_framework/MODULE.bazel`:

```python
"rules_dotnet nuget.resolve multi-framework e2e (pinned)"

module(
    name = "e2e_nuget_resolve_multi_framework",
    version = "0.0.0",
    compatibility_level = 1,
)

bazel_dep(name = "rules_dotnet", version = "0.0.0")
local_path_override(
    module_name = "rules_dotnet",
    path = "../..",
)

dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
dotnet.toolchain(dotnet_version = "10.0.401")
use_repo(dotnet, "dotnet_toolchains")

register_toolchains("@dotnet_toolchains//:all")

nuget = use_extension("@rules_dotnet//dotnet:nuget.bzl", "nuget")
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
    },
    frameworks = ["net8.0", "net10.0"],
)
use_repo(nuget, "nuget.net10.0", "nuget.net8.0")

# Only needed to make the Bazel CI RBE config work. Not needed for using rules_dotnet.
bazel_dep(name = "bazel_ci_rules", version = "1.0.0", dev_dependency = True)
bazel_dep(name = "platforms", version = "0.0.10", dev_dependency = True)

internal_dev_deps = use_extension("//:internal_dev_deps.bzl", "internal_dev_deps", dev_dependency = True)
use_repo(internal_dev_deps, "buildkite_config")
```

Create `e2e/nuget_resolve_multi_framework/src/lib/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "lib",
    srcs = ["Json.cs"],
    target_frameworks = [
        "net8.0",
        "net10.0",
    ],
    deps = select({
        "@rules_dotnet//dotnet:tfm_net8.0": ["@nuget.net8.0//newtonsoft.json"],
        "@rules_dotnet//dotnet:tfm_net10.0": ["@nuget.net10.0//newtonsoft.json"],
    }),
)
```

Create `e2e/nuget_resolve_multi_framework/src/lib/Json.cs`:

```csharp
using Newtonsoft.Json;

namespace MultiFramework;

public static class Json
{
    public static string Hello() => JsonConvert.SerializeObject(new { hello = "world" });
}
```

- [x] **Step 3: Generate the lock file via the pin flow**

Run (vanuit `e2e/nuget_resolve_multi_framework`): `bazel run @nuget.net10.0//:pin`
Expected: `Wrote nuget_resolve.json. ...`

Verify:

```bash
python3 - <<'EOF'
import json
lock = json.load(open("nuget_resolve.json"))
assert sorted(lock["frameworks"]) == ["net10.0", "net8.0"], lock["frameworks"].keys()
for tfm in ("net8.0", "net10.0"):
    pkgs = lock["frameworks"][tfm]["packages"]
    assert [p["id"] for p in pkgs] == ["Newtonsoft.Json"], (tfm, pkgs)
    assert pkgs[0]["version"] == "13.0.3", pkgs
print("lock file OK")
EOF
```

Expected: `lock file OK`. (Let op: `sorted(["net8.0", "net10.0"])` is `["net10.0", "net8.0"]` — ordinaal sorteert "1" voor "8".)

- [x] **Step 4: Pin the module**

In `e2e/nuget_resolve_multi_framework/MODULE.bazel`, voeg `lock_file` toe. Old:

```python
    frameworks = ["net8.0", "net10.0"],
)
```

New:

```python
    frameworks = ["net8.0", "net10.0"],
    lock_file = "//:nuget_resolve.json",
)
```

- [x] **Step 5: Build for both frameworks**

rules_dotnet bouwt één TFM-variant per invocation: de `tfm_transition` kiest uit `target_frameworks` de hoogste die compatibel is met de flag `@rules_dotnet//dotnet:target_framework` (default de hoogste). Bouw daarom beide varianten expliciet:

```bash
bazel build //... --@rules_dotnet//dotnet:target_framework=net8.0
bazel build //... --@rules_dotnet//dotnet:target_framework=net10.0
```

Expected: beide runs `INFO: Build completed successfully`. De `select()` in `//src/lib` adresseert per variant de bijbehorende hub (`@nuget.net8.0`/`@nuget.net10.0`), dus een ontbrekende of kapotte hub faalt de bijbehorende run.

- [x] **Step 6: Commit**

```bash
git add e2e/nuget_resolve_multi_framework
git commit -m "Add pinned multi-framework nuget.resolve e2e module"
```

---

### Task 15: e2e/nuget_resolve_pinning — repin-detectie en de repin-flow

Een gepinde module plus een testscript dat bewijst: (1) een verouderd lockbestand faalt de build met de repin-instructies, (2) `REPIN=1 bazel run @nuget.net10.0//:pin` werkt het lockbestand bij, (3) de build slaagt daarna. Het script draait buiten Bazel (geneste Bazel kan niet in een test); CI bouwt de module in zijn uitgangstoestand.

**Files:**
- Create: `e2e/nuget_resolve_pinning/MODULE.bazel`
- Create: `e2e/nuget_resolve_pinning/.bazelrc`
- Create: `e2e/nuget_resolve_pinning/.bazelversion`
- Create: `e2e/nuget_resolve_pinning/internal_dev_deps.bzl`
- Create: `e2e/nuget_resolve_pinning/BUILD.bazel`
- Create: `e2e/nuget_resolve_pinning/src/hello/BUILD.bazel`
- Create: `e2e/nuget_resolve_pinning/src/hello/hello.cs`
- Create: `e2e/nuget_resolve_pinning/nuget_resolve.json` (gegenereerd via de pin-flow)
- Create: `e2e/nuget_resolve_pinning/test.sh`

- [x] **Step 1: Create the module scaffolding**

```bash
cp e2e/nuget_resolve_basic/.bazelrc e2e/nuget_resolve_basic/.bazelversion e2e/nuget_resolve_basic/internal_dev_deps.bzl e2e/nuget_resolve_basic/BUILD.bazel e2e/nuget_resolve_pinning/
mkdir -p e2e/nuget_resolve_pinning/src
cp -r e2e/nuget_resolve_basic/src/hello e2e/nuget_resolve_pinning/src/hello
```

- [x] **Step 2: Create the module (nog zonder lock_file)**

Create `e2e/nuget_resolve_pinning/MODULE.bazel`:

```python
"rules_dotnet nuget.resolve pinning e2e"

module(
    name = "e2e_nuget_resolve_pinning",
    version = "0.0.0",
    compatibility_level = 1,
)

bazel_dep(name = "rules_dotnet", version = "0.0.0")
local_path_override(
    module_name = "rules_dotnet",
    path = "../..",
)

dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
dotnet.toolchain(dotnet_version = "10.0.401")
use_repo(dotnet, "dotnet_toolchains")

register_toolchains("@dotnet_toolchains//:all")

nuget = use_extension("@rules_dotnet//dotnet:nuget.bzl", "nuget")
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
    },
    frameworks = ["net10.0"],
)
use_repo(nuget, "nuget.net10.0")

# Only needed to make the Bazel CI RBE config work. Not needed for using rules_dotnet.
bazel_dep(name = "bazel_ci_rules", version = "1.0.0", dev_dependency = True)
bazel_dep(name = "platforms", version = "0.0.10", dev_dependency = True)

internal_dev_deps = use_extension("//:internal_dev_deps.bzl", "internal_dev_deps", dev_dependency = True)
use_repo(internal_dev_deps, "buildkite_config")
```

- [x] **Step 3: Generate the lock file and pin the module**

Run (vanuit `e2e/nuget_resolve_pinning`):

```bash
bazel run @nuget.net10.0//:pin
```

Expected: `Wrote nuget_resolve.json. ...`

Voeg daarna `lock_file` toe aan de tag. Old:

```python
    frameworks = ["net10.0"],
)
```

New:

```python
    frameworks = ["net10.0"],
    lock_file = "//:nuget_resolve.json",
)
```

Verify: `bazel build //...` → `INFO: Build completed successfully`.

- [x] **Step 4: Write the repin test script**

Create `e2e/nuget_resolve_pinning/test.sh`:

```bash
#!/usr/bin/env bash
# Proves the repin flow:
#  1. a lock file whose input hash no longer matches the tag fails the build
#     with the repin instructions;
#  2. `REPIN=1 bazel run @nuget.net10.0//:pin` refreshes the lock file;
#  3. the build succeeds again.
# Restores MODULE.bazel and nuget_resolve.json on exit.
set -euo pipefail
cd "$(dirname "$0")"

cleanup() {
  git checkout -- MODULE.bazel MODULE.bazel.lock nuget_resolve.json
  rm -f MODULE.bazel.bak build.log
}
trap cleanup EXIT

echo "--- baseline: the pinned build succeeds"
bazel build //...

echo "--- make the lock stale: add Serilog to the packages"
sed -i.bak 's|"Newtonsoft.Json": "13.0.3"|"Newtonsoft.Json": "13.0.3",\n        "Serilog": "4.0.0"|' MODULE.bazel
rm -f MODULE.bazel.bak

echo "--- the build must now fail with the repin instructions"
if bazel build //... 2> build.log; then
  echo "FAIL: expected the build to fail with a stale lock file" >&2
  exit 1
fi
grep -q "REPIN=1 bazel run @nuget.net10.0//:pin" build.log || {
  echo "FAIL: the failure did not name the repin command" >&2
  cat build.log >&2
  exit 1
}

echo "--- repin"
REPIN=1 bazel run @nuget.net10.0//:pin

echo "--- the lock file now contains Serilog and the build succeeds"
grep -q '"Serilog"' nuget_resolve.json
bazel build //...

echo "PASS"
```

Maak het uitvoerbaar: `chmod +x e2e/nuget_resolve_pinning/test.sh`.

- [x] **Step 5: Run the script**

Run: `e2e/nuget_resolve_pinning/test.sh`
Expected: eindigt met `PASS`; daarna is de working tree schoon (`git status --short e2e/nuget_resolve_pinning` toont alleen de nieuwe, nog te committen bestanden).

- [x] **Step 6: Commit**

```bash
git add e2e/nuget_resolve_pinning
git commit -m "Add nuget.resolve pinning/repin e2e module"
```

### Task 16: examples/nuget_resolve — het voorbeeld

Een kleine C#-app die Serilog met de console-sink gebruikt, met ingecheckt `nuget_resolve.json`, opgenomen in `examples/MODULE.bazel`. De tag heet `nuget_resolve` (niet `nuget`): Task 18 voegt in dezelfde module een tweede resolve-tag met `name = "nuget"` toe voor `gazelle_csharp`, en namen moeten uniek zijn.

**Files:**
- Create: `examples/nuget_resolve/BUILD.bazel`
- Create: `examples/nuget_resolve/Program.cs`
- Create: `examples/nuget_resolve/nuget_resolve.json` (gegenereerd via de pin-flow)
- Modify: `examples/MODULE.bazel`

- [x] **Step 1: Add the resolve tag (nog zonder lock_file)**

In `examples/MODULE.bazel`. Old:

```python
use_repo(paket_example, "paket.main", "paket.othergroup")
```

New:

```python
use_repo(paket_example, "paket.main", "paket.othergroup")

# nuget.resolve for //nuget_resolve: transitive resolution with a checked-in
# nuget_resolve.json. The tag is named after the example; the gazelle_csharp
# example below uses its own tag named "nuget".
nuget = use_extension("@rules_dotnet//dotnet:nuget.bzl", "nuget")
nuget.resolve(
    name = "nuget_resolve",
    packages = {
        "Serilog": "4.0.0",
        "Serilog.Sinks.Console": "6.0.0",
    },
    frameworks = ["net10.0"],
)
use_repo(nuget, "nuget_resolve.net10.0")
```

- [x] **Step 2: Create the example app**

Create `examples/nuget_resolve/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary")

csharp_binary(
    name = "nuget_resolve",
    srcs = ["Program.cs"],
    target_frameworks = ["net10.0"],
    deps = [
        "@nuget_resolve.net10.0//serilog",
        "@nuget_resolve.net10.0//serilog.sinks.console",
    ],
)
```

Create `examples/nuget_resolve/Program.cs`:

```csharp
using Serilog;

public static class Program
{
    public static void Main()
    {
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Debug()
            .WriteTo.Console()
            .CreateLogger();
        Log.Information("Hello from {Example}", "nuget_resolve");
        Log.CloseAndFlush();
    }
}
```

- [x] **Step 3: Generate the lock file via the pin flow**

Run (vanuit `examples/`): `bazel run @nuget_resolve.net10.0//:pin`
Expected: `Wrote nuget_resolve.json. Check it in and point the resolve tag at it with lock_file = "//:nuget_resolve.json".`

Verplaats het bestand naar de example-map en controleer de inhoud:

```bash
mv nuget_resolve.json nuget_resolve/nuget_resolve.json
python3 - <<'EOF'
import json
lock = json.load(open("nuget_resolve/nuget_resolve.json"))
assert lock["version"] == 1
assert isinstance(lock["inputHash"], str) and lock["inputHash"].isdigit()
pkgs = {p["id"]: p["version"] for p in lock["frameworks"]["net10.0"]["packages"]}
assert pkgs["Serilog"] == "4.0.0", pkgs
assert pkgs["Serilog.Sinks.Console"] == "6.0.0", pkgs
print("lock file OK:", len(pkgs), "packages")
EOF
```

Expected: `lock file OK: N packages` (N ≥ 2; de sink trekt transitief alleen Serilog mee, dus N == 2 is de verwachte uitkomst).

- [x] **Step 4: Pin the tag**

In `examples/MODULE.bazel`, voeg `lock_file` toe aan de `nuget_resolve`-tag. Old:

```python
nuget.resolve(
    name = "nuget_resolve",
    packages = {
        "Serilog": "4.0.0",
        "Serilog.Sinks.Console": "6.0.0",
    },
    frameworks = ["net10.0"],
)
```

New:

```python
nuget.resolve(
    name = "nuget_resolve",
    packages = {
        "Serilog": "4.0.0",
        "Serilog.Sinks.Console": "6.0.0",
    },
    frameworks = ["net10.0"],
    lock_file = "//nuget_resolve:nuget_resolve.json",
)
```

- [x] **Step 5: Build, run, and verify the pin is stable**

Run (vanuit `examples/`):

```bash
bazel run //nuget_resolve && bazel run @nuget_resolve.net10.0//:pin && git status --short nuget_resolve/
```

Expected: de app print een Serilog-logregel met `Hello from "nuget_resolve"`; het tweede commando schrijft hetzelfde bestand opnieuw — `git status` toont geen wijziging aan `nuget_resolve/nuget_resolve.json` (stabiel, deterministisch).

- [x] **Step 6: Commit**

```bash
git add examples/nuget_resolve examples/MODULE.bazel examples/MODULE.bazel.lock
git commit -m "Add the nuget_resolve example"
```

---

### Task 17: Gazelle — de NuGet-index leest nuget_resolve.json (TDD)

`dotnet/gazelle/private/nuget/nuget.go` leest voortaan `nuget_resolve.json` (package-id's uit `frameworks → * → packages`), en de default van de lockbestand-configuratie wordt `nuget_resolve.json`. Tests en testdata-fixtures migreren mee.

**Files:**
- Modify: `dotnet/gazelle/private/nuget/nuget.go`
- Modify: `dotnet/gazelle/private/nuget/nuget_test.go`
- Modify: `dotnet/gazelle/dotnetconfig/config.go`
- Modify: `dotnet/gazelle/dotnetconfig/config_test.go`
- Modify: `dotnet/gazelle/configure.go`
- Modify: `dotnet/gazelle/lang.go`
- Modify: `dotnet/gazelle/resolve_test.go`
- Modify: `dotnet/gazelle/testdata/nuget_dep/packages.lock.json` → `dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json`
- Modify: `dotnet/gazelle/testdata/*/expectedStderr.txt` (10 fixtures)

- [x] **Step 1: Update the failing Go tests first**

In `dotnet/gazelle/private/nuget/nuget_test.go`. Old:

```go
const testLock = `{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "Newtonsoft.Json": {
        "type": "Direct",
        "requested": "[13.0.3, )",
        "resolved": "13.0.3",
        "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
      },
      "Microsoft.Testing.Platform": {
        "type": "Transitive",
        "resolved": "1.4.3"
      }
    }
  }
}`

func writeLock(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "packages.lock.json")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}
```

New:

```go
const testLock = `{
  "version": 1,
  "inputHash": "737269301",
  "frameworks": {
    "net10.0": {
      "packages": [
        {
          "id": "Newtonsoft.Json",
          "version": "13.0.3",
          "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
          "urls": ["https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg"]
        },
        {
          "id": "Microsoft.Testing.Platform",
          "version": "1.4.3",
          "sha512": "sha512-AAAA",
          "urls": ["https://feed/microsoft.testing.platform.1.4.3.nupkg"]
        }
      ]
    }
  }
}`

func writeLock(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "nuget_resolve.json")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}
```

In dezelfde file, de ambiguïteitsfixture. Old:

```go
	lock := `{"version": 1, "dependencies": {"net10.0": {"Contoso.Widget": {"type": "Direct"}, "contoso.widget": {"type": "Direct"}}}}`
```

New:

```go
	lock := `{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [{"id": "Contoso.Widget"}, {"id": "contoso.widget"}]}}}`
```

In `dotnet/gazelle/resolve_test.go`. Old:

```go
	writeFile(t, dir, "packages.lock.json", `{"version": 1, "dependencies": {"net10.0": {"Newtonsoft.Json": {"type": "Direct", "resolved": "13.0.3"}}}}`)
	idx, err := nuget.LoadIndex(filepath.Join(dir, "packages.lock.json"))
```

New:

```go
	writeFile(t, dir, "nuget_resolve.json", `{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [{"id": "Newtonsoft.Json", "version": "13.0.3", "sha512": "sha512-AAAA", "urls": ["https://feed/newtonsoft.json.13.0.3.nupkg"]}]}}}`)
	idx, err := nuget.LoadIndex(filepath.Join(dir, "nuget_resolve.json"))
```

In `dotnet/gazelle/dotnetconfig/config_test.go`. Old:

```go
	if got := c.NugetLockFile(); got != "packages.lock.json" {
		t.Errorf("NugetLockFile() = %q, want %q", got, "packages.lock.json")
	}
```

New:

```go
	if got := c.NugetLockFile(); got != "nuget_resolve.json" {
		t.Errorf("NugetLockFile() = %q, want %q", got, "nuget_resolve.json")
	}
```

- [x] **Step 2: Run the Go tests to verify they fail**

Run: `bazel test //dotnet/gazelle/...`
Expected: FAIL — `//dotnet/gazelle/private/nuget:nuget_test` faalt (de parser leest nog `dependencies`), en `//dotnet/gazelle:gazelle_test` en `//dotnet/gazelle/dotnetconfig:dotnetconfig_test` falen op de gewijzigde verwachtingen.

- [x] **Step 3: Migrate the index and the defaults**

In `dotnet/gazelle/private/nuget/nuget.go`. Old:

```go
// Package nuget indexes the package IDs of a packages.lock.json file and
// resolves C# namespaces to package IDs by longest prefix match.
package nuget
```

New:

```go
// Package nuget indexes the package IDs of a nuget_resolve.json file and
// resolves C# namespaces to package IDs by longest prefix match.
package nuget
```

Old:

```go
// lockFile mirrors the relevant structure of packages.lock.json:
// dependencies -> target framework -> package ID -> dependency entry.
// Only the package IDs (the map keys) are used.
type lockFile struct {
	Dependencies map[string]map[string]json.RawMessage `json:"dependencies"`
}
```

New:

```go
// lockFile mirrors the relevant structure of nuget_resolve.json:
// frameworks -> target framework -> packages -> package entries.
// Only the package IDs are used.
type lockFile struct {
	Frameworks map[string]struct {
		Packages []struct {
			ID string `json:"id"`
		} `json:"packages"`
	} `json:"frameworks"`
}
```

Old:

```go
// Index resolves namespaces to NuGet package IDs. A nil *Index is valid and
// resolves nothing (used when no packages.lock.json exists).
```

New:

```go
// Index resolves namespaces to NuGet package IDs. A nil *Index is valid and
// resolves nothing (used when no nuget_resolve.json exists).
```

Old:

```go
// LoadIndex reads packages.lock.json from path.
```

New:

```go
// LoadIndex reads nuget_resolve.json from path.
```

Old:

```go
	idx := &Index{ids: map[string][]string{}}
	for _, deps := range lf.Dependencies {
		for id := range deps {
			lower := strings.ToLower(id)
			idx.ids[lower] = appendUnique(idx.ids[lower], id)
		}
	}
	return idx, nil
}
```

New:

```go
	idx := &Index{ids: map[string][]string{}}
	for _, group := range lf.Frameworks {
		for _, pkg := range group.Packages {
			lower := strings.ToLower(pkg.ID)
			idx.ids[lower] = appendUnique(idx.ids[lower], pkg.ID)
		}
	}
	return idx, nil
}
```

In `dotnet/gazelle/dotnetconfig/config.go`. Old:

```go
	nugetLockFile:     "packages.lock.json",
```

New:

```go
	nugetLockFile:     "nuget_resolve.json",
```

Old:

```go
// NugetLockFile returns the packages.lock.json path relative to the repo root.
func (c *Config) NugetLockFile() string { return c.nugetLockFile }

// SetNugetLockFile sets the packages.lock.json path relative to the repo root.
func (c *Config) SetNugetLockFile(v string) { c.nugetLockFile = v }
```

New:

```go
// NugetLockFile returns the nuget_resolve.json path relative to the repo root.
func (c *Config) NugetLockFile() string { return c.nugetLockFile }

// SetNugetLockFile sets the nuget_resolve.json path relative to the repo root.
func (c *Config) SetNugetLockFile(v string) { c.nugetLockFile = v }
```

In `dotnet/gazelle/configure.go`. Old:

```go
	fs.StringVar(&cr.nugetLockFile, "dotnet_nuget_lock_file", "packages.lock.json",
		"Path of the packages.lock.json file, relative to the repository root.")
```

New:

```go
	fs.StringVar(&cr.nugetLockFile, "dotnet_nuget_lock_file", "nuget_resolve.json",
		"Path of the nuget_resolve.json file, relative to the repository root.")
```

Old:

```go
			log.Printf("no packages.lock.json at %s; NuGet resolution is disabled", lockPath)
```

New:

```go
			log.Printf("no nuget_resolve.json at %s; NuGet resolution is disabled", lockPath)
```

In `dotnet/gazelle/lang.go`. Old:

```go
	// nugetIndex resolves namespaces to NuGet package IDs. It is loaded once
	// from packages.lock.json during Configure of the repository root and is
	// nil when the file does not exist.
```

New:

```go
	// nugetIndex resolves namespaces to NuGet package IDs. It is loaded once
	// from nuget_resolve.json during Configure of the repository root and is
	// nil when the file does not exist.
```

- [x] **Step 4: Run the Go tests to verify they pass**

Run: `bazel test //dotnet/gazelle/private/nuget:nuget_test //dotnet/gazelle:gazelle_test //dotnet/gazelle/dotnetconfig:dotnetconfig_test`
Expected: PASS.

- [x] **Step 5: Migrate the gazelle_generation_test fixtures**

Hernoem de lockfile-fixture van `nuget_dep` en herschrijf hem naar het nieuwe formaat:

```bash
git mv dotnet/gazelle/testdata/nuget_dep/packages.lock.json dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json
```

Vervang de inhoud van `dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json` door:

```json
{
  "version": 1,
  "inputHash": "737269301",
  "frameworks": {
    "net10.0": {
      "packages": [
        {
          "id": "Newtonsoft.Json",
          "version": "13.0.3",
          "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
          "urls": [
            "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg"
          ]
        }
      ]
    }
  }
}
```

De tien fixtures zonder lockbestand loggen de ontbrekende-default-melding; werk die bij met:

```bash
sed -i 's|no packages.lock.json at %WORKSPACEPATH%/packages.lock.json|no nuget_resolve.json at %WORKSPACEPATH%/nuget_resolve.json|' dotnet/gazelle/testdata/*/expectedStderr.txt
```

Verify:

```bash
grep -rln "packages.lock.json" dotnet/gazelle
```

Expected: geen output — niets in `dotnet/gazelle` verwijst meer naar het oude formaat.

- [x] **Step 6: Run the full gazelle test suite**

Run: `bazel test //dotnet/gazelle/...`
Expected: PASS — inclusief alle `gazelle_generation_test`s onder `//dotnet/gazelle/testdata`.

- [x] **Step 7: Commit**

```bash
git add dotnet/gazelle
git commit -m "Read nuget_resolve.json in the Gazelle NuGet index"
```

---

### Task 18: Migratie examples/gazelle_csharp naar nuget.resolve

Vervangt de `packages_lock`-tag door `nuget.resolve` met een via de pin-flow gegenereerd `gazelle_csharp/nuget_resolve.json`. De gegenereerde labels (`@nuget.net10.0//newtonsoft.json`) blijven identiek, dus de BUILD-bestanden van het voorbeeld veranderen niet.

**Files:**
- Modify: `examples/MODULE.bazel`
- Modify: `examples/gazelle_csharp/BUILD.bazel`
- Create: `examples/gazelle_csharp/nuget_resolve.json` (gegenereerd via de pin-flow)
- Delete: `examples/gazelle_csharp/packages.lock.json`

- [x] **Step 1: Replace the packages_lock block (nog zonder lock_file)**

In `examples/MODULE.bazel`. Old:

```python
packages_lock = use_extension("@rules_dotnet//dotnet:packages_lock.bzl", "packages_lock")
packages_lock.parse(lock = "//gazelle_csharp:packages.lock.json")
use_repo(packages_lock, "nuget.net10.0")
```

New (hergebruik de `nuget`-proxy uit Task 16 — een tweede tag op dezelfde extensie):

```python
# gazelle_csharp resolves its NuGet dependency with nuget.resolve; the Gazelle
# extension indexes the same nuget_resolve.json to map namespaces to packages.
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
    },
    frameworks = ["net10.0"],
)
use_repo(nuget, "nuget.net10.0")
```

- [x] **Step 2: Generate the lock file via the pin flow**

Run (vanuit `examples/`):

```bash
bazel run @nuget.net10.0//:pin
mv nuget_resolve.json gazelle_csharp/nuget_resolve.json
```

Expected: `Wrote nuget_resolve.json. Check it in and point the resolve tag at it with lock_file = "//:nuget_resolve.json".` en daarna staat het bestand op `gazelle_csharp/nuget_resolve.json`. Controleer:

```bash
python3 - <<'EOF'
import json
lock = json.load(open("gazelle_csharp/nuget_resolve.json"))
pkgs = {p["id"]: p["version"] for p in lock["frameworks"]["net10.0"]["packages"]}
assert pkgs == {"Newtonsoft.Json": "13.0.3"}, pkgs
print("lock file OK")
EOF
```

Expected: `lock file OK`.

- [x] **Step 3: Pin the tag en verwijder packages.lock.json**

In `examples/MODULE.bazel`, voeg `lock_file` toe aan de tag met `name = "nuget"`. Old:

```python
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
    },
    frameworks = ["net10.0"],
)
```

New:

```python
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
    },
    frameworks = ["net10.0"],
    lock_file = "//gazelle_csharp:nuget_resolve.json",
)
```

Verwijder het oude lockbestand:

```bash
git rm examples/gazelle_csharp/packages.lock.json
```

- [x] **Step 4: Point the gazelle target at the new lock file**

In `examples/gazelle_csharp/BUILD.bazel`. Old:

```python
gazelle(
    name = "gazelle",
    extra_args = [
        "-dotnet_nuget_lock_file=gazelle_csharp/packages.lock.json",
        "gazelle_csharp",
    ],
    gazelle = "gazelle_bin",
)
```

New:

```python
gazelle(
    name = "gazelle",
    extra_args = [
        "-dotnet_nuget_lock_file=gazelle_csharp/nuget_resolve.json",
        "gazelle_csharp",
    ],
    gazelle = "gazelle_bin",
)
```

- [x] **Step 5: Verify gazelle produces no diff and everything builds**

Run (vanuit `examples/`):

```bash
bazel run //gazelle_csharp:gazelle && git status --short gazelle_csharp/ && bazel build //gazelle_csharp/... && bazel test //gazelle_csharp/...
```

Expected: gazelle draait zonder wijzigingen (`git status` toont geen gewijzigde BUILD-bestanden onder `gazelle_csharp/`); build en test slagen.

- [x] **Step 6: Commit**

```bash
git add examples/MODULE.bazel examples/MODULE.bazel.lock examples/gazelle_csharp
git commit -m "Migrate gazelle_csharp to nuget.resolve"
```

---

### Task 19: Migratie e2e/gazelle_net10.0 naar nuget.resolve

Zelfde migratie als Task 18, maar deze module gebruikt de default lockbestandsnaam (geen `-dotnet_nuget_lock_file`-flag), dus het lockbestand hoort in de module-root als `nuget_resolve.json`.

**Files:**
- Modify: `e2e/gazelle_net10.0/MODULE.bazel`
- Create: `e2e/gazelle_net10.0/nuget_resolve.json` (gegenereerd via de pin-flow)
- Delete: `e2e/gazelle_net10.0/packages.lock.json`

- [x] **Step 1: Replace the packages_lock block (nog zonder lock_file)**

In `e2e/gazelle_net10.0/MODULE.bazel`. Old:

```python
packages_lock = use_extension("@rules_dotnet//dotnet:packages_lock.bzl", "packages_lock")
packages_lock.parse(lock = "//:packages.lock.json")
use_repo(packages_lock, "nuget.net10.0")
```

New:

```python
nuget = use_extension("@rules_dotnet//dotnet:nuget.bzl", "nuget")
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
    },
    frameworks = ["net10.0"],
)
use_repo(nuget, "nuget.net10.0")
```

- [x] **Step 2: Generate the lock file via the pin flow**

Run (vanuit `e2e/gazelle_net10.0/`): `bazel run @nuget.net10.0//:pin`
Expected: `Wrote nuget_resolve.json. ...` — het bestand staat direct op de juiste plek (de module-root is de default-bestemming). Controleer:

```bash
python3 - <<'EOF'
import json
lock = json.load(open("nuget_resolve.json"))
pkgs = {p["id"]: p["version"] for p in lock["frameworks"]["net10.0"]["packages"]}
assert pkgs == {"Newtonsoft.Json": "13.0.3"}, pkgs
print("lock file OK")
EOF
```

Expected: `lock file OK`.

- [x] **Step 3: Pin the tag en verwijder packages.lock.json**

In `e2e/gazelle_net10.0/MODULE.bazel`. Old:

```python
    frameworks = ["net10.0"],
)
use_repo(nuget, "nuget.net10.0")
```

New:

```python
    frameworks = ["net10.0"],
    lock_file = "//:nuget_resolve.json",
)
use_repo(nuget, "nuget.net10.0")
```

Verwijder het oude lockbestand:

```bash
git rm e2e/gazelle_net10.0/packages.lock.json
```

- [x] **Step 4: Verify gazelle produces no diff and everything builds**

Run (vanuit `e2e/gazelle_net10.0/`):

```bash
bazel run //:gazelle && git status --short . && bazel build //... && bazel test //...
```

Expected: gazelle draait zonder wijzigingen aan BUILD-bestanden; `git status` toont alleen de wijzigingen van deze task (`MODULE.bazel`, `MODULE.bazel.lock`, het nieuwe `nuget_resolve.json`, het verwijderde `packages.lock.json`); build en test slagen.

- [x] **Step 5: Commit**

```bash
git add e2e/gazelle_net10.0
git commit -m "Migrate e2e gazelle_net10.0 to nuget.resolve"
```

---

### Task 20: Verwijdering van packages_lock

Alle gebruikers zijn gemigreerd (Tasks 18–19) of verdwijnen mee (`examples/packages_json`, `e2e/net10.0_packages_lock`). Dit verwijdert de inhoud van commits `474a2cf`, `ada755c`, `d312390` en `bd337ce`.

**Files:**
- Delete: `dotnet/packages_lock.bzl`
- Delete: `dotnet/private/packages_lock/` (`BUILD.bazel`, `extension.bzl`, `lock.bzl`)
- Delete: `dotnet/private/tests/packages_lock/` (`BUILD.bazel`, `extension_test.bzl`, `lock_test.bzl`)
- Delete: `e2e/net10.0_packages_lock/`
- Delete: `examples/packages_json/`
- Modify: `dotnet/BUILD.bazel`

- [x] **Step 1: Delete the files**

```bash
git rm dotnet/packages_lock.bzl
git rm -r dotnet/private/packages_lock dotnet/private/tests/packages_lock e2e/net10.0_packages_lock examples/packages_json
```

- [x] **Step 2: Remove the bzl_library from dotnet/BUILD.bazel**

Old:

```python
bzl_library(
    name = "packages_lock",
    srcs = ["packages_lock.bzl"],
    visibility = ["//visibility:public"],
    deps = ["//dotnet/private/packages_lock:extension"],
)

exports_files(["defs.bzl"])
```

New:

```python
exports_files(["defs.bzl"])
```

- [x] **Step 3: Verify no references remain**

```bash
grep -rn "packages_lock" dotnet examples e2e MODULE.bazel BUILD.bazel 2>/dev/null | grep -v bazel-out
```

Expected: geen output. (De docs onder `docs/superpowers/` noemen `packages_lock` historisch; die blijven.)

- [x] **Step 4: Verify the repo, the examples and the migrated e2e module still build**

Run (vanuit de repo-root):

```bash
bazel build //dotnet/... && bazel test //dotnet/private/tests/... //dotnet/gazelle/...
```

Expected: alles PASS.

Run (vanuit `examples/`): `bazel build //...`
Expected: `INFO: Build completed successfully` (`examples/packages_json` was een eigen geneste module en wordt door deze build nooit meegenomen; verwijdering is dus onzichtbaar voor de examples-build).

Run (vanuit `e2e/gazelle_net10.0/`): `bazel build //... && bazel test //...`
Expected: alles slaagt.

- [x] **Step 5: Commit**

```bash
git add -A dotnet/packages_lock.bzl dotnet/private/packages_lock dotnet/private/tests/packages_lock e2e/net10.0_packages_lock examples/packages_json dotnet/BUILD.bazel
git commit -m "Remove the packages_lock module extension"
```

---

### Task 21: CI — nieuwe e2e-modules in .bazelci/presubmit.yml

Elke e2e-map is een eigen bazel-module en wordt door de `e2e`-taskmatrix gebouwd en getest. Elke module bouwt `nuget_resolver_tool` vanuit een schone output base (eigen working directory), wat tevens de risico-mitigatie "CI-test bouwt de tool vanuit een schone repository-cache" dekt. `e2e/nuget_resolve_pinning/test.sh` draait bewust niet in CI (geneste Bazel in een test kan niet); CI bouwt die module in zijn consistente uitgangstoestand.

**Files:**
- Modify: `.bazelci/presubmit.yml`

- [x] **Step 1: Add the four modules to the e2e matrix**

In `.bazelci/presubmit.yml`. Old:

```yaml
  e2e_working_directory: ["e2e/net8.0", "e2e/net9.0", "e2e/net10.0", "e2e/web_sdk", "e2e/gazelle_net10.0"]
```

New:

```yaml
  e2e_working_directory: ["e2e/net8.0", "e2e/net9.0", "e2e/net10.0", "e2e/web_sdk", "e2e/gazelle_net10.0", "e2e/nuget_resolve_basic", "e2e/nuget_resolve_transitive", "e2e/nuget_resolve_multi_framework", "e2e/nuget_resolve_pinning"]
```

- [x] **Step 2: Verify the YAML parses and lists the new modules**

```bash
python3 -c "
import yaml
cfg = yaml.safe_load(open('.bazelci/presubmit.yml'))
dirs = cfg['matrix']['e2e_working_directory']
for d in ['e2e/nuget_resolve_basic', 'e2e/nuget_resolve_transitive', 'e2e/nuget_resolve_multi_framework', 'e2e/nuget_resolve_pinning']:
    assert d in dirs, d
print('presubmit.yml OK:', len(dirs), 'e2e modules')
"
```

Expected: `presubmit.yml OK: 9 e2e modules`.

- [x] **Step 3: Commit**

```bash
git add .bazelci/presubmit.yml
git commit -m "Run the nuget_resolve e2e modules in CI"
```

---

### Task 22: Eindvalidatie

Volledige verificatie van alle oppervlakken die dit plan raakt. Geen nieuwe bestanden; er is niets te committen.

- [x] **Step 1: Root repository**

Run (vanuit de repo-root): `bazel test //...`
Expected: alles PASS, inclusief `//dotnet/private/tests/nuget_resolve/...`, `//dotnet/private/nuget_resolve:tool_version_test`, `//tools/nuget_resolver/tests:nuget_resolver_test` en `//dotnet/gazelle/...`.

- [x] **Step 2: Examples**

Run (vanuit `examples/`): `bazel build //... && bazel test //...`
Expected: alles slaagt, inclusief `//nuget_resolve` en `//gazelle_csharp/...`.

- [x] **Step 3: e2e-modules**

Run, vanuit elke map:

```bash
for d in e2e/gazelle_net10.0 e2e/nuget_resolve_basic e2e/nuget_resolve_transitive e2e/nuget_resolve_multi_framework e2e/nuget_resolve_pinning; do
  (cd "$d" && bazel build //... && bazel test //...) || exit 1
done
```

Expected: elke module bouwt en test groen.

- [x] **Step 4: De repin-flow**

Run: `e2e/nuget_resolve_pinning/test.sh`
Expected: eindigt met `PASS`; `git status --short` toont daarna geen gewijzigde bestanden.

- [x] **Step 5: Schone-fetch-controle van de tool-build (risicomitigatie 2)**

Run (vanuit `e2e/nuget_resolve_transitive/`):

```bash
bazel clean --expunge && bazel build //...
```

Expected: `INFO: Build completed successfully` — de volledige keten (tool-build uit gepinde folder-feed, resolutie, hubs) werkt vanuit een volledig schone repository-cache.
