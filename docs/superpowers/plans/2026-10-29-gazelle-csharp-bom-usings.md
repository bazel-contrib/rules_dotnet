# Gazelle C# BOM Usings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-subagent-driven-development (recommended) or superpowers-executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zorg dat Gazelle een eerste C#-`using` na een UTF-8-BOM herkent en bewijs met parser- en NuGet-goldenregressietests dat de dependency behouden blijft, terwijl file-scoped namespaces gevolgd door usings onveranderd werken.

**Architecture:** Voeg eerst synthetische file-scoped behoudstests en vervolgens rood-verwachte BOM-regressietests toe aan de bestaande parser- en `nuget_dep`-golden. Normaliseer daarna uitsluitend in `parser.Parse` exact één optionele U+FEFF-prefix met `strings.TrimPrefix` vóór `blankCommentsAndStrings`; `ParseFile`, matching, dependencyresolutie en BUILD-generatie blijven ongewijzigd.

**Tech Stack:** Go met de bestaande `testing`-tabeltests, C#-bronfixtures, JSON NuGet-index, Bazel `gazelle_generation_test`, Starlark BUILD-output.

**Spec:** `docs/superpowers/specs/2026-10-29-gazelle-csharp-bom-usings-design.md` (goedgekeurd; dit plan verandert de scope niet).

---

## Uitvoeringscontract voor iedere implementer

Werk vanuit `/home/jhobert/Projects/Gazelle/rules_dotnet`. Gebruik voor iedere Go-aanroep exact de omgeving `CGO_ENABLED=0 GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache`, zoals in de commando's hieronder uitgeschreven. Voer geen `gazelle`- of `buildifier`-schrijfacties uit en wijzig geen resolver, regexes, `strings.TrimSpace`, API's of niet-genoemde fixtures.

De taken zijn bewust in TDD-volgorde geordend. Tasks 1 en 2 eindigen groen. Task 3 commit uitsluitend een unittest waarvan de BOM-subtest op de ongefixeerde parser rood is en de file-scoped controle groen blijft. Task 4 commit uitsluitend een golden waarvan de Store-BOM-vergelijking op de ongefixeerde parser rood is. Die rode tussenresultaten zijn het vereiste regressiebewijs, geen fout in de testuitvoering. Pas Task 5 mag `parser.go` wijzigen en moet alle relevante controles groen maken.

Voer aan het einde van iedere task een implementer-side review uit: vergelijk de feitelijke diff met de exacte old/new-content van die task, controleer bytes waar gevraagd, en corrigeer alleen binnen de genoemde bestanden. Herhaal na iedere autocorrectie de relevante verificatie voordat je commit. Als een BOM-test onverwacht slaagt vóór Task 5, of een file-scoped controle daar juist faalt, stop dan met commit en corrigeer de testcase naar de gespecificeerde inhoud; verander niet de parser of verwachte dependency om de rode controle weg te werken.

Stage uitsluitend de expliciet genoemde bestanden. Laat ongerelateerde bestaande wijzigingen ongemoeid en neem ze nooit in een commit op. Als een te wijzigen bestand al onverwachte wijzigingen bevat waardoor een exacte old-string of byte-guard niet past, stop dan en rapporteer de botsing in plaats van de inhoud te overschrijven. Iedere commit gebruikt een imperative message in bestaande repositorystijl, zonder conventieprefix.

## Bestandskaart

| Bestand | Wijziging en verantwoordelijkheid |
|---|---|
| `dotnet/gazelle/private/parser/parser_test.go` | Task 1 voegt de file-scoped behoudstest toe; Task 3 voegt de BOM/block-namespace-regressietest toe |
| `dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json` | Task 2 voegt synthetische MessagePack-metadata aan de bestaande `net10.0`-packagelijst toe; alleen de id wordt voor resolutie gebruikt |
| `dotnet/gazelle/testdata/nuget_dep/src/FileScoped/FileScoped.cs` | Task 2 maakt een nieuwe synthetische file-scoped namespace gevolgd door `using MessagePack;` |
| `dotnet/gazelle/testdata/nuget_dep/src/FileScoped/BUILD.out` | Task 2 verwacht een `filescoped`-library met de MessagePack-dependency |
| `dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs` | Task 4 schrijft exact `EF BB BF` aan bytepositie nul en maakt een kleine synthetische BOM/block-namespacefixture |
| `dotnet/gazelle/testdata/nuget_dep/src/Store/BUILD.out` | Task 4 verwacht de gesorteerde MessagePack- en Newtonsoft.Json-labels |
| `dotnet/gazelle/private/parser/parser.go` | Task 5 verwijdert exact één optionele BOM vóór alle bestaande parsing |

