package gazelle

import (
	"path/filepath"
	"reflect"
	"testing"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/language"
	"github.com/bazelbuild/bazel-gazelle/merger"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

const net10Directive = "# gazelle:dotnet_target_frameworks net10.0\n"

// generate runs GenerateRules for package rel rooted at dir, where the
// given .cs files have already been written to disk.
func generate(t *testing.T, l *csharpLang, c *config.Config, dir, rel string, files ...string) language.GenerateResult {
	t.Helper()
	return l.GenerateRules(language.GenerateArgs{
		Config:       c,
		Dir:          filepath.Join(dir, filepath.FromSlash(rel)),
		Rel:          rel,
		RegularFiles: files,
	})
}

const calculatorSrc = `namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;
}
`

const nunitTestSrc = `using Calculator;
using NUnit.Framework;

namespace Calculator.Tests;

[TestFixture]
public sealed class ArithmeticTests
{
    [Test]
    public void AddWorks()
    {
        Assert.AreEqual(4, Arithmetic.Add(2, 2));
    }
}
`

const xunitTestSrc = `using Calculator;
using Xunit;

namespace Calculator.Tests;

public sealed class ArithmeticTests
{
    [Fact]
    public void AddWorks()
    {
        Assert.Equal(4, Arithmetic.Add(2, 2));
    }
}
`

const programSrc = `using System;

namespace App;

public static class Program
{
    public static void Main(string[] args)
    {
        Console.WriteLine("hi");
    }
}
`

const programWithMethodSrc = `using System;
using Calculator;

namespace App;

public static class Program
{
    public static int Run() => Arithmetic.Add(2, 2);

    public static void Main(string[] args)
    {
        Console.WriteLine(Run());
    }
}
`

const appTestSrc = `using App;
using NUnit.Framework;

namespace App.Tests;

[TestFixture]
public sealed class ProgramTests
{
    [Test]
    public void RunWorks()
    {
        Assert.AreEqual(4, Program.Run());
    }
}
`

func TestGenerateLibrary(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/calculator")
	writeFile(t, filepath.Join(dir, "src", "calculator"), "Calculator.cs", calculatorSrc)

	res := generate(t, l, c, dir, "src/calculator", "Calculator.cs")
	if len(res.Gen) != 1 || len(res.Imports) != 1 {
		t.Fatalf("GenerateRules() = %d rules, %d imports; want 1, 1", len(res.Gen), len(res.Imports))
	}
	lib := res.Gen[0]
	if lib.Kind() != "csharp_library" || lib.Name() != "calculator" {
		t.Errorf("rule = %s %s, want csharp_library calculator", lib.Kind(), lib.Name())
	}
	if got := lib.AttrStrings("srcs"); !reflect.DeepEqual(got, []string{"Calculator.cs"}) {
		t.Errorf("srcs = %v, want [Calculator.cs]", got)
	}
	if got := lib.AttrStrings("target_frameworks"); !reflect.DeepEqual(got, []string{"net10.0"}) {
		t.Errorf("target_frameworks = %v, want [net10.0]", got)
	}
	if got := lib.AttrString("project_sdk"); got != "default" {
		t.Errorf("project_sdk = %q, want default", got)
	}
	if got := lib.AttrStrings("visibility"); !reflect.DeepEqual(got, []string{"//visibility:public"}) {
		t.Errorf("visibility = %v, want [//visibility:public]", got)
	}
	if lib.Attr("internals_visible_to") != nil {
		t.Error("internals_visible_to is set, want unset")
	}
	input, ok := res.Imports[0].(resolveInput)
	if !ok {
		t.Fatalf("Imports[0] = %T, want resolveInput", res.Imports[0])
	}
	if !reflect.DeepEqual(input.own, []string{"Calculator"}) {
		t.Errorf("own = %v, want [Calculator]", input.own)
	}
	if len(input.imports) != 0 {
		t.Errorf("imports = %v, want empty", input.imports)
	}
	if got, _ := lib.PrivateAttr(namespacesKey).([]string); !reflect.DeepEqual(got, []string{"Calculator"}) {
		t.Errorf("private namespaces = %v, want [Calculator]", got)
	}
}

func TestGenerateLibraryAndNunitTest(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/calculator")
	writeFile(t, filepath.Join(dir, "src", "calculator"), "Calculator.cs", calculatorSrc)
	writeFile(t, filepath.Join(dir, "src", "calculator"), "CalculatorTests.cs", nunitTestSrc)

	res := generate(t, l, c, dir, "src/calculator", "Calculator.cs", "CalculatorTests.cs")
	if len(res.Gen) != 2 || len(res.Imports) != 2 {
		t.Fatalf("GenerateRules() = %d rules, %d imports; want 2, 2", len(res.Gen), len(res.Imports))
	}
	lib, test := res.Gen[0], res.Gen[1]
	if lib.Kind() != "csharp_library" {
		t.Errorf("Gen[0] = %s, want csharp_library", lib.Kind())
	}
	if got := lib.AttrStrings("internals_visible_to"); !reflect.DeepEqual(got, []string{"calculator_nunit_test"}) {
		t.Errorf("internals_visible_to = %v, want [calculator_nunit_test]", got)
	}
	if test.Kind() != "csharp_nunit_test" || test.Name() != "calculator_nunit_test" {
		t.Errorf("test rule = %s %s, want csharp_nunit_test calculator_nunit_test", test.Kind(), test.Name())
	}
	if got := test.AttrStrings("srcs"); !reflect.DeepEqual(got, []string{"CalculatorTests.cs"}) {
		t.Errorf("test srcs = %v, want [CalculatorTests.cs]", got)
	}
	if got := test.AttrStrings("deps"); !reflect.DeepEqual(got, []string{":calculator"}) {
		t.Errorf("test deps = %v, want [:calculator]", got)
	}
	input := res.Imports[1].(resolveInput)
	if !reflect.DeepEqual(input.imports, []string{"Calculator", "NUnit.Framework"}) {
		t.Errorf("test imports = %v, want [Calculator NUnit.Framework]", input.imports)
	}
	if !reflect.DeepEqual(input.own, []string{"Calculator.Tests"}) {
		t.Errorf("test own = %v, want [Calculator.Tests]", input.own)
	}
}

func TestGenerateForcedFramework(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/calculator")
	// Re-configure the package with a forced framework directive.
	f, err := rule.LoadData(filepath.Join(dir, "src", "calculator", "BUILD.bazel"), "src/calculator",
		[]byte("# gazelle:dotnet_test_framework nunit\n"))
	if err != nil {
		t.Fatal(err)
	}
	l.Configure(c, "src/calculator", f)

	writeFile(t, filepath.Join(dir, "src", "calculator"), "Calculator.cs", calculatorSrc)
	writeFile(t, filepath.Join(dir, "src", "calculator"), "CalculatorTests.cs", xunitTestSrc)

	res := generate(t, l, c, dir, "src/calculator", "Calculator.cs", "CalculatorTests.cs")
	if len(res.Gen) != 2 {
		t.Fatalf("GenerateRules() = %d rules, want 2", len(res.Gen))
	}
	if got := res.Gen[1].Kind(); got != "csharp_nunit_test" {
		t.Errorf("test rule kind = %s, want csharp_nunit_test (forced)", got)
	}
}

func TestGenerateBinary(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/app")
	writeFile(t, filepath.Join(dir, "src", "app"), "Program.cs", programSrc)

	res := generate(t, l, c, dir, "src/app", "Program.cs")
	if len(res.Gen) != 1 || len(res.Imports) != 1 {
		t.Fatalf("GenerateRules() = %d rules, %d imports; want 1, 1", len(res.Gen), len(res.Imports))
	}
	bin := res.Gen[0]
	if bin.Kind() != "csharp_binary" || bin.Name() != "program" {
		t.Errorf("rule = %s %s, want csharp_binary program", bin.Kind(), bin.Name())
	}
	if got := bin.AttrStrings("srcs"); !reflect.DeepEqual(got, []string{"Program.cs"}) {
		t.Errorf("srcs = %v, want [Program.cs]", got)
	}
	input := res.Imports[0].(resolveInput)
	if !reflect.DeepEqual(input.imports, []string{"System"}) {
		t.Errorf("imports = %v, want [System]", input.imports)
	}
	if !reflect.DeepEqual(input.own, []string{"App"}) {
		t.Errorf("own = %v, want [App]", input.own)
	}
}

func TestGenerateBinaryDisabled(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/app")
	f, err := rule.LoadData(filepath.Join(dir, "src", "app", "BUILD.bazel"), "src/app",
		[]byte("# gazelle:dotnet_generate_binary false\n"))
	if err != nil {
		t.Fatal(err)
	}
	l.Configure(c, "src/app", f)

	writeFile(t, filepath.Join(dir, "src", "app"), "Program.cs", programSrc)
	res := generate(t, l, c, dir, "src/app", "Program.cs")
	if len(res.Gen) != 1 || res.Gen[0].Kind() != "csharp_library" {
		t.Fatalf("GenerateRules() = %d rules (%s), want one csharp_library", len(res.Gen), res.Gen[0].Kind())
	}
	if got := res.Gen[0].AttrStrings("srcs"); !reflect.DeepEqual(got, []string{"Program.cs"}) {
		t.Errorf("srcs = %v, want [Program.cs]", got)
	}
}

func TestGenerateSkipsUnparseableFiles(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/broken")
	writeFile(t, filepath.Join(dir, "src", "broken"), "Broken.cs", "namespace Broken;\nvar s = \"unterminated;")
	writeFile(t, filepath.Join(dir, "src", "broken"), "Good.cs", "namespace Broken;\npublic class C {}\n")

	res := generate(t, l, c, dir, "src/broken", "Broken.cs", "Good.cs")
	if len(res.Gen) != 1 {
		t.Fatalf("GenerateRules() = %d rules, want 1", len(res.Gen))
	}
	if got := res.Gen[0].AttrStrings("srcs"); !reflect.DeepEqual(got, []string{"Good.cs"}) {
		t.Errorf("srcs = %v, want [Good.cs] (Broken.cs skipped)", got)
	}
}

func TestGenerateEmptyDirDeletesRules(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/gone")
	f, err := rule.LoadData(filepath.Join(dir, "src", "gone", "BUILD.bazel"), "src/gone",
		[]byte("csharp_library(name = \"gone\")\n"))
	if err != nil {
		t.Fatal(err)
	}

	res := l.GenerateRules(language.GenerateArgs{
		Config: c,
		Dir:    filepath.Join(dir, "src", "gone"),
		Rel:    "src/gone",
		File:   f,
	})
	if len(res.Gen) != 0 || len(res.Empty) != 1 {
		t.Fatalf("GenerateRules() = %d gen, %d empty; want 0, 1", len(res.Gen), len(res.Empty))
	}
	if res.Empty[0].Kind() != "csharp_library" || res.Empty[0].Name() != "gone" {
		t.Errorf("Empty[0] = %s %s, want csharp_library gone", res.Empty[0].Kind(), res.Empty[0].Name())
	}
}

func TestGenerateSkipsDotnetOutputDirectories(t *testing.T) {
	tests := []struct {
		name string
		rel  string
	}{
		{name: "root bin", rel: "bin"},
		{name: "root obj", rel: "obj"},
		{name: "nested bin", rel: "src/bin"},
		{name: "nested obj", rel: "src/obj/Debug/net10.0"},
		{name: "mixed case bin", rel: "src/BiN"},
		{name: "mixed case obj", rel: "src/OBJ"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			l, c, dir := setupLang(t, net10Directive, "src", "src/obj", "src/obj/Debug", tc.rel)
			writeFile(t, filepath.Join(dir, filepath.FromSlash(tc.rel)), "Output.cs", calculatorSrc)

			res := generate(t, l, c, dir, tc.rel, "Output.cs")
			if len(res.Gen) != 0 || len(res.Imports) != 0 || len(res.Empty) != 0 {
				t.Fatalf(
					"GenerateRules() = %d gen, %d imports, %d empty; want 0, 0, 0",
					len(res.Gen), len(res.Imports), len(res.Empty),
				)
			}
		})
	}
}

