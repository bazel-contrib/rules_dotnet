# Gazelle Nullable and Implicit Usings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-subagent-driven-development (recommended) or superpowers-executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Voeg overerfbare Gazelle-directives voor nullable en implicit usings toe en laat alle C#-rules bij ingeschakelde implicit usings een deterministische SDK-/TFM-specifieke `GlobalUsings.g.cs` compileren, met gerichte tests en een geïsoleerde e2e-module.

**Architecture:** De Go-configuratie bewaart per instelling een waarde plus een expliciete geconfigureerd-status; één generatiehelper schrijft alleen effectief geconfigureerde attributen op alle vijf gegenereerde kinds, met een beperkte bestaande-rule-merge zodat expliciete overrides bestaande scalars bijwerken terwijl unset en `# keep` behouden blijven. Een pure Starlark-helper kiest de vaste .NET 10-namespaces op het oorspronkelijke `project_sdk` en de exacte TFM, waarna `AssemblyAction` bij `implicit_usings = True` één `actions.write`-bron vóór alle compileervertakkingen aan de lokale `srcs` toevoegt. De bestaande resolver, F#-rules, macro-API's en bestaande e2e-modules blijven ongewijzigd.

**Tech Stack:** Go 1.24 via rules_go, Bazel 9.1.1, Starlark, bazel_skylib `unittest`/`analysistest`, C#/.NET SDK 10.0.401, Gazelle 0.51.3, NUnit/xUnit/MSTest via de bestaande C#-macro's, Buildkite YAML.

**Spec:** `docs/superpowers/specs/2026-10-24-gazelle-nullable-implicit-usings-design.md` (goedgekeurd; dit plan wijzigt de goedgekeurde semantiek niet).

---

## Uitvoerings- en omgevingscontract

Werk vanuit `/home/jhobert/Projects/Gazelle/rules_dotnet`, branch `feature/gazelle`. Voer in iedere nieuwe shell deze bestaande omgevingsworkarounds uit vóór Go- of Bazel-commando's:

```bash
export JAVA_HOME="$(bazel info java-home 2>/dev/null)"
export GOPATH=/tmp/opencode/gopath
export GOCACHE=/tmp/opencode/gocache
export CGO_ENABLED=0
```

`CGO_ENABLED=0` is nodig voor de lokale `go test`-commando's: anders faalt `runtime/cgo` in deze omgeving met `/usr/include/stdc-predef.h: Permission denied`. De Gazelle-code en haar tests zijn pure Go en hebben cgo niet nodig.

De repository root gebruikt Bazel 9.1.1. De analysecode in dit plan gebruikt uitsluitend API's die in de Bazel 9.1.1-bron `src/main/java/com/google/devtools/build/lib/starlarkbuildapi/ActionApi.java` bestaan: `Action.content`, `Action.inputs` (een `depset`), `Action.outputs` (een `depset`) en `Action.argv`. Omdat de nieuwe schrijfactie een letterlijke string schrijft, is `content` tijdens analyse beschikbaar; er is geen execution-time-expansie en geen niet-bestaande helper nodig. De actuele `@bazel_skylib//lib:unittest.bzl` levert met `analysistest.target_actions(env)` de acties van `target_under_test` via zijn bestaande action-retrieving-aspect; `dotnet/private/tests/utils.bzl` gebruikt datzelfde analysepad al met `Action.argv` voor C#-compileracties.

Iedere task heeft een eigen, afgebakende implementatiecommit en daarna een aparte statuscommit op dit plan. Laat bij een statusupdate alle oorspronkelijke steps en checkboxes staan; verander alleen die task's enkele `**Status:** pending`-regel in de opgegeven completed-regel. Stage nooit Bazel-output, geheimen of ongerelateerde wijzigingen. De laatste task heeft geen productwijziging en krijgt daarom alleen zijn eigen statuscommit.

**Normatieve randvoorwaarden:**

- `dotnet_nullable` accepteert exact `disable`, `enable`, `warnings`, `annotations`; `dotnet_implicit_usings` accepteert exact `disable`, `enable`. Case en synoniemen worden niet genormaliseerd.
- Niet-geconfigureerd betekent: geen `SetAttr` voor dat onderwerp. Expliciet `disable` betekent juist wel `nullable = "disable"` of het echte Starlark-boolean `implicit_usings = False` schrijven. Unset is geen reset bij merge.
- De actuele Gazelle-merger bewaart een al aanwezige niet-mergeable scalar zelfs wanneer de gegenereerde regel een andere waarde heeft. Markeer deze attributen daarom **niet** globaal als `MergeableAttrs`: dat zou ze bij unset juist verwijderen. Task 3 gebruikt in `generate.go` een stub-merge met alleen de effectief geconfigureerde attributen, zodat expliciete waarden bestaande regels overschrijven en de bestaande `# keep`-semantiek via `rule.MergeRules` behouden blijft.
- De gegenereerde kinds zijn uitsluitend `csharp_library`, `csharp_binary`, `csharp_nunit_test`, `csharp_xunit_test`, `csharp_mstest_test`. Generieke `csharp_test` krijgt de publieke rule-ondersteuning maar geen nieuwe Gazelle-generatie.
- De resolver verandert niet, er worden geen expliciete usings verwijderd, er komt geen `.csproj`-lezer, geen vrije namespacelijst, geen nieuwe project-SDK en geen automatische `langversion`-wijziging.
- Bestaande e2e-mappen, met name `e2e/gazelle_net10.0`, zijn geen schrijfdoel. De root-BUILD van de nieuwe e2e krijgt alleen `dotnet_target_frameworks net10.0`, geen van beide nieuwe directives.

## Bestandskaart en verantwoordelijkheden

### Bestaande bestanden die in de implementatiefase wijzigen

| Bestand | Verantwoordelijkheid |
|---|---|
| `dotnet/gazelle/dotnetconfig/config.go` | Directiveconstanten, tri-state-/vijf-toestandsconfiguratie, getters, setters en validatie |
| `dotnet/gazelle/configure.go` | `KnownDirectives`, overerving via bestaande `Configure`, fatale validatiefouten |
| `dotnet/gazelle/generate.go` | Eén gedeelde attribuut-helper voor library, drie testvarianten en binary plus een beperkte merge van expliciet geconfigureerde scalars op bestaande regels |
| `dotnet/gazelle/dotnetconfig/config_test.go` | Defaults, geldige/ongeldige waarden, overerving en isolatie |
| `dotnet/gazelle/lang_test.go` | Registratie en echte `Configure`-doorvoer |
| `dotnet/gazelle/generate_test.go` | Matrix over vijf generated kinds, attribuutafwezigheid, booleans en expliciete override op een bestaande regel |
| `dotnet/private/rules/common/attrs.bzl` | Publiek `implicit_usings: attr.bool(default = False)` op alleen C#-common-attrs |
| `dotnet/private/rules/csharp/library.bzl` | Doorvoer `ctx.attr.implicit_usings` naar `AssemblyAction` |
| `dotnet/private/rules/csharp/binary.bzl` | Dezelfde doorvoer voor binaries en bootstrap-varianten via de gedeelde compileerfunctie |
| `dotnet/private/rules/csharp/test.bzl` | Dezelfde doorvoer voor generieke tests en daardoor alle frameworkmacro's |
| `dotnet/private/rules/csharp/actions/csharp_assembly.bzl` | Eén gegenereerde bron per target/TFM vóór normale, internals- en reference-only-compilatie |
| `dotnet/private/rules/csharp/actions/BUILD.bazel` | `bzl_library` en dependencyregistratie van de helper |
| `.bazelci/presubmit.yml` | Alleen één extra `e2e_working_directory` voor de nieuwe module |

### Nieuwe bestanden in de implementatiefase

| Bestand | Verantwoordelijkheid |
|---|---|
| `dotnet/private/rules/csharp/actions/implicit_usings.bzl` | Pure namespaceselectie en `actions.write` met vaste header, LF en trailing newline |
| `dotnet/private/tests/csharp_implicit_usings/BUILD.bazel` | Pure tests, actie-analyse en compileer-/runtargets voor alle publieke C#-varianten |
| `dotnet/private/tests/csharp_implicit_usings/implicit_usings_test.bzl` | Exacte volledige namespacetests voor alle SDK's en `NET_FRAMEWORKS` |
| `dotnet/private/tests/csharp_implicit_usings/action_test.bzl` | Analyse van write-inhoud, outputs, write-inputs, compilerinputs en argumenten |
| `dotnet/private/tests/csharp_implicit_usings/{Library,Binary,GenericTest,NUnitTests,XunitTests,MSTestTests,Internals,Disabled}.cs` | Compileerfixtures die implicit usings aantoonbaar nodig hebben of expliciet uitschakelen |
| `dotnet/gazelle/testdata/nullable_implicit_usings/**` | Automatisch ontdekte golden voor unset, expliciete defaults, enable, overerving, disable en merge-behoud |
| `e2e/gazelle_nullable_implicit_usings/{MODULE.bazel,.bazelrc,.bazelversion,BUILD.bazel,internal_dev_deps.bzl}` | Zelfstandige module en eigen Gazelle-binary; geen nieuwe rootdirectives |
| `e2e/gazelle_nullable_implicit_usings/src/unset/**` | Unset-fixture zonder beide attributen en met expliciete usings |
| `e2e/gazelle_nullable_implicit_usings/src/enabled/**` | Enabled library, binary en NUnit-test plus inherited en disabled children |
| `e2e/gazelle_nullable_implicit_usings/MODULE.bazel.lock` | Door Bazel 9.1.1 gegenereerde reproduceerbare module-lock; alleen dit genegeerde bestand wordt met `git add -f` toegevoegd |

`dotnet/private/rules/csharp/{nunit_test,xunit_test,mstest_test}.bzl`, `dotnet/defs.bzl`, de resolver, F#-bestanden, `.gitignore` en iedere bestaande e2e-module blijven expliciet ongewijzigd. De macro's geven `implicit_usings` al via `**kwargs` door.

---

### Task 1: Dotnetconfig-waarden, geconfigureerd-status en validatie
**Status:** completed — Dotnetconfig bewaart en valideert beide waarden met expliciete geconfigureerd-status, overerving en isolatie.

**Files:**
- Modify: `dotnet/gazelle/dotnetconfig/config.go`
- Test: `dotnet/gazelle/dotnetconfig/config_test.go`

- [ ] **Step 1: Voeg de falende configuratietests toe**

Wijzig in `dotnet/gazelle/dotnetconfig/config_test.go` de import exact van:

```go
import (
	"reflect"
	"testing"
)
```

naar:

```go
import (
	"reflect"
	"strings"
	"testing"
)
```

Vervang in hetzelfde bestand exact deze overgang na `TestDefaults`:

```go
}

func TestNewChildInheritsAndIsolates(t *testing.T) {
```

door deze volledige new string met de nieuwe tests ertussen:

```go
}

func TestNullableAndImplicitUsingsDefaults(t *testing.T) {
	c := New("/repo")
	if got, configured := c.Nullable(); configured || got != "" {
		t.Errorf("Nullable() = %q, %v; want empty, false", got, configured)
	}
	if got, configured := c.ImplicitUsings(); configured || got {
		t.Errorf("ImplicitUsings() = %v, %v; want false, false", got, configured)
	}
}

func assertDirectiveValueError(t *testing.T, err error, value, allowed string) {
	t.Helper()
	if err == nil {
		t.Fatalf("value %q returned nil error, want error", value)
	}
	if !strings.Contains(err.Error(), "possible values are "+allowed) {
		t.Errorf("error %q does not contain allowed values %q", err, allowed)
	}
	if !strings.Contains(err.Error(), "\""+value+"\"") {
		t.Errorf("error %q does not contain received value %q", err, value)
	}
}

func TestSetNullableValidation(t *testing.T) {
	c := New("/repo")
	for _, value := range []string{"disable", "enable", "warnings", "annotations"} {
		if err := c.SetNullable(value); err != nil {
			t.Fatalf("SetNullable(%q) = %v, want nil", value, err)
		}
		if got, configured := c.Nullable(); !configured || got != value {
			t.Errorf("Nullable() after %q = %q, %v", value, got, configured)
		}
	}
	for _, value := range []string{"true", "Enable", "annotations "} {
		assertDirectiveValueError(t, c.SetNullable(value), value, "disable/enable/warnings/annotations")
	}
	if got, configured := c.Nullable(); !configured || got != "annotations" {
		t.Errorf("invalid setter mutated Nullable() to %q, %v", got, configured)
	}
}

func TestSetImplicitUsingsValidation(t *testing.T) {
	c := New("/repo")
	for _, tc := range []struct {
		value string
		want  bool
	}{{"disable", false}, {"enable", true}} {
		if err := c.SetImplicitUsings(tc.value); err != nil {
			t.Fatalf("SetImplicitUsings(%q) = %v, want nil", tc.value, err)
		}
		if got, configured := c.ImplicitUsings(); !configured || got != tc.want {
			t.Errorf("ImplicitUsings() after %q = %v, %v; want %v, true", tc.value, got, configured, tc.want)
		}
	}
	for _, value := range []string{"true", "false", "warnings", "annotations", "Enable"} {
		assertDirectiveValueError(t, c.SetImplicitUsings(value), value, "disable/enable")
	}
	if got, configured := c.ImplicitUsings(); !configured || !got {
		t.Errorf("invalid setter mutated ImplicitUsings() to %v, %v; want true, true", got, configured)
	}
}

func TestNullableAndImplicitUsingsInheritanceAndIsolation(t *testing.T) {
	root := New("/repo")
	if err := root.SetNullable("enable"); err != nil {
		t.Fatal(err)
	}
	if err := root.SetImplicitUsings("enable"); err != nil {
		t.Fatal(err)
	}

	child := root.NewChild()
	sibling := root.NewChild()
	if got, configured := child.Nullable(); !configured || got != "enable" {
		t.Errorf("child Nullable() = %q, %v; want enable, true", got, configured)
	}
	if got, configured := child.ImplicitUsings(); !configured || !got {
		t.Errorf("child ImplicitUsings() = %v, %v; want true, true", got, configured)
	}

	if err := child.SetNullable("disable"); err != nil {
		t.Fatal(err)
	}
	if got, configured := child.ImplicitUsings(); !configured || !got {
		t.Errorf("nullable override changed child ImplicitUsings() to %v, %v", got, configured)
	}
	if err := child.SetImplicitUsings("disable"); err != nil {
		t.Fatal(err)
	}
	if got, configured := child.Nullable(); !configured || got != "disable" {
		t.Errorf("child Nullable() after overrides = %q, %v; want disable, true", got, configured)
	}
	if got, configured := child.ImplicitUsings(); !configured || got {
		t.Errorf("child ImplicitUsings() after overrides = %v, %v; want false, true", got, configured)
	}

	grandchild := child.NewChild()
	if got, configured := grandchild.Nullable(); !configured || got != "disable" {
		t.Errorf("grandchild Nullable() = %q, %v; want disable, true", got, configured)
	}
	if got, configured := grandchild.ImplicitUsings(); !configured || got {
		t.Errorf("grandchild ImplicitUsings() = %v, %v; want false, true", got, configured)
	}
	for name, cfg := range map[string]*Config{"root": root, "sibling": sibling} {
		if got, configured := cfg.Nullable(); !configured || got != "enable" {
			t.Errorf("%s Nullable() = %q, %v after child mutation; want enable, true", name, got, configured)
		}
		if got, configured := cfg.ImplicitUsings(); !configured || !got {
			t.Errorf("%s ImplicitUsings() = %v, %v after child mutation; want true, true", name, got, configured)
		}
	}
}

func TestNewChildInheritsAndIsolates(t *testing.T) {
```

- [ ] **Step 2: Draai de tests en bevestig de rode uitgangstoestand**

Run: `go test ./dotnet/gazelle/dotnetconfig/ -run 'TestNullableAndImplicitUsings|TestSetNullableValidation|TestSetImplicitUsingsValidation' -v`

Expected: compilatie FAALT met `c.Nullable undefined`, `c.ImplicitUsings undefined`, `c.SetNullable undefined` en `c.SetImplicitUsings undefined`.

- [ ] **Step 3: Implementeer de configuratie minimaal**

Vervang in `dotnet/gazelle/dotnetconfig/config.go` exact:

```go
	// DotnetProjectSdk sets the project_sdk attr of generated targets.
	// Defaults to "default".
	DotnetProjectSdk = "dotnet_project_sdk"
	// DotnetVisibility adds a visibility entry to generated targets.
```

door:

```go
	// DotnetProjectSdk sets the project_sdk attr of generated targets.
	// Defaults to "default".
	DotnetProjectSdk = "dotnet_project_sdk"
	// DotnetNullable sets the nullable attr of generated C# targets.
	// Valid values are "disable", "enable", "warnings" and "annotations".
	DotnetNullable = "dotnet_nullable"
	// DotnetImplicitUsings sets the implicit_usings attr of generated C# targets.
	// Valid values are "disable" and "enable".
	DotnetImplicitUsings = "dotnet_implicit_usings"
	// DotnetVisibility adds a visibility entry to generated targets.
```

Vervang de huidige struct:

```go
type Config struct {
	repoRoot          string
	targetFrameworks  []string
	nugetRepoPrefix   string
	resolves          map[string]string
	testFramework     string
	generateBinary    bool
	projectSdk        string
	visibility        []string
	unresolvedImports string
	nugetLockFile     string
}
```

door:

```go
type Config struct {
	repoRoot                  string
	targetFrameworks          []string
	nugetRepoPrefix           string
	resolves                  map[string]string
	testFramework             string
	generateBinary            bool
	projectSdk                string
	nullable                  string
	nullableConfigured        bool
	implicitUsings            bool
	implicitUsingsConfigured  bool
	visibility                []string
	unresolvedImports         string
	nugetLockFile             string
}
```

Vervang de huidige `New` exact van:

```go
// New returns the root Config with default values.
func New(repoRoot string) *Config {
	return &Config{
		repoRoot:          repoRoot,
		nugetRepoPrefix:   "nuget.",
		resolves:          map[string]string{},
		generateBinary:    true,
		projectSdk:        "default",
		unresolvedImports: "warn",
		nugetLockFile:     "nuget_resolve.json",
	}
}
```

naar:

```go
// New returns the root Config with default values.
func New(repoRoot string) *Config {
	return &Config{
		repoRoot:                 repoRoot,
		nugetRepoPrefix:          "nuget.",
		resolves:                 map[string]string{},
		generateBinary:           true,
		projectSdk:               "default",
		nullable:                 "",
		nullableConfigured:       false,
		implicitUsings:           false,
		implicitUsingsConfigured: false,
		unresolvedImports:        "warn",
		nugetLockFile:            "nuget_resolve.json",
	}
}
```

Vervang in hetzelfde bestand exact:

```go
// SetProjectSdk sets the project_sdk attr value for generated targets.
func (c *Config) SetProjectSdk(v string) { c.projectSdk = v }

// AddVisibility appends a visibility entry.
```

door:

```go
// SetProjectSdk sets the project_sdk attr value for generated targets.
func (c *Config) SetProjectSdk(v string) { c.projectSdk = v }

// Nullable returns the nullable value and whether a directive configured it.
// The empty, unconfigured state is distinct from the rule default "disable".
func (c *Config) Nullable() (string, bool) { return c.nullable, c.nullableConfigured }

// SetNullable validates and sets the nullable directive value.
func (c *Config) SetNullable(value string) error {
	switch value {
	case "disable", "enable", "warnings", "annotations":
		c.nullable = value
		c.nullableConfigured = true
		return nil
	}
	return fmt.Errorf("possible values are disable/enable/warnings/annotations, got %q", value)
}

// ImplicitUsings returns the boolean value and whether a directive configured it.
// False, false means unset; false, true means explicitly disabled.
func (c *Config) ImplicitUsings() (bool, bool) {
	return c.implicitUsings, c.implicitUsingsConfigured
}

// SetImplicitUsings validates and sets the implicit-usings directive value.
func (c *Config) SetImplicitUsings(value string) error {
	switch value {
	case "disable":
		c.implicitUsings = false
	case "enable":
		c.implicitUsings = true
	default:
		return fmt.Errorf("possible values are disable/enable, got %q", value)
	}
	c.implicitUsingsConfigured = true
	return nil
}

// AddVisibility appends a visibility entry.
```

`NewChild` blijft ongewijzigd: de structkopie erft beide waarden en beide geconfigureerd-flags, terwijl child-overrides op de kopie plaatsvinden.

- [ ] **Step 4: Formatteer en draai de configuratietests groen**

```bash
gofmt -w dotnet/gazelle/dotnetconfig/config.go dotnet/gazelle/dotnetconfig/config_test.go
go test ./dotnet/gazelle/dotnetconfig/ -v
```

Expected: alle configuratietests PASS, inclusief defaults, alle geldige waarden, foutmeldingen, onafhankelijke overrides en parent/sibling-isolatie.

- [ ] **Step 5: Review de taskdiff**

```bash
git status --short
git diff --check
git diff -- dotnet/gazelle/dotnetconfig/config.go dotnet/gazelle/dotnetconfig/config_test.go
git log --oneline -10
```

Expected: `git diff --check` is stil en exit 0; de diff bevat alleen deze twee configuratiebestanden en geen generator- of resolverwijziging.

- [ ] **Step 6: Commit de configuratie**

```bash
git add dotnet/gazelle/dotnetconfig/config.go dotnet/gazelle/dotnetconfig/config_test.go
git commit -m "Add nullable and implicit usings Gazelle configuration"
```

- [ ] **Step 7: Werk alleen deze taskstatus bij**

Vervang in dit plan onder Task 1 exact `**Status:** pending` door:

```markdown
**Status:** completed — Dotnetconfig bewaart en valideert beide waarden met expliciete geconfigureerd-status, overerving en isolatie.
```

- [ ] **Step 8: Commit de statusupdate**

```bash
git diff --check
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 1 complete in plan"
```

---

### Task 2: Directive-registratie en Configure-doorvoer
**Status:** completed — Beide directives zijn geregistreerd en Configure verwerkt enable, disable en overerving via het bestaande fatale foutpad.

**Files:**
- Modify: `dotnet/gazelle/configure.go`
- Test: `dotnet/gazelle/lang_test.go`

- [ ] **Step 1: Voeg de falende registratie- en Configure-tests toe**

Wijzig in `dotnet/gazelle/lang_test.go` de import van:

```go
import (
	"reflect"
	"testing"
```

naar:

```go
import (
	"path/filepath"
	"reflect"
	"testing"
```

Vervang in hetzelfde bestand exact de staart van `TestConfigureInheritance`:

```go
	if got := cfg.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net10.0"}) {
		t.Errorf("TargetFrameworks() = %v, want [net10.0]", got)
	}
}
```

door diezelfde staart plus deze volledige nieuwe tests:

```go
	if got := cfg.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net10.0"}) {
		t.Errorf("TargetFrameworks() = %v, want [net10.0]", got)
	}
}

func TestKnownDirectivesIncludeNullableAndImplicitUsings(t *testing.T) {
	l := NewLanguage().(*csharpLang)
	directives := l.KnownDirectives()
	for _, want := range []string{"dotnet_nullable", "dotnet_implicit_usings"} {
		found := false
		for _, got := range directives {
			if got == want {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("KnownDirectives() = %v, missing %q", directives, want)
		}
	}
}

func TestConfigureNullableAndImplicitUsings(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src")
	parentFile, err := rule.LoadData(
		filepath.Join(dir, "src", "BUILD.bazel"),
		"src",
		[]byte("# gazelle:dotnet_nullable annotations\n# gazelle:dotnet_implicit_usings enable\n"),
	)
	if err != nil {
		t.Fatal(err)
	}
	l.Configure(c, "src", parentFile)
	l.Configure(c, "src/child", nil)
	l.Configure(c, "src/sibling", nil)

	assertConfig := func(rel, wantNullable string, wantImplicit bool) {
		t.Helper()
		cfg := getConfig(c, rel)
		if cfg == nil {
			t.Fatalf("no config for %s", rel)
		}
		if got, configured := cfg.Nullable(); !configured || got != wantNullable {
			t.Errorf("%s Nullable() = %q, %v; want %q, true", rel, got, configured, wantNullable)
		}
		if got, configured := cfg.ImplicitUsings(); !configured || got != wantImplicit {
			t.Errorf("%s ImplicitUsings() = %v, %v; want %v, true", rel, got, configured, wantImplicit)
		}
	}
	assertConfig("src", "annotations", true)
	assertConfig("src/child", "annotations", true)
	assertConfig("src/sibling", "annotations", true)

	childFile, err := rule.LoadData(
		filepath.Join(dir, "src", "child", "BUILD.bazel"),
		"src/child",
		[]byte("# gazelle:dotnet_nullable disable\n# gazelle:dotnet_implicit_usings disable\n"),
	)
	if err != nil {
		t.Fatal(err)
	}
	l.Configure(c, "src/child", childFile)
	assertConfig("src/child", "disable", false)
	assertConfig("src", "annotations", true)
	assertConfig("src/sibling", "annotations", true)
}
```