De root-`BUILD.in`/`BUILD.out`, bestaande resolvercode, andere goldenfixtures en `SignalRServerBuilderExtensions.cs` blijven ongewijzigd. Geen enkele test of fixture neemt inhoud van dat laatste bestand over.

---

### Task 1: Voeg de file-scoped parserbehoudstest toe

**Files:**
- Modify: `dotnet/gazelle/private/parser/parser_test.go`
- Test: `dotnet/gazelle/private/parser/parser_test.go`

- [x] **Step 1: Controleer de beginstatus van het testbestand**

Run:

```bash
git status --short -- dotnet/gazelle/private/parser/parser_test.go
```

Expected: geen uitvoer en exit 0. Als er wel uitvoer is, stop volgens het uitvoeringscontract in plaats van bestaande wijzigingen te overschrijven.

- [x] **Step 2: Voeg de file-scoped testcase toe**

Vervang in `dotnet/gazelle/private/parser/parser_test.go` exact deze old string:

```go
		{
			name:       "file-scoped namespace",
			src:        "using System;\n\nnamespace Foo.Bar;\n\npublic class C {}\n",
			wantNs:     "Foo.Bar",
			wantUsings: []Using{{Namespace: "System"}},
		},
		{
			name:       "block namespace with usings inside",
```

door deze new string:

```go
		{
			name:       "file-scoped namespace",
			src:        "using System;\n\nnamespace Foo.Bar;\n\npublic class C {}\n",
			wantNs:     "Foo.Bar",
			wantUsings: []Using{{Namespace: "System"}},
		},
		{
			name:       "file-scoped namespace followed by usings",
			src:        "namespace Fixture;\n\nusing MessagePack;\n\npublic class C {}\n",
			wantNs:     "Fixture",
			wantUsings: []Using{{Namespace: "MessagePack"}},
		},
		{
			name:       "block namespace with usings inside",
```

Formatteer alleen dit bestand:

```bash
gofmt -w dotnet/gazelle/private/parser/parser_test.go
```

Expected: `gofmt` is stil en exit 0. De nieuwe test gebruikt geen BOM en verwacht exact namespace `Fixture` en één using `MessagePack`.

- [x] **Step 3: Verifieer dat de file-scoped controle op de ongefixeerde parser slaagt**

Run:

```bash
CGO_ENABLED=0 GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache go test ./dotnet/gazelle/private/parser -run '^TestParseNamespacesAndUsings$/^file-scoped_namespace_followed_by_usings$' -v
```

Expected: exit 0 met deze sleutelregels; er is nog geen BOM-test in dit bestand:

```text
--- PASS: TestParseNamespacesAndUsings/file-scoped_namespace_followed_by_usings
PASS
ok  	github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/parser
```

- [x] **Step 4: Draai de volledige parser-unittests**

Run:

```bash
CGO_ENABLED=0 GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache go test ./dotnet/gazelle/private/parser
```

Expected: exit 0 en één `ok`-regel voor `github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/parser`, zonder `FAIL`.

- [x] **Step 5: Review, corrigeer binnen scope en commit alleen de behoudstest**

Run:

```bash
git diff --check
git status --short
git diff -- dotnet/gazelle/private/parser/parser_test.go
```

Expected: `git diff --check` is stil; de enige gewijzigde file is `dotnet/gazelle/private/parser/parser_test.go`; de diff bevat alleen de testcase `file-scoped namespace followed by usings`. Corrigeer afwijkingen alleen in dit bestand en herhaal Steps 2-5. Stage en commit daarna exact:

```bash
git add dotnet/gazelle/private/parser/parser_test.go
git diff --cached --check
git diff --cached --name-only
git commit -m "Add file-scoped C# using parser coverage"
```

Expected vóór de commit: `git diff --cached --name-only` toont uitsluitend `dotnet/gazelle/private/parser/parser_test.go`. Expected na de commit: een nieuwe commit met message `Add file-scoped C# using parser coverage`.

