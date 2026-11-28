package parser

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func TestBlankCommentsAndStrings(t *testing.T) {
	tests := []struct {
		name    string
		src     string
		want    string
		wantErr string
	}{
		{
			name: "line comment",
			src:  "using X; // using Y;\nnamespace Z;",
			want: "using X;            \nnamespace Z;",
		},
		{
			name: "block comment with newlines",
			src:  "a /* one\ntwo */ b",
			want: "a       \n       b",
		},
		{
			name: "double quoted string",
			src:  `var s = "namespace Fake;";` + "\nnamespace Real;",
			want: "var s =                  ;" + "\nnamespace Real;",
		},
		{
			name: "string with escaped quote",
			src:  `var s = "a\"b"; namespace R;`,
			want: `var s =       ; namespace R;`,
		},
		{
			name: "char literal",
			src:  "var c = 'x'; namespace R;",
			want: "var c =    ; namespace R;",
		},
		{
			name: "verbatim string with doubled quote",
			src:  `var s = @"a""b"; namespace R;`,
			want: `var s =        ; namespace R;`,
		},
		{
			name: "verbatim multiline string keeps newlines",
			src:  "var s = @\"one\ntwo\"; namespace R;",
			want: "var s =      \n    ; namespace R;",
		},
		{
			name: "interpolated string",
			src:  `var s = $"value: {x}"; namespace R;`,
			want: `var s =              ; namespace R;`,
		},
		{
			name: "raw string",
			src:  "var s = \"\"\"namespace Fake;\"\"\"; namespace R;",
			want: "var s =                      ; namespace R;",
		},
		{
			name: "verbatim identifier is not a string",
			src:  "var @class = 1; namespace R;",
			want: "var @class = 1; namespace R;",
		},
		{
			name:    "unterminated string",
			src:     `var s = "oops;`,
			wantErr: "unterminated string",
		},
		{
			name:    "unterminated block comment",
			src:     "a /* oops",
			wantErr: "unterminated block comment",
		},
		{
			name:    "unterminated raw string",
			src:     "var s = \"\"\"oops",
			wantErr: "unterminated raw string",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := blankCommentsAndStrings(tc.src)
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("blankCommentsAndStrings() error = %v, want substring %q", err, tc.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("blankCommentsAndStrings() unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("blankCommentsAndStrings()\n got: %q\nwant: %q", got, tc.want)
			}
		})
	}
}

func TestParseNamespacesAndUsings(t *testing.T) {
	tests := []struct {
		name       string
		src        string
		wantNs     string
		wantUsings []Using
	}{
		{
			name:       "file-scoped namespace",
			src:        "using System;\n\nnamespace Foo.Bar;\n\npublic class C {}\n",
			wantNs:     "Foo.Bar",
			wantUsings: []Using{{Namespace: "System"}},
		},
		{
			name:       "file-scoped namespace followed by usings",
			src:        "namespace Fixture;\n\nusing MessagePack;\n\npublic class C {}\n",
			wantNs:     "Fixture",
			wantUsings: []Using{{Namespace: "MessagePack"}},
		},
		{
			name:       "UTF-8 BOM with block namespace",
			src:        "\uFEFFusing MessagePack;\nusing Newtonsoft.Json;\n\nnamespace Store\n{\n    public class C {}\n}\n",
			wantNs:     "Store",
			wantUsings: []Using{{Namespace: "MessagePack"}, {Namespace: "Newtonsoft.Json"}},
		},
		{
			name:       "block namespace with usings inside",
			src:        "using System;\n\nnamespace Foo\n{\n    using System.IO;\n    public class C {}\n}\n",
			wantNs:     "Foo",
			wantUsings: []Using{{Namespace: "System"}, {Namespace: "System.IO"}},
		},
		{
			name:   "global using, using static, alias",
			src:    "global using System;\nusing static System.Math;\nusing IO = System.IO;\nnamespace N;\n",
			wantNs: "N",
			wantUsings: []Using{
				{Namespace: "System", Global: true},
				{Namespace: "System.Math", Static: true},
				{Alias: "IO", Namespace: "System.IO"},
			},
		},
		{
			name:   "using declaration is not a using directive",
			src:    "namespace N;\nclass C { void M() { using var x = Get(); } }\n",
			wantNs: "N",
		},
		{
			name:   "namespace in comment and string ignored",
			src:    "// namespace Fake;\nvar s = \"namespace AlsoFake;\";\nnamespace Real;\n",
			wantNs: "Real",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f, err := Parse("test.cs", tc.src)
			if err != nil {
				t.Fatal(err)
			}
			if f.Namespace != tc.wantNs {
				t.Errorf("Namespace = %q, want %q", f.Namespace, tc.wantNs)
			}
			if !reflect.DeepEqual(f.Usings, tc.wantUsings) {
				t.Errorf("Usings = %+v, want %+v", f.Usings, tc.wantUsings)
			}
		})
	}
}