- [ ] **Step 2: Draai de tests en bevestig de falende registratie/doorvoer**

Run: `go test ./dotnet/gazelle/ -run 'TestKnownDirectivesIncludeNullableAndImplicitUsings|TestConfigureNullableAndImplicitUsings' -v`

Expected: FAIL; de eerste test meldt ontbrekende directive-namen en de tweede meldt dat nullable/implicit usings niet geconfigureerd zijn.

- [ ] **Step 3: Registreer en verwerk beide directives**

Vervang in `dotnet/gazelle/configure.go` de returnlijst van `KnownDirectives` exact van:

```go
	return []string{
		dotnetconfig.DotnetTargetFrameworks,
		dotnetconfig.DotnetNugetRepoPrefix,
		dotnetconfig.DotnetResolve,
		dotnetconfig.DotnetTestFramework,
		dotnetconfig.DotnetGenerateBinary,
		dotnetconfig.DotnetProjectSdk,
		dotnetconfig.DotnetVisibility,
		dotnetconfig.DotnetUnresolvedImports,
	}
```

naar:

```go
	return []string{
		dotnetconfig.DotnetTargetFrameworks,
		dotnetconfig.DotnetNugetRepoPrefix,
		dotnetconfig.DotnetResolve,
		dotnetconfig.DotnetTestFramework,
		dotnetconfig.DotnetGenerateBinary,
		dotnetconfig.DotnetProjectSdk,
		dotnetconfig.DotnetNullable,
		dotnetconfig.DotnetImplicitUsings,
		dotnetconfig.DotnetVisibility,
		dotnetconfig.DotnetUnresolvedImports,
	}
```

Vervang in de directive-`switch` exact:

```go
			case dotnetconfig.DotnetProjectSdk:
				cfg.SetProjectSdk(d.Value)
			case dotnetconfig.DotnetVisibility:
				cfg.AddVisibility(d.Value)
```

door:

```go
			case dotnetconfig.DotnetProjectSdk:
				cfg.SetProjectSdk(d.Value)
			case dotnetconfig.DotnetNullable:
				if err := cfg.SetNullable(d.Value); err != nil {
					log.Fatalf("invalid value for directive %q: %v", dotnetconfig.DotnetNullable, err)
				}
			case dotnetconfig.DotnetImplicitUsings:
				if err := cfg.SetImplicitUsings(d.Value); err != nil {
					log.Fatalf("invalid value for directive %q: %v", dotnetconfig.DotnetImplicitUsings, err)
				}
			case dotnetconfig.DotnetVisibility:
				cfg.AddVisibility(d.Value)
```

De setterfout bevat ontvangen waarde en toegestane set; deze bestaande `log.Fatalf`-vorm voegt de directive-naam toe. Er komen geen flags of nieuwe foutpaden bij.

- [ ] **Step 4: Formatteer en draai de Go-tests**

```bash
gofmt -w dotnet/gazelle/configure.go dotnet/gazelle/lang_test.go
go test ./dotnet/gazelle/... -v
```

Expected: alle Go-tests onder `dotnet/gazelle` PASS; de bestaande resolver- en generatietests blijven ongewijzigd slagen.

- [ ] **Step 5: Review en commit de directive-doorvoer**

```bash
git status --short
git diff --check
git diff -- dotnet/gazelle/configure.go dotnet/gazelle/lang_test.go
git log --oneline -10
git add dotnet/gazelle/configure.go dotnet/gazelle/lang_test.go
git commit -m "Register nullable and implicit usings directives"
```

Expected vóór de commit: alleen de twee genoemde bestanden zijn gewijzigd; `git diff --check` is stil.

- [ ] **Step 6: Werk alleen deze taskstatus bij**

Vervang onder Task 2 exact `**Status:** pending` door:

```markdown
**Status:** completed — Beide directives zijn geregistreerd en Configure verwerkt enable, disable en overerving via het bestaande fatale foutpad.
```

- [ ] **Step 7: Commit de statusupdate**

```bash
git diff --check
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 2 complete in plan"
```

---

### Task 3: Gedeelde attribuutgeneratie voor alle vijf generated kinds
**Status:** completed — Eén Go-helper schrijft alleen geconfigureerde attributen op library, binary en alle drie gegenereerde testframeworkkinds; de beperkte bestaande-rule-merge bewaart unset en `# keep` en past expliciete overrides toe.

**Files:**
- Modify: `dotnet/gazelle/generate.go`
- Test: `dotnet/gazelle/generate_test.go`

- [ ] **Step 1: Voeg de falende generatiematrix en bestaande-rule-test toe**

Vervang aan het einde van `dotnet/gazelle/generate_test.go` exact deze bestaande staart:

```go
	if !reflect.DeepEqual(input.imports, []string{"App", "NUnit.Framework"}) {
		t.Errorf("test imports = %v, want [App NUnit.Framework]", input.imports)
	}
}
```

door diezelfde staart plus deze complete fixture en test:

```go
	if !reflect.DeepEqual(input.imports, []string{"App", "NUnit.Framework"}) {
		t.Errorf("test imports = %v, want [App NUnit.Framework]", input.imports)
	}
}

const mstestTestSrc = `using Calculator;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace Calculator.Tests;

[TestClass]
public sealed class ArithmeticTests
{
    [TestMethod]
    public void AddWorks()
    {
        Assert.AreEqual(4, Arithmetic.Add(2, 2));
    }
}
`

func TestGenerateNullableAndImplicitUsingsMatrix(t *testing.T) {
	tests := []struct {
		name           string
		directives     string
		nullable       string
		nullableSet    bool
		implicit       bool
		implicitSet    bool
	}{
		{name: "unset"},
		{
			name:        "explicit disable",
			directives:  "# gazelle:dotnet_nullable disable\n# gazelle:dotnet_implicit_usings disable\n",
			nullable:    "disable",
			nullableSet: true,
			implicit:    false,
			implicitSet: true,
		},
		{
			name:        "enable",
			directives:  "# gazelle:dotnet_nullable enable\n# gazelle:dotnet_implicit_usings enable\n",
			nullable:    "enable",
			nullableSet: true,
			implicit:    true,
			implicitSet: true,
		},
		{
			name:        "warnings does not configure implicit usings",
			directives:  "# gazelle:dotnet_nullable warnings\n",
			nullable:    "warnings",
			nullableSet: true,
		},
		{
			name:        "annotations does not configure implicit usings",
			directives:  "# gazelle:dotnet_nullable annotations\n",
			nullable:    "annotations",
			nullableSet: true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			l, c, dir := setupLang(t, net10Directive+tc.directives, "src", "src/matrix")
			sources := map[string]string{
				"Calculator.cs":  calculatorSrc,
				"NUnitTests.cs":  nunitTestSrc,
				"XUnitTests.cs":  xunitTestSrc,
				"MSTestTests.cs": mstestTestSrc,
				"Program.cs":     programSrc,
			}
			for name, src := range sources {
				writeFile(t, filepath.Join(dir, "src", "matrix"), name, src)
			}

			res := generate(
				t,
				l,
				c,
				dir,
				"src/matrix",
				"Calculator.cs",
				"MSTestTests.cs",
				"NUnitTests.cs",
				"Program.cs",
				"XUnitTests.cs",
			)
			if len(res.Gen) != 5 {
				t.Fatalf("GenerateRules() returned %d rules, want 5", len(res.Gen))
			}
			rules := map[string]*rule.Rule{}
			for _, r := range res.Gen {
				if _, exists := rules[r.Kind()]; exists {
					t.Fatalf("duplicate generated kind %s", r.Kind())
				}
				rules[r.Kind()] = r
			}

			for _, kind := range []string{
				"csharp_library",
				"csharp_binary",
				"csharp_nunit_test",
				"csharp_xunit_test",
				"csharp_mstest_test",
			} {
				r := rules[kind]
				if r == nil {
					t.Errorf("missing generated kind %s", kind)
					continue
				}
				nullableAttr := r.Attr("nullable")
				if !tc.nullableSet && nullableAttr != nil {
					t.Errorf("%s nullable is set to %v, want absent", kind, nullableAttr)
				}
				if tc.nullableSet {
					if nullableAttr == nil {
						t.Errorf("%s nullable is absent, want %q", kind, tc.nullable)
					} else if got := r.AttrString("nullable"); got != tc.nullable {
						t.Errorf("%s nullable = %q, want %q", kind, got, tc.nullable)
					}
				}

				implicitAttr := r.Attr("implicit_usings")
				if !tc.implicitSet && implicitAttr != nil {
					t.Errorf("%s implicit_usings is set to %v, want absent", kind, implicitAttr)
				}
				if tc.implicitSet {
					if implicitAttr == nil {
						t.Errorf("%s implicit_usings is absent, want configured boolean", kind)
					} else if got := r.AttrBool("implicit_usings"); got != tc.implicit {
						t.Errorf("%s implicit_usings = %v, want %v", kind, got, tc.implicit)
					}
				}
			}
		})
	}
}

func TestGenerateExplicitDirectivesOverrideExistingAttrs(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/existing")
	existing, err := rule.LoadData(
		filepath.Join(dir, "src", "existing", "BUILD.bazel"),
		"src/existing",
		[]byte(`# gazelle:dotnet_nullable disable
# gazelle:dotnet_implicit_usings disable

csharp_library(
    name = "existing",
    srcs = ["Calculator.cs"],
    implicit_usings = True,
    nullable = "enable",
)
`),
	)
	if err != nil {
		t.Fatal(err)
	}
	l.Configure(c, "src/existing", existing)
	writeFile(t, filepath.Join(dir, "src", "existing"), "Calculator.cs", calculatorSrc)

	res := l.GenerateRules(language.GenerateArgs{
		Config:       c,
		Dir:          filepath.Join(dir, "src", "existing"),
		Rel:          "src/existing",
		RegularFiles: []string{"Calculator.cs"},
		File:         existing,
	})
	if len(res.Gen) != 1 {
		t.Fatalf("GenerateRules() returned %d rules, want 1", len(res.Gen))
	}

	// Run the same pre-resolve merge as Gazelle. Explicit directives must win
	// even though these scalar attributes are not globally mergeable.
	rule.MergeRules(res.Gen[0], existing.Rules[0], csharpKindInfo.MergeableAttrs, existing.Path)
	got := existing.Rules[0]
	if value := got.AttrString("nullable"); value != "disable" {
		t.Errorf("merged nullable = %q, want disable", value)
	}
	if got.Attr("implicit_usings") == nil {
		t.Error("merged implicit_usings is absent, want explicit False")
	} else if value := got.AttrBool("implicit_usings"); value {
		t.Error("merged implicit_usings = True, want explicit False")
	}
}
```

De combinatie `Attr("implicit_usings") != nil` en `AttrBool("implicit_usings")` onderscheidt afwezig, expliciet `False` en expliciet `True`. De productiecode hieronder geeft een echte Go-bool aan `rule.SetAttr`; de golden in Task 4 bewijst de uiteindelijke `True`/`False`-serialisatie en de echte BUILD-merge.

- [ ] **Step 2: Draai de matrix en bestaande-rule-test en bevestig de rode uitgangstoestand**

Run: `go test ./dotnet/gazelle/ -run 'TestGenerateNullableAndImplicitUsingsMatrix|TestGenerateExplicitDirectivesOverrideExistingAttrs' -v`

Expected: in de matrix PASS alleen `unset`; `explicit disable`, `enable`, `warnings` en `annotations` FAIL wegens ontbrekende attributen. De bestaande-rule-test FAILT bovendien met `merged nullable = "enable", want disable` en `merged implicit_usings = True, want explicit False`: alleen `SetAttr` op de nieuwe regel zou dit tweede defect niet oplossen.

- [ ] **Step 3: Implementeer één gedeelde attribuuthelper en gebruik hem overal**

Vervang in `dotnet/gazelle/generate.go` exact:

```go
	"sort"
	"strings"

	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/parser"
```

door:

```go
	"sort"
	"strings"

	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/dotnetconfig"
	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/parser"
```

