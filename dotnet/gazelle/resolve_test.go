package gazelle

import (
	"bytes"
	"log"
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
	writeFile(t, dir, "nuget_resolve.json", `{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [{"id": "Newtonsoft.Json", "version": "13.0.3", "sha512": "sha512-AAAA", "urls": ["https://feed/newtonsoft.json.13.0.3.nupkg"]}]}}}`)
	idx, err := nuget.LoadIndex(filepath.Join(dir, "nuget_resolve.json"))
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

func TestResolveOverrideMultipleLabels(t *testing.T) {
	directives := "# gazelle:dotnet_target_frameworks net10.0\n" +
		"# gazelle:dotnet_resolve MediatR @nuget.net10.0//mediatr.contracts @nuget.net10.0//mediatr @nuget.net10.0//mediatr\n"
	l, c, _ := setupLang(t, directives, "src", "src/app")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	ix.Finish()

	want := []string{"@nuget.net10.0//mediatr", "@nuget.net10.0//mediatr.contracts"}

	for _, imp := range []string{"MediatR", "MediatR.Pipeline"} {
		t.Run("import="+imp, func(t *testing.T) {
			r := rule.NewRule("csharp_library", "app")
			r.SetAttr("deps", []string{"@nuget.net10.0//mediatr"})
			input := resolveInput{imports: []string{imp}, own: []string{"App"}}
			l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app"))

			if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, want) {
				t.Errorf("deps for %q = %v, want %v", imp, got, want)
			}
		})
	}
}

