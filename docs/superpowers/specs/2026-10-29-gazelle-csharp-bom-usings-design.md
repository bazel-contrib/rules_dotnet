# Design: UTF-8 BOM voor C#-usings in Gazelle

Datum: 2026-10-29
Status: **goedgekeurd door de gebruiker**

Dit document beschrijft de goedgekeurde, begrensde BOM-fix en zijn regressietests.
Het is een design-specificatie, geen implementatieplan.

## Doel

De C#-Gazelle-parser herkent een eerste `using`-directive ook wanneer een
UTF-8-bronbestand met een byte order mark begint. Daardoor blijft de bijbehorende
NuGet-dependency behouden in gegenereerde BUILD-output. De bestaande ondersteuning
voor een geldige file-scoped namespace gevolgd door usings wordt met tests bestendigd,
zonder de parser-API of dependencyresolutie te wijzigen.

## Niet-doelen

- **Geen volledige C#-parser of grammatica-uitbreiding.** De bestaande lichtgewicht
  lexer/regex-aanpak blijft behouden.
- **Geen publieke of interne API-wijziging.** `Parse(name, src)` en `ParseFile(path)`
  behouden hun signatuur en resultaattype.
- **Geen algemene Unicode- of encoderingnormalisatie.** Er komt geen UTF-16-detectie,
  transcodering of verwijdering van BOM's op andere posities.
- **Geen wijziging aan namespace-resolutie, NuGet-prefixmatching of BUILD-generatie.**
  Alleen de invoer van de bestaande parsing wordt genormaliseerd.
- **Geen letterlijke overname van `SignalRServerBuilderExtensions.cs`.** Dat bestand
  is alleen de aanleiding; de tests gebruiken nieuwe, synthetische C#-bronnen.
- **Geen verbreding naar andere parserproblemen of ongerelateerde refactoring.**

## Context

`parser.Parse` roept nu direct `blankCommentsAndStrings(src)` aan en verwerkt daarna
elke regel met `strings.TrimSpace`. De op `^using` verankerde regex ziet daardoor een
regel die met U+FEFF begint niet als using-directive: Go's `TrimSpace` verwijdert dit
teken niet. Een UTF-8 BOM bestaat in de Go-string uit de bytes `EF BB BF`, zodat bij
`BOM + using MessagePack;` juist de eerste import en zijn dependency verdwijnen.

De aanleiding is `/home/jhobert/Projects/Gazelle/SignalRServerBuilderExtensions.cs`,
dat met die drie bytes begint. De inhoud van dat bestand wordt niet als fixture
gekopieerd. De bestaande goldenfixture `dotnet/gazelle/testdata/nuget_dep` bewijst al
NuGet-resolutie via `nuget_resolve.json`: package-id's worden via langste-prefixmatch
naar labels zoals `@nuget.net10.0//newtonsoft.json` omgezet. Die resolutieketen is
geschikt om zonder C#-compilatie het verlies van de eerste import zichtbaar te maken.

## Voorgestelde architectuur

### Eén gerichte normalisatie in `parser.Parse`

Aan het begin van `Parse`, **vóór** `blankCommentsAndStrings` en alle matching, wordt
alleen een exacte UTF-8 BOM aan bytepositie nul van `src` verwijderd. De bewerking is
een enkele conditionele prefixverwijdering van U+FEFF (`EF BB BF`), geen aanpassing van
`TrimSpace` of van de using-regex.

De grenzen zijn expliciet:

- zonder BOM blijft `src` byte voor byte gelijk;
- precies één voorafgaande BOM wordt verwijderd, ook als er nog een BOM volgt;
- een BOM na whitespace, commentaar of ergens verder in het bestand blijft staan;
- regeleinden en de rest van de bron worden niet herschreven;
- bestaande foutafhandeling voor ongeldige strings en commentaren blijft ongewijzigd.

Doordat `ParseFile` aan `Parse` delegeert, geldt de fix voor zowel direct aangeleverde
tekst als van schijf gelezen `.cs`-bestanden. Na deze ene normalisatie doorlopen
namespace-extractie, usings, testdetectie en entry-pointdetectie exact de bestaande
codepaden. Er komt geen aparte BOM-aware resolver of een tweede parseerpad.

## Bestanden die wijzigen

Alleen deze specificatie wordt in de huidige fase toegevoegd. De implementatiefase
blijft beperkt tot de volgende bestanden.

### Gewijzigd

- `dotnet/gazelle/private/parser/parser.go` — één optionele BOM aan het begin van
  `src` verwijderen vóór blanking en matching.
- `dotnet/gazelle/private/parser/parser_test.go` — tabelgevallen voor BOM met block
  namespace en voor file-scoped namespace gevolgd door usings.
- `dotnet/gazelle/testdata/nuget_dep/nuget_resolve.json` — `MessagePack` als extra
  package-id in de bestaande `net10.0`-packagelijst. De overige metadata volgt de
  bestaande fixturevorm; de Gazelle-index gebruikt voor deze test alleen de id.
- `dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs` — synthetische BOM-fixture
  met `using MessagePack;` als eerste regel, daarna de bestaande Newtonsoft-using en
  een block-scoped `namespace Store`.
- `dotnet/gazelle/testdata/nuget_dep/src/Store/BUILD.out` — de bestaande dependency
  behouden en `@nuget.net10.0//messagepack` toevoegen.

### Nieuw

- `dotnet/gazelle/testdata/nuget_dep/src/FileScoped/FileScoped.cs` — synthetische,
  geldige bron met eerst `namespace FileScoped;`, daarna `using MessagePack;` en een
  eenvoudige class zonder test- of entry-pointmarkeringen.