Vervang vervolgens exact:

```go
// GenerateRules implements language.Language.
func (l *csharpLang) GenerateRules(args language.GenerateArgs) language.GenerateResult {
```

door:

```go
// setNullableAndImplicitUsingsAttrs writes only explicitly configured values
// and returns exactly those attribute names for the existing-rule merge below.
func setNullableAndImplicitUsingsAttrs(r *rule.Rule, cfg *dotnetconfig.Config) map[string]bool {
	configured := map[string]bool{}
	if value, isConfigured := cfg.Nullable(); isConfigured {
		r.SetAttr("nullable", value)
		configured["nullable"] = true
	}
	if value, isConfigured := cfg.ImplicitUsings(); isConfigured {
		r.SetAttr("implicit_usings", value)
		configured["implicit_usings"] = true
	}
	return configured
}

// mergeNullableAndImplicitUsingsAttrs applies explicit directives to the one
// existing rule matched by kind and name. Gazelle otherwise preserves existing
// non-mergeable scalars. A stub containing only configured attributes keeps
// unset attributes untouched and delegates # keep handling to MergeRules.
func mergeNullableAndImplicitUsingsAttrs(generated *rule.Rule, file *rule.File, cfg *dotnetconfig.Config) {
	if file == nil {
		return
	}
	override := rule.NewRule(generated.Kind(), generated.Name())
	mergeable := setNullableAndImplicitUsingsAttrs(override, cfg)
	if len(mergeable) == 0 {
		return
	}

	var existing *rule.Rule
	for _, candidate := range file.Rules {
		if candidate.Name() != generated.Name() {
			continue
		}
		if candidate.Kind() != generated.Kind() || existing != nil {
			// Match the normal merger's ambiguous-name behavior: do not update
			// any candidate when there is no unique kind-and-name match.
			return
		}
		existing = candidate
	}
	if existing != nil {
		rule.MergeRules(override, existing, mergeable, file.Path)
	}
}

// GenerateRules implements language.Language.
func (l *csharpLang) GenerateRules(args language.GenerateArgs) language.GenerateResult {
```

Vervang in de library-branch exact:

```go
		lib.SetAttr("visibility", cfg.Visibility())
		if len(testTargetNames) > 0 {
```

door:

```go
		lib.SetAttr("visibility", cfg.Visibility())
		setNullableAndImplicitUsingsAttrs(lib, cfg)
		if len(testTargetNames) > 0 {
```

Vervang in de test-loop exact:

```go
		r.SetAttr("visibility", cfg.Visibility())
		switch {
```

door:

```go
		r.SetAttr("visibility", cfg.Visibility())
		setNullableAndImplicitUsingsAttrs(r, cfg)
		switch {
```

Deze ene test-loopaanroep dekt NUnit, xUnit en MSTest. Vervang in de binary-loop exact:

```go
		r.SetAttr("visibility", cfg.Visibility())
		// Binaries advertise their namespaces like libraries do, so a
```

door:

```go
		r.SetAttr("visibility", cfg.Visibility())
		setNullableAndImplicitUsingsAttrs(r, cfg)
		// Binaries advertise their namespaces like libraries do, so a
```

Vervang aan het einde van `GenerateRules` exact:

```go
	return res
}
```

door:

```go
	for _, generated := range res.Gen {
		mergeNullableAndImplicitUsingsAttrs(generated, args.File, cfg)
	}
	return res
}
```

De aanroepen in de library-, test- en binary-branches dekken de vijf generated kinds. De laatste loop gebruikt voor bestaande regels dezelfde helper op een stub; alleen de teruggegeven, effectief geconfigureerde namen zijn mergeable in die beperkte merge. Daardoor overschrijft expliciet `disable` een bestaande `enable`, terwijl unset geen attribuut toevoegt of verwijdert en `rule.MergeRules` de bestaande `# keep`-regels toepast. Verander `csharpKindInfo.MergeableAttrs` niet: als deze twee namen daar globaal in stonden, zou een gegenereerde regel zonder geconfigureerd attribuut een bestaand attribuut bij unset verwijderen.

Er is bewust geen nieuwe `csharp_test`-generatie en geen wijziging aan `srcs`, TFM's, SDK, visibility, deps, IVT of `resolveInput`.

- [ ] **Step 4: Formatteer en draai de volledige generatietests**

```bash
gofmt -w dotnet/gazelle/generate.go dotnet/gazelle/generate_test.go
go test ./dotnet/gazelle/ -run 'TestGenerate' -v
go test ./dotnet/gazelle/...
```

Expected: alle vijf kinds slagen in alle vijf configuratiescenario's; de bestaande-rule-test eindigt met `nullable = "disable"` en aanwezig `implicit_usings = False`; de volledige Go-package-suite PASS.

- [ ] **Step 5: Review en commit de generatorwijziging**

```bash
git status --short
git diff --check
git diff -- dotnet/gazelle/generate.go dotnet/gazelle/generate_test.go
git log --oneline -10
git add dotnet/gazelle/generate.go dotnet/gazelle/generate_test.go
git commit -m "Generate nullable and implicit usings attributes"
```

Expected vóór de commit: exact deze twee bestanden; geen resolverdiff en `git diff --check` is stil.

- [ ] **Step 6: Werk alleen deze taskstatus bij**

Vervang onder Task 3 exact `**Status:** pending` door:

```markdown
**Status:** completed — Eén Go-helper schrijft alleen geconfigureerde attributen op library, binary en alle drie gegenereerde testframeworkkinds; de beperkte bestaande-rule-merge bewaart unset en `# keep` en past expliciete overrides toe.
```

- [ ] **Step 7: Commit de statusupdate**

```bash
git diff --check
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 3 complete in plan"
```

---

### Task 4: Golden voor serialisatie, overerving en merge-behoud
**Status:** completed — De golden bewijst unset, expliciete defaults, enable, overerving, child-disable inclusief vervanging van een bestaande enable, en behoud van handmatige attributen bij unset.

**Files:**
- Create: `dotnet/gazelle/testdata/nullable_implicit_usings/MODULE.bazel`
- Create: `dotnet/gazelle/testdata/nullable_implicit_usings/expectedStderr.txt`
- Create: `dotnet/gazelle/testdata/nullable_implicit_usings/BUILD.in`
- Create: `dotnet/gazelle/testdata/nullable_implicit_usings/BUILD.out`
- Create: `dotnet/gazelle/testdata/nullable_implicit_usings/src/unset/{BUILD.out,Unset.cs}`
- Create: `dotnet/gazelle/testdata/nullable_implicit_usings/src/manual/{BUILD.in,BUILD.out,Manual.cs}`
- Create: `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/{BUILD.in,BUILD.out,Enabled.cs,Program.cs}`
- Create: `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/inherited/{BUILD.out,Inherited.cs}`
- Create: `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/disabled/{BUILD.in,BUILD.out,Disabled.cs}`

- [ ] **Step 1: Maak de root-, unset- en manual-fixture**

Maak vanuit de repository-root eerst de nieuwe fixturemappen en daarna een leeg `dotnet/gazelle/testdata/nullable_implicit_usings/MODULE.bazel` (nul bytes; het bestand is alleen de bestaande golden-discoverymarker):

```bash
mkdir -p dotnet/gazelle/testdata/nullable_implicit_usings/src/unset dotnet/gazelle/testdata/nullable_implicit_usings/src/manual dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/inherited dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/disabled
: > dotnet/gazelle/testdata/nullable_implicit_usings/MODULE.bazel
```

Expected: beide commando's exit 0; de rootmap en alle vier source-submappen bestaan voordat de bestanden hieronder worden geschreven.

Create `dotnet/gazelle/testdata/nullable_implicit_usings/expectedStderr.txt`:

```text
gazelle: no nuget_resolve.json at %WORKSPACEPATH%/nuget_resolve.json; NuGet resolution is disabled
```

Create zowel `dotnet/gazelle/testdata/nullable_implicit_usings/BUILD.in` als `dotnet/gazelle/testdata/nullable_implicit_usings/BUILD.out` met exact:

```python
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/unset/Unset.cs`:

```csharp
namespace Unset;

public static class Values
{
    public static int One() => 1;
}
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/unset/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "unset",
    srcs = ["Unset.cs"],
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/manual/Manual.cs`:

```csharp
namespace Manual;

public static class Values
{
    public static int Two() => 2;
}
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/manual/BUILD.in`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "manual",
    srcs = ["Manual.cs"],
    implicit_usings = True,
    nullable = "annotations",
)
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/manual/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "manual",
    srcs = ["Manual.cs"],
    implicit_usings = True,
    nullable = "annotations",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)
```

De manual-case bewijst dat unset geen delete/reset is. De unset-case is een nieuwe regel en bevat juist geen van beide attributen.

- [ ] **Step 2: Maak enabled, inherited en disabled**

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/BUILD.in`:

```python
# gazelle:dotnet_nullable enable
# gazelle:dotnet_implicit_usings enable
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/Enabled.cs`:

```csharp
namespace Enabled;

public static class Values
{
    public static int Three() => 3;
}
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/Program.cs`:

```csharp
namespace Enabled;

public static class Program
{
    public static void Main(string[] args)
    {
    }
}
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/BUILD.out`:

```python
# gazelle:dotnet_nullable enable
# gazelle:dotnet_implicit_usings enable

load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary", "csharp_library")

csharp_library(
    name = "enabled",
    srcs = ["Enabled.cs"],
    implicit_usings = True,
    nullable = "enable",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)