func TestParseFrameworkDetection(t *testing.T) {
	tests := []struct {
		name string
		src  string
		want Framework
	}{
		{"none", "namespace N;\npublic class C {}\n", FrameworkNone},
		{"nunit by using", "using NUnit.Framework;\nnamespace N;\npublic class C {}\n", FrameworkNUnit},
		{"nunit by attribute", "namespace N;\n[TestFixture]\npublic class C {}\n", FrameworkNUnit},
		{"nunit by TestCase attribute", "namespace N;\npublic class C { [TestCase(1)] public void M() {} }\n", FrameworkNUnit},
		{"xunit by using", "using Xunit;\nnamespace N;\npublic class C {}\n", FrameworkXUnit},
		{"xunit by Fact attribute", "namespace N;\npublic class C { [Fact] public void M() {} }\n", FrameworkXUnit},
		{"xunit by Theory attribute", "namespace N;\npublic class C { [Theory] public void M() {} }\n", FrameworkXUnit},
		{"mstest by using", "using Microsoft.VisualStudio.TestTools.UnitTesting;\nnamespace N;\npublic class C {}\n", FrameworkMSTest},
		{"mstest by TestClass attribute", "namespace N;\n[TestClass]\npublic class C {}\n", FrameworkMSTest},
		{"nunit beats xunit", "using NUnit.Framework;\nusing Xunit;\nnamespace N;\n", FrameworkNUnit},
		{"xunit beats mstest", "namespace N;\n[TestClass]\npublic class C { [Fact] public void M() {} }\n", FrameworkXUnit},
		{"TestMethod does not trigger nunit", "namespace N;\npublic class C { [TestMethod] public void M() {} }\n", FrameworkMSTest},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f, err := Parse("test.cs", tc.src)
			if err != nil {
				t.Fatal(err)
			}
			if f.Framework != tc.want {
				t.Errorf("Framework = %q, want %q", f.Framework, tc.want)
			}
		})
	}
}

func TestParseEntryPoints(t *testing.T) {
	tests := []struct {
		name string
		src  string
		want bool
	}{
		{"static void Main", "namespace N;\nclass P { static void Main(string[] args) { } }\n", true},
		{"static async Task Main", "namespace N;\nclass P { static async Task Main() { } }\n", true},
		{"static int Main", "namespace N;\nclass P { static int Main() => 0; }\n", true},
		{"top-level statements", "using System;\nConsole.WriteLine(\"hi\");\n", true},
		{"library file", "namespace N;\npublic class C {}\n", false},
		{"record is not an entry point", "namespace N;\npublic record R(int X);\n", false},
		{"assembly attribute only", "using System.Runtime.CompilerServices;\n[assembly: InternalsVisibleTo(\"x\")]\n", false},
		{"Main in string is not an entry point", "namespace N;\nclass C { string s = \"static void Main(\"; }\n", false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f, err := Parse("test.cs", tc.src)
			if err != nil {
				t.Fatal(err)
			}
			if f.HasEntryPoint != tc.want {
				t.Errorf("HasEntryPoint = %v, want %v", f.HasEntryPoint, tc.want)
			}
		})
	}
}

func TestParseErrorOnUnterminatedString(t *testing.T) {
	if _, err := Parse("bad.cs", `var s = "oops;`); err == nil {
		t.Fatal("Parse() = nil error, want error")
	}
}

func TestParseFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "A.cs")
	if err := os.WriteFile(path, []byte("namespace FromDisk;\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	f, err := ParseFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if f.Name != "A.cs" || f.Namespace != "FromDisk" {
		t.Errorf("ParseFile() = %+v, want Name=A.cs Namespace=FromDisk", f)
	}
}

func TestParseDeclaredTypes(t *testing.T) {
	tests := []struct {
		name string
		src  string
		want []string
	}{
		{
			name: "class interface enum struct record delegate",
			src: `namespace Foo.Bar;
public class MyClass {}
public interface IMyInterface {}
public enum MyEnum { A, B }
public struct MyStruct {}
public record MyRecord(int X);
public record class MyRecordClass(int X);
public record struct MyRecordStruct(int X);
public delegate Task<int> MyDelegate(string s);
`,
			want: []string{
				"IMyInterface",
				"MyClass",
				"MyDelegate",
				"MyEnum",
				"MyRecord",
				"MyRecordClass",
				"MyRecordStruct",
				"MyStruct",
			},
		},
		{
			name: "generic constraints across newlines are not declared types",
			src: `namespace Foo;
public class Box<T, U>
    where T : class
    where U : struct
{
}
`,
			want: []string{"Box"},
		},
		{
			name: "comments and strings are ignored",
			src: `namespace Foo;
// public class FakeComment {}
public class Real { string s = "public enum FakeString {}"; }
`,
			want: []string{"Real"},
		},
		{
			name: "nested types in file-scoped and block-scoped namespaces are excluded",
			src: `namespace Agrifirm.Common
{
    public class CoreConstants
    {
        public static class ClaimTypes { }
        public static class DataReplication { }
        public delegate void NestedHandler();
    }
}
`,
			want: []string{"CoreConstants"},
		},
		{
			name: "anonymous delegate ignored and tuple-returning delegate captured",
			src: `namespace Foo;
public delegate (int X, int Y) MakePoint();
public class Runner
{
    public void Run() { Action a = delegate { Foo(); }; }
}
`,
			want: []string{"MakePoint", "Runner"},
		},
		{
			name: "preprocessor directives and file-local types are ignored",
			src: `namespace Foo;
#region class FakeRegion
file class LocalHelper {}
file sealed record LocalRec(int X);
public class PublicType {}
#endregion
`,
			want: []string{"PublicType"},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			f, err := Parse("Test.cs", tc.src)
			if err != nil {
				t.Fatalf("Parse() error = %v", err)
			}
			if !reflect.DeepEqual(f.DeclaredTypes, tc.want) {
				t.Errorf("DeclaredTypes = %v, want %v", f.DeclaredTypes, tc.want)
			}
		})
	}
}

