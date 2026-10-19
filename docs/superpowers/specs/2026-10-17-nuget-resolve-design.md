# Design: `nuget.resolve` — NuGet-resolutie en pinning voor rules_dotnet

Datum: 2026-10-17
Status: goedgekeurd door gebruiker

## Doel

Een nieuwe bzlmod-module-extensie `nuget` met een `resolve`-tag die
NuGet-afhankelijkheden transitief resolveert — naar het model van
`maven_install` + Coursier + `maven_install.json` uit
[rules_jvm_external](https://github.com/bazel-contrib/rules_jvm_external),
maar voor NuGet. De resolutielogica is een eigen C#-tool in rules_dotnet die
de gepubliceerde NuGet SDK-packages gebruikt (`NuGet.Protocol`,
`NuGet.DependencyResolver.Core` — dezelfde graafresolutie als
`dotnet restore`). Het resultaat wordt gepind in een eigen
JSON-lockbestand (`nuget_resolve.json`) met sha512-integriteit per package en
een input-hash die een verouderde pin detecteert. De bestaande
`packages_lock`-extensie (die NuGet's `packages.lock.json` las zonder zelf te
resolven) verdwijnt volledig; de twee resterende gebruikers migreren naar
`nuget.resolve`.

## Niet-doelen

- **Geen `packages.lock.json`-ondersteuning.** Dat formaat (geschreven door
  `dotnet restore`) wordt niet gelezen; de feature wordt verwijderd, niet
  vervangen door een tweede formaat in dezelfde extensie.
- **De resolver wordt niet gebouwd uit de NuGet.Client-broncode.** De checkout
  op `/home/jhobert/Projects/Gazelle/NuGet.Client` dient alleen als
  documentatie/referentie voor de resolver-API's. De tool verwijst naar
  gepubliceerde `NuGet.*`-packages van nuget.org.
- **Geen prebuilt binaries, geen MSBuild RestoreCommand.** De tool wordt bij
  fetch-tijd offline gebouwd met de bootstrap-.NET-SDK die rules_dotnet al
  downloadt.
- **Geen veranderingen aan Paket.** De `paket`-extensie blijft ongewijzigd
  bestaan.
- **Alleen bzlmod.** Net als `paket` en `packages_lock` is dit een
  module-extensie; er komt geen WORKSPACE-API.
- **Geen source/symbol-packages, geen Central Package Management, geen
  samenvoegen van meerdere resolve-tags tot één graaf.** Elke `resolve`-tag is
  een eigen, onafhankelijke graaf.

## Context

Bestaande machinery waar dit op voortbouwt:

- **Hub/spoke-repository's**
  (`dotnet/private/rules/nuget/nuget_repo.bzl` + `nuget_archive.bzl`): één
  hub-repository per dependency-groep met een `BUILD.bazel` per package, plus
  één gedeelde `nuget_archive`-spoke per unieke package-versie. Zowel `paket`
  als `packages_lock` gebruiken dit; `nuget.resolve` hergebruikt het voor de
  gepinde variant. `nuget_archive.bzl` exporteert `write_repository_for_testing`
  met een `prefix`-parameter — expliciet bedoeld om de targets van een package
  in een willekeurige repository te schrijven ("Several packages can then share
  one repository") — en vormt daarmee de basis voor de ongepinde hub.
- **De (te verwijderen) `packages_lock`-extensie**
  (`dotnet/private/packages_lock/extension.bzl`): het patroon voor tag-verzameling
  over modules heen, de `claimed`-check tegen framework-collisies, netrc-ondersteuning
  en `extension_metadata(root_module_direct_deps/...)`.
- **De `paket`-extensie** (`dotnet/private/paket/extension.bzl`): idem, plus het
  patroon van een integriteits-`facts`-cache.
- **Bootstrap-SDK**: `dotnet/extensions.bzl` laat alleen rules_dotnet zelf een
  bootstrap-SDK pinnen (`bootstrap_toolchain`, nu 10.0.401). De SDK-repository's
  heten `dotnet_sdk.<versie>_<platform>` (bijv. `dotnet_sdk.10.0.401_linux-x64`)
  en worden luie gefetcht.
- **rules_jvm_external** (`private/rules/coursier.bzl`,
  `maven_install.bzl`, `generate_pin_repository.bzl`, `v3_lock_file.bzl`): het
  pinning-model — een ongepinde repository die resolveert en een `:pin`-target
  aanbiedt, een gepinde repository die alleen het lockbestand leest, een
  input-signatuur die in Starlark wordt berekend (`hash()` over een canonieke
  representatie), en `REPIN=1` als environment-variable die "repin is aan de
  gang" aangeeft zodat validatie dan waarschuwt in plaats van faalt.

## API

Een module-extensie `nuget`, geladen uit `@rules_dotnet//dotnet:nuget.bzl`, met
één tag `resolve`. De onderliggende repository-rules blijven private.

```starlark
nuget = use_extension("@rules_dotnet//dotnet:nuget.bzl", "nuget")
nuget.resolve(
    name = "nuget",
    packages = {
        "Newtonsoft.Json": "13.0.3",
        "Serilog": "4.0.0",
    },
    frameworks = ["net8.0", "net10.0"],
    sources = ["https://api.nuget.org/v3/index.json"],
    lock_file = "//:nuget_resolve.json",   # optioneel
    fail_if_repin_required = True,
)
use_repo(nuget, "nuget.net8.0", "nuget.net10.0")
```

Attributen van `resolve`:

| Attribuut | Type | Betekenis |
|---|---|---|
| `name` | string, verplicht | Prefix voor de repository's: hub per framework als `<name>.<tfm>`, resolve-repository als `unpinned_<name>`. |
| `packages` | string_dict, verplicht, niet-leeg | Package-id → versie of versie-range in NuGet's PackageReference-syntax: `13.0.3` (minimumversie, resolveert naar de laagst toepasselijke), `[13.0.3]` (exact), `4.0.*` (floating). Semantiek identiek aan `dotnet restore`. |
| `frameworks` | string_list, verplicht, niet-leeg | De target frameworks waarvoor geresolvet wordt. Elke TFM wordt een eigen hub-repository: `@nuget.net10.0//<package-id-lowercase>`. |
| `sources` | string_list | De NuGet-feeds, in opzoekvolgorde. V3 (`index.json`) en V2 worden ondersteund. Default: `["https://api.nuget.org/v3/index.json"]`. |
| `lock_file` | label, optioneel | Het ingecheckte lockbestand. Zonder dit attribuut wordt bij elke fetch opnieuw geresolvet (ongepinde modus). |
| `fail_if_repin_required` | bool, default `True` | Alleen van betekenis mét `lock_file`: faal de build als de inputs niet meer overeenkomen met het lockbestand. Zonder `lock_file` is het attribuut inert. |
| `netrc` | label, optioneel | Netrc-bestand met credentials voor de feeds. Default de netrc van de gebruiker, zoals bij `packages_lock`. |

Packages worden per framework geadresseerd als `@nuget.<framework>//<package>`,
identiek aan de bestaande extensies (de hub genereert de lowercase-alias, het
versie-gesuffixte label `<id>/<versie>` en het `//<package>/tools`-target).

`dev_dependency = True` op de `use_extension` werkt zoals bij `packages_lock`:
de hubs van de root-module worden dan als `root_module_direct_dev_deps`
gerapporteerd.

## Architectuur

Vier componenten.

### 1. De resolver-tool (`tools/nuget_resolver/`)

Een C#-console-applicatie in de rules_dotnet-repository, met
`PackageReference`s op de gepubliceerde `NuGet.Protocol`- en
`NuGet.DependencyResolver.Core`-packages. Input: een JSON-specificatie
(packages met versie-ranges, frameworks, sources) plus de door de
repository-rule berekende input-hash. Per framework resolveert de tool de
volledige transitieve graaf met dezelfde NuGet-API's die `dotnet restore`
gebruikt (`SourceRepository`-providers uit `NuGet.Protocol`, graafresolutie uit
`NuGet.DependencyResolver.Core`). Per geresolvet package legt de tool vast:
id (originele casing), genormaliseerde versie, download-URL(s) en de sha512
als SRI-string (`sha512-<base64>`). De hash komt uit de feed-metadata
(`packageHash` in de registratie) en wordt geverifieerd door de `.nupkg` te
downloaden en de bytes zelf te hashen; bij mismatch faalt de tool. Output: het
`nuget_resolve.json`-bestand (zie formaat hieronder), met de meegegeven
input-hash erin gestempeld. Fouten (onbekende package, onbevredigbare range,
TFM-incompatibiliteit, feed-/auth-fouten) geven een niet-nul exitcode met de
NuGet-foutmelding op stderr; de repository-rule faalt met die melding.

De tool target het framework van de bootstrap-SDK-band (nu net10.0, bij
bootstrap-SDK 10.0.401); de TFM en de SDK-versie worden in één constante
bijgehouden (zie component 2).

### 2. Tool-bootstrap bij fetch-tijd

De extensie declareert één interne repository `nuget_resolver_tool` die de
tool offline bouwt:

1. De volledige, transitieve `.nupkg`-sluiting van de tool is gepind in
   `dotnet/private/nuget_resolve/tool.bzl` (`TOOL_PACKAGES`: id, versie,
   sha512-integriteit), gedownload met `repository_ctx.download` (met
   integriteit) en neergelegd als local folder feed.
2. De repository-rule schrijft een `NuGet.config` die alleen die folder feed
   als bron heeft en bouwt de tool met `dotnet publish` uit de bootstrap-SDK.
   De SDK wordt als label-attribuut meegegeven:
   `@dotnet_sdk.<bootstrap-versie>_<host-platform>//:dotnet` — labels in
   repository-rules resolven via de repo-mapping van de rules_dotnet-.bzl-context,
   dus rules_dotnet's eigen `MODULE.bazel` neemt de per-platform
   bootstrap-SDK-repository's op in zijn `use_repo(dotnet, ...)` (luie fetch,
   geen kosten voor wie de tool niet bouwt). Het host-platform wordt gekozen
   met dezelfde `PLATFORMS`-mapping als de SDK-repository's.
3. De bootstrap-SDK-versie staat als private constante in
   `dotnet/private/nuget_resolve/tool.bzl`; een test in rules_dotnet bewaakt
   dat die gelijk blijft aan de versie die `MODULE.bazel` aan
   `dotnet.bootstrap_toolchain` geeft.

De tool-repository is volledig gepind (alle inputs hebben integriteit) en wordt
daardoor door Bazel's repository-cache hergebruikt; alleen een wijziging in de
pins of de toolbron triggert een herbouw. Er is één tool-repository per
extensie-instantie, gedeeld door alle `resolve`-tags.

### 3. Repository-generatie (hub/spoke)

- **Gepinde modus** (`lock_file` gezet): de extensie leest het lockbestand op
  extensie-evaluatiemoment (`module_ctx.read`, zoals `packages_lock` dat doet)
  en declareert per unieke package-versie een bestaande `nuget_archive`-spoke
  (gedeeld tussen frameworks). Per framework declareert ze de gepinde
  hub-repository-rule uit `pinned_hub.bzl`, die het lockbestand zelf leest, de
  input-hash valideert (zie component 4) en de hub-BUILD-files genereert met de
  bestaande hub-generatie uit `nuget_repo.bzl`. De spoke krijgt de sha512 uit
  het lockbestand als `integrity` en de opgenomen download-URL's via een nieuw
  optioneel attribuut `urls` op `nuget_archive` — daarmee is bij een gepinde
  build geen feed-index-download meer nodig om URL's af te leiden (`sources`
  blijft bestaan voor `paket`; als `urls` gezet is, wordt de URL-afleiding
  overgeslagen en dient `sources` alleen nog voor auth).