func TestGenerateDoesNotSkipBinObjSubstrings(t *testing.T) {
	for _, rel := range []string{"src/binary", "src/object"} {
		t.Run(rel, func(t *testing.T) {
			l, c, dir := setupLang(t, net10Directive, "src", rel)
			writeFile(t, filepath.Join(dir, filepath.FromSlash(rel)), "Calculator.cs", calculatorSrc)

			res := generate(t, l, c, dir, rel, "Calculator.cs")
			if len(res.Gen) != 1 || len(res.Imports) != 1 || len(res.Empty) != 0 {
				t.Fatalf(
					"GenerateRules() = %d gen, %d imports, %d empty; want 1, 1, 0",
					len(res.Gen), len(res.Imports), len(res.Empty),
				)
			}
			if got := res.Gen[0].Kind(); got != "csharp_library" {
				t.Errorf("generated kind = %q, want csharp_library", got)
			}
		})
	}
}

func TestGenerateOutputDirDeletesOnlyExistingCsharpRules(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/bin")
	f, err := rule.LoadData(
		filepath.Join(dir, "src", "bin", "BUILD.bazel"),
		"src/bin",
		[]byte(`csharp_library(name = "stale")
csharp_binary(name = "old_program")
csharp_nunit_test(name = "stale_test")
filegroup(name = "keep")
`),
	)
	if err != nil {
		t.Fatal(err)
	}
	// Valid source ensures RED comes from missing output guard, not no-source cleanup.
	writeFile(t, filepath.Join(dir, "src", "bin"), "Generated.cs", calculatorSrc)

	res := l.GenerateRules(language.GenerateArgs{
		Config:       c,
		Dir:          filepath.Join(dir, "src", "bin"),
		Rel:          "src/bin",
		RegularFiles: []string{"Generated.cs"},
		File:         f,
	})
	if len(res.Gen) != 0 || len(res.Imports) != 0 || len(res.Empty) != 3 {
		t.Fatalf("GenerateRules() = %d gen, %d imports, %d empty; want 0, 0, 3", len(res.Gen), len(res.Imports), len(res.Empty))
	}

	want := []struct{ kind, name string }{
		{kind: "csharp_library", name: "stale"},
		{kind: "csharp_binary", name: "old_program"},
		{kind: "csharp_nunit_test", name: "stale_test"},
	}
	for i, expected := range want {
		got := res.Empty[i]
		if got.Kind() != expected.kind || got.Name() != expected.name {
			t.Errorf("Empty[%d] = %s %s, want %s %s", i, got.Kind(), got.Name(), expected.kind, expected.name)
		}
	}
}

