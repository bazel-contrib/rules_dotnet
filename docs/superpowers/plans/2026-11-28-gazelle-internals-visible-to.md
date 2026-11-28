# Gazelle Automatic `internals_visible_to` Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically detect cross-target references to `internal` C# types in `RulesDotnet/dotnet/gazelle` and populate `internals_visible_to` on the declaring target with the consumer assembly names.

**Architecture:** Extract top-level `InternalTypes` in `parser.go`, attach compact `consumerInfo` metadata (`usings`, `own`, `refs`) to generated rules (libraries, binaries, and tests) and parsed hand-written libraries, index consumers under a reverse `csharp_ns_consumer` namespace language in `RuleIndex` alongside an in-memory `(pkg, name) → consumerInfo` map on `Resolver`, and during `Resolve()` on providers with `internalTypes`, add matching consumer assembly names (`out` or `name`) to `internals_visible_to` (registered in `ResolveAttrs`).

**Tech Stack:** Go, `bazel-gazelle` (`rule`, `resolve`, `language`, `label`, `config`), `go test`.

**Spec:** `RulesDotnet/docs/superpowers/specs/2026-11-28-gazelle-internals-visible-to-design.md`

## Global Constraints

- Pure Go inside `RulesDotnet/dotnet/gazelle`; no Roslyn or .NET SDK invocations.
- Each rule mutates only its own `internals_visible_to` attribute during `Resolve()`; never mutate another package's `*rule.Rule`.
- Preserve existing `internals_visible_to` entries (sibling tests and manually added entries) and emit sorted, deduplicated output.
- Do not add `internals_visible_to` to `NonEmptyAttrs`.
- Compatible with `c.AliasMap` and existing unit tests (including `TestImportsIndexesBinaryNamespaces`, where a synthetic test rule without `consumerInfoKey` returns `nil`).

## Review Focus

- Default-internal top-level types (no `public` or `internal` keyword, e.g. `class Helper {}`) are `internal` in C# and must be captured in `InternalTypes`, while `public` types, `file`-scoped types, and nested `internal` types must be excluded → pinned in Task 1.
- A consumer that has `using Ns;` (or encloses `Ns`) but does NOT reference the `internal` type name must NOT be added to `internals_visible_to` → pinned in Task 3.
- A consumer with a custom `out` attribute (e.g. `out = "Custom.Assembly"`) must have `"Custom.Assembly"` (not its target `name`) added to `internals_visible_to` → pinned in Task 3.
- A separate test target (`csharp_mstest_test` / `csharp_nunit_test` / `csharp_xunit_test`) in another package referencing an `internal` type must be indexed as a consumer and added to `internals_visible_to` → pinned in Task 2 & Task 3.
- A consumer referencing an `internal` type via a relative qualified name without `using` (e.g. `Tenant.SecretTenant` from `Agrifirm.Common.Configuration`) must be detected via parent-namespace consumer lookup → pinned in Task 3.

---

### Task 1: Extract `InternalTypes` in Parser

**Files:**
- Modify: `RulesDotnet/dotnet/gazelle/private/parser/parser.go:200-375`
- Test: `RulesDotnet/dotnet/gazelle/private/parser/parser_test.go`

**Interfaces:**
- Consumes: `extractTopLevelTypes` brace-depth loop (existing in `parser.go`)
- Produces:
  - `File.InternalTypes []string` — sorted, deduplicated top-level type names declared without `public` (explicit `internal` or no access modifier; `file`-scoped and nested types excluded)

- [ ] **Step 1: Write failing test `TestParseInternalTypes` in `RulesDotnet/dotnet/gazelle/private/parser/parser_test.go`**

```go
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
```

- [ ] **Step 2: Run parser tests to verify RED**

Run (from `RulesDotnet/`): `GOCACHE=/tmp/go-build go test -v ./dotnet/gazelle/private/parser -run TestParseInternalTypes`
Expected: FAIL (`f.InternalTypes undefined`).

- [ ] **Step 3: Implement `InternalTypes` extraction in `RulesDotnet/dotnet/gazelle/private/parser/parser.go`**

- Add `InternalTypes []string` to `File`.
- Add `publicTypeDeclRe = regexp.MustCompile(`\bpublic[ \t]+(?:(?:abstract|sealed|static|partial|readonly|ref|unsafe|new)[ \t]+)*(?:class|struct|interface|enum|record(?:[ \t]+(?:class|struct))?|delegate)\b`)`.
- Inside `extractTopLevelTypes(segment)`: for each `;`-split statement (already excluding `fileScopedRe` and non-top-level brace depths), check `isPublic := publicTypeDeclRe.MatchString(stmt)`; when capturing a type name from `typeDeclNameRe` or `delegateNameRe`, if `!isPublic`, also add it to `internalSet`.
- Deduplicate and sort `f.InternalTypes`.

- [ ] **Step 4: Run parser tests to verify GREEN**