---

### Task 2: Voeg MessagePack en de groene file-scoped golden toe

**Files:**
- Modify: `dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json`
- Create: `dotnet/gazelle/testdata/nuget_dep/src/FileScoped/FileScoped.cs`
- Create: `dotnet/gazelle/testdata/nuget_dep/src/FileScoped/BUILD.out`
- Test: `dotnet/gazelle/testdata/nuget_dep`

- [x] **Step 1: Controleer de fixturebeginstatus en maak alleen de nieuwe directory**

Run:

```bash
git status --short -- dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json dotnet/gazelle/testdata/nuget_dep/src/FileScoped
test -d dotnet/gazelle/testdata/nuget_dep/src
mkdir -p dotnet/gazelle/testdata/nuget_dep/src/FileScoped
```

Expected: de statusopdracht geeft geen uitvoer; `test -d` en `mkdir -p` slagen met exit 0. Stop bij een bestaande onverwachte wijziging in plaats van die te overschrijven.

- [x] **Step 2: Voeg MessagePack aan de bestaande NuGet-index toe**

Vervang in `dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json` exact deze old string:

```json
        {
          "id": "Newtonsoft.Json",
          "version": "13.0.3",
          "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
          "urls": [
            "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg"
          ]
        }
```

door deze new string:

```json
        {
          "id": "MessagePack",
          "version": "3.1.4",
          "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
          "urls": [
            "https://api.nuget.org/v3-flatcontainer/messagepack/3.1.4/messagepack.3.1.4.nupkg"
          ]
        },
        {
          "id": "Newtonsoft.Json",
          "version": "13.0.3",
          "sha512": "sha512-HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ==",
          "urls": [
            "https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg"
          ]
        }
```

Dit is bewust synthetische fixturemetadata in de bestaande vorm; de golden downloadt niets en gebruikt voor de index alleen de package-id. Wijzig `inputHash`, frameworknaam en Newtonsoft.Json-metadata niet.

Valideer de JSON:

```bash
python3 -m json.tool dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json >/dev/null
```

Expected: geen uitvoer en exit 0.

- [x] **Step 3: Maak `FileScoped.cs` met exact deze volledige inhoud**

Bestand: `dotnet/gazelle/testdata/nuget_dep/src/FileScoped/FileScoped.cs`

```csharp
namespace FileScoped;

using MessagePack;

public class Packet
{
}
```

Het bestand eindigt met LF en bevat geen BOM, testmarkering, `Main` of top-level statement.

- [x] **Step 4: Maak `BUILD.out` met exact deze volledige inhoud**

Bestand: `dotnet/gazelle/testdata/nuget_dep/src/FileScoped/BUILD.out`

```starlark
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "filescoped",
    srcs = ["FileScoped.cs"],
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
    deps = ["@nuget.net10.0//messagepack"],
)
```

Het bestand eindigt met LF. Maak geen `BUILD.in` in deze directory en verander de root-`BUILD.in`/`BUILD.out` niet.

- [x] **Step 5: Bewijs dat de file-scoped golden vóór de BOM-fix slaagt**

Run:

```bash
bazel test //dotnet/gazelle/testdata:nuget_dep
```

Expected: exit 0 met `//dotnet/gazelle/testdata:nuget_dep   PASSED` en uiteindelijk `Executed 1 out of 1 test: 1 test passes.` (of dezelfde pass-samenvatting als Bazel de cache benoemt). De bestaande Store-golden en nieuwe FileScoped-golden slagen allebei op de nog ongefixeerde parser.

- [x] **Step 6: Review, corrigeer binnen scope en commit de groene golden**

Run:

```bash
git diff --check
git status --short
git diff -- dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json dotnet/gazelle/testdata/nuget_dep/src/FileScoped/FileScoped.cs dotnet/gazelle/testdata/nuget_dep/src/FileScoped/BUILD.out
```

Expected: alleen de drie genoemde fixturebestanden zijn nieuw/gewijzigd; `Store.cs`, `Store/BUILD.out` en `parser.go` zijn ongemoeid; `git diff --check` is stil. Review met name dat `FileScoped.cs` eerst de file-scoped namespace en daarna de using heeft. Corrigeer alleen deze drie bestanden en herhaal Steps 2-6 bij een afwijking. Stage en commit exact:

