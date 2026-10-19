package gazelle

import (
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
