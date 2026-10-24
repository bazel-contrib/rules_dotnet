# Design: Gazelle-directives voor `nullable` en `implicit_usings`

Datum: 2026-10-24
Status: **goedgekeurd door de gebruiker**

Dit document beschrijft het door de gebruiker goedgekeurde ontwerp, met name
benadering A: een publiek C#-rule-attribuut plus per-target gegenereerde
global-usings-bron. Het is een design-specificatie, geen implementatieplan.

## Doel

De C#-Gazelle-extensie krijgt de overerfbare directives
`# gazelle:dotnet_nullable <disable|enable|warnings|annotations>` en
`# gazelle:dotnet_implicit_usings <disable|enable>`. Gazelle zet een expliciet
geconfigureerde waarde om in respectievelijk het bestaande string-attribuut
`nullable` en een nieuw boolean-attribuut `implicit_usings` op gegenereerde
C#-libraries, -binaries en -tests. Bij ingeschakelde implicit usings genereren
de C#-rules per target en TFM een deterministische `.g.cs`-bron met de
namespaces die bij de gekozen project-SDK horen; zonder expliciete directive
blijft de bestaande BUILD-merge- en defaultsemantiek behouden.

## Scope en niet-doelen

### In scope

- Configuratie, validatie, overerving en child-overrides voor beide nieuwe
  Gazelle-directives.
- Generatie van de twee attributen op alle vijf rule-varianten die Gazelle
  daadwerkelijk genereert: `csharp_library`, `csharp_binary`,
  `csharp_nunit_test`, `csharp_xunit_test` en `csharp_mstest_test`.
- Een publiek `implicit_usings`-attribuut voor handgeschreven en gegenereerde
  C#-libraries, -binaries en -tests, inclusief generieke `csharp_test` en de
  drie test-frameworkmacro's.
- Vaste namespacesets op basis van .NET 10 voor `default`, `web`, `razor` en
  `blazorwasm`, inclusief de .NET Framework-uitzondering voor
  `System.Net.Http`.
- Een nieuwe, zelfstandige e2e-module
  `e2e/gazelle_nullable_implicit_usings` met een eigen CI-entry.
- Gerichte Go-, golden-, Starlark-, analyse-, compileer- en e2e-tests.

### Niet-doelen

- **Geen F#-ondersteuning.** De bestaande F#-rules, hun `nullable`-attribuut en
  hun compileracties blijven ongewijzigd.
- **Geen vrije namespaces of MSBuild-`Using`-items.** Gebruikers kunnen via dit
  ontwerp geen extra implicit-using-namespace doorgeven; alleen de vastgelegde
  SDK-sets worden gegenereerd.
- **Geen `.csproj`-uitlezing.** C#-bronbestanden en Gazelle-directives blijven
  de inputs; projectbestanden worden niet geparseerd.
- **Geen nieuwe project-SDK's.** `worker` en `windowsdesktop` worden niet
  toegevoegd aan `project_sdk`, en er komen geen namespacesets voor die SDK's.
- **Geen SDK-generatortabel uit de F#-SDK-generator.** De verworpen benadering B
  zou de namespaces via die generator laten bepalen, maar vergroot de scope en
  koppelt deze feature onnodig aan SDK-generatie.
- **Geen door Gazelle beheerde `.cs`-global-usings-bronnen.** De verworpen
  benadering C zou bronnen in de source tree laten schrijven. Dit geeft
  bezits-, schoonmaak- en lifecycleproblemen bij meerdere targets en helpt
  handgeschreven rules niet.
- **Geen wijziging aan bestaande e2e-modules.** In het bijzonder blijft
  `e2e/gazelle_net10.0` ongewijzigd.
- **Geen wijziging van bestaand defaultgedrag.** Targets zonder het nieuwe
  attribuut blijven zich gedragen als `implicit_usings = False`; bestaande
  `nullable`-defaults en compilerargumenten blijven gelijk.
- **Geen afhankelijkheidsresolutie uit gegenereerde implicit usings.** De
  Gazelle-resolver wordt niet uitgebreid en expliciete `using`-directives in
  bronbestanden worden niet verwijderd.
- **Geen automatische taalversieverhoging of `compiler_options`-omleiding.** De
  feature gebruikt een echte C#-bron en laat de bestaande
  `langversion`-afhandeling intact.

## Context

De implementatie sluit aan op de volgende bestaande structuren:

- `dotnet/private/rules/common/attrs.bzl` definieert `CSHARP_COMMON_ATTRS`.
  Daar staat `nullable` al als `attr.string` met de waarden `disable`, `enable`,
  `warnings` en `annotations` en default `disable`. `implicit_usings` bestaat
  nog niet. `CSHARP_LIBRARY_COMMON_ATTRS` en `CSHARP_BINARY_COMMON_ATTRS`
  nemen de gemeenschappelijke attributen over, waardoor library, binary en
  generieke test dezelfde publieke API delen.