```bash
git add dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json dotnet/gazelle/testdata/nuget_dep/src/FileScoped/FileScoped.cs dotnet/gazelle/testdata/nuget_dep/src/FileScoped/BUILD.out
git diff --cached --check
git diff --cached --name-only
git diff --cached -- dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json dotnet/gazelle/testdata/nuget_dep/src/FileScoped/FileScoped.cs dotnet/gazelle/testdata/nuget_dep/src/FileScoped/BUILD.out
git commit -m "Add file-scoped NuGet golden coverage"
```

Expected vóór de commit: de staged namen zijn exact de drie genoemde bestanden en de staged diff toont ook de volledige inhoud van beide nieuwe bestanden, die exact overeenkomt met Steps 3 en 4. Corrigeer een afwijking vóór de commit en herhaal de golden en stagingcontrole. Expected na de commit: een nieuwe commit met message `Add file-scoped NuGet golden coverage`.

---

### Task 3: Voeg de rode BOM-parserregressietest toe

**Files:**
- Modify: `dotnet/gazelle/private/parser/parser_test.go`
- Test: `dotnet/gazelle/private/parser/parser_test.go`

- [x] **Step 1: Controleer dat alleen de beoogde testbasis aanwezig is**

Run:

```bash
git status --short -- dotnet/gazelle/private/parser/parser_test.go dotnet/gazelle/private/parser/parser.go
```

Expected: geen uitvoer en exit 0; Tasks 1 en 2 zijn gecommit en de parser is nog ongefixeerd.

- [x] **Step 2: Voeg de BOM/block-namespacecase toe zonder parserwijziging**

Vervang in `dotnet/gazelle/private/parser/parser_test.go` exact deze old string:

```go
		{
			name:       "file-scoped namespace followed by usings",
			src:        "namespace Fixture;\n\nusing MessagePack;\n\npublic class C {}\n",
			wantNs:     "Fixture",
			wantUsings: []Using{{Namespace: "MessagePack"}},
		},
		{
			name:       "block namespace with usings inside",
```

door deze new string:

```go
		{
			name:       "file-scoped namespace followed by usings",
			src:        "namespace Fixture;\n\nusing MessagePack;\n\npublic class C {}\n",
			wantNs:     "Fixture",
			wantUsings: []Using{{Namespace: "MessagePack"}},
		},
		{
			name:       "UTF-8 BOM with block namespace",
			src:        "\uFEFFusing MessagePack;\nusing Newtonsoft.Json;\n\nnamespace Store\n{\n    public class C {}\n}\n",
			wantNs:     "Store",
			wantUsings: []Using{{Namespace: "MessagePack"}, {Namespace: "Newtonsoft.Json"}},
		},
		{
			name:       "block namespace with usings inside",
```

Formatteer alleen de test:

```bash
gofmt -w dotnet/gazelle/private/parser/parser_test.go
```

Expected: `gofmt` is stil. De Go-string bevat de letterlijke escape `\uFEFF` uitsluitend aan het begin; de verwachte usinglijst heeft exact twee elementen in bronvolgorde.

- [x] **Step 3: Bewijs dat alleen de nieuwe BOM-controle rood is**

Run:

```bash
CGO_ENABLED=0 GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache go test ./dotnet/gazelle/private/parser -run '^TestParseNamespacesAndUsings$/^UTF-8_BOM_with_block_namespace$' -v
```

Expected: niet-nul exit met `--- FAIL: TestParseNamespacesAndUsings/UTF-8_BOM_with_block_namespace`. De assertie toont namespace `Store` als correct, maar de feitelijke usinglijst bevat alleen `Newtonsoft.Json`; de gewenste lijst begint met `MessagePack` gevolgd door `Newtonsoft.Json`. De fout mag geen parse-error zijn.

- [x] **Step 4: Herhaal de file-scoped controletest op dezelfde ongefixeerde parser**

Run:

```bash
CGO_ENABLED=0 GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache go test ./dotnet/gazelle/private/parser -run '^TestParseNamespacesAndUsings$/^file-scoped_namespace_followed_by_usings$' -v
```

Expected: exit 0 met `--- PASS: TestParseNamespacesAndUsings/file-scoped_namespace_followed_by_usings` en `PASS`. Zo blijft het BOM-regressiebewijs gescheiden van het bestaande file-scoped gedrag.