- **Ongepinde modus** (geen `lock_file`): de resolutie vindt plaats in de
  repository-rule `unpinned_<name>`, pas ná extensie-evaluatie, dus de
  extensie kan dan geen spokes declareren. De ongepinde hub `<name>.<tfm>` is
  daarom een monolithische repository-rule met een label-dependency op
  `unpinned_<name>//:nuget_resolve.json`: hij leest dat bestand, downloadt en
  extraheert elke package in de eigen repository (met de sha512 uit het bestand
  als integriteit) en schrijft de package-targets met de bestaande
  prefix-machinery (`write_repository_for_testing`-patroon). Dit is dezelfde
  monolithische opzet als `maven_install` zonder pin; gedeelde spokes en
  luiheid komen pas met pinnen. `nuget_repo.bzl` wordt hiervoor gerefactord
  zodat de hub-BUILD-generatie door beide hub-repository-rules wordt
  hergebruikt: de gepinde (archieven als cross-repo `@<spoke>`-labels) en de
  ongepinde (archieven in de eigen repository).

Adressering is in beide modi identiek: `@<name>.<tfm>//<package>`.

### 4. Pinning en repin (naar rules_jvm_external)

- **`unpinned_<name>`** resolveert en schrijft `nuget_resolve.json`, en biedt
  een `:pin`-run-target: een shell-script (zoals `pin.sh` bij
  rules_jvm_external) dat het gegenereerde bestand naar
  `$BUILD_WORKSPACE_DIRECTORY/<pad uit lock_file-label>` kopieert — of naar
  `nuget_resolve.json` in de workspace-root als `lock_file` niet gezet is,
  zodat de eerste pin ook zo ontstaat. De resolve-repository is
  `reproducible = False` gemarkeerd.