func TestResolveOverrideChildReplacesParent(t *testing.T) {
	directives := "# gazelle:dotnet_target_frameworks net10.0\n" +
		"# gazelle:dotnet_resolve MediatR @a//mediatr @a//mediatr.contracts\n"
	l, c, dir := setupLang(t, directives, "src", "src/other")

	childFile, err := rule.LoadData(
		filepath.Join(dir, "src/app/BUILD.bazel"),
		"src/app",
		[]byte("# gazelle:dotnet_resolve MediatR @custom//mediatr\n"),
	)
	if err != nil {
		t.Fatal(err)
	}
	l.Configure(c, "src/app", childFile)

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	ix.Finish()

	appRule := rule.NewRule("csharp_library", "app")
	l.Resolver.Resolve(c, ix, nil, appRule, resolveInput{imports: []string{"MediatR"}, own: []string{"App"}}, label.New("", "src/app", "app"))
	if got := appRule.AttrStrings("deps"); !reflect.DeepEqual(got, []string{"@custom//mediatr"}) {
		t.Errorf("src/app deps = %v, want [@custom//mediatr]", got)
	}

	otherRule := rule.NewRule("csharp_library", "other")
	l.Resolver.Resolve(c, ix, nil, otherRule, resolveInput{imports: []string{"MediatR"}, own: []string{"Other"}}, label.New("", "src/other", "other"))
	wantParent := []string{"@a//mediatr", "@a//mediatr.contracts"}
	if got := otherRule.AttrStrings("deps"); !reflect.DeepEqual(got, wantParent) {
		t.Errorf("src/other deps = %v, want %v", got, wantParent)
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

func TestResolveHandlesExactOwnNamespaceForUnindexedTest(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "src", "src/app")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	ix.Finish()

	r := rule.NewRule("csharp_nunit_test", "app_nunit_test")
	input := resolveInput{imports: []string{"Foo.Tests"}, own: []string{"Foo.Tests"}}

	var logOutput bytes.Buffer
	previousLogOutput := log.Writer()
	log.SetOutput(&logOutput)
	defer log.SetOutput(previousLogOutput)

	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app_nunit_test"))

	if got := logOutput.String(); got != "" {
		t.Errorf("log output = %q, want no unresolved import warning", got)
	}
	if got := r.AttrStrings("deps"); len(got) != 0 {
		t.Errorf("deps = %v, want empty", got)
	}
}

func TestResolveCollectsAllWorkspaceProvidersDeterministically(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "src", "src/app", "src/zeta", "src/alpha")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	// Index in reverse lexical order so expected output also verifies sorting.
	indexLibrary(t, l, c, ix, "src/zeta", "zeta", "Shared")
	indexLibrary(t, l, c, ix, "src/alpha", "alpha", "Shared")
	ix.Finish()

	r := rule.NewRule("csharp_library", "app")
	r.SetAttr("deps", []string{"//manual:dep"})
	input := resolveInput{imports: []string{"Shared"}, own: []string{"App"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app"))

	got := r.AttrStrings("deps")
	want := []string{"//manual:dep", "//src/alpha", "//src/zeta"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v", got, want)
	}
}

func TestResolveKeepsOtherProviderWhenOwnNamespaceMatches(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "src", "src/calculator", "src/other")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	indexLibrary(t, l, c, ix, "src/other", "other", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_library", "calculator")
	input := resolveInput{imports: []string{"Calculator"}, own: []string{"Calculator"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator"))

	got := r.AttrStrings("deps")
	want := []string{"//src/other"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v (self excluded by label, other provider retained)", got, want)
	}
}

func TestResolveSelfOnlyDoesNotFallBackToNuGet(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/calculator")
	writeFile(t, dir, "nuget_resolve.json", `{"version":1,"frameworks":{"net10.0":{"packages":[{"id":"Calculator"}]}}}`)
	idx, err := nuget.LoadIndex(filepath.Join(dir, "nuget_resolve.json"))
	if err != nil {
		t.Fatal(err)
	}
	l.nugetIndex = idx

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_library", "calculator")
	// Deliberately keep own different from import to exercise label self-filtering later.
	input := resolveInput{imports: []string{"Calculator"}, own: []string{"App"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator"))

	if got := r.AttrStrings("deps"); len(got) != 0 {
		t.Errorf("deps = %v, want empty; self-only workspace match must not fall back to NuGet", got)
	}
}

func TestResolveParentNamespaceFallbackWithOwnParentNamespace(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "src", "src/app", "src/acme")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/acme", "acme", "Acme")
	ix.Finish()

	r := rule.NewRule("csharp_library", "app")
	input := resolveInput{
		imports: []string{"Acme.Widget.SomeType"},
		own:     []string{"Acme"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app"))

	got := r.AttrStrings("deps")
	want := []string{"//src/acme"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v (own namespace must not suppress parent fallback)", got, want)
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

func TestResolveWebSdkNamespaces(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/web")
	writeFile(t, dir, "nuget_resolve.json", `{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [{"id": "Microsoft.AspNetCore.Authentication.JwtBearer", "version": "10.0.0", "sha512": "sha512-AAAA", "urls": ["https://feed/jwt.nupkg"]}]}}}`)
	idx, err := nuget.LoadIndex(filepath.Join(dir, "nuget_resolve.json"))
	if err != nil {
		t.Fatal(err)
	}
	l.nugetIndex = idx

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	ix.Finish()

	for _, sdk := range []string{"web", "razor", "blazorwasm"} {
		t.Run("sdk="+sdk, func(t *testing.T) {
			var buf bytes.Buffer
			origOut := log.Writer()
			log.SetOutput(&buf)
			defer log.SetOutput(origOut)

			r := rule.NewRule("csharp_library", "web")
			r.SetAttr("project_sdk", sdk)
			input := resolveInput{
				imports: []string{
					"Microsoft.AspNetCore.Authentication.JwtBearer",
					"Microsoft.AspNetCore.Builder",
					"Microsoft.AspNetCore.Http",
					"Microsoft.AspNetCore.Mvc",
					"Microsoft.Net.Http.Headers",
				},
				own: []string{"Web"},
			}
			l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/web", "web"))

			if buf.Len() > 0 {
				t.Errorf("unexpected unresolved warnings for project_sdk=%q: %s", sdk, buf.String())
			}
			want := []string{"@nuget.net10.0//microsoft.aspnetcore.authentication.jwtbearer"}
			if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, want) {
				t.Errorf("deps = %v, want %v", got, want)
			}
		})
	}

	t.Run("sdk=default warns on aspnetcore shared framework", func(t *testing.T) {
		var buf bytes.Buffer
		origOut := log.Writer()
		log.SetOutput(&buf)
		defer log.SetOutput(origOut)

		r := rule.NewRule("csharp_library", "lib")
		r.SetAttr("project_sdk", "default")
		input := resolveInput{
			imports: []string{"Microsoft.AspNetCore.Http"},
			own:     []string{"Lib"},
		}
		l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/web", "lib"))

		if !bytes.Contains(buf.Bytes(), []byte(`unresolved C# import "Microsoft.AspNetCore.Http"`)) {
			t.Errorf("expected unresolved warning for default SDK, got: %q", buf.String())
		}
	})
}

func TestResolveTestFrameworkNamespaces(t *testing.T) {
	nugetLock := `{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [` +
		`{"id": "NUnit", "version": "4.0.0", "sha512": "sha512-AAAA", "urls": ["https://feed/nunit.nupkg"]},` +
		`{"id": "xunit", "version": "2.9.0", "sha512": "sha512-BBBB", "urls": ["https://feed/xunit.nupkg"]},` +
		`{"id": "MSTest.TestFramework", "version": "4.0.0", "sha512": "sha512-CCCC", "urls": ["https://feed/mstest.nupkg"]}` +
		`]}}}`

	newEnv := func(t *testing.T, directives string, withNuget bool) (*csharpLang, *config.Config, *resolve.RuleIndex) {
		t.Helper()
		l, c, dir := setupLang(t, directives, "src", "src/tests")
		if withNuget {
			writeFile(t, dir, "nuget_resolve.json", nugetLock)
			idx, err := nuget.LoadIndex(filepath.Join(dir, "nuget_resolve.json"))
			if err != nil {
				t.Fatal(err)
			}
			l.nugetIndex = idx
		}
		ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
		ix.Finish()
		return l, c, ix
	}

	testCases := []struct {
		kind    string
		imports []string
	}{
		{
			kind: "csharp_nunit_test",
			imports: []string{
				"NUnit.Framework",
				"NUnit.Framework.Legacy",
				"NUnit.Framework.Assert",
				"NUnitLite",
				"NUnitLite.AutoRun",
			},
		},
		{
			kind: "csharp_xunit_test",
			imports: []string{
				"Xunit",
				"Xunit.Sdk",
				"Xunit.Assert",
			},
		},
		{
			kind: "csharp_mstest_test",
			imports: []string{
				"Microsoft.VisualStudio.TestTools.UnitTesting",
				"Microsoft.VisualStudio.TestTools.UnitTesting.Assert",
				"Microsoft.Testing.Platform",
				"Microsoft.Testing.Platform.Builder",
			},
		},
	}

	for _, tc := range testCases {
		t.Run("implicit/"+tc.kind, func(t *testing.T) {
			l, c, ix := newEnv(t, net10Directive, true)

			var buf bytes.Buffer
			origOut := log.Writer()
			log.SetOutput(&buf)
			defer log.SetOutput(origOut)

			r := rule.NewRule(tc.kind, "sample_test")
			input := resolveInput{imports: tc.imports, own: []string{"Sample.Tests"}}
			l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/tests", "sample_test"))

			if buf.Len() > 0 {
				t.Errorf("unexpected warnings for %s: %s", tc.kind, buf.String())
			}
			if got := r.AttrStrings("deps"); len(got) != 0 {
				t.Errorf("deps for %s = %v, want empty (implicit test framework must take precedence over NuGet)", tc.kind, got)
			}
		})
	}

	t.Run("non-test rules still resolve NuGet and warn on unresolved test framework", func(t *testing.T) {
		for _, kind := range []string{"csharp_library", "csharp_binary"} {
			l, c, ix := newEnv(t, net10Directive, true)

			var buf bytes.Buffer
			origOut := log.Writer()
			log.SetOutput(&buf)
			defer log.SetOutput(origOut)

			r := rule.NewRule(kind, "helper")
			input := resolveInput{
				imports: []string{"NUnit.Framework", "Microsoft.VisualStudio.TestTools.UnitTesting"},
				own:     []string{"Helper"},
			}
			l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/tests", "helper"))

			wantDeps := []string{"@nuget.net10.0//nunit"}
			if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, wantDeps) {
				t.Errorf("%s deps = %v, want %v", kind, got, wantDeps)
			}
			if !bytes.Contains(buf.Bytes(), []byte(`unresolved C# import "Microsoft.VisualStudio.TestTools.UnitTesting"`)) {
				t.Errorf("%s expected unresolved warning for MSTest namespace, got: %q", kind, buf.String())
			}
		}
	})

	t.Run("explicit dotnet_resolve wins over implicit test framework including using static", func(t *testing.T) {
		directives := net10Directive + "# gazelle:dotnet_resolve NUnit.Framework @custom//nunit\n"
		l, c, ix := newEnv(t, directives, true)

		var buf bytes.Buffer
		origOut := log.Writer()
		log.SetOutput(&buf)
		defer log.SetOutput(origOut)

		for _, imp := range []string{"NUnit.Framework", "NUnit.Framework.Assert"} {
			r := rule.NewRule("csharp_nunit_test", "sample_nunit_test")
			input := resolveInput{imports: []string{imp}, own: []string{"Sample.Tests"}}
			l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/tests", "sample_nunit_test"))

			wantDeps := []string{"@custom//nunit"}
			if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, wantDeps) {
				t.Errorf("import %q deps = %v, want %v", imp, got, wantDeps)
			}
		}
		if buf.Len() > 0 {
			t.Errorf("unexpected warnings: %s", buf.String())
		}
	})

	t.Run("dot boundary prevents prefix false positives", func(t *testing.T) {
		cases := []struct {
			kind string
			imp  string
		}{
			{"csharp_xunit_test", "XunitExtensions"},
			{"csharp_nunit_test", "NUnit.FrameworkExtra"},
			{"csharp_mstest_test", "Microsoft.VisualStudio.TestTools.UnitTestingExtra"},
		}
		for _, tc := range cases {
			l, c, ix := newEnv(t, net10Directive, false)

			var buf bytes.Buffer
			origOut := log.Writer()
			log.SetOutput(&buf)
			defer log.SetOutput(origOut)

			r := rule.NewRule(tc.kind, "sample_test")
			input := resolveInput{imports: []string{tc.imp}, own: []string{"Sample.Tests"}}
			l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/tests", "sample_test"))

			wantMsg := `unresolved C# import "` + tc.imp + `"`
			if !bytes.Contains(buf.Bytes(), []byte(wantMsg)) {
				t.Errorf("%s import %q: expected warning %q, got %q", tc.kind, tc.imp, wantMsg, buf.String())
			}
		}
	})

	t.Run("cross-framework imports are not suppressed", func(t *testing.T) {
		cases := []struct {
			kind string
			imp  string
		}{
			{"csharp_nunit_test", "Xunit"},
			{"csharp_mstest_test", "NUnit.Framework"},
			{"csharp_xunit_test", "Microsoft.VisualStudio.TestTools.UnitTesting"},
		}
		for _, tc := range cases {
			l, c, ix := newEnv(t, net10Directive, false)

			var buf bytes.Buffer
			origOut := log.Writer()
			log.SetOutput(&buf)
			defer log.SetOutput(origOut)

			r := rule.NewRule(tc.kind, "sample_test")
			input := resolveInput{imports: []string{tc.imp}, own: []string{"Sample.Tests"}}
			l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/tests", "sample_test"))

			wantMsg := `unresolved C# import "` + tc.imp + `"`
			if !bytes.Contains(buf.Bytes(), []byte(wantMsg)) {
				t.Errorf("%s import %q: expected warning %q, got %q", tc.kind, tc.imp, wantMsg, buf.String())
			}
		}
	})
}

func TestResolveExactNuGetNotShadowedByWorkspaceParentNamespace(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/acme", "src/app")
	writeFile(t, dir, "nuget_resolve.json", `{"version": 1, "inputHash": "1", "frameworks": {"net10.0": {"packages": [{"id": "Acme.Logging", "version": "1.0.0", "sha512": "sha512-AAAA", "urls": ["https://feed/acme.logging.nupkg"]}]}}}`)
	idx, err := nuget.LoadIndex(filepath.Join(dir, "nuget_resolve.json"))
	if err != nil {
		t.Fatal(err)
	}
	l.nugetIndex = idx

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/acme", "acme", "Acme")
	ix.Finish()

	r := rule.NewRule("csharp_library", "app")
	input := resolveInput{imports: []string{"Acme.Logging"}, own: []string{"App"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app"))

	want := []string{"@nuget.net10.0//acme.logging"}
	if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v (workspace parent namespace must not shadow exact NuGet package)", got, want)
	}
}

func indexLibraryWithTypes(t *testing.T, l *csharpLang, c *config.Config, ix *resolve.RuleIndex, pkg, name string, namespaces, types []string) {
	t.Helper()
	f := rule.EmptyFile(pkg+"/BUILD.bazel", pkg)
	r := rule.NewRule("csharp_library", name)
	r.SetPrivateAttr(namespacesKey, namespaces)
	r.SetPrivateAttr(typesKey, types)
	ix.AddRule(c, r, f)
}

func TestResolveImplicitParentNamespaceType(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "common", "common/Agrifirm.Common", "common/Agrifirm.Common/HealthChecks", "common/Agrifirm.Common/HealthChecks/Dapr")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common", "agrifirm_common",
		[]string{"Agrifirm.Common"},
		[]string{"Agrifirm.Common.DependencyInjectionExtensions"},
	)
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common/HealthChecks", "healthchecks",
		[]string{"Agrifirm.Common.HealthChecks"},
		[]string{"Agrifirm.Common.HealthChecks.ICustomHealthCheck"},
	)
	ix.Finish()

	r := rule.NewRule("csharp_library", "dapr")
	input := resolveInput{
		own:  []string{"Agrifirm.Common.HealthChecks.Dapr"},
		refs: []string{"DaprSideCarHealthCheck", "ICustomHealthCheck"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Agrifirm.Common/HealthChecks/Dapr", "dapr"))

	want := []string{"//common/Agrifirm.Common/HealthChecks:healthchecks"}
	if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v (must resolve parent type without pulling unreferenced grandparent)", got, want)
	}
}

func TestResolveImplicitRelativeAndFullyQualifiedNames(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive,
		"common",
		"common/Agrifirm.Common",
		"common/Agrifirm.Common/Configuration",
		"common/Agrifirm.Common/Tenant",
		"other",
		"other/app",
	)

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common", "constants",
		[]string{"Agrifirm.Common"},
		[]string{"Agrifirm.Common.CoreConstants"},
	)
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common", "agrifirm_common",
		[]string{"Agrifirm.Common"},
		[]string{"Agrifirm.Common.DependencyInjectionExtensions"},
	)
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common/Tenant", "tenant_enum",
		[]string{"Agrifirm.Common.Tenant"},
		[]string{"Agrifirm.Common.Tenant.Tenant"},
	)
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common/Tenant", "tenant",
		[]string{"Agrifirm.Common.Tenant"},
		[]string{"Agrifirm.Common.Tenant.TenantContext"},
	)
	ix.Finish()

	t.Run("relative sibling and enclosing type", func(t *testing.T) {
		r := rule.NewRule("csharp_library", "configuration")
		input := resolveInput{
			own: []string{"Agrifirm.Common.Configuration"},
			refs: []string{
				"CoreConstants.Authentication.B2cAgrifirm",
				"Tenant.Tenant",
				"Tenant.Tenant.Agrifirm",
			},
		}
		l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Agrifirm.Common/Configuration", "configuration"))

		want := []string{
			"//common/Agrifirm.Common/Tenant:tenant_enum",
			"//common/Agrifirm.Common:constants",
		}
		if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, want) {
			t.Errorf("deps = %v, want %v", got, want)
		}
	})

	t.Run("grandparent-relative qualified name", func(t *testing.T) {
		r := rule.NewRule("csharp_library", "tenant")
		input := resolveInput{
			own:  []string{"Agrifirm.Common.Tenant"},
			refs: []string{"Common.Tenant.Tenant.Agrifirm"},
		}
		l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Agrifirm.Common/Tenant", "tenant"))

		want := []string{":tenant_enum"}
		if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, want) {
			t.Errorf("deps = %v, want %v", got, want)
		}
	})

	t.Run("fully qualified name without using", func(t *testing.T) {
		r := rule.NewRule("csharp_library", "app")
		input := resolveInput{
			own:  []string{"Other.App"},
			refs: []string{"Agrifirm.Common.Tenant.Tenant"},
		}
		l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "other/app", "app"))

		want := []string{"//common/Agrifirm.Common/Tenant:tenant_enum"}
		if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, want) {
			t.Errorf("deps = %v, want %v", got, want)
		}
	})
}