Run (from `RulesDotnet/`): `GOCACHE=/tmp/go-build go test -v ./dotnet/gazelle/private/parser`
Expected: PASS.

---

### Task 2: Wire `ResolveAttrs`, `consumerInfo`, and `internalTypes` in Generation

**Files:**
- Modify: `RulesDotnet/dotnet/gazelle/constants.go:1-20`
- Modify: `RulesDotnet/dotnet/gazelle/lang.go:34-39`
- Modify: `RulesDotnet/dotnet/gazelle/resolve.go:17-35`
- Modify: `RulesDotnet/dotnet/gazelle/generate.go:180-420`
- Test: `RulesDotnet/dotnet/gazelle/generate_test.go`

**Interfaces:**
- Consumes: `parser.File.InternalTypes` (from Task 1)
- Produces:
  - `constants.go`: `const nsConsumerLanguageName = "csharp_ns_consumer"`, `const consumerInfoKey = "csharp_consumer_info"`
  - `lang.go`: `csharpKindInfo.ResolveAttrs["internals_visible_to"] = true`
  - `resolve.go`: `type consumerInfo struct { assemblyName string; usings, own, refs []string }`, `resolveInput.internalTypes []string`
  - `generate.go`:
    - `internalTypesOf(files []*parser.File) []string` (returns sorted, deduplicated `Namespace.TypeName` for files with non-empty `Namespace`)
    - Sets `consumerInfoKey` private attr on generated `csharp_library`, `csharp_binary`, and test rules (`csharp_nunit_test`, `csharp_xunit_test`, `csharp_mstest_test`)
    - Sets `resolveInput.internalTypes` on generated `csharp_library` and `csharp_binary` rules

- [ ] **Step 1: Write failing test `TestGenerateSetsInternalTypesAndConsumerInfo` in `RulesDotnet/dotnet/gazelle/generate_test.go`**

Verify:
1. For a package with `EmbeddedResourceReader.cs` (`internal static class EmbeddedResourceReader`) and a test file (`using NUnit.Framework;`), `GenerateRules` sets `resolveInput.internalTypes = ["Agrifirm.Common.Mail.Utilities.EmbeddedResourceReader"]` on the library, and attaches `consumerInfoKey` (`consumerInfo`) to both the library and the `csharp_nunit_test` rule.
2. For an unnamespaced file (`internal class GlobalOnly {}`), `internalTypes` is empty.

- [ ] **Step 2: Run generation tests to verify RED**

Run (from `RulesDotnet/`): `GOCACHE=/tmp/go-build GOMODCACHE=/tmp/go-mod go test -v ./dotnet/gazelle -run TestGenerateSetsInternalTypesAndConsumerInfo`
Expected: FAIL (undefined symbols).

- [ ] **Step 3: Implement constants, `ResolveAttrs`, `consumerInfo`, and `internalTypesOf`**

- Update `constants.go`, `lang.go`, `resolve.go` (`consumerInfo` + `resolveInput.internalTypes`), and `generate.go` (`internalTypesOf` + setting `consumerInfoKey` on library, test, and binary rules).

- [ ] **Step 4: Run gazelle tests to verify GREEN**

Run (from `RulesDotnet/`): `GOCACHE=/tmp/go-build GOMODCACHE=/tmp/go-mod go test ./dotnet/gazelle/...`
Expected: PASS.

---

### Task 3: Reverse Consumer Index & `internals_visible_to` Resolution

**Files:**
- Modify: `RulesDotnet/dotnet/gazelle/resolve.go:25-275`
- Test: `RulesDotnet/dotnet/gazelle/resolve_test.go`

**Interfaces:**
- Consumes: `nsConsumerLanguageName`, `consumerInfoKey`, `consumerInfo`, `resolveInput.internalTypes`, `internalTypesOf` (from Task 2)
- Produces:
  - `Resolver.Imports`: indexes `csharp_ns_consumer` specs and stores `consumerInfo` (with `assemblyName = ru.AttrString("out")` else `ru.Name()`) in `r.consumers[consumerKey{pkg, name}]` for generated C# rules (libraries, binaries, tests) and hand-written `csharp_library` rules parsed from disk
  - `Resolver.Resolve`: populates `internals_visible_to` on providers with `len(input.internalTypes) > 0` by matching candidate consumers from `RuleIndex` (`csharp_ns_consumer`) and verifying `consumerReferencesInternalType(ci, ns, typeName)`

- [ ] **Step 1: Write failing tests in `RulesDotnet/dotnet/gazelle/resolve_test.go`**

