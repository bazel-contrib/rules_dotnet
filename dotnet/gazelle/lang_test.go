package gazelle

import (
	"path/filepath"
	"reflect"
	"testing"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

func TestNewLanguageKindsAndLoads(t *testing.T) {
	l := NewLanguage()
	kinds := l.Kinds()
	for _, want := range []string{
		"csharp_library",
		"csharp_binary",
		"csharp_test",
		"csharp_nunit_test",
		"csharp_xunit_test",
		"csharp_mstest_test",
	} {
		if _, ok := kinds[want]; !ok {
			t.Errorf("Kinds() missing %q", want)
		}
	}
	loads := l.Loads()
	if len(loads) != 1 || loads[0].Name != "@rules_dotnet//dotnet:defs.bzl" {
		t.Errorf("Loads() = %+v, want a single load from @rules_dotnet//dotnet:defs.bzl", loads)
	}
}

func TestApparentLoads(t *testing.T) {
	l := NewLanguage().(*csharpLang)

	loads := l.ApparentLoads(func(module string) string {
		if module == "rules_dotnet" {
			return "my_dotnet"
		}
		return ""
	})
	if len(loads) != 1 || loads[0].Name != "@my_dotnet//dotnet:defs.bzl" {
		t.Errorf("ApparentLoads() = %+v, want @my_dotnet//dotnet:defs.bzl", loads)
	}

	loads = l.ApparentLoads(func(string) string { return "" })
	if len(loads) != 1 || loads[0].Name != "@rules_dotnet//dotnet:defs.bzl" {
		t.Errorf("ApparentLoads() fallback = %+v, want @rules_dotnet//dotnet:defs.bzl", loads)
	}
}

func TestImportsIndexesLibraryNamespaces(t *testing.T) {
	l := NewLanguage().(*csharpLang)
	res := l.Resolver
	f := rule.EmptyFile("src/calculator/BUILD.bazel", "src/calculator")

	lib := rule.NewRule("csharp_library", "calculator")
	lib.SetPrivateAttr(namespacesKey, []string{"Calculator", "Calculator.Util"})
	specs := res.Imports(config.New(), lib, f)
	if len(specs) != 2 {
		t.Fatalf("Imports() = %v, want 2 specs", specs)
	}
	for i, want := range []string{"Calculator", "Calculator.Util"} {
		if specs[i].Lang != "csharp" || specs[i].Imp != want {
			t.Errorf("specs[%d] = %+v, want {Lang: csharp, Imp: %s}", i, specs[i], want)
		}
	}

	if got := res.Imports(config.New(), rule.NewRule("csharp_binary", "b"), f); got != nil {
		t.Errorf("Imports(csharp_binary) = %v, want nil", got)
	}
}

func TestConfigureInheritance(t *testing.T) {
	_, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/app")
	cfg := getConfig(c, "src/app")
	if cfg == nil {
		t.Fatal("no config for src/app")
	}
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