- **Gepinde hubs** valideren bij fetch: de hub-repository-rule berekent de
  input-hash opnieuw uit de tag-attributen en vergelijkt die met de
  `inputHash` in het lockbestand. Bij mismatch faalt de fetch met
  repin-instructies als `fail_if_repin_required = True` (en `REPIN` niet gezet
  is); anders waarschuwt hij en bouwt hij door met het bestaande lockbestand.
  Elke gepinde hub bevat ook `alias(name = "pin", actual = "@unpinned_<name>//:pin")`,
  zodat het repin-commando een repository gebruikt die de gebruiker sowieso in
  `use_repo` heeft:

  ```
  REPIN=1 bazel run @nuget.net10.0//:pin
  ```

  (Dit is de concrete invulling van het `REPIN=1 bazel run @<name>//:pin` uit
  het goedgekeurde ontwerp: omdat er geen kale `@<name>`-repository is —
  alleen hubs per framework — leeft het pin-target in de hub. De alias zorgt
  dat het commando werkt ongeacht welke repository's de gebruiker in
  `use_repo` heeft opgenomen.)
- **`REPIN=1`**: de gepinde hub declareert `environ = ["REPIN"]`; met `REPIN`
  gezet waarschuwt validatie in plaats van te falen, zodat het pin-target zelf
  altijd gebouwd kan worden terwijl het lockbestand oud is. (Zelfde redenatie
  als `is_repin_required` in rules_jvm_external.)

