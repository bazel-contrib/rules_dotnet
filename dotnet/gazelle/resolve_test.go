package gazelle

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"

	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/nuget"
	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// setupLang returns a language instance configured for the root (with the
// given directives) and for each package in rels, plus the temp repo root.
func setupLang(t *testing.T, rootDirectives string, rels ...string) (*csharpLang, *config.Config, string) {
	t.Helper()
	dir := t.TempDir()
	c := config.New()
	c.RepoRoot = dir
	l := NewLanguage().(*csharpLang)

	f, err := rule.LoadData(filepath.Join(dir, "BUILD.bazel"), "", []byte(rootDirectives))
	if err != nil {
		t.Fatal(err)
	}
	l.Configure(c, "", f)
	for _, rel := range rels {
		l.Configure(c, rel, nil)
	}
	return l, c, dir
}

func writeFile(t *testing.T, dir, name, content string) {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// indexLibrary indexes a csharp_library named name in package pkg providing
// the given namespaces.
func indexLibrary(t *testing.T, l *csharpLang, c *config.Config, ix *resolve.RuleIndex, pkg, name string, namespaces ...string) {
	t.Helper()
	f := rule.EmptyFile(pkg+"/BUILD.bazel", pkg)
	r := rule.NewRule("csharp_library", name)
	r.SetPrivateAttr(namespacesKey, namespaces)
	ix.AddRule(c, r, f)
}

func TestResolveNamespaces(t *testing.T) {
	l, c, dir := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/app")
	writeFile(t, dir, "packages.lock.json", `{"version": 1, "dependencies": {"net10.0": {"Newtonsoft.Json": {"type": "Direct", "resolved": "13.0.3"}}}}`)
	idx, err := nuget.LoadIndex(filepath.Join(dir, "packages.lock.json"))
	if err != nil {
		t.Fatal(err)
	}
	l.nugetIndex = idx

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_binary", "program")
	input := resolveInput{
		imports: []string{"Calculator", "Newtonsoft.Json.Linq", "System", "Acme.Does.Not.Exist"},
		own:     []string{"App"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "program"))

	got := r.AttrStrings("deps")
	want := []string{"//src/calculator", "@nuget.net10.0//newtonsoft.json"}
	sort.Strings(want)
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v", got, want)
	}
}

func TestResolveOverride(t *testing.T) {
	l, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n# gazelle:dotnet_resolve Acme.Widget @acme//widget\n", "src", "src/app")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	ix.Finish()

	r := rule.NewRule("csharp_library", "app")
	input := resolveInput{imports: []string{"Acme.Widget"}, own: []string{"App"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app"))

	if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, []string{"@acme//widget"}) {
		t.Errorf("deps = %v, want [@acme//widget]", got)
	}
}

func TestResolveKeepsExistingDepsAndSimplifiesSamePackage(t *testing.T) {
	l, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/calculator")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_nunit_test", "calculator_nunit_test")
	r.SetAttr("deps", []string{":calculator", "//manual:dep"})
	input := resolveInput{imports: []string{"Calculator"}, own: []string{"Calculator.Tests"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator_nunit_test"))

	got := r.AttrStrings("deps")
	want := []string{"//manual:dep", ":calculator"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v", got, want)
	}
}

func TestResolveSkipsSelfImport(t *testing.T) {
	l, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/calculator")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_library", "calculator")
	input := resolveInput{imports: []string{"Calculator"}, own: []string{"Calculator"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator"))

	if got := r.AttrStrings("deps"); len(got) != 0 {
		t.Errorf("deps = %v, want empty", got)
	}
}

func TestResolveSamePackageWithRepoName(t *testing.T) {
	l, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/calculator")
	// Simulate a real workspace: RuleIndex.AddRule stamps every indexed
	// label with c.RepoName, which gazelle's test harness leaves empty.
	c.RepoName = "rules_dotnet_examples"

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_nunit_test", "calculator_nunit_test")
	r.SetAttr("deps", []string{":calculator"})
	input := resolveInput{imports: []string{"Calculator"}, own: []string{"Calculator.Tests"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator_nunit_test"))

	got := r.AttrStrings("deps")
	want := []string{":calculator"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v", got, want)
	}
}

func TestImportsIndexesBinaryNamespaces(t *testing.T) {
	l := NewLanguage().(*csharpLang)
	res := l.Resolver
	f := rule.EmptyFile("src/app/BUILD.bazel", "src/app")

	bin := rule.NewRule("csharp_binary", "program")
	bin.SetPrivateAttr(namespacesKey, []string{"App"})
	specs := res.Imports(config.New(), bin, f)
	if len(specs) != 1 || specs[0].Lang != "csharp" || specs[0].Imp != "App" {
		t.Errorf("Imports(csharp_binary) = %v, want [{csharp App}]", specs)
	}

	// A binary without the private attr (e.g. hand-written) is not indexed.
	if got := res.Imports(config.New(), rule.NewRule("csharp_binary", "tool"), f); got != nil {
		t.Errorf("Imports(csharp_binary without namespaces) = %v, want nil", got)
	}

	// Test rules are never indexed.
	test := rule.NewRule("csharp_nunit_test", "app_nunit_test")
	test.SetPrivateAttr(namespacesKey, []string{"App.Tests"})
	if got := res.Imports(config.New(), test, f); got != nil {
		t.Errorf("Imports(csharp_nunit_test) = %v, want nil", got)
	}
}

func TestResolveTestAgainstSiblingBinary(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "src", "src/app")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	f := rule.EmptyFile("src/app/BUILD.bazel", "src/app")
	bin := rule.NewRule("csharp_binary", "program")
	bin.SetPrivateAttr(namespacesKey, []string{"App"})
	ix.AddRule(c, bin, f)
	ix.Finish()

	r := rule.NewRule("csharp_nunit_test", "app_nunit_test")
	input := resolveInput{imports: []string{"App"}, own: []string{"App.Tests"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app_nunit_test"))

	got := r.AttrStrings("deps")
	want := []string{":program"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v (same-package binary label, relativized)", got, want)
	}
}