func TestGenerateTestInBinaryOnlyDirectory(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/app")
	writeFile(t, filepath.Join(dir, "src", "app"), "Program.cs", programWithMethodSrc)
	writeFile(t, filepath.Join(dir, "src", "app"), "ProgramTests.cs", appTestSrc)

	res := generate(t, l, c, dir, "src/app", "Program.cs", "ProgramTests.cs")
	if len(res.Gen) != 2 || len(res.Imports) != 2 {
		t.Fatalf("GenerateRules() = %d rules, %d imports; want 2, 2", len(res.Gen), len(res.Imports))
	}
	// Gen order: test rules before binaries (see GenerateRules).
	test, bin := res.Gen[0], res.Gen[1]
	if test.Kind() != "csharp_nunit_test" || test.Name() != "app_nunit_test" {
		t.Errorf("Gen[0] = %s %s, want csharp_nunit_test app_nunit_test", test.Kind(), test.Name())
	}
	if got := test.AttrStrings("deps"); !reflect.DeepEqual(got, []string{":program"}) {
		t.Errorf("test deps = %v, want [:program] (sibling dep on the entry-point binary)", got)
	}
	if bin.Kind() != "csharp_binary" || bin.Name() != "program" {
		t.Errorf("Gen[1] = %s %s, want csharp_binary program", bin.Kind(), bin.Name())
	}
	if got, _ := bin.PrivateAttr(namespacesKey).([]string); !reflect.DeepEqual(got, []string{"App"}) {
		t.Errorf("binary private namespaces = %v, want [App]", got)
	}
	if bin.Attr("internals_visible_to") != nil {
		t.Error("binary internals_visible_to is set, want unset (the tested method is public)")
	}
	input := res.Imports[0].(resolveInput)
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
		name        string
		directives  string
		nullable    string
		nullableSet bool
		implicit    bool
		implicitSet bool
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

func TestGenerateExplicitDirectivesOverrideAliasedExistingAttrs(t *testing.T) {
	l, c, dir := setupLang(t, net10Directive, "src", "src/aliased")
	existing, err := rule.LoadData(
		filepath.Join(dir, "src", "aliased", "BUILD.bazel"),
		"src/aliased",
		[]byte(`# gazelle:alias_kind custom_csharp_library csharp_library
# gazelle:dotnet_nullable disable
# gazelle:dotnet_implicit_usings disable

custom_csharp_library(
    name = "aliased",
    srcs = ["Calculator.cs"],
    implicit_usings = True,
    nullable = "enable",
)
`),
	)
	if err != nil {
		t.Fatal(err)
	}
	commonConfigurer := config.CommonConfigurer{}
	commonConfigurer.Configure(c, "src/aliased", existing)
	l.Configure(c, "src/aliased", existing)
	if got := c.AliasMap["custom_csharp_library"]; got != "csharp_library" {
		t.Fatalf("AliasMap[custom_csharp_library] = %q, want csharp_library", got)
	}
	writeFile(t, filepath.Join(dir, "src", "aliased"), "Calculator.cs", calculatorSrc)

	res := l.GenerateRules(language.GenerateArgs{
		Config:       c,
		Dir:          filepath.Join(dir, "src", "aliased"),
		Rel:          "src/aliased",
		RegularFiles: []string{"Calculator.cs"},
		File:         existing,
	})
	if len(res.Gen) != 1 {
		t.Fatalf("GenerateRules() returned %d rules, want 1", len(res.Gen))
	}

	// Exercise Gazelle's alias-aware pre-resolve match and normal second merge.
	merger.MergeFile(existing, nil, res.Gen, merger.PreResolve, l.Kinds(), c.AliasMap)
	if len(existing.Rules) != 1 {
		t.Fatalf("normal merge left %d rules, want one aliased match", len(existing.Rules))
	}
	got := existing.Rules[0]
	if got.Kind() != "custom_csharp_library" {
		t.Fatalf("merged rule kind = %q, want custom_csharp_library", got.Kind())
	}
	if value := got.AttrString("nullable"); value != "disable" {
		t.Errorf("merged nullable = %q, want disable", value)
	}
	if got.Attr("implicit_usings") == nil {
		t.Error("merged implicit_usings is absent, want explicit False")
	} else if value := got.AttrBool("implicit_usings"); value {
		t.Error("merged implicit_usings = True, want explicit False")
	}
}