csharp_binary(
    name = "program",
    srcs = ["Program.cs"],
    implicit_usings = True,
    nullable = "enable",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/inherited/Inherited.cs`:

```csharp
namespace Inherited;

public static class Values
{
    public static int Four() => 4;
}
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/inherited/BUILD.out` (bewust geen `BUILD.in` en dus geen eigen directives):

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "inherited",
    srcs = ["Inherited.cs"],
    implicit_usings = True,
    nullable = "enable",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/disabled/BUILD.in` met zowel de child-directives als een bestaande regel op `enable`, zodat deze golden tegelijk overerving van de enabled-parent en vervanging van een eerdere expliciete enable dekt:

```python
# gazelle:dotnet_nullable disable
# gazelle:dotnet_implicit_usings disable

load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "disabled",
    srcs = ["Disabled.cs"],
    implicit_usings = True,
    nullable = "enable",
)
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/disabled/Disabled.cs`:

```csharp
namespace Disabled;

public static class Values
{
    public static int Five() => 5;
}
```

Create `dotnet/gazelle/testdata/nullable_implicit_usings/src/enabled/disabled/BUILD.out`:

```python
# gazelle:dotnet_nullable disable
# gazelle:dotnet_implicit_usings disable

load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "disabled",
    srcs = ["Disabled.cs"],
    implicit_usings = False,
    nullable = "disable",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)
```

- [ ] **Step 3: Draai de golden en controleer dat er geen fixture-drift is**

Run: `bazel test //dotnet/gazelle/testdata:nullable_implicit_usings`

Expected: PASS; de bestaande `gazelle_generation_test` ontdekt de nieuwe module automatisch via `MODULE.bazel`, en de gegenereerde bestanden zijn bytegelijk aan alle `BUILD.out`-bestanden. In het bijzonder blijft de manual-regel bij unset op `annotations`/`True`, terwijl de bestaande disabled-regel van `enable`/`True` naar `disable`/`False` gaat.

Run daarna:

```bash
git diff --check
git status --short -- dotnet/gazelle/testdata/nullable_implicit_usings
```

Expected: geen whitespacefouten; alleen de nieuwe fixturebestanden zijn untracked. De vermelde attribuutvolgorde volgt Gazelle/buildtools: `name` en `srcs` hebben prioriteit, `deps` komt laatst en de overige attributen zijn alfabetisch.

- [ ] **Step 4: Review en commit de golden**

```bash
git status --short
git diff --check
git diff -- dotnet/gazelle/testdata/nullable_implicit_usings
git log --oneline -10
git add dotnet/gazelle/testdata/nullable_implicit_usings
git diff --cached --check
git diff --cached --stat
git commit -m "Add nullable and implicit usings generation golden"
```

- [ ] **Step 5: Werk alleen deze taskstatus bij**

Vervang onder Task 4 exact `**Status:** pending` door:

```markdown
**Status:** completed — De golden bewijst unset, expliciete defaults, enable, overerving, child-disable inclusief vervanging van een bestaande enable, en behoud van handmatige attributen bij unset.
```

- [ ] **Step 6: Commit de statusupdate**

```bash
git diff --check
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 4 complete in plan"
```

---

### Task 5: Pure Starlark-namespaceselectie en write-helper
**Status:** completed — De pure helper bevat de exacte .NET 10-sets, NET_FRAMEWORKS-uitzondering en een deterministische actions.write-helper.

**Files:**
- Create: `dotnet/private/rules/csharp/actions/implicit_usings.bzl`
- Modify: `dotnet/private/rules/csharp/actions/BUILD.bazel`
- Create: `dotnet/private/tests/csharp_implicit_usings/BUILD.bazel`
- Create: `dotnet/private/tests/csharp_implicit_usings/implicit_usings_test.bzl`

- [ ] **Step 1: Schrijf de falende pure helpertests**

Maak vanuit de repository-root het nieuwe testpackage en controleer de map:

```bash
mkdir -p dotnet/private/tests/csharp_implicit_usings
test -d dotnet/private/tests/csharp_implicit_usings
```

Expected: beide commando's exit 0 en geen output.

Create `dotnet/private/tests/csharp_implicit_usings/implicit_usings_test.bzl` volledig:

```python
"""Exact tests for the fixed .NET 10 implicit-using namespace sets."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    "//dotnet/private/rules/csharp/actions:implicit_usings.bzl",
    "implicit_usings_namespaces",
)

_BASE = [
    "System",
    "System.Collections.Generic",
    "System.IO",
    "System.Linq",
    "System.Net.Http",
    "System.Threading",
    "System.Threading.Tasks",
]

_BASE_NET_FRAMEWORK = [
    "System",
    "System.Collections.Generic",
    "System.IO",
    "System.Linq",
    "System.Threading",
    "System.Threading.Tasks",
]

_WEB = _BASE + [
    "System.Net.Http.Json",
    "Microsoft.AspNetCore.Builder",
    "Microsoft.AspNetCore.Hosting",
    "Microsoft.AspNetCore.Http",
    "Microsoft.AspNetCore.Routing",
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Hosting",
    "Microsoft.Extensions.Logging",
]

_WEB_NET_FRAMEWORK = _BASE_NET_FRAMEWORK + [
    "System.Net.Http.Json",
    "Microsoft.AspNetCore.Builder",
    "Microsoft.AspNetCore.Hosting",
    "Microsoft.AspNetCore.Http",
    "Microsoft.AspNetCore.Routing",
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Hosting",
    "Microsoft.Extensions.Logging",
]

_BLAZORWASM = _BASE + [
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Logging",
]

_BLAZORWASM_NET_FRAMEWORK = _BASE_NET_FRAMEWORK + [
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Logging",
]

_CASES = [
    ("default", "net10.0", _BASE),
    ("razor", "net10.0", _BASE),
    ("web", "net10.0", _WEB),
    ("blazorwasm", "net10.0", _BLAZORWASM),
    ("default", "net48", _BASE_NET_FRAMEWORK),
    ("razor", "net48", _BASE_NET_FRAMEWORK),
    ("web", "net48", _WEB_NET_FRAMEWORK),
    ("blazorwasm", "net48", _BLAZORWASM_NET_FRAMEWORK),
    ("default", "netstandard2.0", _BASE),
]

def _namespaces_test_impl(ctx):
    env = unittest.begin(ctx)
    for project_sdk, target_framework, expected in _CASES:
        actual = implicit_usings_namespaces(project_sdk, target_framework)
        asserts.equals(
            env,
            expected,
            actual,
            "implicit usings for %s/%s" % (project_sdk, target_framework),
        )
    return unittest.end(env)

namespaces_test = unittest.make(_namespaces_test_impl)

def implicit_usings_test_suite(name):
    unittest.suite(name, namespaces_test)
```

Create `dotnet/private/tests/csharp_implicit_usings/BUILD.bazel` volledig:

```python
load(":implicit_usings_test.bzl", "implicit_usings_test_suite")

implicit_usings_test_suite(name = "implicit_usings_namespaces_test")
```

- [ ] **Step 2: Draai de pure test en bevestig dat de helper ontbreekt**

Run: `bazel test //dotnet/private/tests/csharp_implicit_usings:implicit_usings_namespaces_test`

Expected: FAIL tijdens loading met `no such target '//dotnet/private/rules/csharp/actions:implicit_usings.bzl'`.

- [ ] **Step 3: Implementeer de vaste tabel en de geïsoleerde write-helper**

Create `dotnet/private/rules/csharp/actions/implicit_usings.bzl` volledig:

```python
"""Generate deterministic C# global usings for the supported project SDKs."""

load("//dotnet/private:common.bzl", "NET_FRAMEWORKS")

_BASE_NAMESPACES = [
    "System",
    "System.Collections.Generic",
    "System.IO",
    "System.Linq",
    "System.Net.Http",
    "System.Threading",
    "System.Threading.Tasks",
]

_WEB_EXTRA_NAMESPACES = [
    "System.Net.Http.Json",
    "Microsoft.AspNetCore.Builder",
    "Microsoft.AspNetCore.Hosting",
    "Microsoft.AspNetCore.Http",
    "Microsoft.AspNetCore.Routing",
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Hosting",
    "Microsoft.Extensions.Logging",
]

_BLAZORWASM_EXTRA_NAMESPACES = [
    "Microsoft.Extensions.Configuration",
    "Microsoft.Extensions.DependencyInjection",
    "Microsoft.Extensions.Logging",
]

def implicit_usings_namespaces(project_sdk, target_framework):
    """Return the complete ordered namespace list for an unnormalized SDK/TFM.

    Razor deliberately receives only the base set. Blazor WebAssembly receives
    only its own extensions; neither uses the pack-selection normalization to
    "web". The existing project_sdk and pack validation handles invalid pairs.
    """
    namespaces = [
        namespace
        for namespace in _BASE_NAMESPACES
        if namespace != "System.Net.Http" or target_framework not in NET_FRAMEWORKS
    ]
    if project_sdk == "web":
        namespaces = namespaces + _WEB_EXTRA_NAMESPACES
    elif project_sdk == "blazorwasm":
        namespaces = namespaces + _BLAZORWASM_EXTRA_NAMESPACES
    return namespaces

def write_implicit_usings(actions, *, out_dir, target_name, project_sdk, target_framework):
    """Declare and write one deterministic global-usings source for one TFM."""
    output = actions.declare_file("%s/%s.GlobalUsings.g.cs" % (out_dir, target_name))
    lines = ["// <auto-generated />"]
    for namespace in implicit_usings_namespaces(project_sdk, target_framework):
        lines.append("global using global::%s;" % namespace)
    lines.append("")
    actions.write(
        output = output,
        content = "\n".join(lines),
        mnemonic = "CSharpImplicitUsings",
    )
    return output
```

Vervang in `dotnet/private/rules/csharp/actions/BUILD.bazel` exact:

```python
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "scoped_css",
```

door:

```python
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "implicit_usings",
    srcs = ["implicit_usings.bzl"],
    visibility = ["//dotnet:__subpackages__"],
    deps = ["//dotnet/private:common"],
)

bzl_library(
    name = "scoped_css",
```

De helper importeert bewust niet `normalize_project_sdk`; `NET_FRAMEWORKS` levert de bestaande exacte TFM-classificatie. De laatste lege string in `lines` garandeert één afsluitende LF.

- [ ] **Step 4: Draai de pure tests groen en review**

```bash
bazel test //dotnet/private/tests/csharp_implicit_usings:implicit_usings_namespaces_test
git diff --check
```

Expected: PASS voor alle negen cases: default, razor, web en blazorwasm; alle vier met `net48`; en `netstandard2.0` met behouden `System.Net.Http`. `git diff --check` is stil.

- [ ] **Step 5: Commit de pure helper**

```bash
git status --short
git diff -- dotnet/private/rules/csharp/actions/implicit_usings.bzl dotnet/private/rules/csharp/actions/BUILD.bazel dotnet/private/tests/csharp_implicit_usings
git log --oneline -10
git add dotnet/private/rules/csharp/actions/implicit_usings.bzl dotnet/private/rules/csharp/actions/BUILD.bazel dotnet/private/tests/csharp_implicit_usings/BUILD.bazel dotnet/private/tests/csharp_implicit_usings/implicit_usings_test.bzl
git diff --cached --check
git diff --cached --stat
git commit -m "Add implicit usings namespace helper"
```

- [ ] **Step 6: Werk alleen deze taskstatus bij**

Vervang onder Task 5 exact `**Status:** pending` door:

```markdown
**Status:** completed — De pure helper bevat de exacte .NET 10-sets, NET_FRAMEWORKS-uitzondering en een deterministische actions.write-helper.
```

- [ ] **Step 7: Commit de statusupdate**

```bash
git diff --check
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 5 complete in plan"
```

---

### Task 6: Publiek attribuut, AssemblyAction en analyse-/compileertests
**Status:** completed — Alle publieke C#-varianten ondersteunen implicit_usings; analyse dekt write-bytes, paden, unset/disable en alle compileervertakkingen.

**Files:**
- Modify: `dotnet/private/rules/common/attrs.bzl`
- Modify: `dotnet/private/rules/csharp/library.bzl`
- Modify: `dotnet/private/rules/csharp/binary.bzl`
- Modify: `dotnet/private/rules/csharp/test.bzl`
- Modify: `dotnet/private/rules/csharp/actions/csharp_assembly.bzl`
- Modify: `dotnet/private/rules/csharp/actions/BUILD.bazel`
- Modify: `dotnet/private/tests/csharp_implicit_usings/BUILD.bazel`
- Create: `dotnet/private/tests/csharp_implicit_usings/action_test.bzl`
- Create: `dotnet/private/tests/csharp_implicit_usings/{Library,Binary,GenericTest,NUnitTests,XunitTests,MSTestTests,Internals,Disabled}.cs`

- [ ] **Step 1: Schrijf de actie-analysistest met de ondersteunde Bazel 9.1.1-API**

Create `dotnet/private/tests/csharp_implicit_usings/action_test.bzl` volledig:

```python
"""Analysis tests for implicit-usings write and CSharpCompile actions."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")

_DEFAULT_CONTENT = "\n".join([
    "// <auto-generated />",
    "global using global::System;",
    "global using global::System.Collections.Generic;",
    "global using global::System.IO;",
    "global using global::System.Linq;",
    "global using global::System.Net.Http;",
    "global using global::System.Threading;",
    "global using global::System.Threading.Tasks;",
    "",
])

def _global_usings_inputs(action):
    return [
        input_file
        for input_file in action.inputs.to_list()
        if input_file.basename.endswith(".GlobalUsings.g.cs")
    ]

def _implicit_usings_action_test_impl(ctx):
    env = analysistest.begin(ctx)
    actions = analysistest.target_actions(env)
    compile_actions = [action for action in actions if action.mnemonic == "CSharpCompile"]
    write_actions = [action for action in actions if action.mnemonic == "CSharpImplicitUsings"]
    enabled = ctx.attr.expected_content != ""

    asserts.equals(env, ctx.attr.expected_compile_actions, len(compile_actions))
    asserts.equals(env, 1 if enabled else 0, len(write_actions))

    output = None
    if enabled and len(write_actions) == 1:
        write_action = write_actions[0]
        asserts.equals(env, [], write_action.inputs.to_list())
        outputs = write_action.outputs.to_list()
        asserts.equals(env, 1, len(outputs))
        if len(outputs) == 1:
            output = outputs[0]
            asserts.true(
                env,
                output.path.endswith(ctx.attr.expected_output_suffix),
                "unexpected implicit-usings path: %s" % output.path,
            )
        asserts.equals(env, ctx.attr.expected_content, write_action.content)

    for compile_action in compile_actions:
        global_inputs = _global_usings_inputs(compile_action)
        asserts.equals(env, 1 if enabled else 0, len(global_inputs))
        if enabled and output != None and len(global_inputs) == 1:
            asserts.equals(env, output.path, global_inputs[0].path)
            global_args = [
                arg
                for arg in compile_action.argv
                if arg == output.path or arg.endswith("/" + output.basename)
            ]
            asserts.equals(env, 1, len(global_args), "global source must reach csc exactly once")

        if ctx.attr.expected_source:
            source_inputs = [
                input_file
                for input_file in compile_action.inputs.to_list()
                if input_file.basename == ctx.attr.expected_source
            ]
            asserts.equals(env, 1, len(source_inputs))
            source_args = [
                arg
                for arg in compile_action.argv
                if arg == ctx.attr.expected_source or arg.endswith("/" + ctx.attr.expected_source)
            ]
            asserts.equals(env, 1, len(source_args))

        for expected_arg in ctx.attr.expected_args:
            asserts.true(
                env,
                expected_arg in compile_action.argv,
                "missing existing compiler argument %s" % expected_arg,
            )

    return analysistest.end(env)

implicit_usings_action_test = analysistest.make(
    _implicit_usings_action_test_impl,
    attrs = {
        "expected_compile_actions": attr.int(default = 1),
        "expected_content": attr.string(default = _DEFAULT_CONTENT),
        "expected_output_suffix": attr.string(default = ""),
        "expected_source": attr.string(default = ""),
        "expected_args": attr.string_list(default = []),
    },
)
```

De write-actie krijgt geen inputs; `outputs.to_list()` levert het gedeclareerde bestand, `content` de letterlijke bytes en iedere compileractie wordt via zijn eigen `inputs`-depset en `argv` gecontroleerd. Het `internals_enabled`-target verwacht twee compileracties en dekt daarmee internals-reference plus reference-only; `library_enabled` dekt de normale vorm.

- [ ] **Step 2: Maak alle C#-fixtures**

Create `dotnet/private/tests/csharp_implicit_usings/Library.cs`:

```csharp
namespace ImplicitUsings;

public static class Library
{
    public static IReadOnlyList<int> Values() => new List<int> { 1, 2 };

    public static Task<int> Answer() => Task.FromResult(42);
}
```

Create `dotnet/private/tests/csharp_implicit_usings/Binary.cs`:

```csharp
namespace ImplicitUsings;

public static class Binary
{
    public static void Main(string[] args)
    {
        Console.WriteLine(new List<int> { 42 }.Count);
    }
}
```

Create `dotnet/private/tests/csharp_implicit_usings/GenericTest.cs`:

```csharp
public static class GenericTest
{
    public static int Main()
    {
        var values = new List<int> { 1, 2 };
        return values.Count == 2 ? 0 : 1;
    }
}
```

Create `dotnet/private/tests/csharp_implicit_usings/NUnitTests.cs`:

```csharp
using NUnit.Framework;

namespace ImplicitUsings;

[TestFixture]
public sealed class NUnitTests
{
    [Test]
    public void ListComesFromImplicitUsings()
    {
        Assert.AreEqual(2, new List<int> { 1, 2 }.Count);
    }
}
```

Create `dotnet/private/tests/csharp_implicit_usings/XunitTests.cs`:

```csharp
using Xunit;

namespace ImplicitUsings;

public sealed class XunitTests
{
    [Fact]
    public void ListComesFromImplicitUsings()
    {
        Assert.Equal(2, new List<int> { 1, 2 }.Count);
    }
}
```

Create `dotnet/private/tests/csharp_implicit_usings/MSTestTests.cs`:

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace ImplicitUsings;

[TestClass]
public sealed class MSTestTests
{
    [TestMethod]
    public void ListComesFromImplicitUsings()
    {
        Assert.AreEqual(2, new List<int> { 1, 2 }.Count);
    }
}
```

Create `dotnet/private/tests/csharp_implicit_usings/Internals.cs`:

```csharp
namespace ImplicitUsings;

internal static class Internals
{
    internal static int Count() => new List<int> { 1, 2 }.Count;
}
```

Create `dotnet/private/tests/csharp_implicit_usings/Disabled.cs`:

```csharp
using System.Collections.Generic;

namespace ImplicitUsings;

public static class Disabled
{
    public static int Count() => new List<int> { 1, 2 }.Count;
}
```

Alleen frameworknamespaces en de expliciete disabled-using staan in de bronnen; de enabled-fixtures kunnen zonder de gegenereerde basis-usings niet compileren.

- [ ] **Step 3: Zet de volledige analyse- en compileermatrix in BUILD**

Vervang de huidige volledige inhoud van `dotnet/private/tests/csharp_implicit_usings/BUILD.bazel`:

```python
load(":implicit_usings_test.bzl", "implicit_usings_test_suite")

implicit_usings_test_suite(name = "implicit_usings_namespaces_test")
```

door:

```python
load(
    "//dotnet:defs.bzl",
    "csharp_binary",
    "csharp_library",
    "csharp_mstest_test",
    "csharp_nunit_test",
    "csharp_test",
    "csharp_xunit_test",
)
load(":action_test.bzl", "implicit_usings_action_test")
load(":implicit_usings_test.bzl", "implicit_usings_test_suite")

csharp_library(
    name = "library_enabled",
    srcs = ["Library.cs"],
    implicit_usings = True,
    target_frameworks = ["net10.0"],
)

implicit_usings_action_test(
    name = "library_enabled_actions_test",
    target_under_test = ":library_enabled",
    expected_output_suffix = "library_enabled/net10.0/library_enabled.GlobalUsings.g.cs",
)

csharp_binary(
    name = "binary_enabled",
    srcs = ["Binary.cs"],
    implicit_usings = True,
    target_frameworks = ["net10.0"],
)

implicit_usings_action_test(
    name = "binary_enabled_actions_test",
    target_under_test = ":binary_enabled",
    expected_output_suffix = "binary_enabled/net10.0/binary_enabled.GlobalUsings.g.cs",
)

csharp_test(
    name = "generic_test_enabled",
    srcs = ["GenericTest.cs"],
    implicit_usings = True,
    target_frameworks = ["net10.0"],
)

implicit_usings_action_test(
    name = "generic_test_enabled_actions_test",
    target_under_test = ":generic_test_enabled",
    expected_output_suffix = "generic_test_enabled/net10.0/generic_test_enabled.GlobalUsings.g.cs",
)

csharp_nunit_test(
    name = "nunit_test_enabled",
    srcs = ["NUnitTests.cs"],
    implicit_usings = True,
    target_frameworks = ["net10.0"],
)

implicit_usings_action_test(
    name = "nunit_test_enabled_actions_test",
    target_under_test = ":nunit_test_enabled",
    expected_output_suffix = "nunit_test_enabled/net10.0/nunit_test_enabled.GlobalUsings.g.cs",
)

csharp_xunit_test(
    name = "xunit_test_enabled",
    srcs = ["XunitTests.cs"],
    implicit_usings = True,
    target_frameworks = ["net10.0"],
)

implicit_usings_action_test(
    name = "xunit_test_enabled_actions_test",
    target_under_test = ":xunit_test_enabled",
    expected_output_suffix = "xunit_test_enabled/net10.0/xunit_test_enabled.GlobalUsings.g.cs",
)

csharp_mstest_test(
    name = "mstest_test_enabled",
    srcs = ["MSTestTests.cs"],
    implicit_usings = True,
    target_frameworks = ["net10.0"],
)

implicit_usings_action_test(
    name = "mstest_test_enabled_actions_test",
    target_under_test = ":mstest_test_enabled",
    expected_output_suffix = "mstest_test_enabled/net10.0/mstest_test_enabled.GlobalUsings.g.cs",
)

csharp_library(
    name = "internals_enabled",
    srcs = ["Internals.cs"],
    implicit_usings = True,
    internals_visible_to = ["friend"],
    target_frameworks = ["net10.0"],
)

implicit_usings_action_test(
    name = "internals_enabled_actions_test",
    target_under_test = ":internals_enabled",
    expected_compile_actions = 2,
    expected_output_suffix = "internals_enabled/net10.0/internals_enabled.GlobalUsings.g.cs",
)

csharp_library(
    name = "library_unset",
    srcs = ["Disabled.cs"],
    target_frameworks = ["net10.0"],
)

implicit_usings_action_test(
    name = "library_unset_actions_test",
    target_under_test = ":library_unset",
    expected_args = ["/nullable:disable"],
    expected_content = "",
    expected_source = "Disabled.cs",
)

csharp_library(
    name = "library_disabled",
    srcs = ["Disabled.cs"],
    implicit_usings = False,
    target_frameworks = ["net10.0"],
)

implicit_usings_action_test(
    name = "library_disabled_actions_test",
    target_under_test = ":library_disabled",
    expected_args = ["/nullable:disable"],
    expected_content = "",
    expected_source = "Disabled.cs",
)

implicit_usings_test_suite(name = "implicit_usings_namespaces_test")
```

- [ ] **Step 4: Bevestig de falende publieke-API-test**

Run: `bazel test //dotnet/private/tests/csharp_implicit_usings:library_enabled_actions_test`

Expected: FAIL tijdens package-analyse; de fout bevat zowel `no such attribute 'implicit_usings'` als `csharp_library`.

- [ ] **Step 5: Voeg het publieke attribuut en de helperdependency toe**

Vervang in `dotnet/private/rules/common/attrs.bzl` exact:

```python
        "nullable": attr.string(
            doc = "Enable nullable context, or nullable warnings.",
```

door:

```python
        "implicit_usings": attr.bool(
            doc = """Generate and compile one deterministic global-usings source per target framework for the selected project SDK.

            Global using directives require C# 10 or higher. For older target frameworks, set `langversion` explicitly; this attribute does not change the language version.""",
            mandatory = False,
            default = False,
        ),
        "nullable": attr.string(
            doc = "Enable nullable context, or nullable warnings.",
```

Vervang in `dotnet/private/rules/csharp/actions/BUILD.bazel` exact:

```python
    deps = [
        ":razor",
        ":scoped_css",
```

door:

```python
    deps = [
        ":implicit_usings",
        ":razor",
        ":scoped_css",
```

- [ ] **Step 6: Genereer de gedeelde bron in AssemblyAction**

Vervang in `dotnet/private/rules/csharp/actions/csharp_assembly.bzl` exact:

```python
load(
    "//dotnet/private/rules/csharp/actions:razor.bzl",
    "partition_srcs",
    "razor_compile_inputs",
)
```

door:

```python
load(
    "//dotnet/private/rules/csharp/actions:implicit_usings.bzl",
    "write_implicit_usings",
)
load(
    "//dotnet/private/rules/csharp/actions:razor.bzl",
    "partition_srcs",
    "razor_compile_inputs",
)
```

Vervang in de `AssemblyAction`-signatuur exact:

```python
        allow_unsafe_blocks,
        nullable,
        run_analyzers,
```

door:

```python
        allow_unsafe_blocks,
        implicit_usings,
        nullable,
        run_analyzers,
```

Vervang in de `AssemblyAction`-docstring exact:

```python
        allow_unsafe_blocks: Compiles the target with /unsafe
        nullable: Enable nullable context, or nullable warnings.
        run_analyzers: Enable analyzers.
```

door:

```python
        allow_unsafe_blocks: Compiles the target with /unsafe
        implicit_usings: Whether to generate and compile the SDK-specific global-usings source.
        nullable: Enable nullable context, or nullable warnings.
        run_analyzers: Enable analyzers.
```

Vervang in `AssemblyAction` dit bestaande blok:

```python
    assembly_version_cs = _write_assembly_version_csharp(actions, target_name, assembly_name, version)
    if assembly_version_cs:
        srcs = srcs + [assembly_version_cs]

    out_dll = actions.declare_file("%s/%s.%s" % (out_dir, assembly_name, out_ext))
```

door:

```python
    assembly_version_cs = _write_assembly_version_csharp(actions, target_name, assembly_name, version)
    if assembly_version_cs:
        srcs = srcs + [assembly_version_cs]

    if implicit_usings:
        implicit_usings_cs = write_implicit_usings(
            actions,
            out_dir = out_dir,
            target_name = target_name,
            project_sdk = project_sdk,
            target_framework = target_framework,
        )
        srcs = srcs + [implicit_usings_cs]

    out_dll = actions.declare_file("%s/%s.%s" % (out_dir, assembly_name, out_ext))
```

- [ ] **Step 7: Geef het attribuut door vanuit library, binary en test**

Vervang in `dotnet/private/rules/csharp/library.bzl` exact:

```python
        allow_unsafe_blocks = ctx.attr.allow_unsafe_blocks,
        nullable = ctx.attr.nullable,
        run_analyzers = ctx.attr.run_analyzers,
```

door:

```python
        allow_unsafe_blocks = ctx.attr.allow_unsafe_blocks,
        implicit_usings = ctx.attr.implicit_usings,
        nullable = ctx.attr.nullable,
        run_analyzers = ctx.attr.run_analyzers,
```

Vervang in `dotnet/private/rules/csharp/binary.bzl` exact:

```python
        allow_unsafe_blocks = ctx.attr.allow_unsafe_blocks,
        nullable = ctx.attr.nullable,
        run_analyzers = ctx.attr.run_analyzers,
```

door:

```python
        allow_unsafe_blocks = ctx.attr.allow_unsafe_blocks,
        implicit_usings = ctx.attr.implicit_usings,
        nullable = ctx.attr.nullable,
        run_analyzers = ctx.attr.run_analyzers,
```

Vervang in `dotnet/private/rules/csharp/test.bzl` exact:

```python
        allow_unsafe_blocks = ctx.attr.allow_unsafe_blocks,
        nullable = ctx.attr.nullable,
        run_analyzers = ctx.attr.run_analyzers,
```

door:

```python
        allow_unsafe_blocks = ctx.attr.allow_unsafe_blocks,
        implicit_usings = ctx.attr.implicit_usings,
        nullable = ctx.attr.nullable,
        run_analyzers = ctx.attr.run_analyzers,
```

Bij `False` wordt het nieuwe blok niet uitgevoerd. Bij `True` ligt de toevoeging vóór alle drie bestaande `_compile`-paden en blijft de publieke `ctx.files.srcs` ongewijzigd.

- [ ] **Step 8: Draai analyse, compilatie en nullable-regressietests**

```bash
bazel build //dotnet/private/tests/csharp_implicit_usings/...
bazel test //dotnet/private/tests/csharp_implicit_usings/... //dotnet/private/tests/csharp_nullable/... //dotnet/private/tests/internals_visible_to/...
git diff --check
```

Expected: build completed successfully; de pure test en alle negen analysistests PASS; generic, NUnit, xUnit en MSTest draaien PASS; bestaande nullable- en internals-tests blijven PASS. Voor unset en disabled is er geen write-actie/global-input en blijft `/nullable:disable` aanwezig.

- [ ] **Step 9: Review en commit de C#-doorvoer**

```bash
git status --short
git diff -- dotnet/private/rules/common/attrs.bzl dotnet/private/rules/csharp/library.bzl dotnet/private/rules/csharp/binary.bzl dotnet/private/rules/csharp/test.bzl dotnet/private/rules/csharp/actions/csharp_assembly.bzl dotnet/private/rules/csharp/actions/BUILD.bazel dotnet/private/tests/csharp_implicit_usings
git log --oneline -10
git add dotnet/private/rules/common/attrs.bzl dotnet/private/rules/csharp/library.bzl dotnet/private/rules/csharp/binary.bzl dotnet/private/rules/csharp/test.bzl dotnet/private/rules/csharp/actions/csharp_assembly.bzl dotnet/private/rules/csharp/actions/BUILD.bazel dotnet/private/tests/csharp_implicit_usings
git diff --cached --check
git diff --cached --stat
git commit -m "Compile implicit usings for C# targets"
```

Expected vóór de commit: geen F#-, macro-, `defs.bzl`- of resolverwijziging; `git diff --check` uit Step 8 was stil.

- [ ] **Step 10: Werk alleen deze taskstatus bij**

Vervang onder Task 6 exact `**Status:** pending` door:

```markdown
**Status:** completed — Alle publieke C#-varianten ondersteunen implicit_usings; analyse dekt write-bytes, paden, unset/disable en alle compileervertakkingen.
```

- [ ] **Step 11: Commit de statusupdate**

```bash
git diff --check
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 6 complete in plan"
```

---

### Task 7: Nieuwe zelfstandige e2e-module en vier scenario's
**Status:** completed — De zelfstandige e2e-module bevat werkende unset-, enabled-, inherited- en disabled-scenario's met idempotente gegenereerde BUILD-files.

**Files:**
- Create: `e2e/gazelle_nullable_implicit_usings/{MODULE.bazel,.bazelrc,.bazelversion,BUILD.bazel,internal_dev_deps.bzl}`
- Create: `e2e/gazelle_nullable_implicit_usings/src/unset/{BUILD.bazel,Unset.cs}`
- Create: `e2e/gazelle_nullable_implicit_usings/src/enabled/{BUILD.bazel,Enabled.cs,Program.cs,EnabledTests.cs}`
- Create: `e2e/gazelle_nullable_implicit_usings/src/enabled/inherited/{BUILD.bazel,Inherited.cs}`
- Create: `e2e/gazelle_nullable_implicit_usings/src/enabled/disabled/{BUILD.bazel,Disabled.cs}`

- [ ] **Step 1: Maak de module-scaffolding zonder nieuwe rootdirectives**

Maak vanuit de repository-root de zelfstandige module en al haar source-mappen:

```bash
mkdir -p e2e/gazelle_nullable_implicit_usings/src/unset e2e/gazelle_nullable_implicit_usings/src/enabled/inherited e2e/gazelle_nullable_implicit_usings/src/enabled/disabled
test -d e2e/gazelle_nullable_implicit_usings/src/enabled/inherited
```

Expected: beide commando's exit 0 en geen output. Er wordt geen bestaande e2e-map als schrijfdoel gebruikt.

Create `e2e/gazelle_nullable_implicit_usings/.bazelversion`:

```text
9.1.1
```

Create `e2e/gazelle_nullable_implicit_usings/.bazelrc`:

```text
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

Create `e2e/gazelle_nullable_implicit_usings/internal_dev_deps.bzl`:

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

Create `e2e/gazelle_nullable_implicit_usings/MODULE.bazel`:

```python
"rules_dotnet C# Gazelle nullable and implicit usings e2e"

module(
    name = "e2e_gazelle_nullable_implicit_usings",
    version = "0.0.0",
    compatibility_level = 1,
)

bazel_dep(name = "rules_dotnet", version = "0.0.0")
local_path_override(
    module_name = "rules_dotnet",
    path = "../..",
)

bazel_dep(name = "gazelle", version = "0.51.3", repo_name = "bazel_gazelle")

dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
dotnet.toolchain(dotnet_version = "10.0.401")
use_repo(dotnet, "dotnet_toolchains")

register_toolchains("@dotnet_toolchains//:all")

# rules_go is a direct dependency so its Go SDK is registered for gazelle_binary.
bazel_dep(name = "rules_go", version = "0.59.0")

go_sdk = use_extension("@rules_go//go:extensions.bzl", "go_sdk")
go_sdk.download(version = "1.24.12")

# Only needed to make the Bazel CI RBE config work.
bazel_dep(name = "bazel_ci_rules", version = "1.0.0", dev_dependency = True)
bazel_dep(name = "platforms", version = "0.0.10", dev_dependency = True)

internal_dev_deps = use_extension("//:internal_dev_deps.bzl", "internal_dev_deps", dev_dependency = True)
use_repo(internal_dev_deps, "buildkite_config")
```

Create `e2e/gazelle_nullable_implicit_usings/BUILD.bazel`:

```python
load("@bazel_gazelle//:def.bzl", "gazelle", "gazelle_binary")

package(default_visibility = ["//visibility:public"])

# gazelle:dotnet_target_frameworks net10.0

gazelle_binary(
    name = "gazelle_bin",
    languages = ["@rules_dotnet//dotnet/gazelle"],
)

# Regenerate the BUILD files in this module:
# bazel run //:gazelle
gazelle(
    name = "gazelle",
    gazelle = "gazelle_bin",
)
```

De bestaande NUnit-macro levert zijn eigen vastgepinde frameworkdeps via `paket.rules_dotnet_nuget_packages`; er is voor deze module geen extra NuGet-resolutie of `nuget_resolve.json` nodig. Gazelle toont daarom de bestaande informatieve `no nuget_resolve.json`-logregel met `NuGet resolution is disabled` en de bestaande unresolved-import-waarschuwing voor `NUnit.Framework`; beide zijn verwacht en geen fout.

- [ ] **Step 2: Maak het unset-scenario**

Create `e2e/gazelle_nullable_implicit_usings/src/unset/Unset.cs`:

```csharp
using System.Collections.Generic;

namespace Unset;

public static class Values
{
    public static IReadOnlyList<int> All() => new List<int> { 1 };
}
```

Create `e2e/gazelle_nullable_implicit_usings/src/unset/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "unset",
    srcs = ["Unset.cs"],
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)
```

Noch root noch deze subtree heeft een nieuwe directive; de BUILD bevat daarom geen `nullable` en geen `implicit_usings`.

- [ ] **Step 3: Maak enabled met library, binary en test**

Create `e2e/gazelle_nullable_implicit_usings/src/enabled/Enabled.cs`:

```csharp
namespace Enabled;