func TestResolveImplicitSameNamespaceSplitTarget(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "common", "common/Agrifirm.Common", "common/Agrifirm.Common/Tenant")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common/Tenant", "tenant_enum",
		[]string{"Agrifirm.Common.Tenant"},
		[]string{"Agrifirm.Common.Tenant.Tenant"},
	)
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common/Tenant", "tenant",
		[]string{"Agrifirm.Common.Tenant"},
		[]string{"Agrifirm.Common.Tenant.TenantContext"},
	)
	ix.Finish()

	r := rule.NewRule("csharp_library", "tenant")
	input := resolveInput{
		own:  []string{"Agrifirm.Common.Tenant"},
		refs: []string{"Tenant", "TenantContext"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Agrifirm.Common/Tenant", "tenant"))

	want := []string{":tenant_enum"}
	if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v", got, want)
	}
}

func TestImportsIndexesHandWrittenLibraryFromDisk(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "common", "common/Tenant")
	writeFile(t, filepath.Join(dir, "common/Tenant"), "Tenant.cs", "namespace Agrifirm.Common.Tenant;\npublic enum Tenant { A }\n")

	f := rule.EmptyFile(filepath.Join(dir, "common/Tenant/BUILD.bazel"), "common/Tenant")
	r := rule.NewRule("csharp_library", "tenant_enum")
	r.SetAttr("srcs", []string{"Tenant.cs"})

	specs := l.Resolver.Imports(c, r, f)
	want := []resolve.ImportSpec{
		{Lang: languageName, Imp: "Agrifirm.Common.Tenant"},
		{Lang: typeLanguageName, Imp: "Agrifirm.Common.Tenant.Tenant"},
		{Lang: nsConsumerLanguageName, Imp: "Agrifirm"},
		{Lang: nsConsumerLanguageName, Imp: "Agrifirm.Common"},
		{Lang: nsConsumerLanguageName, Imp: "Agrifirm.Common.Tenant"},
	}
	if !reflect.DeepEqual(specs, want) {
		t.Errorf("Imports() = %v, want %v", specs, want)
	}
}