## Dataflow

```
MODULE.bazel
  └─ nuget.resolve tag
       └─ extensie evalueert tags (claimed-check, metadata)
            ├─ declareert nuget_resolver_tool   (gepinde nupkg's + bootstrap-SDK → dotnet publish)
            ├─ declareert unpinned_<name>        (voert de tool uit, schrijft nuget_resolve.json, :pin-target)
            ├─ gepind: leest lock_file, declareert nuget_archive-spokes + gepinde hubs <name>.<tfm>
            │            (hubs valideren inputHash bij fetch; spokes downloaden met sha512-integriteit)
            └─ ongepind: declareert monolithische hubs <name>.<tfm>
                          (lezen unpinned_<name>//:nuget_resolve.json, downloaden zelf)
```

## Lockbestandformaat: `nuget_resolve.json`

Eigen formaat, gemodelleerd naar `maven_install.json` (niet NuGet's
`packages.lock.json`). Deterministisch geserialiseerd: keys gesorteerd, packages
gesorteerd op id (case-insensitive, ordinaal), indentatie van twee spaties —
diff-vriendelijk en stabiel tussen runs.

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

| Veld | Betekenis |
|---|---|
| `version` | Formaatversie, nu `1`. De lezer faalt met een duidelijke melding bij een onbekende versie (geen stille misparse). |
| `inputHash` | De input-hash (zie hieronder), als decimale string. Geschreven door de tool, door de repository-rule aangereikt. |
| `frameworks` | Map van TFM (lowercase, zoals in `frameworks`) naar de geresolvete graaf van dat framework. |
| `packages[].id` | Package-id in originele casing. |
| `packages[].version` | De genormaliseerde geresolvete versie. |
| `packages[].sha512` | SRI-string `sha512-<base64>`, direct bruikbaar als Bazel-download-integriteit. |
| `packages[].urls` | De feitelijke download-URL('s) van de `.nupkg`, in feed-volgorde. |

Dependency-edges staan bewust níet in het bestand: de hub/spoke-machinery
leest die bij fetch uit de `.nuspec` in de package zelf (`package_info.bzl`),
zoals nu ook bij `paket` en `packages_lock`.

### Input-hash

De input-hash wordt **in Starlark** berekend — nooit in de tool — zodat de
ongepinde en gepinde kant gegarandeerd dezelfde berekening gebruiken (het
patroon van `compute_dependency_inputs_signature` uit rules_jvm_external):
`hash()` over een canonieke string van
`{"frameworks": gesorteerd, "packages": gesorteerde dict, "sources": in opgegeven volgorde}`.
De ongepinde resolve-rule geeft de hash mee aan de tool, die hem ongemoeid in
het lockbestand stempelt; de gepinde hub berekent hem opnieuw uit de
tag-attributen en vergelijkt. De hash is een versheid-detector, geen
security-mechanisme (integriteit komt van de sha512 per package). Zoals
rules_jvm_external een lijst oude hash-algoritmen accepteert, houdt
`input_hash.bzl` een lijst vervangen algoritmen bij: een lockbestand met een
oude-maar-herkende hash waarschuwt ("draai repin") in plaats van te falen.

## Foutafhandeling

- **Onbekende package/versie, onbevredigbare range, TFM-incompatibel**: de
  tool exit met niet-nul en de NuGet-foutmelding; de resolve-repository faalt
  met die melding.
- **Feed-/auth-fouten**: `netrc`-attribuut op de tag, met de netrc van de
  gebruiker als default (zoals `packages_lock`). De resolve-repository geeft het
  netrc-pad als argument aan de tool, die er de per-host credentials uit leest
  voor zijn feed-requests; de spoke-downloads van `nuget_archive` gebruiken het
  bestaande `netrc`-attribuut op die repository-rule.
- **Framework-collisie tussen resolve-tags** (ook over modules heen): de
  extensie houdt een `claimed`-map bij zoals `packages_lock` en faalt met welke
  tag welke repository al claimt; advies: een andere `name` kiezen. De check
  dekt zowel `<name>.<tfm>` als `unpinned_<name>`.
- **Verouderd lockbestand**: input-hash-mismatch → `fail_if_repin_required`
  faalt met de repin-instructies (`REPIN=1 bazel run @<name>.<tfm>//:pin`), of
  waarschuwt als het attribuut `False` is.
- **Handmatig bewerkt of corrupt lockbestand**: ongeldige JSON, ontbrekende
  verplichte velden of onbekende `version` → fail met de melding dat het
  bestand niet handmatig bewerkt moet worden en hoe te repinnen. Een
  sha512-mismatch bij download faalt via Bazel's integriteitscontrole.
- **Ongeldige TFM-string**: de tool faalt met de NuGet-parseerfout. Verder
  wordt een TFM niet tegen de rules_dotnet-configureerbare set gevalideerd;
  packages die niets voor een TFM aanbieden resolveren via de bestaande
  `unsupported_frameworks`-machinery.

## Testplan

- **Starlark-unittests** (`dotnet/private/tests/nuget_resolve/`, in het
  bestaande `rules_testing`-patroon): lockbestand-parser en -validator (geldig,
  ontbrekende velden, onbekende versie), input-hash (stabiel voor dezelfde
  inputs; verandert bij elke wijziging in packages, frameworks of sources;
  oude algoritmen waarschuwen), repository-naamgeving, en de
  `claimed`-collisie tussen twee tags.
- **Tool-unittests** (`tools/nuget_resolver/tests/`, `csharp_test` tegen een
  local-folder-feed-fixture, geen netwerk): exacte versie, minimumversie,
  floating range (`4.0.*`), transitieve resolutie met diamond (versie-unificatie),
  multi-framework, sha512-stempeling en -verificatie, en de foutpaden
  (onbekende id, onbevredigbare range).
- **Example**: `examples/nuget_resolve/` — een kleine C#-app die een transitief
  geresolvet package gebruikt (bijv. Serilog met een sink), met ingecheckt
  `nuget_resolve.json`, opgenomen in `examples/MODULE.bazel`.
- **e2e** (elke e2e-directory is een eigen bazel-module, zoals `e2e/net10.0`;
  nieuwe mappen worden toegevoegd aan de `e2e_working_directory`-lijst in
  `.bazelci/presubmit.yml`):
  - `e2e/nuget_resolve_basic/` — één package, **ongepind** (resolveert bij
    fetch), `bazel build` + `bazel run`.
  - `e2e/nuget_resolve_transitive/` — gepind, met twee gevallen: een diepe
    keten (A → B → C → D, waarbij de build een type uit D gebruikt) en een
    diamond met versie-unificatie (twee paden naar hetzelfde package met
    verschillende minimumversies).
  - `e2e/nuget_resolve_multi_framework/` — gepind, `net8.0` + `net10.0` uit
    één tag, gebouwd voor beide frameworks.
  - `e2e/nuget_resolve_pinning/` — repin-detectie: een fixture-module met een
    bewust verouderd lockbestand (input-hash klopt niet) waarvan een
    testscript vaststelt dat `bazel build` faalt met de repin-instructies, en
    dat `REPIN=1 bazel run @nuget.<tfm>//:pin` het lockbestand bijwerkt waarna
    de build slaagt.

## Verwijdering en migratie van `packages_lock`

**Verwijderd** (inhoud van commits `474a2cf`, `ada755c`, `d312390`, `bd337ce`
en het `packages_lock`-e2e):

- `dotnet/packages_lock.bzl`
- `dotnet/private/packages_lock/` (`BUILD.bazel`, `extension.bzl`, `lock.bzl`)
- `dotnet/private/tests/packages_lock/`
- De `packages_lock`-`bzl_library` in `dotnet/BUILD.bazel`
- `e2e/net10.0_packages_lock/`
- `examples/packages_json/`

**Gemigreerd naar `nuget.resolve`** (met een via de pin-flow gegenereerd
`nuget_resolve.json` in plaats van `packages.lock.json`):

- `examples/gazelle_csharp` + het `packages_lock`-blok in
  `examples/MODULE.bazel` (regels ~60-62).
- `e2e/gazelle_net10.0` (`MODULE.bazel` regels ~23-25).

Omdat die twee de Gazelle-extensie demonstreren, migreert de Gazelle-NuGet-index
mee: `dotnet/gazelle/private/nuget/nuget.go` leest `nuget_resolve.json`
(package-id's uit `frameworks → * → packages`) in plaats van
`packages.lock.json`; de default van de lockbestand-configuratie in
`dotnet/gazelle/dotnetconfig/config.go` wordt `nuget_resolve.json`. De
bijbehorende Go-tests en testdata-fixtures (`nuget_test.go`, `config_test.go`,
`resolve_test.go`, `testdata/`) worden bijgewerkt.

## Bestanden

**Nieuw:**

- `dotnet/nuget.bzl` — publieke ingang (docstring + re-export van de extensie).
- `dotnet/private/nuget_resolve/BUILD.bazel`
- `dotnet/private/nuget_resolve/extension.bzl` — tag-class, verzameling over
  modules, `claimed`-check, declaratie van tool-/resolve-/hub-/spoke-repository's,
  `extension_metadata`.
- `dotnet/private/nuget_resolve/lock.bzl` — Starlark-parser en -validator voor
  `nuget_resolve.json`.
- `dotnet/private/nuget_resolve/input_hash.bzl` — canonieke input-hash plus
  lijst vervangen algoritmen.
- `dotnet/private/nuget_resolve/tool.bzl` — `TOOL_PACKAGES`-pin,
  bootstrap-SDK-versieconstante, tool-build-repository-rule.
- `dotnet/private/nuget_resolve/resolve.bzl` — ongepinde resolve-repository-rule
  (voert de tool uit, schrijft het lockbestand, genereert het `:pin`-script).
- `dotnet/private/nuget_resolve/pinned_hub.bzl` — gepinde hub-repository-rule
  (input-hash-validatie met `environ = ["REPIN"]`, `:pin`-alias).
- `dotnet/private/nuget_resolve/unpinned_hub.bzl` — monolithische ongepinde
  hub-repository-rule.
- `tools/nuget_resolver/` — `NuGetResolver.csproj`, bronbestanden, `BUILD.bazel`.
- `tools/nuget_resolver/tests/` — `csharp_test`s met folder-feed-fixture.
- `dotnet/private/tests/nuget_resolve/` — Starlark-unittests.
- `examples/nuget_resolve/`
- `e2e/nuget_resolve_basic/`, `e2e/nuget_resolve_transitive/`,
  `e2e/nuget_resolve_multi_framework/`, `e2e/nuget_resolve_pinning/`

**Gewijzigd:**

- `dotnet/private/rules/nuget/nuget_archive.bzl` — nieuw optioneel attribuut
  `urls` (slaat de feed-index-URL-afleiding over).
- `dotnet/private/rules/nuget/nuget_repo.bzl` — hub-BUILD-generatie herbruikbaar
  gemaakt voor de hub-repository-rules (inclusief in-repo archieven voor de
  ongepinde hub).
- `dotnet/BUILD.bazel` — `packages_lock`-`bzl_library` weg, `nuget`-`bzl_library` erbij.
- `MODULE.bazel` — per-platform bootstrap-SDK-repository's toegevoegd aan
  `use_repo(dotnet, ...)` zodat de tool-build-rule ze kan labelen.
- `dotnet/gazelle/private/nuget/nuget.go`,
  `dotnet/gazelle/dotnetconfig/config.go` (+ tests en testdata) — index leest
  `nuget_resolve.json`.
- `examples/MODULE.bazel`, `examples/gazelle_csharp/` — migratie naar
  `nuget.resolve`.
- `e2e/gazelle_net10.0/MODULE.bazel` — migratie naar `nuget.resolve`.
- `.bazelci/presubmit.yml` — nieuwe e2e-mappen in `e2e_working_directory`.

**Verwijderd:** zie de lijst onder "Verwijdering en migratie".

## Risico's en mitigaties

1. **Cross-extensie labels naar de bootstrap-SDK-repository's raken bzlmod-
   beperkingen** (repo-mapping van extensies). Mitigatie: labels in
   repository-rules resolven via de rules_dotnet-.bzl-context; rules_dotnet's
   eigen `use_repo(dotnet, ...)` maakt de SDK-repository's zichtbaar en de
   naamgeving (`dotnet_sdk.<versie>_<platform>`) is deterministisch. Fallback
   als dit in de implementatie toch niet werkt: de `nuget`-extensie declareert
   de SDK zelf opnieuw via de bestaande publieke `dotnet_sdk_repositories`
   (kost een extra SDK-download, functioneel equivalent).
2. **De offline tool-build breekt op een ontbrekende transitieve
   tool-dependency.** De folder feed moet de volledige sluiting bevatten.
   Mitigatie: `TOOL_PACKAGES` wordt als volledige sluiting met integriteiten
   gepind (bijgewerkt via een gedocumenteerde repin-stap), en een CI-test bouwt
   `nuget_resolver_tool` vanuit een schone repository-cache.
3. **SDK-versie en tool-TFM lopen uit elkaar** (de constante in `tool.bzl`
   versus de pin in `MODULE.bazel`). Mitigatie: een test in rules_dotnet die
   beide vergelijkt faalt zodra ze divergeren.
4. **Starlark `hash()` is implementatie-afhankelijk.** Een wijziging in Bazel's
   string-hash zou alle bestaande lockbestanden als "oud" markeren. Mitigatie:
   de lijst vervangen algoritmen in `input_hash.bzl` (zelfde patroon als
   rules_jvm_externals `old_hashes`) waarschuwt in plaats van te falen;
   bovendien is de hash geen security-grens — dat is de sha512.
5. **Ongepinde hubs downloaden eager en delen geen spokes**, waardoor een
   ongepinde multi-framework-setup meer downloadt dan een gepinde. Mitigatie:
   bewuste afweging (ongepind is de tijdelijke "ik stel mijn dependencies
   samen"-modus, zoals bij `maven_install`); Bazel's repository-cache dekt
   herhaalde downloads via integriteit; de documentatie stuurt aan op pinnen.

## Besluitenoverzicht

- Eén publieke module-extensie `nuget` (`@rules_dotnet//dotnet:nuget.bzl`) met
  één tag `resolve`; repository-rules blijven private.
- Resolver is een eigen C#-tool (`tools/nuget_resolver/`) op gepubliceerde
  `NuGet.*`-packages; de NuGet.Client-checkout is alleen referentie.
- De tool wordt bij fetch-tijd offline gebouwd: gepinde `.nupkg`-sluiting als
  folder feed + bootstrap-SDK (`dotnet publish`); geen prebuilt binaries.
- Eigen lockbestand `nuget_resolve.json`: `version`, `inputHash`, en per
  framework de platte, gesorteerde packagelijst met id, genormaliseerde versie,
  sha512 (SRI) en download-URL's. Geen `packages.lock.json`.
- De input-hash wordt in Starlark berekend en aan de tool meegegeven; vervangen
  algoritmen waarschuwen in plaats van te falen.
- Gepinde modus hergebruikt de bestaande hub/spoke-machinery; `nuget_archive`
  krijgt een optioneel `urls`-attribuut zodat gepinde downloads geen
  feed-index meer ophalen.
- Ongepinde modus gebruikt monolithische hub-repository's die de output van
  `unpinned_<name>` lezen en zelf downloaden (prefix-machinery).
- Pinning naar rules_jvm_external: `unpinned_<name>` voert de resolver uit en
  heeft het `:pin`-run-target; elke gepinde hub valideert de input-hash
  (`fail_if_repin_required`, `REPIN=1` waarschuwt) en aliast `:pin`.
  Repin-commando: `REPIN=1 bazel run @<name>.<tfm>//:pin`.
- `packages_lock` wordt volledig verwijderd (inclusief `examples/packages_json`
  en `e2e/net10.0_packages_lock`); `examples/gazelle_csharp` en
  `e2e/gazelle_net10.0` migreren naar `nuget.resolve`, en de Gazelle-NuGet-index
  leest voortaan `nuget_resolve.json`.