public static class Values
{
    public static IReadOnlyList<int> All() => new List<int> { 2, 3 };

    public static Task<int> SumAsync() => Task.FromResult(5);
}
```

Create `e2e/gazelle_nullable_implicit_usings/src/enabled/Program.cs`:

```csharp
using Enabled;

namespace EnabledApp;

public static class Program
{
    public static int Run() => Values.All().Count;

    public static void Main(string[] args)
    {
        Console.WriteLine(Run());
    }
}
```

Create `e2e/gazelle_nullable_implicit_usings/src/enabled/EnabledTests.cs`:

```csharp
using Enabled;
using NUnit.Framework;

namespace Enabled.Tests;

[TestFixture]
public sealed class EnabledTests
{
    [Test]
    public void ImplicitUsingsCompileLibraryAndTest()
    {
        var expected = new List<int> { 2, 3 };
        CollectionAssert.AreEqual(expected, Values.All());
        Assert.AreEqual(5, Values.SumAsync().Result);
    }
}
```

Create `e2e/gazelle_nullable_implicit_usings/src/enabled/BUILD.bazel`:

```python
# gazelle:dotnet_nullable enable
# gazelle:dotnet_implicit_usings enable

load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary", "csharp_library", "csharp_nunit_test")

csharp_library(
    name = "enabled",
    srcs = ["Enabled.cs"],
    implicit_usings = True,
    internals_visible_to = ["enabled_nunit_test"],
    nullable = "enable",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)