- [x] **Step 5: Review het rode bewijs en commit alleen de regressietest**

Run:

```bash
git diff --check
git status --short
git diff -- dotnet/gazelle/private/parser/parser_test.go dotnet/gazelle/private/parser/parser.go
```

Expected: alleen `parser_test.go` is gewijzigd; de diff voegt uitsluitend `UTF-8 BOM with block namespace` toe; `parser.go` heeft geen diff; `git diff --check` is stil. Als de BOM-test in Step 3 slaagde of om een andere reden faalde, corrigeer dan alleen de testcase naar Step 2 en herhaal Steps 2-5. Commit niet vóór het verwachte rode resultaat is vastgesteld. Stage en commit daarna exact:

```bash
git add dotnet/gazelle/private/parser/parser_test.go
git diff --cached --check
git diff --cached --name-only
git commit -m "Add UTF-8 BOM parser regression test"
```

Expected vóór de commit: alleen `dotnet/gazelle/private/parser/parser_test.go` is staged. Expected na de commit: een nieuwe commit met message `Add UTF-8 BOM parser regression test`; de BOM-test blijft bewust rood tot Task 5.

---

### Task 4: Voeg de echte BOM-bytes en rode Store-golden toe

**Files:**
- Modify: `dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs`
- Modify: `dotnet/gazelle/testdata/nuget_dep/src/Store/BUILD.out`
- Test: `dotnet/gazelle/testdata/nuget_dep`

- [x] **Step 1: Controleer de onaangeroerde Store-fixture**

Run:

```bash
git status --short -- dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs dotnet/gazelle/testdata/nuget_dep/src/Store/BUILD.out
python3 - <<'PY'
from pathlib import Path
path = Path("dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs")
data = path.read_bytes()
assert not data.startswith(b"\xef\xbb\xbf"), "Store.cs already starts with a BOM"
assert data.startswith(b"using Newtonsoft.Json;\n"), "unexpected Store.cs prefix"
print("Store.cs has the expected pre-BOM prefix")
PY
```

Expected: `git status` is stil en Python drukt exact `Store.cs has the expected pre-BOM prefix` met exit 0. Stop bij een andere uitkomst.

- [x] **Step 2: Schrijf de synthetische BOM-fixture via een binaire old-byte-guard**

Voer exact dit commando uit; het schrijft alleen als de volledige oude file byte voor byte overeenkomt en verandert geen bestandsmodus:

```bash
python3 - <<'PY'
from pathlib import Path

path = Path("dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs")
old = b"""using Newtonsoft.Json;

namespace Store;

public static class Serializer
{
    public static string ToJson(object value) => JsonConvert.SerializeObject(value);
}
"""
new = b"\xef\xbb\xbf" + b"""using MessagePack;
using Newtonsoft.Json;

namespace Store
{
    public static class Serializer
    {
        public static string ToJson(object value) => JsonConvert.SerializeObject(value);
    }
}
"""
actual = path.read_bytes()
if actual != old:
    raise SystemExit("Store.cs does not match the approved pre-BOM fixture; stop without writing")
path.write_bytes(new)
PY
```

Expected: geen uitvoer en exit 0. De nieuwe C#-inhoud begint onmiddellijk na de drie BOM-bytes met `using MessagePack;`, heeft daarna `using Newtonsoft.Json;`, gebruikt een block-scoped `namespace Store`, behoudt LF-regeleinden en eindigt op LF. Er is geen inhoud uit `SignalRServerBuilderExtensions.cs` overgenomen.

- [x] **Step 3: Werk de Store-verwachting bij naar beide gesorteerde dependencies**

Vervang de volledige inhoud van `dotnet/gazelle/testdata/nuget_dep/src/Store/BUILD.out` exact van:

```starlark
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "store",
    srcs = ["Store.cs"],
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
    deps = ["@nuget.net10.0//newtonsoft.json"],
)
```

naar:

```starlark
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "store",
    srcs = ["Store.cs"],
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
    deps = [
        "@nuget.net10.0//messagepack",
        "@nuget.net10.0//newtonsoft.json",
    ],
)
```

Wijzig geen andere attributen en voeg geen `BUILD.in` toe.

- [x] **Step 4: Controleer de BOM en de volledige Store-bytes**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