- `dotnet/gazelle/testdata/nuget_dep/src/FileScoped/BUILD.out` — verwachte library met
  `FileScoped.cs` en dependency `@nuget.net10.0//messagepack`.

De bestaande root-`BUILD.in`/`BUILD.out`, resolverbestanden en andere goldenfixtures
blijven ongewijzigd.

## Teststrategie

### Parser-unittests

De bestaande tabel in `TestParseNamespacesAndUsings` krijgt twee gevallen:

1. **BOM plus block namespace.** De bron begint expliciet met U+FEFF, onmiddellijk
   gevolgd door `using MessagePack;`, bevat daarna een tweede using en een block-scoped
   namespace. De assertions controleren de namespace en de volledige usinglijst in
   bronvolgorde, inclusief `MessagePack` als eerste element. Zonder de fix mislukt dit
   geval doordat alleen de eerste using ontbreekt.
2. **File-scoped namespace gevolgd door usings.** Een bron zonder BOM declareert eerst
   een geldige `namespace Fixture;` en plaatst daarna een package-using vóór de class.
   Namespace en usinglijst worden exact gecontroleerd. Dit bestaande werkzame gedrag
   moet vóór en na de fix gelijk blijven.

### Bestaande goldenfixture uitbreiden

`Store.cs` krijgt letterlijk de bytes `EF BB BF` als allereerste inhoud; er mag geen
commentaar of whitespace voorafgaan. De bron blijft bewust klein en structureel, met
MessagePack als eerste externe package-using, Newtonsoft.Json als tweede externe using
en een block namespace. De verwachte `Store/BUILD.out` bevat beide gesorteerde
NuGet-labels. Daarmee bewijst de golden niet alleen parseroutput, maar ook dat de eerste
using de bestaande resolutie tot een concrete dependency bereikt.

De nieuwe `FileScoped`-golden plaatst de package-using na de file-scoped namespace en
controleert via zijn eigen `BUILD.out` dat ook deze vorm een library met de
MessagePack-dependency oplevert. Deze golden is een behoudstest en hoeft op de oude
parser niet te falen.

Als negatieve controle moeten zowel de BOM-unittest als de aangepaste `nuget_dep`-golden
falen wanneer uitsluitend de BOM-normalisatie uit de uiteindelijke wijziging wordt
teruggedraaid. De file-scoped unittest en golden moeten in die vergelijking juist
blijven slagen, zodat regressiebewijs en bestaand gedrag niet met elkaar worden verward.

## Verificatie

Na de implementatie zijn de minimale controles:

```sh
CGO_ENABLED=0 GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache go test ./dotnet/gazelle/...
bazel test //dotnet/gazelle/private/parser:parser_test //dotnet/gazelle/testdata:nuget_dep
```

Deze commando's worden niet in de huidige specificatiefase uitgevoerd; er wordt nu geen
productcode of testcode gewijzigd.

## Risico's en mitigaties

1. **De normalisatie verwijdert meer dan alleen de toegestane BOM.** Een brede trim of
   vervanging zou legitieme broninhoud kunnen wijzigen. Mitigatie: uitsluitend één
   exacte U+FEFF-prefix op bytepositie nul verwijderen, vóór alle andere verwerking;
   BOM's elders en overige bytes blijven expliciet buiten scope.
2. **Een unittest slaagt zonder het verloren dependencygedrag te bewijzen.** Alleen een
   parserassertie dekt de uiteindelijke BUILD-impact niet. Mitigatie: MessagePack aan
   de bestaande NuGet-index toevoegen en het exacte MessagePack-label in `BUILD.out`
   eisen; bovendien moet de golden zonder de fix falen.
3. **Een editor verwijdert ongemerkt de BOM uit de goldenfixture.** Daarmee verliest de
   test zijn regressiewaarde. Mitigatie: de unittest bouwt U+FEFF expliciet in de
   teststring en de fixture-eis vermeldt de letterlijke beginbytes `EF BB BF`; het
   negatieve-controlecriterium bewaakt dat de BOM-tests op ongefixeerde code falen.
4. **De file-scoped behoudstest leidt tot onnodige resolverwijzigingen.** Mitigatie: de
   bestandslijst sluit resolver- en generatiecode uit en vereist dat deze testcase zowel
   vóór als na de fix hetzelfde resultaat heeft.

## Besluitenoverzicht

- `parser.Parse` verwijdert vóór blanking en matching exact één optionele UTF-8 BOM,
  uitsluitend aan het begin van `src`.
- `strings.TrimSpace`, de bestaande regexes, parser-API's, foutpaden en alle
  resolutielogica blijven ongewijzigd.
- Een nieuwe synthetische BOM-test combineert een eerste MessagePack-using met een
  block namespace en controleert namespace en usingvolgorde exact.
- De bestaande `nuget_dep`-golden gebruikt eveneens synthetische C# met BOM en bewijst
  via `BUILD.out` zowel de MessagePack- als de bestaande Newtonsoft.Json-dependency.
- `MessagePack` wordt aan de bestaande `net10.0`-fixture-index toegevoegd; er is geen
  nieuwe resolver of goldenrunner nodig.
- Een afzonderlijke file-scoped unittest en golden bestendigen een namespace gevolgd
  door usings zonder het werkingsmechanisme daarvan te wijzigen.
- De BOM-unittest en BOM-golden moeten op code zonder de fix falen; de file-scoped
  controles moeten ook zonder de fix slagen.
- Het externe SignalR-voorbeeld wordt niet gekopieerd en er komen geen codewijzigingen
  buiten de genoemde parser- en fixturebestanden.