csharp_nunit_test(
    name = "enabled_nunit_test",
    srcs = ["EnabledTests.cs"],
    implicit_usings = True,
    nullable = "enable",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
    deps = [":enabled"],
)

csharp_binary(
    name = "program",
    srcs = ["Program.cs"],
    implicit_usings = True,
    nullable = "enable",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
    deps = [":enabled"],
)
```

- [ ] **Step 4: Maak inherited en disabled onder de enabled-parent**

Create `e2e/gazelle_nullable_implicit_usings/src/enabled/inherited/Inherited.cs`:

```csharp
namespace Inherited;

public static class Values
{
    public static IReadOnlyList<int> All() => new List<int> { 4, 5 };

    public static Task<int> SumAsync() => Task.FromResult(9);
}
```

Create `e2e/gazelle_nullable_implicit_usings/src/enabled/inherited/BUILD.bazel` zonder eigen nieuwe directives:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "inherited",
    srcs = ["Inherited.cs"],
    implicit_usings = True,
    nullable = "enable",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)
```

Create `e2e/gazelle_nullable_implicit_usings/src/enabled/disabled/Disabled.cs`:

```csharp
using System.Collections.Generic;

namespace Disabled;

public static class Values
{
    public static IReadOnlyList<int> All() => new List<int> { 6, 7 };
}
```

Create `e2e/gazelle_nullable_implicit_usings/src/enabled/disabled/BUILD.bazel`:

```python
# gazelle:dotnet_nullable disable
# gazelle:dotnet_implicit_usings disable

load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "disabled",
    srcs = ["Disabled.cs"],
    implicit_usings = False,
    nullable = "disable",
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)
```

- [ ] **Step 5: Bewijs vóór de eerste commit dat Gazelle-output exact is**

Run vanuit `e2e/gazelle_nullable_implicit_usings`:

```bash
sha256sum BUILD.bazel src/unset/BUILD.bazel src/enabled/BUILD.bazel src/enabled/inherited/BUILD.bazel src/enabled/disabled/BUILD.bazel > /tmp/opencode/gazelle-nullable-implicit-usings-builds.sha256
bazel run //:gazelle
sha256sum --check /tmp/opencode/gazelle-nullable-implicit-usings-builds.sha256
```

Expected: Gazelle exit 0; alle vijf checksumregels eindigen op `OK`, dus geen van de ingecheckte BUILD-bestanden verandert. De informatieve melding dat `nuget_resolve.json` ontbreekt en de waarschuwing over unresolved `NUnit.Framework` zijn verwacht; er verschijnen geen nieuwe rootdirectives.