- `dotnet/private/rules/csharp/{nunit_test,xunit_test,mstest_test}.bzl` zijn
  macro's rond `csharp_test`. Ze geven overige `**kwargs` door, zodat een nieuw
  gemeenschappelijk rule-attribuut zonder macrospecifieke attributenlogica
  beschikbaar komt.
- `dotnet/private/rules/csharp/{library,binary,test}.bzl` roepen elk de
  gedeelde `AssemblyAction` uit
  `dotnet/private/rules/csharp/actions/csharp_assembly.bzl` aan. Die actie
  verwerkt al gegenereerde C#-bronnen en heeft drie compileervormen: normaal,
  met een internals-reference bij `internals_visible_to`, en een daaropvolgende
  reference-only-compilatie.
- `dotnet/gazelle/dotnetconfig/config.go` bevat de per-directory-configuratie.
  `NewChild` kopieert de ouderconfiguratie en kloont veranderbare collecties;
  `Configure` in `dotnet/gazelle/configure.go` verwerkt directives en meldt
  ongeldige waarden via het bestaande fatale foutpad.
- `dotnet/gazelle/generate.go` genereert de vijf genoemde concrete kinds.
  `csharp_test` staat wel in `csharpKinds` voor onderhoud en resolutie, maar
  wordt niet door `GenerateRules` gegenereerd.
- `project_sdk` accepteert nu `default`, `web`, `razor` en `blazorwasm`.
  `normalize_project_sdk` in `dotnet/private/sdk/packs.bzl` normaliseert
  `razor` en `blazorwasm` naar `web` **uitsluitend voor pack-selectie**. Die
  normalisatie mag de implicit-using-keuze niet overnemen.
- `NET_FRAMEWORKS` in `dotnet/private/common.bzl` levert de bestaande exacte
  classificatie van .NET Framework-TFM's.
- `dotnet/gazelle/testdata/BUILD.bazel` ontdekt goldenfixtures automatisch met
  `gazelle_generation_test`. De bestaande C#-regeltests staan onder
  `dotnet/private/tests`, waaronder `csharp_nullable`.
- Elke map onder `e2e` is een zelfstandige Bazel-module.
  `.bazelci/presubmit.yml` voert voor elke afzonderlijke
  `e2e_working_directory` een build- en testtaak uit.

## Voorgestelde architectuur en componenten

### 1. Publieke C#-rule-API

`CSHARP_COMMON_ATTRS` krijgt één nieuw attribuut:

| Attribuut | Type | Default | Betekenis |
|---|---|---|---|
| `implicit_usings` | `attr.bool` | `False` | Bij `True` wordt per target en TFM een bron met de voor de project-SDK en TFM geldende `global using`-regels gegenereerd en meegecompileerd. Bij `False` wordt geen implicit-usings-bron of schrijfactie gemaakt. |

Het bestaande `nullable`-attribuut verandert niet. De Gazelle-directive
`dotnet_nullable` stuurt dus een bestaande publieke API aan, terwijl
`dotnet_implicit_usings` bovenop het nieuwe attribuut werkt. Omdat het attribuut
in de gemeenschappelijke C#-attrs staat, werkt het voor handgeschreven
libraries, binaries, generieke tests en frameworkmacro's op dezelfde manier als
voor Gazelle-output. De macrobestanden behoeven daarvoor geen gewijzigde
attribuutsignatuur.

`library.bzl`, `binary.bzl` en `test.bzl` geven `ctx.attr.implicit_usings` aan
`AssemblyAction` door. De F#-tegenhangers krijgen deze parameter niet.

### 2. Gazelle-configuratie en directives

`dotnetconfig.Config` houdt voor elk onderwerp een **expliciete
geconfigureerd-status** bij. Voor implicit usings vormen niet-geconfigureerd,
expliciet `disable` en expliciet `enable` samen een tri-state; nullable kent
niet-geconfigureerd plus de vier expliciete waarden. Een boolean met alleen
default `False` is onvoldoende, omdat de generator onderscheid moet maken
tussen "geen directive" en "schrijf expliciet `False`". Het ontwerp gebruikt
daarom per instelling een waarde plus een aanwezigheidsindicatie, met getters
die de waarde alleen samen met "geconfigureerd" aan de generator aanbieden.

| Directive | Toegestane waarden | Gegenereerd attribuut |
|---|---|---|
| `dotnet_nullable` | `disable`, `enable`, `warnings`, `annotations` | `nullable = "<waarde>"` |
| `dotnet_implicit_usings` | `disable`, `enable` | `implicit_usings = False` of `implicit_usings = True` |

Beide namen worden in `Configurer.KnownDirectives` geregistreerd en in
`Configure` verwerkt. De configuratiewaarden zijn exact en lowercase.
`NewChild` erft zowel de waarde als de aanwezigheidsindicatie. Een child mag
beide onafhankelijk overschrijven; een wijziging in een child verandert de
ouder of een sibling niet. Er komen geen nieuwe command-lineflags.

De root start voor beide instellingen niet-geconfigureerd. Een subtree begint
met een kopie van de ouderconfiguratie; alleen een eigen directive wijzigt de
overgeërfde waarde of geconfigureerd-status in die subtree. "Overerving"
betekent hier overerving van de **effectieve Gazelle-configuratie**, niet van
Bazel-attributen tussen targets.