func TestImportsIgnoresMissingHandWrittenSrcs(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "common", "common/Gen")
	f := rule.EmptyFile(filepath.Join(dir, "common/Gen/BUILD.bazel"), "common/Gen")
	r := rule.NewRule("csharp_library", "gen")
	r.SetAttr("srcs", []string{"DoesNotExist.cs"})

	if specs := l.Resolver.Imports(c, r, f); len(specs) != 0 {
		t.Errorf("Imports() = %v, want empty", specs)
	}
}

func TestResolveExplicitUsingStillReturnsAllSplitProviders(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "common", "common/Agrifirm.Common", "common/Agrifirm.Common/Tenant", "src", "src/app")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common/Tenant", "tenant_enum",
		[]string{"Agrifirm.Common.Tenant"},
		[]string{"Agrifirm.Common.Tenant.Tenant"},
	)
	indexLibraryWithTypes(t, l, c, ix,
		"common/Agrifirm.Common/Tenant", "tenant",
		[]string{"Agrifirm.Common.Tenant"},
		[]string{"Agrifirm.Common.Tenant.TenantContext"},
	)
	ix.Finish()

	r := rule.NewRule("csharp_library", "app")
	input := resolveInput{
		imports: []string{"Agrifirm.Common.Tenant"},
		own:     []string{"App"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app"))

	want := []string{
		"//common/Agrifirm.Common/Tenant:tenant",
		"//common/Agrifirm.Common/Tenant:tenant_enum",
	}
	if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v", got, want)
	}
}