- [ ] **Step 6: Build en test de nieuwe module**

Run vanuit dezelfde modulemap:

```bash
bazel build //...
bazel test //...
```

Expected: build completed successfully; `//src/enabled:enabled_nunit_test` PASS. Enabled en inherited compileren alleen omdat de gegenereerde bronnen `Console`, `List<T>`, `IReadOnlyList<T>` en `Task` beschikbaar maken; unset en disabled compileren met hun expliciete usings.

- [ ] **Step 7: Review en commit uitsluitend de modulebestanden**

```bash
git status --short
git diff --check
git diff -- e2e/gazelle_nullable_implicit_usings
git log --oneline -10
git add e2e/gazelle_nullable_implicit_usings
git diff --cached --check
git diff --cached --stat
git commit -m "Add nullable and implicit usings e2e module"
```

`MODULE.bazel.lock` wordt door `**/MODULE.bazel.lock` genegeerd en hoort bij Task 8; de gewone `git add` hierboven neemt dat bestand en geen enkele Bazel-output mee. Bestaande e2e-mappen mogen niet in status of diff voorkomen.

- [ ] **Step 8: Werk alleen deze taskstatus bij**

Vervang onder Task 7 exact `**Status:** pending` door:

```markdown
**Status:** completed — De zelfstandige e2e-module bevat werkende unset-, enabled-, inherited- en disabled-scenario's met idempotente gegenereerde BUILD-files.
```

- [ ] **Step 9: Commit de statusupdate**

```bash
git diff --check
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 7 complete in plan"
```

---

### Task 8: Genereer en verifieer het e2e-module-lockbestand
**Status:** completed — Bazel 9.1.1 heeft de nieuwe module-lock gegenereerd en lockfile_mode=error, build, test en Gazelle-idempotentie slagen.

**Files:**
- Create: `e2e/gazelle_nullable_implicit_usings/MODULE.bazel.lock` (door Bazel gegenereerd)

- [ ] **Step 1: Genereer de lock met de gepinde Bazel en alle targets**

Run vanuit `e2e/gazelle_nullable_implicit_usings`:

```bash
bazel build --lockfile_mode=update //...
bazel test --lockfile_mode=update //...
```

Expected: beide commando's slagen en Bazel 9.1.1 schrijft `MODULE.bazel.lock` met de registry-hashes, geselecteerde moduleversies en actuele extension-digests van deze lokale `rules_dotnet`-implementatie. Het bestand wordt niet handmatig samengesteld: die digests zijn pas na de voorgaande implementatiecommits bekend.

- [ ] **Step 2: Bewijs lockfile-error-modus en Gazelle-idempotentie**

Run vanuit de modulemap:

```bash
bazel run --lockfile_mode=error //:gazelle
bazel build --lockfile_mode=error //...
bazel test --lockfile_mode=error //...
```

Expected: alles slaagt zonder lockfile-updates; de NUnit-test blijft PASS.

Run daarna vanuit de repository-root:

```bash
git diff --exit-code -- e2e/gazelle_nullable_implicit_usings
```

Expected: exit 0 en geen diff in de reeds gecommitte module-BUILD-files. Het nog genegeerde lockbestand verandert deze diff niet; de checksum-test uit Task 7 en deze post-commit-diff bewijzen samen de idempotentie.

- [ ] **Step 3: Valideer de gegenereerde JSON en lockversie**

```bash
python3 -c 'import json; p = "e2e/gazelle_nullable_implicit_usings/MODULE.bazel.lock"; data = json.load(open(p)); assert data["lockFileVersion"] == 26, data["lockFileVersion"]; assert data["registryFileHashes"]; assert "moduleExtensions" in data; print("MODULE.bazel.lock OK: version", data["lockFileVersion"])'
git diff --check
```

Expected vanuit de repository-root: `MODULE.bazel.lock OK: version 26`; `git diff --check` is stil. Dit is een gegenereerd artefact met volledige inhoud op schijf, geen handgeschreven partial lock.

- [ ] **Step 4: Review en force-add alleen het verplichte lockbestand**

```bash
git status --short --ignored=matching -- e2e/gazelle_nullable_implicit_usings
git check-ignore -v e2e/gazelle_nullable_implicit_usings/MODULE.bazel.lock
git log --oneline -10
git add -f e2e/gazelle_nullable_implicit_usings/MODULE.bazel.lock
git diff --cached --check
git diff --cached --stat
git commit -m "Lock the nullable and implicit usings e2e module"
```

Expected vóór commit: `git check-ignore` toont `.gitignore:22:**/MODULE.bazel.lock`; de staged stat bevat exact één bestand, namelijk het nieuwe lockbestand. `.gitignore` zelf en bestaande genegeerde lockbestanden blijven ongewijzigd en unstaged.

- [ ] **Step 5: Werk alleen deze taskstatus bij**

Vervang onder Task 8 exact `**Status:** pending` door:

```markdown
**Status:** completed — Bazel 9.1.1 heeft de nieuwe module-lock gegenereerd en lockfile_mode=error, build, test en Gazelle-idempotentie slagen.
```

- [ ] **Step 6: Commit de statusupdate**

```bash
git diff --check
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 8 complete in plan"
```

---

### Task 9: Registreer alleen de nieuwe e2e-module in CI
**Status:** completed — CI bevat één extra zelfstandige working directory met de bestaande build- en testmatrix; alle oude entries zijn behouden.

**Files:**
- Modify: `.bazelci/presubmit.yml`

- [ ] **Step 1: Draai de CI-validatie en bevestig dat de nieuwe entry ontbreekt**

```bash
python3 -c "
import yaml
cfg = yaml.safe_load(open('.bazelci/presubmit.yml'))
dirs = cfg['matrix']['e2e_working_directory']
assert len(dirs) == 10, dirs
assert dirs.count('e2e/gazelle_nullable_implicit_usings') == 1, dirs
assert 'e2e/gazelle_net10.0' in dirs
assert cfg['tasks']['e2e']['build_targets'] == ['//...']
assert cfg['tasks']['e2e']['test_targets'] == ['//...']
print('presubmit.yml OK:', len(dirs), 'e2e modules')
"
```

Expected: exit 1 met `AssertionError` op `len(dirs) == 10`; de actuele matrix heeft negen entries en bevat de nieuwe module nog niet. Wijzig geen andere matrix- of taskwaarden.

- [ ] **Step 2: Voeg de nieuwe working directory aan de bestaande matrix toe**

Vervang in `.bazelci/presubmit.yml` exact:

```yaml
  e2e_working_directory: ["e2e/net8.0", "e2e/net9.0", "e2e/net10.0", "e2e/web_sdk", "e2e/gazelle_net10.0", "e2e/nuget_resolve_basic", "e2e/nuget_resolve_transitive", "e2e/nuget_resolve_multi_framework", "e2e/nuget_resolve_pinning"]
```

door:

```yaml
  e2e_working_directory: ["e2e/net8.0", "e2e/net9.0", "e2e/net10.0", "e2e/web_sdk", "e2e/gazelle_net10.0", "e2e/nuget_resolve_basic", "e2e/nuget_resolve_transitive", "e2e/nuget_resolve_multi_framework", "e2e/nuget_resolve_pinning", "e2e/gazelle_nullable_implicit_usings"]
```

De bestaande `e2e`-task blijft ongewijzigd en voert voor deze nieuwe working directory zelfstandig `build_targets: ["//..."]` en `test_targets: ["//..."]` uit.

- [ ] **Step 3: Draai de CI-validatie groen**

```bash
python3 -c "
import yaml
cfg = yaml.safe_load(open('.bazelci/presubmit.yml'))
dirs = cfg['matrix']['e2e_working_directory']
assert len(dirs) == 10, dirs
assert dirs.count('e2e/gazelle_nullable_implicit_usings') == 1, dirs
assert 'e2e/gazelle_net10.0' in dirs
assert cfg['tasks']['e2e']['build_targets'] == ['//...']
assert cfg['tasks']['e2e']['test_targets'] == ['//...']
print('presubmit.yml OK:', len(dirs), 'e2e modules')
"
```

Expected: `presubmit.yml OK: 10 e2e modules`; alle negen oude entries staan er nog en alleen de nieuwe module is toegevoegd.

- [ ] **Step 4: Review en commit alleen CI**

```bash
git status --short
git diff --check
git diff -- .bazelci/presubmit.yml
git log --oneline -10
git add .bazelci/presubmit.yml
git commit -m "Run the nullable and implicit usings e2e module in CI"
```

- [ ] **Step 5: Werk alleen deze taskstatus bij**

Vervang onder Task 9 exact `**Status:** pending` door:

```markdown
**Status:** completed — CI bevat één extra zelfstandige working directory met de bestaande build- en testmatrix; alle oude entries zijn behouden.
```

- [ ] **Step 6: Commit de statusupdate**

```bash
git diff --check
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 9 complete in plan"
```

---

### Task 10: Eindverificatie volgens de goedgekeurde spec
**Status:** completed — Alle gerichte Go-, golden-, Starlark-, analyse-, compileer- en e2e-verificaties slagen; nieuwe en bestaande e2e-modules zijn zonder drift.

**Files:**
- Test: `dotnet/gazelle/...`
- Test: `dotnet/private/tests/csharp_implicit_usings/...`
- Test: `dotnet/private/tests/csharp_nullable/...`
- Test: `dotnet/private/tests/internals_visible_to/...`
- Test: `e2e/gazelle_nullable_implicit_usings`
- Modify: alleen de Task 10-status in `docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md`

- [ ] **Step 1: Draai de voorgeschreven gerichte root-tests**

Run vanuit de repository-root:

```bash
bazel test //dotnet/gazelle/...
bazel test //dotnet/private/tests/csharp_implicit_usings/... //dotnet/private/tests/csharp_nullable/... //dotnet/private/tests/internals_visible_to/...
```

Expected: beide commando's exit 0; alle relevante tests PASS. Er is bewust geen repositorybrede `bazel test //...` als harde eis.

- [ ] **Step 2: Draai Gazelle in de nieuwe e2e en eis een lege modulediff**

Run vanuit `e2e/gazelle_nullable_implicit_usings`: `bazel run //:gazelle`

Expected: exit 0; de informatieve melding dat `nuget_resolve.json` ontbreekt en de reeds toegestane unresolved-NUnit-waarschuwing verschijnen, zonder fatale fout.

Run daarna vanuit de repository-root: `git diff --exit-code -- e2e/gazelle_nullable_implicit_usings`

Expected: exit 0 en geen output; root, unset, enabled, inherited, disabled en de lock blijven exact ongewijzigd.

- [ ] **Step 3: Build en test de volledige nieuwe e2e-module**

Run vanuit `e2e/gazelle_nullable_implicit_usings`:

```bash
bazel build //...
bazel test //...
```

Expected: build completed successfully en `//src/enabled:enabled_nunit_test` PASS.

- [ ] **Step 4: Controleer dat iedere bestaande e2e ongewijzigd is**

Run vanuit de repository-root:

```bash
git status --porcelain -- e2e ':(exclude)e2e/gazelle_nullable_implicit_usings'
git diff --exit-code -- e2e ':(exclude)e2e/gazelle_nullable_implicit_usings'
```

Expected: beide commando's geven geen output en exit 0. Dit dekt ook untracked niet-genegeerde bestanden in bestaande modules en sluit alleen de nieuwe module uit.

- [ ] **Step 5: Controleer de taskstatus en werk alleen Task 10 bij**

Controleer met `git status --short` dat er vóór deze statusupdate geen ongecommitte implementatiewijzigingen zijn. Vervang daarna onder Task 10 exact `**Status:** pending` door:

```markdown
**Status:** completed — Alle gerichte Go-, golden-, Starlark-, analyse-, compileer- en e2e-verificaties slagen; nieuwe en bestaande e2e-modules zijn zonder drift.
```

Verwijder of vink geen oorspronkelijke steps aan.

- [ ] **Step 6: Commit de laatste status en controleer de eindstatus**

```bash
git diff --check
git diff -- docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git log --oneline -10
git add docs/superpowers/plans/2026-10-24-gazelle-nullable-implicit-usings.md
git commit -m "Mark Task 10 complete in plan"
git status --short
```

Expected: de commit bevat alleen de Task 10-statusregel; de laatste `git status --short` is leeg. Er zijn geen open implementatieartefacten of ongerelateerde wijzigingen.