func TestParseReferencedNames(t *testing.T) {
	src := `using Agrifirm.Common.Other;
namespace Agrifirm.Common.Configuration
{
    public class AuthenticationSettings
    {
        public Dictionary<Tenant.Tenant, string> Map { get; } = new();
        public string Scheme(Tenant.Tenant tenant) =>
            tenant == Tenant.Tenant.Agrifirm
                ? CoreConstants.Authentication.B2cAgrifirm
                : "CoreConstants.Fake";
    }
}
`
	f, err := Parse("AuthenticationSettings.cs", src)
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	has := map[string]bool{}
	for _, r := range f.ReferencedNames {
		has[r] = true
	}
	for _, want := range []string{
		"Tenant.Tenant",
		"Tenant.Tenant.Agrifirm",
		"CoreConstants.Authentication.B2cAgrifirm",
	} {
		if !has[want] {
			t.Errorf("ReferencedNames missing %q; got %v", want, f.ReferencedNames)
		}
	}
	for _, forbid := range []string{
		"Agrifirm.Common.Other",
		"Agrifirm.Common.Configuration",
		"CoreConstants.Fake",
		"public",
		"class",
		"string",
		"namespace",
	} {
		if has[forbid] {
			t.Errorf("ReferencedNames must not contain %q; got %v", forbid, f.ReferencedNames)
		}
	}
}

func TestParseReferencedNamesEdgeCases(t *testing.T) {
	src := `global   using Foo.Global;
#region Tenant
namespace Bar.Baz { public class C : BaseType {} }
#endregion
`
	f, err := Parse("Edge.cs", src)
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	has := map[string]bool{}
	for _, r := range f.ReferencedNames {
		has[r] = true
	}
	if !has["BaseType"] {
		t.Errorf("ReferencedNames missing BaseType from single-line block namespace; got %v", f.ReferencedNames)
	}
	for _, forbid := range []string{"Tenant", "Foo.Global", "Bar.Baz"} {
		if has[forbid] {
			t.Errorf("ReferencedNames must not contain %q; got %v", forbid, f.ReferencedNames)
		}
	}
	if len(f.Usings) != 1 || f.Usings[0].Namespace != "Foo.Global" || !f.Usings[0].Global {
		t.Errorf("Usings = %+v, want single global using Foo.Global", f.Usings)
	}
}

func TestParseInternalTypes(t *testing.T) {
	src := `namespace Agrifirm.Common.Mail;
public class PublicClass
{
    internal class NestedInternal {}
}
internal static class EmbeddedResourceReader {}
internal sealed class Authorizer(int x) {}
internal enum ConnectionState { Connecting }
internal delegate void InternalHandler();
class DefaultInternalClass {}
file class FileLocalClass {}
`
	f, err := Parse("Types.cs", src)
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	want := []string{
		"Authorizer",
		"ConnectionState",
		"DefaultInternalClass",
		"EmbeddedResourceReader",
		"InternalHandler",
	}
	if !reflect.DeepEqual(f.InternalTypes, want) {
		t.Errorf("InternalTypes = %v, want %v", f.InternalTypes, want)
	}
}

func TestParseMultiLineModifiersAndUsingAlias(t *testing.T) {
	src := `using Utils = Agrifirm.Common.Mail.Utilities;
namespace Foo;
public
class PublicOnNextLine {}
public static
class PublicStaticOnNextLine {}
file
class FileOnNextLine {}
internal
class InternalOnNextLine {}
`
	f, err := Parse("Multi.cs", src)
	if err != nil {
		t.Fatalf("Parse() error = %v", err)
	}
	wantDeclared := []string{"InternalOnNextLine", "PublicOnNextLine", "PublicStaticOnNextLine"}
	if !reflect.DeepEqual(f.DeclaredTypes, wantDeclared) {
		t.Errorf("DeclaredTypes = %v, want %v", f.DeclaredTypes, wantDeclared)
	}
	wantInternal := []string{"InternalOnNextLine"}
	if !reflect.DeepEqual(f.InternalTypes, wantInternal) {
		t.Errorf("InternalTypes = %v, want %v", f.InternalTypes, wantInternal)
	}
	if len(f.Usings) != 1 || f.Usings[0].Alias != "Utils" || f.Usings[0].Namespace != "Agrifirm.Common.Mail.Utilities" {
		t.Errorf("Usings = %+v, want [{Alias:Utils Namespace:Agrifirm.Common.Mail.Utilities}]", f.Usings)
	}
}