func TestResolveImplicitInnermostScopeShadowsParent(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "pkg", "pkg/sub")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibraryWithTypes(t, l, c, ix,
		"pkg", "parent",
		[]string{"Acme"},
		[]string{"Acme.Extensions"},
	)
	indexLibraryWithTypes(t, l, c, ix,
		"pkg/sub", "sub",
		[]string{"Acme.Sub"},
		[]string{"Acme.Sub.Extensions"},
	)
	ix.Finish()

	r := rule.NewRule("csharp_library", "sub")
	input := resolveInput{
		own:  []string{"Acme.Sub"},
		refs: []string{"Extensions.Init"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "pkg/sub", "sub"))

	if got := r.AttrStrings("deps"); len(got) != 0 {
		t.Errorf("deps = %v, want empty (self type in Acme.Sub must shadow Acme.Extensions)", got)
	}
}

func TestResolveImplicitMultiNamespaceScopeOrder(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "pkg", "pkg/sub")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibraryWithTypes(t, l, c, ix,
		"pkg", "parent",
		[]string{"A"},
		[]string{"A.Widget"},
	)
	indexLibraryWithTypes(t, l, c, ix,
		"pkg/sub", "sub",
		[]string{"A.B", "A.C"},
		[]string{"A.C.Widget"},
	)
	ix.Finish()

	r := rule.NewRule("csharp_library", "sub")
	input := resolveInput{
		own:  []string{"A.B", "A.C"},
		refs: []string{"Widget"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "pkg/sub", "sub"))

	if got := r.AttrStrings("deps"); len(got) != 0 {
		t.Errorf("deps = %v, want empty (deeper scope A.C must be checked before parent A)", got)
	}
}