path = Path("dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs")
expected = b"\xef\xbb\xbf" + b"""using MessagePack;
using Newtonsoft.Json;

namespace Store
{
    public static class Serializer
    {
        public static string ToJson(object value) => JsonConvert.SerializeObject(value);
    }
}
"""
data = path.read_bytes()
assert data == expected, "Store.cs differs from the exact synthetic BOM fixture"
assert data[:3] == bytes.fromhex("ef bb bf")
assert data.count(b"\xef\xbb\xbf") == 1, "Store.cs must contain exactly one BOM"
print(f"first-bytes={data[:3].hex(' ')}")
print("Store.cs bytes match the synthetic BOM fixture")
PY
```

Expected: exit 0 met exact deze twee regels. De volledige bytevergelijking sluit onbedoelde whitespace-, regeleind- en classwijzigingen uit:

```text
first-bytes=ef bb bf
Store.cs bytes match the synthetic BOM fixture
```

- [x] **Step 5: Bewijs dat de Store-BOM-golden op de ongefixeerde parser faalt**

Run:

```bash
bazel test //dotnet/gazelle/testdata:nuget_dep --test_output=all
```

Expected: niet-nul exit met `//dotnet/gazelle/testdata:nuget_dep   FAILED`. Het testlog toont voor Store dat de gegenereerde `deps` het verwachte label `@nuget.net10.0//messagepack` niet bevat terwijl `@nuget.net10.0//newtonsoft.json` behouden blijft. Er mag geen mismatch voor `src/FileScoped/BUILD.out` in het log staan: die golden was in Task 2 op dezelfde parser groen en Task 4 wijzigt die bestanden niet. Verwijder de BOM of het MessagePack-label niet om dit rode resultaat te vermijden.

- [x] **Step 6: Review bytes en diff, corrigeer binnen scope en commit de rode golden**

Run:

```bash
git diff --check
git status --short
git diff -- dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs dotnet/gazelle/testdata/nuget_dep/src/Store/BUILD.out
```

Expected: alleen de twee Store-bestanden zijn gewijzigd; de diff bevat de synthetische MessagePack-using, block namespace en twee gesorteerde labels; `parser.go`, de FileScoped-bestanden en resolvercode hebben geen diff; `git diff --check` is stil. Als `Store.cs` gecorrigeerd moet worden, herstel dan eerst uitsluitend dit bestand naar de oude bytes uit de huidige HEAD met `git restore --source=HEAD -- dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs`, voer daarna opnieuw de binaire old-byte-guard en write uit Step 2 uit, en herhaal Steps 4-6. Gebruik geen globale restore. Stage pas na het verwachte rode goldenresultaat:

```bash
git add dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs dotnet/gazelle/testdata/nuget_dep/src/Store/BUILD.out
git diff --cached --check
git diff --cached --name-only
git commit -m "Add UTF-8 BOM NuGet golden regression"
```

Expected vóór de commit: alleen de twee Store-bestanden zijn staged. Expected na de commit: een nieuwe commit met message `Add UTF-8 BOM NuGet golden regression`; de golden blijft bewust rood tot Task 5.

---

### Task 5: Normaliseer één BOM en voer volledige verificatie uit

**Files:**
- Modify: `dotnet/gazelle/private/parser/parser.go`
- Test: `dotnet/gazelle/private/parser/parser_test.go`
- Test: `dotnet/gazelle/testdata/nuget_dep`

- [x] **Step 1: Controleer dat de fix op een schone parser start**

Run:

```bash
git status --short -- dotnet/gazelle/private/parser/parser.go
```

Expected: geen uitvoer en exit 0. De rode tests uit Tasks 3 en 4 zijn al gecommit; voeg in deze task geen nieuwe fixtures of resolverwijzigingen toe.

- [x] **Step 2: Voeg de minimale normalisatie vóór blanking toe**

Vervang in `dotnet/gazelle/private/parser/parser.go` exact:

```go
func Parse(name, src string) (*File, error) {
	blanked, err := blankCommentsAndStrings(src)
```

door:

```go
func Parse(name, src string) (*File, error) {
	src = strings.TrimPrefix(src, "\uFEFF")
	blanked, err := blankCommentsAndStrings(src)
```