### 3. Gedeelde generatiehelper en merge-semantiek

Een kleine helper in de Go-generatielaag krijgt een `rule.Rule` en de
effectieve dotnetconfig. De helper zet uitsluitend de geconfigureerde attributen
en wordt aangeroepen voor elk van de vijf gegenereerde kinds. Daardoor staat de
beslissing op één plek en kan een test-frameworkvariant niet worden vergeten.
De bestaande generatie van `srcs`, `target_frameworks`, `project_sdk`,
`visibility`, `deps` en `internals_visible_to` blijft ongewijzigd.

De kern van de output- en mergesemantiek is:

| Effectieve configuratie | Wat de generator doet | Gedrag bij een nieuw gegenereerd target |
|---|---|---|
| Geen `dotnet_nullable`-directive | `nullable` niet met `SetAttr` zetten en niet in nieuwe output schrijven | Bestaande rule-default `disable` geldt. |
| `dotnet_nullable disable` | `nullable = "disable"` schrijven | Nullable is expliciet uitgeschakeld; de defaultwaarde wordt bewust wel geschreven. |
| `dotnet_nullable enable` | `nullable = "enable"` schrijven | Bestaande compilerlogica gebruikt `/nullable:enable`. |
| `dotnet_nullable warnings` | `nullable = "warnings"` schrijven | Bestaande compilerlogica gebruikt `/nullable:warnings`. |
| `dotnet_nullable annotations` | `nullable = "annotations"` schrijven | Bestaande compilerlogica gebruikt `/nullable:annotations`. |
| Geen `dotnet_implicit_usings`-directive | `implicit_usings` niet met `SetAttr` zetten en niet in nieuwe output schrijven | Het nieuwe rule-default `False` geldt; er is geen gegenereerde implicit-usings-bron. |
| `dotnet_implicit_usings disable` | `implicit_usings = False` schrijven | Expliciet uitgeschakeld; er is geen gegenereerde bron. De defaultwaarde wordt bewust wel geschreven. |
| `dotnet_implicit_usings enable` | `implicit_usings = True` schrijven | De C#-actie genereert en compileert de SDK-specifieke bron. |

Het verschil tussen **unset** en **expliciet `False`** is dus zichtbaar in de
BUILD-file, niet in het compilerresultaat van een nieuw target: beide gedragen
zich als `False`, maar alleen expliciet `disable` schrijft het attribuut.

De afwezigheid van een directive is geen verwijderopdracht. Bij het mergen van
een bestaande regel laat Gazelle een attribuut dat de generator niet zet met
rust; zo blijft bijvoorbeeld een handmatig gezet `nullable = "annotations"`
behouden wanneer `dotnet_nullable` niet is geconfigureerd. Hetzelfde geldt voor
een reeds aanwezige `implicit_usings = True`. Alleen een directive verwijderen
reset zo'n bestaand attribuut daarom niet. Een expliciete `disable` in de
effectieve configuratie schrijft juist wel `nullable = "disable"` of
`implicit_usings = False` en zet een eerdere of overgeërfde `enable` terug.

Als een child zijn eigen override verwijdert terwijl de ouder nog `enable`
heeft, erft de child opnieuw `enable`; dat is geen unset-scenario. Pas wanneer
de effectieve configuratie niet-geconfigureerd is, laat de generator het
attribuut onaangeroerd. Bestaande Gazelle-merge- en `# keep`-semantiek blijft
verder ongewijzigd.

### 4. Starlark-helper voor implicit usings

Een nieuwe geïsoleerde helper in
`dotnet/private/rules/csharp/actions/implicit_usings.bzl` heeft twee duidelijke
verantwoordelijkheden:

1. Een pure functie bepaalt uit het **niet-genormaliseerde** `project_sdk` en de
   exacte `target_framework` de volledige, geordende namespacelijst. De
   pack-normalisatie `razor`/`blazorwasm` → `web` wordt hier niet gebruikt.
2. Een actiefunctie declareert bij `True` één bestand met het bestaande
   target/TFM-`out_dir` als basis, met logisch pad
   `<target_name>/<tfm>/<target_name>.GlobalUsings.g.cs` in de Bazel-output, en
   schrijft de inhoud met `actions.write`.

De inhoud is deterministisch: eerst exact de header `// <auto-generated />`,
daarna per namespace één regel van de vorm
`global using global::<namespace>;`, in de hieronder vastgelegde volgorde, met
LF-regeleinden en een afsluitende newline. Er komen geen timestamps,
workspace-paden of netto SDK-installatiegegevens in de inhoud. Dezelfde inputs
leveren daardoor dezelfde bytes op.

`AssemblyAction` roept de helper alleen aan wanneer `implicit_usings` `True` is.
Het resulterende bestand wordt één keer aan de gedeelde lokale `srcs`-lijst
toegevoegd voordat de bestaande vertakking voor normale en
internals/reference-only-compilaties wordt gekozen. Daardoor krijgen alle
relevante compileracties dezelfde bron precies één keer als input. Bij `False`
wordt noch `actions.declare_file` noch `actions.write` voor implicit usings
uitgevoerd en blijft de huidige `srcs`-lijst ongewijzigd.