func TestImportsRespectsAliasMap(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "common", "common/Tenant")
	c.AliasMap = map[string]string{"custom_csharp_library": "csharp_library"}
	writeFile(t, filepath.Join(dir, "common/Tenant"), "Tenant.cs", "namespace Agrifirm.Common.Tenant;\npublic enum Tenant { A }\n")

	f := rule.EmptyFile(filepath.Join(dir, "common/Tenant/BUILD.bazel"), "common/Tenant")
	r := rule.NewRule("custom_csharp_library", "tenant_enum")
	r.SetAttr("srcs", []string{"Tenant.cs"})

	specs := l.Resolver.Imports(c, r, f)
	want := []resolve.ImportSpec{
		{Lang: languageName, Imp: "Agrifirm.Common.Tenant"},
		{Lang: typeLanguageName, Imp: "Agrifirm.Common.Tenant.Tenant"},
		{Lang: nsConsumerLanguageName, Imp: "Agrifirm"},
		{Lang: nsConsumerLanguageName, Imp: "Agrifirm.Common"},
		{Lang: nsConsumerLanguageName, Imp: "Agrifirm.Common.Tenant"},
	}
	if !reflect.DeepEqual(specs, want) {
		t.Errorf("Imports() = %v, want %v", specs, want)
	}
}

