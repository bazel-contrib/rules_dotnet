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