Add tests covering all 6 scenarios:
1. `TestResolveInternalsVisibleToExplicitUsing`: `Mail/Models/Requests:requests` (with `using Agrifirm.Common.Mail.Utilities;` and `refs: ["EmbeddedResourceReader.GetResource"]`) is added to `//common/Agrifirm.Common/Mail/Utilities:utilities`'s `internals_visible_to = ["requests"]`.
2. `TestResolveInternalsVisibleToSeparateTestTarget`: `//common/Agrifirm.Common.UnitTests/Middleware/Authorization:authorization_mstest_test` (`csharp_mstest_test`) referencing `SalesAreaKeyUserFallbackAuthorizer` is added to `//common/Agrifirm.Common/Middleware/Authorization:authorization`'s `internals_visible_to = ["authorization_mstest_test"]`.
3. `TestResolveInternalsVisibleToUsesCustomOutAssemblyName`: consumer with `out = "Custom.Consumer"` adds `"Custom.Consumer"` instead of its target `name`.
4. `TestResolveInternalsVisibleToIgnoresNonReferencingConsumer`: consumer importing `Agrifirm.Common.Mail.Utilities` that only references `OtherPublicHelper` is NOT added to `internals_visible_to`.
5. `TestResolveInternalsVisibleToPreservesExistingEntries`: existing `internals_visible_to = ["utilities_nunit_test"]` is preserved and sorted alongside `"requests"`.
6. `TestResolveInternalsVisibleToRelativeQualifiedRef`: `Agrifirm.Common.Configuration` with `refs: ["Tenant.SecretTenant"]` (no `using`) is added to `Agrifirm.Common.Tenant`'s `internals_visible_to = ["configuration"]`.

- [ ] **Step 2: Run resolve tests to verify RED**

Run (from `RulesDotnet/`): `GOCACHE=/tmp/go-build GOMODCACHE=/tmp/go-mod go test -v ./dotnet/gazelle -run TestResolveInternalsVisibleTo`
Expected: FAIL.

- [ ] **Step 3: Implement reverse consumer indexing and `internals_visible_to` resolution in `RulesDotnet/dotnet/gazelle/resolve.go`**

- Add `consumerKey{pkg, name string}` and `consumers map[consumerKey]consumerInfo` on `Resolver` (initialized in `NewResolver`).
- In `Imports(c, ru, f)`:
  - Resolve aliased `kind` via `c.AliasMap`.
  - Keep existing `csharp` and `csharp_type` indexing for `csharp_library` and `csharp_binary`.
  - For any `isCsharpKind(kind)` rule: extract `ci, hasConsumer := ru.PrivateAttr(consumerInfoKey).(consumerInfo)`. For hand-written `csharp_library` parsed from disk (when `!hasConsumer` and `parsed` is non-empty), build `ci` from `usingNamespaces(parsed)`, `namespacesOf(parsed)`, `referencedNames(parsed)`.
  - If `hasConsumer` (or built from `parsed`) and `f != nil`:
    - Set `ci.assemblyName = ru.AttrString("out")`; if `""`, set `ru.Name()`.
    - Store `r.consumers[consumerKey{pkg: f.Pkg, name: ru.Name()}] = ci`.
    - Emit `{Lang: nsConsumerLanguageName, Imp: ns}` for each deduplicated namespace in `ci.usings` (plus `parentNamespace(u)` when non-empty, covering `using static`) and `enclosingScopes(ci.own)` (excluding `""`).
- In `Resolve(c, ix, rc, ru, imports, from)`:
  - If `len(input.internalTypes) > 0`:
    - Collect existing `ru.AttrStrings("internals_visible_to")` into `ivtSet`.
    - For each `fqType` in `input.internalTypes`, split into `(ns, typeName)` at last `.`.
    - Walk `queryNs := ns; queryNs != ""; queryNs = parentNamespace(queryNs)` and query `ix.FindRulesByImportWithConfig(c, resolve.ImportSpec{Lang: nsConsumerLanguageName, Imp: queryNs}, languageName)`.
    - For each match `m` where `!m.IsSelfImport(from)`: look up `ci, ok := r.consumers[consumerKey{pkg: m.Label.Pkg, name: m.Label.Name}]`; if `ok && consumerReferencesInternalType(ci, ns, typeName)` add `ci.assemblyName` to `ivtSet`.
    - Write back sorted `internals_visible_to` if `len(ivtSet) > 0`.
- Implement `consumerReferencesInternalType(ci consumerInfo, ns, typeName string) bool`:
  - Check if any `ref` in `ci.refs` has a dot-prefix matching:
    - `typeName` when `ns` is in `ci.usings` or `ci.own` or an enclosing parent of `ci.own`; OR
    - `relSuffix + "." + typeName` when `ns == scope + "." + relSuffix` for some `scope` in `enclosingScopes(ci.own)` (with `scope == ""` matching fully qualified `ns + "." + typeName`); OR
    - `typeName` when `u == ns + "." + typeName` is in `ci.usings` (`using static` / alias).

- [ ] **Step 4: Run full gazelle test suite to verify GREEN**

Run (from `RulesDotnet/`): `GOCACHE=/tmp/go-build GOMODCACHE=/tmp/go-mod go test -count=1 ./dotnet/gazelle/...`
Expected: PASS on all 4 packages.
