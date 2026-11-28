# Gazelle Implicit C# Type References & Hand-Written Split Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable `RulesDotnet/dotnet/gazelle` to resolve implicit (non-`using`) C# workspace type references and to respect and index hand-written split `csharp_library` targets without introducing circular dependencies.

**Architecture:** Extend the pure-Go C# regex/lexer parser to extract declared top-level type names and referenced identifier chains from comment/string-blanked source, exclude `.cs` files already claimed by hand-written `csharp_library` rules from the generated default library, index `Namespace.TypeName` under a `csharp_type` import language for both generated and hand-written `csharp_library` targets, and match referenced chains against own, enclosing, and global scopes during `Resolve`.

**Tech Stack:** Go, `bazel-gazelle` (`rule`, `resolve`, `language`, `label`, `config`), Bazel (`bazel test //dotnet/gazelle/...`).

**Spec:** `RulesDotnet/docs/superpowers/specs/2026-11-28-gazelle-implicit-refs-and-manual-targets-design.md`

## Global Constraints

- Pure Go inside `RulesDotnet/dotnet/gazelle`; no Roslyn or .NET SDK invocations during Gazelle runs.
- Explicit `using`-directive resolution remains unchanged (namespace-level across all providers) so C# extension methods keep working.
- Implicit non-`using` resolution targets workspace rules only (never NuGet packages).
- Must never blindly depend on enclosing namespaces whose types are not referenced (anti-goal: circular dependencies with root packages like `Agrifirm.Common`).
- Must remain deterministic (sorted outputs) and compatible with existing synthetic unit tests in `resolve_test.go` that have no `.cs` files on disk.

## Review Focus

- Generic type constraints across newlines (e.g. `where T : class\n    where U : struct`) must not be misparsed as declared type names (`where`) → pinned in Task 1.
- `namespace` and `using` lines must not leak tokens into `ReferencedNames` (e.g. `namespace Agrifirm.Common.Configuration;` must not falsely reference `Agrifirm.Common`) → pinned in Task 1.
- When all `.cs` files in a directory are claimed by hand-written `csharp_library` targets, `GenerateRules` must emit neither a default library nor empty deletion stubs for the hand-written targets → pinned in Task 2.
- A hand-written `csharp_library` whose `srcs` do not exist on disk (e.g. generated files or synthetic tests) must not panic or error during `Imports()` → pinned in Task 3.
- A target referencing a type in an enclosing namespace (`Agrifirm.Common.HealthChecks.Dapr` → `ICustomHealthCheck`) must not pull in an unreferenced grandparent namespace (`Agrifirm.Common`) → pinned in Task 3.

---

### Task 1: Extract `DeclaredTypes` and `ReferencedNames` in Parser

**Files:**
- Modify: `RulesDotnet/dotnet/gazelle/private/parser/parser.go:195-302`
- Test: `RulesDotnet/dotnet/gazelle/private/parser/parser_test.go`

**Interfaces:**
- Consumes: `blankCommentsAndStrings(src string) (string, error)` (existing in `parser.go`)
- Produces:
  - `File.DeclaredTypes []string` — sorted, deduplicated type names declared in the file (`class`, `struct`, `interface`, `enum`, `record`, `record class`, `record struct`, `delegate`)
  - `File.ReferencedNames []string` — sorted, deduplicated identifier and dot-separated chains (`[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*`) from non-`using`/non-`namespace` lines of `blanked`, excluding C# keywords

- [ ] **Step 1: Write failing tests in `RulesDotnet/dotnet/gazelle/private/parser/parser_test.go`**

Add `TestParseDeclaredTypes` and `TestParseReferencedNames`:

```go
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
```

- [ ] **Step 2: Run parser tests to verify they fail**

Run (from `RulesDotnet/`): `bazel test //dotnet/gazelle/private/parser:parser_test`
Expected: FAIL (compile error: `f.DeclaredTypes` and `f.ReferencedNames` undefined).

- [ ] **Step 3: Implement `DeclaredTypes` and `ReferencedNames` extraction in `RulesDotnet/dotnet/gazelle/private/parser/parser.go`**