De bron wordt niet via `compiler_options` geïnjecteerd, niet aan de publieke
`srcs`-configuratie van de gebruiker toegevoegd en niet in de source tree
geschreven. Er worden evenmin extra `resolveInput`-imports gemaakt: de
Gazelle-dependencyresolver ziet alleen expliciete usings in de oorspronkelijke
`.cs`-bestanden, zoals nu.

## Volledige namespacesets

De vaste tabel volgt de [.NET project SDK-documentatie over implicit using
directives](https://learn.microsoft.com/en-us/dotnet/core/project-sdk/overview#implicit-using-directives)
en de .NET 10-SDK-props, waaronder `Microsoft.NET.Sdk.CSharp.props`. De
documentatie bevestigt ook dat `System.Net.Http` vanaf de .NET 8-SDK voor .NET
Framework uit de basisset is verwijderd. De tabel wordt expliciet in
rules_dotnet vastgelegd; zij wordt niet tijdens de build uit een geïnstalleerde
SDK afgeleid.

De volgorde hieronder is tegelijk de schrijfvolgorde in de gegenereerde bron.
Elke set is volledig vermeld; "basis plus" is geen impliciete extra uitbreiding.

### `project_sdk = "default"`

1. `System`
2. `System.Collections.Generic`
3. `System.IO`
4. `System.Linq`
5. `System.Net.Http`
6. `System.Threading`
7. `System.Threading.Tasks`

### `project_sdk = "razor"`

1. `System`
2. `System.Collections.Generic`
3. `System.IO`
4. `System.Linq`
5. `System.Net.Http`
6. `System.Threading`
7. `System.Threading.Tasks`

Razor krijgt dus bewust **niet** automatisch de webset.

### `project_sdk = "web"`

1. `System`
2. `System.Collections.Generic`
3. `System.IO`
4. `System.Linq`
5. `System.Net.Http`
6. `System.Threading`
7. `System.Threading.Tasks`
8. `System.Net.Http.Json`
9. `Microsoft.AspNetCore.Builder`
10. `Microsoft.AspNetCore.Hosting`
11. `Microsoft.AspNetCore.Http`
12. `Microsoft.AspNetCore.Routing`
13. `Microsoft.Extensions.Configuration`
14. `Microsoft.Extensions.DependencyInjection`
15. `Microsoft.Extensions.Hosting`
16. `Microsoft.Extensions.Logging`

### `project_sdk = "blazorwasm"`

1. `System`
2. `System.Collections.Generic`
3. `System.IO`
4. `System.Linq`
5. `System.Net.Http`
6. `System.Threading`
7. `System.Threading.Tasks`
8. `Microsoft.Extensions.Configuration`
9. `Microsoft.Extensions.DependencyInjection`
10. `Microsoft.Extensions.Logging`

Blazor WebAssembly krijgt dus bewust **niet** de volledige webset en ook geen
`System.Net.Http.Json` of ASP.NET Core-namespaces.

### .NET Framework-uitzondering

Als `target_framework` in de bestaande `NET_FRAMEWORKS`-tabel staat, wordt
`System.Net.Http` uit de basisset weggelaten voordat de SDK-specifieke
extra namespaces worden toegevoegd. Er verdwijnt geen andere namespace. Voor
`default` en `razor` is de volledige set in dat geval dus:

1. `System`
2. `System.Collections.Generic`
3. `System.IO`
4. `System.Linq`
5. `System.Threading`
6. `System.Threading.Tasks`

Deze classificatie gebruikt geen stringprefixgissing: `net48` valt bijvoorbeeld
binnen de uitzondering, terwijl `netstandard2.0` en `net10.0` dat niet doen.
Voor `web` en `blazorwasm` geldt dezelfde verwijderregel voor het basiselement
`System.Net.Http`; eventuele ongeldige SDK/TFM-combinaties blijven door de
bestaande pack- en targetvalidatie worden afgehandeld.

Net als bij MSBuild vereist `global using` een ondersteunende C#-taalversie
(C# 10 of hoger). Bij een oudere TFM kan de gebruiker daarom expliciet een
passende `langversion` moeten instellen. De feature wijzigt de bestaande
`default_csharp_lang_version`-logica niet.

## Dataflow

```text
BUILD-directives
  └─ Configurer.KnownDirectives / Configure
       └─ dotnetconfig.Config met waarde + geconfigureerd-status
            ├─ NewChild: overerving, override en isolatie
            └─ GenerateRules
                 └─ gedeelde attr-helper voor vijf gegenereerde kinds
                      ├─ geen directive: attribuut niet zetten
                      ├─ disable: expliciete defaultwaarde schrijven
                      └─ enable/warnings/annotations: geconfigureerde waarde schrijven

Publiek C#-rule-attribuut implicit_usings
  └─ library.bzl / binary.bzl / test.bzl
       └─ AssemblyAction per target en TFM
            ├─ False: geen bestandsdeclaratie, geen write-actie, srcs ongewijzigd
            └─ True
                 └─ pure namespacekeuze(project_sdk, target_framework)
                      └─ actions.write van één deterministische GlobalUsings.g.cs
                           └─ eenmaal in gedeelde srcs
                                ├─ normale compilatie
                                ├─ internals-reference-compilatie
                                └─ reference-only-compilatie
```

Er is bewust geen pijl van de gegenereerde global-usings-bron naar de
Gazelle-parser of -resolver. Expliciete usings blijven in de gebruikersbron
staan en volgen het bestaande resolutiepad.

## Foutafhandeling

- **Ongeldige directive-waarde:** `dotnet_nullable` verwerpt alles behalve de
  vier genoemde strings; `dotnet_implicit_usings` verwerpt onder andere
  `true`, `false`, `warnings` en `annotations`. De setter geeft een beschrijvende
  fout terug en `Configure` volgt het bestaande fatale patroon met de
  directive-naam, de ontvangen waarde en de toegestane waarden. Er vindt geen
  stille normalisatie van case of synoniemen plaats.
- **Niet-ondersteunde taalversie:** de C#-compiler levert zijn normale fout voor
  `global using`. De oplossing is een geschikte expliciete `langversion`; er
  komt geen verborgen upgrade en geen tweede validatielaag die afwijkt van de
  compiler.
- **Project-SDK/TFM-combinaties:** de bestaande `values`-validatie op
  `project_sdk` en bestaande targeting/runtime-pack-fouten blijven leidend.
  Deze feature voegt geen nieuwe SDK's of alternatieve validatie toe.
- **Unset of expliciet `False`:** dit zijn geldige toestanden en geen fouten.
  Er wordt geen leeg implicit-usings-bestand gemaakt en er verschijnt geen
  extra compilerinput.
- **Expliciete en impliciete usings naast elkaar:** Gazelle verwijdert of
  herschrijft geen expliciete usings en de helper probeert niet tegen
  gebruikersbron te dedupliceren. De bestaande compilerdiagnostiek blijft
  gelden.

## Bestanden die wijzigen

De volgende bestandslijst beschrijft de ontwerpgrenzen; alleen deze specificatie
wordt in de huidige specificatiefase daadwerkelijk toegevoegd.

### Gewijzigd in de implementatiefase

- `dotnet/gazelle/dotnetconfig/config.go` — directiveconstanten, waarden plus
  geconfigureerd-status, getters, setters en validatie.
- `dotnet/gazelle/configure.go` — `KnownDirectives`, directive-verwerking en
  foutmeldingen.
- `dotnet/gazelle/generate.go` — één gedeelde attr-helper en aanroep voor alle
  vijf gegenereerde kinds.
- `dotnet/gazelle/dotnetconfig/config_test.go` — defaults, geldige en ongeldige
  waarden, overerving, overrides en isolatie.
- `dotnet/gazelle/generate_test.go` — generatiematrix en afwezig/aanwezig-gedrag
  van beide attributen.
- `dotnet/gazelle/lang_test.go` — dekking dat beide directives als bekend zijn
  geregistreerd.
- `dotnet/private/rules/common/attrs.bzl` — publiek boolean-attribuut
  `implicit_usings` met default `False` op `CSHARP_COMMON_ATTRS`.
- `dotnet/private/rules/csharp/library.bzl`,
  `dotnet/private/rules/csharp/binary.bzl` en
  `dotnet/private/rules/csharp/test.bzl` — doorgeven van het attribuut aan
  `AssemblyAction`.
- `dotnet/private/rules/csharp/actions/csharp_assembly.bzl` — één bron per
  target/TFM genereren en gedeeld aan alle relevante compileerpaden toevoegen.
- `dotnet/private/rules/csharp/actions/BUILD.bazel` — `bzl_library` en
  dependency-registratie voor de nieuwe helper.
- `.bazelci/presubmit.yml` — één extra, zelfstandige
  `e2e_working_directory`-entry voor
  `e2e/gazelle_nullable_implicit_usings`; bestaande entries blijven staan.

De macrobestanden voor NUnit, xUnit en MSTest, `dotnet/defs.bzl`, de
Gazelle-resolver en bestaande e2e-modules hoeven niet te wijzigen.

### Nieuw in de implementatiefase

- `dotnet/private/rules/csharp/actions/implicit_usings.bzl` — pure
  namespaceselectie en geïsoleerde `actions.write`-helper.
- `dotnet/private/tests/csharp_implicit_usings/` — een eigen testpackage met
  `BUILD.bazel`, pure Starlark-helpertests, compile-actie-analysistests en
  C#-fixtures voor library, binary, generieke test en frameworkmacro's.
- `dotnet/gazelle/testdata/nullable_implicit_usings/` — een
  `gazelle_generation_test`-fixture met `MODULE.bazel`, `expectedStderr.txt`,
  `BUILD.in`/`BUILD.out` op root- en child-niveau en `.cs`-fixtures. De golden
  dekt unset, enable, overerving, expliciete disable en behoud van handmatige
  attributen zonder effectieve directive.
- `e2e/gazelle_nullable_implicit_usings/` — een nieuwe zelfstandige module met:
  - `MODULE.bazel`, `MODULE.bazel.lock`, `.bazelrc`, `.bazelversion`,
    `BUILD.bazel` en `internal_dev_deps.bzl` volgens de bestaande e2e-opzet;
  - een eigen `gazelle_binary` en `gazelle`-run-target;
  - bronfixtures en ingecheckte, door Gazelle gegenereerde `BUILD.bazel`-files
    in `src/unset`, `src/enabled`, `src/enabled/inherited` en
    `src/enabled/disabled`.

Er worden geen bestanden gewijzigd of verwijderd onder
`e2e/gazelle_net10.0` of een andere bestaande e2e-module.

## Teststrategie

### 1. Go-configuratietests

De tests in `dotnetconfig/config_test.go` en `lang_test.go` dekken:

- Rootdefault is voor beide instellingen **niet-geconfigureerd**, wat niet
  verward wordt met de rule-defaults `nullable = "disable"` en
  `implicit_usings = False`.
- Alle vier nullable-waarden en beide implicit-usings-waarden worden
  geaccepteerd en exact teruggegeven.
- Ongeldige waarden geven fouten met de toegestane set; voor implicit usings
  worden expliciet `true`/`false` en de nullable-only waarden getest.
- Beide namen staan in `KnownDirectives`.
- `NewChild` erft waarde én geconfigureerd-status. Child-overrides werken per
  instelling onafhankelijk en mutaties lekken niet naar ouder of sibling.
- Een child zonder eigen directive behoudt de ouderwaarde; een child met
  `disable` overschrijft een overgeërfde `enable`.

### 2. Go-generatietests en goldenfixture

De generatietests gebruiken alle vijf daadwerkelijk gegenereerde kinds en
controleren per kind:

- **Unset:** zowel `Attr("nullable")` als `Attr("implicit_usings")` blijft
  afwezig wanneer geen van beide directives is gezet.
- **Disable:** `nullable = "disable"` en `implicit_usings = False` worden wel
  geschreven.
- **Enable:** `nullable = "enable"` en `implicit_usings = True` worden
  geschreven.
- `warnings` en `annotations` komen ongewijzigd als string in `nullable`
  terecht; ze veranderen `implicit_usings` niet.

De nieuwe `gazelle_generation_test`-golden bewijst bovendien de echte
BUILD-serialisatie en merge-semantiek:

- unset bevat geen van beide door deze feature gestuurde attributen in nieuwe output;
- expliciete defaults verschijnen wel als `nullable = "disable"` en
  `implicit_usings = False`;
- een parent met beide directives op `enable` geeft dezelfde attributen aan een
  child zonder eigen directives;
- een child met beide directives op `disable` overschrijft de overgeërfde
  enable;
- een bestaand handmatig `nullable`- of `implicit_usings`-attribuut blijft
  behouden wanneer de effectieve configuratie unset is, zodat ook het
  "directive verwijderen is geen reset"-geval is gedekt.

De fixture test alleen gegenereerde kinds; er wordt geen nieuwe generieke
`csharp_test`-generatie geïntroduceerd.

### 3. Pure Starlark-helpertests

Tests laden de pure functie rechtstreeks en vergelijken de volledige lijst,
inclusief volgorde, voor:

- `default` en `razor`, die exact gelijk zijn aan de zeven basisnamespaces;
- `web`, met alle zestien vastgelegde namespaces;
- `blazorwasm`, met exact de tien vastgelegde namespaces;
- alle vier de project-SDK's met een .NET Framework-TFM zoals `net48`, waarbij
  alleen `System.Net.Http` uit de basis verdwijnt en de SDK-specifieke extra
  namespaces ongewijzigd blijven;
- een niet-.NET Framework-TFM, waarbij `System.Net.Http` juist behouden blijft.

Deze tests bewaken expliciet dat pack-normalisatie van `razor` en `blazorwasm`
niet tot de webset leidt. De actie-analyse in de volgende testlaag controleert
daarnaast de vaste header, de exacte vorm
`global using global::<namespace>;`, de volgorde en de afsluitende newline van
de daadwerkelijk geschreven inhoud.

### 4. C#-analyse- en compileertests

Het nieuwe package `dotnet/private/tests/csharp_implicit_usings` dekt:

- `implicit_usings = True` op `csharp_library`, `csharp_binary`, generieke
  `csharp_test`, `csharp_nunit_test`, `csharp_xunit_test` en
  `csharp_mstest_test`. De eigen fixture-bronnen gebruiken bijvoorbeeld
  `Console`, `List<T>` en `Task` zonder de bijbehorende expliciete basis-usings,
  zodat een geslaagde compilatie de gegenereerde bron aantoonbaar nodig heeft.
  Frameworkspecifieke usings blijven expliciet aanwezig.
- Een handgeschreven target zonder `implicit_usings`-attribuut en een target met
  expliciet `implicit_usings = False`. Analyse van de compilerinputs toont in
  beide gevallen dat er geen `GlobalUsings.g.cs` en geen bijbehorende
  schrijfactie is; zo worden unset en expliciet `False` afzonderlijk getest.
- Bij `True` bevat elke relevante compileractie de gegenereerde bron exact één
  keer. Een target met `internals_visible_to` dekt zowel de
  internals-reference- als de reference-only-compilatie naast de normale vorm.
- De geïnspecteerde schrijfactie heeft het vastgelegde target/TFM-pad en volledig
  deterministische inhoud: exact de auto-generated-header, de verwachte regels
  in SDK-volgorde en een afsluitende newline.
- Het uitgeschakelde pad laat bestaande bronnen en compilerargumenten intact.
- De bestaande tests onder `dotnet/private/tests/csharp_nullable` blijven
  ongewijzigd slagen en bewaken dat de nieuwe doorvoer geen regressie in het
  bestaande nullabilitygedrag veroorzaakt.

### 5. Nieuwe zelfstandige e2e-module en CI

`e2e/gazelle_nullable_implicit_usings` gebruikt `net10.0`: de root configureert
`dotnet_target_frameworks net10.0`, maar geen van beide nieuwe directives. De
module heeft vier afzonderlijke source-scenario's:

1. **`src/unset`: unset.** Noch de root noch deze subtree bevat een van de twee
   nieuwe directives. De gegenereerde BUILD-file bevat geen `nullable` en geen
   `implicit_usings`; de bron gebruikt expliciete usings en bouwt met het
   bestaande defaultgedrag. De afwezigheid van een implicit source wordt door
   de bovenstaande actie-analyse gegarandeerd.
2. **`src/enabled`: enabled.** De directory bevat beide directives op `enable`.
   Gegenereerde library-, binary- en test-targets hebben
   `nullable = "enable"` en `implicit_usings = True`; hun eigen code vereist
   impliciete basis-usings, zodat `bazel build //...` en `bazel test //...` het
   gedrag bewijzen.
3. **`src/enabled/inherited`: overgeërfde enable.** De child heeft geen eigen
   nieuwe directives. Zijn gegenereerde BUILD-file bevat toch beide
   enable-attributen en zijn code gebruikt eveneens impliciete usings.
4. **`src/enabled/disabled`: expliciete override.** De child onder de enabled
   parent zet beide directives op `disable`. De gegenereerde BUILD-file bevat
   expliciet `nullable = "disable"` en `implicit_usings = False`; de code heeft
   expliciete usings en bouwt zonder implicit-usings-ondersteuning.

De ingecheckte BUILD-files zijn onderdeel van de fixture en worden na
`bazel run //:gazelle` op exacte, ongewijzigde output gecontroleerd. De module
gebruikt zijn eigen `MODULE.bazel`, toolchain-, Gazelle-, rules_go- en interne
CI-development-setup. Bestaande e2e-modules worden niet als fixture of
schrijfdoel gebruikt.

De nieuwe map wordt als een extra element aan de bestaande
`e2e_working_directory`-matrix toegevoegd. CI voert daardoor onafhankelijk van
`e2e/gazelle_net10.0` en van de andere modules zowel `bazel build //...` als
`bazel test //...` in `e2e/gazelle_nullable_implicit_usings` uit.

## Verificatie

Na de implementatie vormen de volgende gerichte commando's de minimale
verificatie van de hoofdrepository:

```sh
bazel test //dotnet/gazelle/...
bazel test //dotnet/private/tests/csharp_implicit_usings/... //dotnet/private/tests/csharp_nullable/... //dotnet/private/tests/internals_visible_to/...
```

De nieuwe e2e-module wordt vanuit zijn eigen map volledig gecontroleerd:

```sh
bazel run //:gazelle
bazel build //...
bazel test //...
```

Na `bazel run //:gazelle` moeten de ingecheckte gegenereerde BUILD-files exact
blijven; vanuit de repository-root kan dat met
`git diff --exit-code -- e2e/gazelle_nullable_implicit_usings` worden bewaakt.
De nieuwe CI-matrixentry moet de build en test zelfstandig uitvoeren. Een
volledige implementatie, een volledige repositorybrede testrun of een
implementatieplan maakt geen deel uit van deze specificatiefase.

## Risico's en mitigaties

1. **Unset en expliciet `False` raken door elkaar gehaald.** Een gewone bool met
   default `False` zou Gazelle overal `implicit_usings = False` laten schrijven
   en het onderscheid met geen directive vernietigen. Mitigatie: een expliciete
   geconfigureerd-status naast de waarde, een gedeelde attr-helper en tests die
   zowel attribuutafwezigheid als expliciete `False` afdwingen.
2. **Een gegenereerde testvariant of compileervertakking mist de feature.**
   Mitigatie: alle vijf generated kinds gebruiken dezelfde Go-helper en de
   generatietests vormen een matrix over alle kinds. In Starlark wordt de bron
   vóór de compileervertakking eenmaal aan gedeelde `srcs` toegevoegd;
   analysistests dekken normale, internals-reference- en reference-only-acties.
3. **`razor` of `blazorwasm` krijgt ten onrechte de webset.** De bestaande
   `normalize_project_sdk` maakt dit risico concreet. Mitigatie: de helper krijgt
   de oorspronkelijke `project_sdk`, pack-normalisatie blijft buiten de
   namespacekeuze en pure tests vergelijken de volledige sets exact.
4. **SDK-namespaces of volgorde wijzigen onbedoeld.** Mitigatie: een vaste .NET
   10-tabel in plaats van SDK-afhankelijke detectie, deterministische
   `actions.write`-inhoud en exacte helpertests, inclusief de
   .NET Framework-uitzondering. Toekomstige SDK-wijzigingen worden een bewuste
   wijziging van die tabel en tests.
5. **Oudere TFMs falen door de taalversie.** Mitigatie: het attribuutdocument
   en deze specificatie benoemen de C#-vereiste; gebruikers kunnen
   `langversion` expliciet zetten. Er wordt geen stille defaultwijziging
   geïntroduceerd en de normale compilerfout blijft de waarheidsgetrouwe
   diagnostiek.
6. **De e2e-wijziging raakt bestaande modules of verliest zijn isolatie.**
   Mitigatie: een nieuwe module met eigen configuratie, binary, fixtures en
   gegenereerde BUILD-files, plus een afzonderlijke CI-working-directory. De
   bestandslijst en acceptatie verbieden wijzigingen aan bestaande e2e-mappen.

## Besluitenoverzicht

- Het ontwerp is expliciet door de gebruiker goedgekeurd; benadering A wordt
  gekozen boven SDK-generatie via de F#-generator (B) en door Gazelle beheerde
  `.cs`-bronnen (C).
- `dotnet_nullable` accepteert `disable`, `enable`, `warnings` en `annotations`
  en schrijft een string naar het bestaande `nullable`-attribuut.
- `dotnet_implicit_usings` accepteert alleen `disable` en `enable` en schrijft
  een boolean naar het nieuwe publieke `implicit_usings`-attribuut met default
  `False` op `CSHARP_COMMON_ATTRS`.
- Beide directives staan in `KnownDirectives`, gebruiken de bestaande
  dotnetconfig, worden overgeërd, kunnen per child worden overschreven en
  leveren bij ongeldige waarden duidelijke Configure-fouten.
- Configuratie heeft een expliciete geconfigureerd-status naast de waarde.
  Zonder effectieve directive zet Gazelle het betreffende attribuut niet;
  expliciete `disable` schrijft de defaultwaarde juist wel.
- Voor een nieuw target betekenen unset en `False` allebei: geen
  implicit-usings-bron. Voor bestaande BUILD-regels is unset geen reset:
  bestaande attributen blijven bij normale merge behouden. Een expliciete
  `disable` zet een eerdere of overgeërfde `enable` terug.
- Eén Go-generatiehelper bedient exact `csharp_library`, `csharp_binary`,
  `csharp_nunit_test`, `csharp_xunit_test` en `csharp_mstest_test`. Generieke
  `csharp_test` wordt niet door Gazelle gegenereerd maar ondersteunt het nieuwe
  publieke attribuut wel, net als handgeschreven rules en frameworkmacro's.
- Een geïsoleerde Starlark-helper kiest namespaces op de oorspronkelijke
  `project_sdk` en TFM en gebruikt `actions.write` voor één deterministisch
  `<target_name>/<tfm>/<target_name>.GlobalUsings.g.cs`-bestand met
  auto-generated-header en `global using global::<namespace>;`-regels.
- `AssemblyAction` voegt de bron eenmaal toe vóór de normale,
  internals-reference- en reference-only-compilaties. Bij `False` worden geen
  bestand en actie gemaakt; er wordt geen `compiler_options`-mechanisme
  gebruikt.
- De volledige .NET 10-sets zijn vastgelegd voor `default`, `razor`, `web` en
  `blazorwasm`; `System.Net.Http` ontbreekt in de basis voor
  `NET_FRAMEWORKS`. Razor erft de webset niet en Blazor WebAssembly krijgt de
  volledige webset niet. Worker en WindowsDesktop komen er niet bij.
- `global using` vereist een passende C#-taalversie; oudere TFMs kunnen een
  expliciete `langversion` vereisen. Er komt geen extra project-SDK-validatie of
  automatische taalversiewijziging.
- De Gazelle-dependencyresolver verandert niet: gegenereerde implicit usings
  worden niet als source imports verwerkt en expliciete usings blijven staan.
- Correctheid wordt gedekt door Go-configuratie- en generatietests, een echte
  Gazelle-golden, pure Starlark-tests voor alle sets, analyse- en compileertests
  voor unset/disable/enable en alle compileerpaden, en bestaande
  nullable-regressietests.
- De nieuwe zelfstandige e2e-module `e2e/gazelle_nullable_implicit_usings`
  bevat unset-, enabled-, inherited- en disabled-scenario's en krijgt een eigen
  CI-entry. `e2e/gazelle_net10.0` en alle andere bestaande e2e-modules blijven
  ongewijzigd.
