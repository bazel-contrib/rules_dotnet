package dotnetconfig

import (
	"reflect"
	"strings"
	"testing"
)

func TestDefaults(t *testing.T) {
	c := New("/repo")
	if got := c.NugetRepoPrefix(); got != "nuget." {
		t.Errorf("NugetRepoPrefix() = %q, want %q", got, "nuget.")
	}
	if !c.GenerateBinary() {
		t.Error("GenerateBinary() = false, want true")
	}
	if got := c.ProjectSdk(); got != "default" {
		t.Errorf("ProjectSdk() = %q, want %q", got, "default")
	}
	if got := c.UnresolvedImports(); got != "warn" {
		t.Errorf("UnresolvedImports() = %q, want %q", got, "warn")
	}
	if got := c.NugetLockFile(); got != "nuget_resolve.json" {
		t.Errorf("NugetLockFile() = %q, want %q", got, "nuget_resolve.json")
	}
	if got := c.Visibility(); !reflect.DeepEqual(got, []string{"//visibility:public"}) {
		t.Errorf("Visibility() = %v, want [//visibility:public]", got)
	}
	if got := c.TargetFrameworks(); len(got) != 0 {
		t.Errorf("TargetFrameworks() = %v, want empty", got)
	}
	if got := c.TestFramework(); got != "" {
		t.Errorf("TestFramework() = %q, want empty", got)
	}
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
	root := New("/repo")
	root.SetTargetFrameworks("net10.0")
	root.AddVisibility("//visibility:private")
	if err := root.AddResolve("Acme.Widget @acme//widget"); err != nil {
		t.Fatal(err)
	}

	child := root.NewChild()
	if got := child.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net10.0"}) {
		t.Errorf("child TargetFrameworks() = %v, want [net10.0]", got)
	}
	if got := child.Visibility(); !reflect.DeepEqual(got, []string{"//visibility:private"}) {
		t.Errorf("child Visibility() = %v, want [//visibility:private]", got)
	}
	if lbl, ok := child.ResolveOverride("Acme.Widget"); !ok || lbl != "@acme//widget" {
		t.Errorf("child ResolveOverride() = %q, %v; want @acme//widget, true", lbl, ok)
	}

	// Mutating the child must not leak into the parent.
	child.SetTargetFrameworks("net9.0")
	child.AddVisibility("//other:__pkg__")
	if err := child.AddResolve("Other.Ns //other"); err != nil {
		t.Fatal(err)
	}
	if got := root.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net10.0"}) {
		t.Errorf("root TargetFrameworks() = %v after child mutation, want [net10.0]", got)
	}
	if got := root.Visibility(); !reflect.DeepEqual(got, []string{"//visibility:private"}) {
		t.Errorf("root Visibility() = %v after child mutation, want [//visibility:private]", got)
	}
	if _, ok := root.ResolveOverride("Other.Ns"); ok {
		t.Error("root ResolveOverride(Other.Ns) = true after child mutation, want false")
	}
}

func TestAddResolveValidation(t *testing.T) {
	c := New("/repo")
	if err := c.AddResolve("justonefield"); err == nil {
		t.Error("AddResolve(justonefield) = nil error, want error")
	}
	if err := c.AddResolve("a b c"); err == nil {
		t.Error("AddResolve(a b c) = nil error, want error")
	}
	if err := c.AddResolve("Ns //label"); err != nil {
		t.Errorf("AddResolve(Ns //label) = %v, want nil", err)
	}
}

func TestSetTestFrameworkValidation(t *testing.T) {
	c := New("/repo")
	for _, fw := range []string{"nunit", "xunit", "mstest"} {
		if err := c.SetTestFramework(fw); err != nil {
			t.Errorf("SetTestFramework(%q) = %v, want nil", fw, err)
		}
	}
	if err := c.SetTestFramework("junit"); err == nil {
		t.Error("SetTestFramework(junit) = nil error, want error")
	}
}

func TestSetUnresolvedImportsValidation(t *testing.T) {
	c := New("/repo")
	for _, v := range []string{"warn", "error"} {
		if err := c.SetUnresolvedImports(v); err != nil {
			t.Errorf("SetUnresolvedImports(%q) = %v, want nil", v, err)
		}
	}
	if err := c.SetUnresolvedImports("fail"); err == nil {
		t.Error("SetUnresolvedImports(fail) = nil error, want error")
	}
}

func TestSetTargetFrameworks(t *testing.T) {
	c := New("/repo")
	c.SetTargetFrameworks("net10.0, net9.0")
	if got := c.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net10.0", "net9.0"}) {
		t.Errorf("TargetFrameworks() = %v, want [net10.0 net9.0]", got)
	}
	// Reset semantics: a later directive replaces the list.
	c.SetTargetFrameworks("net8.0")
	if got := c.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net8.0"}) {
		t.Errorf("TargetFrameworks() = %v after reset, want [net8.0]", got)
	}
}

func TestNugetLabel(t *testing.T) {
	c := New("/repo")
	c.SetTargetFrameworks("net10.0")
	if got := c.NugetLabel("Newtonsoft.Json"); got != "@nuget.net10.0//newtonsoft.json" {
		t.Errorf("NugetLabel() = %q, want @nuget.net10.0//newtonsoft.json", got)
	}
	c.SetNugetRepoPrefix("custom.")
	if got := c.NugetLabel("Newtonsoft.Json"); got != "@custom.net10.0//newtonsoft.json" {
		t.Errorf("NugetLabel() = %q, want @custom.net10.0//newtonsoft.json", got)
	}
}

func TestParentForPackage(t *testing.T) {
	root := New("/repo")
	cfgs := Configs{"": root}
	if got := cfgs.ParentForPackage("src"); got != root {
		t.Error("ParentForPackage(src) != root config")
	}
	child := root.NewChild()
	cfgs["src"] = child
	if got := cfgs.ParentForPackage("src/app"); got != child {
		t.Error("ParentForPackage(src/app) != child config")
	}
}