- Add `DeclaredTypes []string` and `ReferencedNames []string` fields to `File`.
- Match declared types on `blanked` using horizontal whitespace (`[ \t]+`) after type keywords so `where T : class\nwhere U : struct` does not cross lines:
  - `typeDeclNameRe = regexp.MustCompile(`\b(?:class|struct|interface|enum|record(?:[ \t]+(?:class|struct))?)[ \t]+([A-Za-z_][A-Za-z0-9_]*)`)`
  - `delegateNameRe = regexp.MustCompile(`\bdelegate[ \t]+[^(\n;]+[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?:<[^>]+>)?[ \t]*\(`)`
  - Skip any captured name that is a C# keyword.
- Extract `ReferencedNames` from `blanked` lines that are NOT `using` or `namespace` declaration lines, using `refChainRe = regexp.MustCompile(`\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\b`)`; skip single-segment matches that are C# keywords (e.g. `public`, `class`, `string`, `int`, `var`, `return`, `new`, `null`, `true`, `false`, `namespace`, `using`, `void`, `async`, `await`, `get`, `set`, `init`, etc.).
- Deduplicate and `sort.Strings` both slices.

- [ ] **Step 4: Run parser tests to verify they pass**

Run (from `RulesDotnet/`): `bazel test //dotnet/gazelle/private/parser:parser_test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C RulesDotnet add dotnet/gazelle/private/parser/parser.go dotnet/gazelle/private/parser/parser_test.go
git -C RulesDotnet commit -m "feat(gazelle): extract declared types and referenced names in C# parser"
```

---

### Task 2: Exclude Hand-Written `csharp_library` `srcs` & Emit `csharp_types` / `refs` in Generation

**Files:**
- Modify: `RulesDotnet/dotnet/gazelle/constants.go:1-10`
- Modify: `RulesDotnet/dotnet/gazelle/generate.go:150-358`
- Modify: `RulesDotnet/dotnet/gazelle/resolve.go:17-25` (add `refs []string` to `resolveInput`)
- Test: `RulesDotnet/dotnet/gazelle/generate_test.go`

**Interfaces:**
- Consumes: `parser.File.DeclaredTypes`, `parser.File.ReferencedNames` (from Task 1)
- Produces:
  - `constants.go`: `const typeLanguageName = "csharp_type"`, `const typesKey = "csharp_types"`
  - `resolve.go`: `resolveInput.refs []string`
  - `generate.go`:
    - `claimedManualSrcs(file *rule.File, libName string) map[string]bool` — returns `.cs` filenames listed in `srcs` of any existing `csharp_library` in `file` with `Name() != libName`
    - `typesOf(files []*parser.File) []string` — sorted, deduplicated `Namespace.TypeName` (or `TypeName` when `Namespace == ""`)
    - `referencedNames(files []*parser.File) []string` — sorted, deduplicated union of `f.ReferencedNames`
    - Generated `csharp_library` and `csharp_binary` rules set `r.SetPrivateAttr(typesKey, typesOf(...))` and all generated rules populate `resolveInput.refs`

- [ ] **Step 1: Write failing tests in `RulesDotnet/dotnet/gazelle/generate_test.go`**

Add tests verifying:
1. `TestGenerateExcludesManualLibrarySrcs`: when `args.File` already has a hand-written `csharp_library(name = "tenant_enum", srcs = ["Tenant.cs"])` alongside `TenantContext.cs` in `src/tenant`, `GenerateRules` generates `tenant` with `srcs = ["TenantContext.cs"]` only (excluding `Tenant.cs`), sets `typesKey` to `["Acme.Tenant.TenantContext"]`, and includes `"Tenant"` in `res.Imports[0].(resolveInput).refs`.
2. `TestGenerateAllSrcsClaimedByManualLibrary`: when `args.File` has a hand-written `csharp_library(name = "constants", srcs = ["CoreConstants.cs"])` and `CoreConstants.cs` is the only `.cs` file in `src/common`, `GenerateRules` emits `len(res.Gen) == 0` and `len(res.Empty) == 0` (does not create a default library and does not delete the hand-written rule).

- [ ] **Step 2: Run gazelle tests to verify they fail**

Run (from `RulesDotnet/`): `bazel test //dotnet/gazelle:gazelle_test`
Expected: FAIL.

- [ ] **Step 3: Implement constants, `claimedManualSrcs`, `typesOf`, and `referencedNames`**

- In `RulesDotnet/dotnet/gazelle/constants.go`: add `typeLanguageName = "csharp_type"` and `typesKey = "csharp_types"`.
- In `RulesDotnet/dotnet/gazelle/resolve.go`: add `refs []string` to `resolveInput`.
- In `RulesDotnet/dotnet/gazelle/generate.go`:
  - Compute `claimed := claimedManualSrcs(args.File, libName)` before classifying `files`; skip `prodFiles` entries where `claimed[f.Name]` is true (test and entry-point files remain unaffected).
  - Set `lib.SetPrivateAttr(typesKey, typesOf(prodFiles))` on `csharp_library` and `r.SetPrivateAttr(typesKey, typesOf([]*parser.File{f}))` on `csharp_binary`.
  - Populate `refs: referencedNames(...)` in `resolveInput` for library, test, and binary rules.

- [ ] **Step 4: Run gazelle tests to verify they pass**

Run (from `RulesDotnet/`): `bazel test //dotnet/gazelle:gazelle_test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git -C RulesDotnet add dotnet/gazelle/constants.go dotnet/gazelle/generate.go dotnet/gazelle/resolve.go dotnet/gazelle/generate_test.go
git -C RulesDotnet commit -m "feat(gazelle): exclude manual library srcs and propagate C# types and refs"
```

---

### Task 3: Index `csharp_type` (Including Hand-Written Targets) and Resolve Implicit References

**Files:**
- Modify: `RulesDotnet/dotnet/gazelle/resolve.go:39-195`
- Test: `RulesDotnet/dotnet/gazelle/resolve_test.go`

**Interfaces:**
- Consumes: `typeLanguageName`, `typesKey`, `resolveInput.refs` (from Task 2), `parser.ParseFile` (from Task 1)
- Produces:
  - `Resolver.Imports`: indexes both `csharp` (namespace) and `csharp_type` (`Namespace.TypeName`) for generated `csharp_library`/`csharp_binary` rules, and parses `.cs` `srcs` relative to `filepath.Dir(f.Path)` for hand-written `csharp_library` rules without `namespacesKey`
  - `Resolver.Resolve`: resolves `input.refs` against `csharp_type` index across scopes (`input.own`, all enclosing `parentNamespace` ancestors, and `""` global scope), excluding self, while leaving `input.imports` resolution unchanged

- [ ] **Step 1: Write failing tests in `RulesDotnet/dotnet/gazelle/resolve_test.go`**

Add helper `indexLibraryWithTypes(t, l, c, ix, pkg, name, namespaces, types)` and tests covering all 6 scenarios:
1. `TestResolveImplicitParentNamespaceType`: `Agrifirm.Common.HealthChecks.Dapr` with `refs: ["ICustomHealthCheck"]` resolves to `//common/Agrifirm.Common/HealthChecks:healthchecks` and does NOT pull in grandparent `//common/Agrifirm.Common:agrifirm_common` (`Agrifirm.Common`, type `Agrifirm.Common.DependencyInjectionExtensions`).
2. `TestResolveImplicitRelativeAndFullyQualifiedNames`: `Agrifirm.Common.Configuration` with `refs: ["Tenant.Tenant", "Tenant.Tenant.Agrifirm", "CoreConstants.Authentication.B2cAgrifirm"]` resolves to `//common/Agrifirm.Common/Tenant:tenant_enum` and `//common/Agrifirm.Common:constants`; also `Common.Tenant.Tenant.Agrifirm` from `Agrifirm.Common.Tenant` and fully qualified `Agrifirm.Common.Tenant.Tenant` from `Other.App` resolve to `//common/Agrifirm.Common/Tenant:tenant_enum`.
3. `TestResolveImplicitSameNamespaceSplitTarget`: `//common/Agrifirm.Common/Tenant:tenant` (`own: ["Agrifirm.Common.Tenant"]`, `refs: ["Tenant"]`) resolves to `:tenant_enum` (relativized, self excluded).
4. `TestImportsIndexesHandWrittenLibraryFromDisk`: a hand-written `csharp_library(name = "tenant_enum", srcs = ["Tenant.cs"])` (no `namespacesKey` private attr) with `Tenant.cs` on disk returns both `{csharp, "Agrifirm.Common.Tenant"}` and `{csharp_type, "Agrifirm.Common.Tenant.Tenant"}` from `Imports()`.
5. `TestImportsIgnoresMissingHandWrittenSrcs`: a hand-written `csharp_library(name = "gen", srcs = ["DoesNotExist.cs"])` returns `nil` without panicking.
6. `TestResolveExplicitUsingStillReturnsAllSplitProviders`: explicit `imports: ["Agrifirm.Common.Tenant"]` returns both `//common/Agrifirm.Common/Tenant:tenant` and `//common/Agrifirm.Common/Tenant:tenant_enum`.

- [ ] **Step 2: Run gazelle tests to verify they fail**

Run (from `RulesDotnet/`): `bazel test //dotnet/gazelle:gazelle_test`
Expected: FAIL.

- [ ] **Step 3: Implement `Imports` and `Resolve` extensions in `RulesDotnet/dotnet/gazelle/resolve.go`**

- In `Imports(c, ru, f)`:
  - Read `namespaces` from `ru.PrivateAttr(namespacesKey)` and `types` from `ru.PrivateAttr(typesKey)`.
  - If `ru.Kind() == "csharp_library"` and `len(namespaces) == 0` and `len(types) == 0` and `f != nil`: parse each `.cs` entry in `ru.AttrStrings("srcs")` from `filepath.Dir(f.Path)` using `parser.ParseFile` (silently skipping missing/unparseable files), deriving `namespaces` via `namespacesOf(parsed)` and `types` via `typesOf(parsed)`.
  - Emit `resolve.ImportSpec{Lang: languageName, Imp: ns}` for each namespace and `resolve.ImportSpec{Lang: typeLanguageName, Imp: typ}` for each type.
- In `Resolve(c, ix, rc, ru, imports, from)`:
  - Keep existing `input.imports` loop unchanged.
  - Build `scopes` from each `ns` in `input.own` (`ns`, `parentNamespace(ns)`, ... until `""`, plus `""` once).
  - Add helper `findWorkspaceRulesBySpec(c, ix, spec, from)` (shared with `findWorkspaceRules`).
  - For each `ref` in `input.refs`, iterate its dot-prefixes (`a`, `a.b`, `a.b.c`):
    - For each `scope` in `scopes`, form `fq` (`scope + "." + prefix` or `prefix` if `scope == ""`), look up `resolve.ImportSpec{Lang: typeLanguageName, Imp: fq}` via `findWorkspaceRulesBySpec`, and add returned labels to `deps`.

- [ ] **Step 4: Run all gazelle tests to verify they pass**

Run (from `RulesDotnet/`): `bazel test //dotnet/gazelle/...`
Expected: PASS (all parser and gazelle tests green).

- [ ] **Step 5: Commit**

```bash
git -C RulesDotnet add dotnet/gazelle/resolve.go dotnet/gazelle/resolve_test.go
git -C RulesDotnet commit -m "feat(gazelle): index C# types and manual libraries, resolve implicit refs"
```

---

### Task 4: End-to-End Verification in Monorepo

**Files:**
- Verify in: `common/Agrifirm.Common/...` (regenerated by Gazelle)

- [ ] **Step 1: Run Gazelle in monorepo**

Run (from repo root): `bazel run //:gazelle`
Expected:
- `common/Agrifirm.Common/Configuration/BUILD.bazel` gains `"//common/Agrifirm.Common:constants"` and `"//common/Agrifirm.Common/Tenant:tenant_enum"` in `deps`.
- `common/Agrifirm.Common/HealthChecks/Dapr/BUILD.bazel` gains `"//common/Agrifirm.Common/HealthChecks:healthchecks"` in `deps`.
- `common/Agrifirm.Common/Tenant/BUILD.bazel` removes `"Tenant.cs"` from `:tenant` `srcs` and adds `":tenant_enum"` to `:tenant` `deps`.
- `common/Agrifirm.Common/BUILD.bazel` removes `"ApplicationConstants.cs"` and `"CoreConstants.cs"` from `:agrifirm_common` `srcs`.

- [ ] **Step 2: Build `//common/...`**

Run (from repo root): `bazel build //common/...`
Expected: `Build completed successfully`.
