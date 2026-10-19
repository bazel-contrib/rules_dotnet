# Design: Gazelle-extensie voor rules_dotnet (C#)

Datum: 2026-10-14
Status: goedgekeurd door gebruiker (met toevoeging examples/e2e)

## Doel

Een [Gazelle](https://github.com/bazel-contrib/bazel-gazelle)-extensie voor
rules_dotnet die BUILD-files genereert en onderhoudt voor C#-broncode, naar
het voorbeeld van de `java/gazelle`-extensie in
[rules_jvm](https://github.com/bazel-contrib/rules_jvm).

## Scope

- **Alleen C#** in de eerste versie. F# komt later (vereist ordering van
  `srcs` en extra parserlogica).
- **Bronbestanden zijn de source of truth.** `.csproj`-bestanden worden niet
  gelezen; de extensie parseert `.cs`-bestanden (Gazelle-filosofie, zoals
  rules_jvm).
- NuGet-afhankelijkheden resolven via **`packages.lock.json`** (de nieuwe
  `packages_lock`-module-extensie in deze repo), niet via Paket.
- Test-frameworks: NUnit, xUnit én MSTest worden gedetecteerd.

## Architectuur

Een nieuwe Go-module `dotnet/gazelle` in de rules_dotnet-repo die Gazelle's
`language.Language`-interface implementeert — dezelfde opbouw als
`java/gazelle` in rules_jvm:

- `lang.go` — registratie, `Kinds()`/`Loads()` voor `csharp_library`,
  `csharp_binary`, `csharp_test`, `csharp_nunit_test`, `csharp_xunit_test`,
  `csharp_mstest_test`.
- `configure.go` + `dotnetconfig/` — directives en CLI-flags.
- `generate.go` — BUILD-regels genereren per directory.
- `resolve.go` — imports mappen naar Bazel-labels.
- `private/parser/` — lichtgewicht C#-parser (Go).
- `private/nuget/` — index van `packages.lock.json` voor namespace→package.

Gebruikers activeren de extensie via:

```starlark
gazelle_binary(
    name = "gazelle",
    languages = ["@rules_dotnet//dotnet/gazelle"],
)
```

De repo krijgt er `go.mod`/`go.sum` en dev-dependencies op `rules_go` en
`bazel_gazelle` bij (rules_dotnet heeft nu nog geen Go-code; gazelle wordt nu
alleen als dev-dependency gebruikt voor bzl-bestanden).

### Parser-aanpak

Lichtgewicht Go-parser (regex/lexer), geen Roslyn of .NET-runtime nodig
tijdens een Gazelle-run. Resolutie gebeurt op package-niveau. De parser- en
resolver-interfaces worden zo ontworpen dat een Roslyn-gebaseerde backend of
assembly-indexering later kan worden toegevoegd (hetzelfde evolutiepad als
rules_jvm: package-niveau eerst, class-level pas veel later).

## Fase 0 — dedicated test-rules in rules_dotnet

xUnit en MSTest hebben nog geen dedicated rules. Analoog aan
`csharp_nunit_test` (macro rond `csharp_test` + framework-deps +
entry-point shim) komen er:

- **`csharp_xunit_test`** — voegt `xunit`-deps en een entry-point shim toe.
  xUnit v3 is self-executing; de shim is minimaal.
- **`csharp_mstest_test`** — voegt `mstest.testframework`-deps en een
  Microsoft.Testing.Platform-gebaseerde shim toe.

Beide in `dotnet/private/rules/csharp/`, geëxporteerd via `dotnet/defs.bzl`,
met eigen unittests naast de bestaande rule-tests.

## C#-parser

Per `.cs`-bestand extraheert de parser:

- `namespace`-declaratie (file-scoped én block-scoped).
- `using`-directives (inclusief `using static`, aliases en `global using`).
- Test-markeringen:
  - NUnit: `using NUnit.Framework`, `[Test]`, `[TestFixture]`
  - xUnit: `using Xunit`, `[Fact]`, `[Theory]`
  - MSTest: `using Microsoft.VisualStudio.TestTools.UnitTesting`,
    `[TestClass]`, `[TestMethod]`
- Entry-point: top-level statements of `static void Main` → binary-kandidaat.

## Generatie

Per directory met `.cs`-bestanden:

- Productie-bestanden → `csharp_library` (naam = genormaliseerde
  directory-naam).
- Test-bestanden, gegroepeerd per gedetecteerd framework →
  `csharp_nunit_test` / `csharp_xunit_test` / `csharp_mstest_test`, met dep
  op de sibling-library. De library krijgt `internals_visible_to` naar de
  test-target(s).
- Entry-point-bestand zonder tests → `csharp_binary`.
- `target_frameworks`, `project_sdk` en `visibility` worden via directives
  gezet.
- Gazelle's merge-semantiek geldt: handmatige attrs en `# keep` blijven
  behouden bij hergeneratie.

## Resolutie

- **Workspace-intern**: elke gegenereerde `csharp_library` indexeert de
  namespaces van zijn bronnen. Een `using Foo.Bar` in een andere directory
  resolveert via Gazelle's standaard resolve-index naar die target.
- **NuGet**: bij `Configure` wordt `packages.lock.json` gelezen en wordt een
  set bekende package-ids opgebouwd. Een `using`-namespace mapt via
  langste-prefix-match op package-id
  (`Newtonsoft.Json.Linq` → `Newtonsoft.Json` → `@nuget.net10.0//newtonsoft.json`).
  Label-vorm: `@<repo_prefix><tfm>//<package-id-lowercase>`; repo-prefix en
  tfm via directives.
- **Overrides**: `# gazelle:dotnet_resolve <namespace> <label>`.
- Onbekende imports: configureerbaar warn of fail (default warn).

## Directives

| Directive | Betekenis |
|---|---|
| `dotnet_target_frameworks` | TFM(s) voor gegenereerde targets (verplicht op root) |
| `dotnet_nuget_repo_prefix` | Repo-prefix voor NuGet-labels (default `nuget.`) |
| `dotnet_resolve` | Handmatige namespace→label override |
| `dotnet_test_framework` | Forceer test-framework per subtree (`nunit`/`xunit`/`mstest`) |
| `dotnet_generate_binary` | Binary-generatie aan/uit |

## Testing

- Go-unittests per component (parser, nuget-index, generate, resolve).
- Gazelle's integratie-testrunner met `testdata/`-cases per scenario:
  library, test per framework, binary, NuGet-dep, override-directive —
  hetzelfde patroon als rules_jvm.

## Examples en e2e

- **`examples/gazelle_csharp`**: een kleine multi-directory C#-solution
  (library + binary + tests in NUnit én xUnit) met `packages.lock.json`,
  `gazelle_binary` in `MODULE.bazel`/`BUILD.bazel` en gegenereerde
  BUILD-files. Demonstreert de `bazel run //:gazelle`-workflow.
- **`e2e/gazelle_<tfm>`**: een nieuwe e2e-module (zelfde opzet als
  `e2e/net10.0_packages_lock`: eigen `MODULE.bazel`, `local_path_override`
  naar rules_dotnet, `packages_lock.parse`) die Gazelle draait op een
  fixture-solution en vervolgens `bazel build //...` en `bazel test //...`
  uitvoert met de gegenereerde BUILD-files.

## Error handling

- Parse-fout in één bestand stopt de run niet; het bestand wordt overgeslagen
  met een warning.
- Ambigue prefix-match (twee packages matchen even lang) → fout met
  suggestie om `dotnet_resolve` te gebruiken.
- Missende `dotnet_target_frameworks` op de root → duidelijke foutmelding.
