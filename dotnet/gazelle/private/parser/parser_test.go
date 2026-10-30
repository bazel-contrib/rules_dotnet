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
				{Namespace: "System.IO"},
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