func indexConsumer(t *testing.T, l *csharpLang, c *config.Config, ix *resolve.RuleIndex, kind, pkg, name, out string, ci consumerInfo) {
	t.Helper()
	f := rule.EmptyFile(pkg+"/BUILD.bazel", pkg)
	r := rule.NewRule(kind, name)
	if out != "" {
		r.SetAttr("out", out)
	}
	r.SetPrivateAttr(consumerInfoKey, ci)
	ix.AddRule(c, r, f)
}

func TestResolveInternalsVisibleToExplicitUsing(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive,
		"common",
		"common/Mail",
		"common/Mail/Utilities",
		"common/Mail/Models",
		"common/Mail/Models/Requests",
	)

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexConsumer(t, l, c, ix, "csharp_library", "common/Mail/Models/Requests", "requests", "", consumerInfo{
		usings: []string{"Agrifirm.Common.Mail.Utilities"},
		own:    []string{"Agrifirm.Common.Mail.Models.Requests"},
		refs:   []string{"EmbeddedResourceReader.GetResource"},
	})
	ix.Finish()

	r := rule.NewRule("csharp_library", "utilities")
	input := resolveInput{
		own:           []string{"Agrifirm.Common.Mail.Utilities"},
		internalTypes: []string{"Agrifirm.Common.Mail.Utilities.EmbeddedResourceReader"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Mail/Utilities", "utilities"))

	want := []string{"requests"}
	if got := r.AttrStrings("internals_visible_to"); !reflect.DeepEqual(got, want) {
		t.Errorf("internals_visible_to = %v, want %v", got, want)
	}
}

func TestResolveInternalsVisibleToSeparateTestTarget(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive,
		"common",
		"common/Auth",
		"common/Tests",
		"common/Tests/Auth",
	)

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexConsumer(t, l, c, ix, "csharp_mstest_test", "common/Tests/Auth", "authorization_mstest_test", "", consumerInfo{
		usings: []string{"Agrifirm.Common.Middleware.Authorization"},
		own:    []string{"Agrifirm.Common.UnitTests.Middleware.Authorization"},
		refs:   []string{"SalesAreaKeyUserFallbackAuthorizer"},
	})
	ix.Finish()

	r := rule.NewRule("csharp_library", "authorization")
	input := resolveInput{
		own:           []string{"Agrifirm.Common.Middleware.Authorization"},
		internalTypes: []string{"Agrifirm.Common.Middleware.Authorization.SalesAreaKeyUserFallbackAuthorizer"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Auth", "authorization"))

	want := []string{"authorization_mstest_test"}
	if got := r.AttrStrings("internals_visible_to"); !reflect.DeepEqual(got, want) {
		t.Errorf("internals_visible_to = %v, want %v", got, want)
	}
}

func TestResolveInternalsVisibleToUsesCustomOutAssemblyName(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "common", "common/Util", "common/Consumer")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexConsumer(t, l, c, ix, "csharp_library", "common/Consumer", "consumer_target", "Custom.Consumer", consumerInfo{
		usings: []string{"Acme.Util"},
		own:    []string{"Acme.Consumer"},
		refs:   []string{"SecretHelper"},
	})
	ix.Finish()

	r := rule.NewRule("csharp_library", "util")
	input := resolveInput{
		own:           []string{"Acme.Util"},
		internalTypes: []string{"Acme.Util.SecretHelper"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Util", "util"))

	want := []string{"Custom.Consumer"}
	if got := r.AttrStrings("internals_visible_to"); !reflect.DeepEqual(got, want) {
		t.Errorf("internals_visible_to = %v, want %v", got, want)
	}
}

func TestResolveInternalsVisibleToIgnoresNonReferencingConsumer(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "common", "common/Util", "common/Other")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexConsumer(t, l, c, ix, "csharp_library", "common/Other", "other", "", consumerInfo{
		usings: []string{"Acme.Util"},
		own:    []string{"Acme.Other"},
		refs:   []string{"PublicHelper"},
	})
	ix.Finish()

	r := rule.NewRule("csharp_library", "util")
	input := resolveInput{
		own:           []string{"Acme.Util"},
		internalTypes: []string{"Acme.Util.SecretHelper"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Util", "util"))

	if got := r.AttrStrings("internals_visible_to"); len(got) != 0 {
		t.Errorf("internals_visible_to = %v, want empty", got)
	}
}

func TestResolveInternalsVisibleToPreservesExistingEntries(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "common", "common/Util", "common/Req")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexConsumer(t, l, c, ix, "csharp_library", "common/Req", "requests", "", consumerInfo{
		usings: []string{"Acme.Util"},
		own:    []string{"Acme.Req"},
		refs:   []string{"SecretHelper"},
	})
	ix.Finish()

	r := rule.NewRule("csharp_library", "util")
	r.SetAttr("internals_visible_to", []string{"util_nunit_test"})
	input := resolveInput{
		own:           []string{"Acme.Util"},
		internalTypes: []string{"Acme.Util.SecretHelper"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Util", "util"))

	want := []string{"requests", "util_nunit_test"}
	if got := r.AttrStrings("internals_visible_to"); !reflect.DeepEqual(got, want) {
		t.Errorf("internals_visible_to = %v, want %v", got, want)
	}
}

func TestResolveInternalsVisibleToRelativeQualifiedRef(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "common", "common/Tenant", "common/Configuration")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexConsumer(t, l, c, ix, "csharp_library", "common/Configuration", "configuration", "", consumerInfo{
		own:  []string{"Agrifirm.Common.Configuration"},
		refs: []string{"Tenant.SecretTenant"},
	})
	ix.Finish()

	r := rule.NewRule("csharp_library", "tenant")
	input := resolveInput{
		own:           []string{"Agrifirm.Common.Tenant"},
		internalTypes: []string{"Agrifirm.Common.Tenant.SecretTenant"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Tenant", "tenant"))

	want := []string{"configuration"}
	if got := r.AttrStrings("internals_visible_to"); !reflect.DeepEqual(got, want) {
		t.Errorf("internals_visible_to = %v, want %v", got, want)
	}
}

func TestResolveInternalsVisibleToDiskIndexedTestRule(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "common", "common/Auth", "common/Tests", "common/Tests/Auth")
	writeFile(t, filepath.Join(dir, "common/Tests/Auth"), "AuthTests.cs",
		"using Agrifirm.Common.Middleware.Authorization;\nnamespace Agrifirm.Common.UnitTests.Middleware.Authorization;\npublic class AuthTests { void T() { _ = new SalesAreaKeyUserFallbackAuthorizer(); } }\n")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	testFile := rule.EmptyFile(filepath.Join(dir, "common/Tests/Auth/BUILD.bazel"), "common/Tests/Auth")
	testRule := rule.NewRule("csharp_mstest_test", "authorization_mstest_test")
	testRule.SetAttr("srcs", []string{"AuthTests.cs"})
	// No consumerInfoKey private attr — simulates partial-tree / index-only Imports().
	ix.AddRule(c, testRule, testFile)
	ix.Finish()

	r := rule.NewRule("csharp_library", "authorization")
	input := resolveInput{
		own:           []string{"Agrifirm.Common.Middleware.Authorization"},
		internalTypes: []string{"Agrifirm.Common.Middleware.Authorization.SalesAreaKeyUserFallbackAuthorizer"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Auth", "authorization"))

	want := []string{"authorization_mstest_test"}
	if got := r.AttrStrings("internals_visible_to"); !reflect.DeepEqual(got, want) {
		t.Errorf("internals_visible_to = %v, want %v", got, want)
	}
}

func TestResolveInternalsVisibleToFQNAndUsingAlias(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "common", "common/Util", "other", "other/app", "other/alias")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexConsumer(t, l, c, ix, "csharp_library", "other/app", "fqn_app", "", consumerInfo{
		own:  []string{"Other.App"},
		refs: []string{"Agrifirm.Common.Util.SecretHelper.Run"},
	})
	indexConsumer(t, l, c, ix, "csharp_library", "other/alias", "alias_app", "", consumerInfo{
		usings:  []string{"Agrifirm.Common.Util"},
		aliases: map[string]string{"U": "Agrifirm.Common.Util"},
		own:     []string{"Other.Alias"},
		refs:    []string{"U.SecretHelper.Run"},
	})
	ix.Finish()

	r := rule.NewRule("csharp_library", "util")
	input := resolveInput{
		own:           []string{"Agrifirm.Common.Util"},
		internalTypes: []string{"Agrifirm.Common.Util.SecretHelper"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "common/Util", "util"))

	want := []string{"alias_app", "fqn_app"}
	if got := r.AttrStrings("internals_visible_to"); !reflect.DeepEqual(got, want) {
		t.Errorf("internals_visible_to = %v, want %v", got, want)
	}
}