`strings` is al geïmporteerd. `strings.TrimPrefix` verwijdert exact één U+FEFF (`EF BB BF`) uitsluitend op bytepositie nul; een tweede BOM en BOM's op andere posities blijven staan. Zonder BOM is `src` ongewijzigd. Wijzig de using-regex, namespace-regex, `TrimSpace`, `ParseFile`, foutafhandeling en alle code na `blankCommentsAndStrings` niet.

- [x] **Step 3: Formatteer en maak beide parservormen groen**

Run:

```bash
gofmt -w dotnet/gazelle/private/parser/parser.go dotnet/gazelle/private/parser/parser_test.go
CGO_ENABLED=0 GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache go test ./dotnet/gazelle/private/parser -run '^TestParseNamespacesAndUsings$' -v
```

Expected: beide commando's slagen; de testuitvoer bevat zowel `--- PASS: TestParseNamespacesAndUsings/UTF-8_BOM_with_block_namespace` als `--- PASS: TestParseNamespacesAndUsings/file-scoped_namespace_followed_by_usings`, gevolgd door `PASS` en de `ok`-regel voor het parserpackage. Er is geen `FAIL`.

- [x] **Step 4: Draai de volledige relevante Go-verificatie**

Run exact:

```bash
CGO_ENABLED=0 GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache go test ./dotnet/gazelle/...
```

Expected: exit 0; ieder getest package eindigt met `ok` en packages zonder tests mogen `[no test files]` tonen; nergens staat `FAIL`. Deze run dekt naast de parser ook de bestaande Gazelle-configuratie, generatie- en resolutietests zonder die code te wijzigen.

- [x] **Step 5: Draai beide relevante Bazel-targets samen**

Run exact:

```bash
bazel test //dotnet/gazelle/private/parser:parser_test //dotnet/gazelle/testdata:nuget_dep
```

Expected: exit 0 met beide sleutelregels en een samenvatting dat beide tests slagen:

```text
//dotnet/gazelle/private/parser:parser_test                             PASSED
//dotnet/gazelle/testdata:nuget_dep                                     PASSED
```

De `nuget_dep`-golden bewijst nu dat Store zowel `@nuget.net10.0//messagepack` als `@nuget.net10.0//newtonsoft.json` krijgt en dat FileScoped `@nuget.net10.0//messagepack` behoudt.

- [x] **Step 6: Herbevestig dat verificatie de BOM-fixture niet heeft herschreven**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

path = Path("dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs")
expected = b"\xef\xbb\xbf" + b"""using MessagePack;
using Newtonsoft.Json;

namespace Store
{
    public static class Serializer
    {
        public static string ToJson(object value) => JsonConvert.SerializeObject(value);
    }
}
"""
data = path.read_bytes()
assert data == expected, "verification changed Store.cs"
assert data.count(b"\xef\xbb\xbf") == 1
print(f"first-bytes={data[:3].hex(' ')}")
print("Store.cs bytes unchanged after verification")
PY
```

Expected: exit 0 met exact:

```text
first-bytes=ef bb bf
Store.cs bytes unchanged after verification
```

- [x] **Step 7: Voer de laatste implementer-side scope-review uit en commit alleen de fix**

Run:

```bash
git diff --check
git status --short
git diff -- dotnet/gazelle/private/parser/parser.go dotnet/gazelle/private/parser/parser_test.go
git log --oneline -10
```

Expected: `git diff --check` is stil; alleen `dotnet/gazelle/private/parser/parser.go` is nog gewijzigd en zijn diff is uitsluitend de ene `src = strings.TrimPrefix(src, "\uFEFF")`-regel. De log bevat de vier eerdere taskcommits met exact de messages uit Tasks 1-4 en geen extra implementatiecommits. Als `gofmt` of verificatie iets anders wijzigde, herstel dat binnen de goedgekeurde scope en herhaal Steps 3-7; stage nooit ongerelateerde drift. Stage en commit exact:

```bash
git add dotnet/gazelle/private/parser/parser.go
git diff --cached --check
git diff --cached --name-only
git commit -m "Handle UTF-8 BOM in C# parser"
git status --short
```

Expected vóór de commit: alleen `dotnet/gazelle/private/parser/parser.go` is staged. Expected na de commit: een nieuwe commit met message `Handle UTF-8 BOM in C# parser`; de laatste `git status --short` is volledig stil. De vijf implementation commits bevatten gezamenlijk uitsluitend de zeven bestanden uit de bestandskaart en geen extra scope.
