# Gazelle Implicit Test-Framework Namespaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teach `dotnet/gazelle`'s C# resolver to treat test-framework namespaces as implicitly provided for `csharp_nunit_test`, `csharp_xunit_test`, and `csharp_mstest_test` targets, with layered resolution precedence so explicit `# gazelle:dotnet_resolve` overrides still win while duplicate NuGet deps are avoided.

**Architecture:** Refactor `Resolver.Resolve` in `RulesDotnet/dotnet/gazelle/resolve.go` into explicit precedence layers per import: (1) `# gazelle:dotnet_resolve` override (walking `imp` → enclosing namespaces), (2) workspace `RuleIndex` (walking `imp` → enclosing namespaces) and `own[imp]`, (3) `isTestFrameworkProvidedNamespace(imp, ru.Kind())`, (4) `nuget_resolve.json`, (5) `isSdkProvidedNamespace`, (6) unresolved warning/error. Update the golden `expectedStderr.txt` fixtures in `dotnet/gazelle/testdata` where matching test-framework warnings are now eliminated.

**Tech Stack:** Go, Bazel (`bazel-gazelle`), `rules_dotnet`.

**Spec:** `RulesDotnet/docs/superpowers/specs/2026-11-28-gazelle-test-framework-namespaces-design.md`

## Global Constraints

- Only the three test rule kinds suppress test-framework namespaces:
  - `csharp_nunit_test`: `NUnit.Framework`, `NUnitLite`
  - `csharp_xunit_test`: `Xunit`
  - `csharp_mstest_test`: `Microsoft.VisualStudio.TestTools.UnitTesting`, `Microsoft.Testing.Platform`
- Non-test rule kinds (`csharp_library`, `csharp_binary`, etc.) must not suppress test-framework namespaces.
- Exact match or dot-delimited prefix match (`ns == base || strings.HasPrefix(ns, base+".")`) — covers exact usings, sub-namespaces, and `using static`.
- Resolution precedence: (1) `# gazelle:dotnet_resolve` override, (2) workspace `RuleIndex` / `own`, (3) implicit test-framework namespace, (4) `nuget_resolve.json`, (5) `isSdkProvidedNamespace`, (6) unresolved warning/error.
- Do not modify `nunit_test.bzl`, `xunit_test.bzl`, or `mstest_test.bzl`.
- If Bazel cache permissions fail in the sandbox, pass `--output_user_root=/tmp/bazel-cache` to `bazel`.

## Review Focus

- `using static` of a test-framework type with `# gazelle:dotnet_resolve` on the parent namespace (e.g. `using static NUnit.Framework.Assert;` + `# gazelle:dotnet_resolve NUnit.Framework @custom//nunit`): explicit override must win over implicit test-framework suppression.
- Dot-boundary prefix mismatch (e.g. `XunitExtensions` in `csharp_xunit_test` or `NUnit.FrameworkExtra` in `csharp_nunit_test`): must NOT be suppressed.
- Cross-framework import (e.g. `Xunit` in `csharp_nunit_test` or `NUnit.Framework` in `csharp_mstest_test`): must NOT be suppressed.
- NuGet duplicate prevention: when `NUnit` / `Xunit` is in `nuget_resolve.json`, a matching test rule must NOT add `@nuget.net10.0//nunit` / `@nuget.net10.0//xunit` to `deps`, while a `csharp_library` importing `NUnit.Framework` MUST still add `@nuget.net10.0//nunit`.
- Sub-namespaces and `using static` without overrides (e.g. `NUnit.Framework.Legacy`, `Microsoft.VisualStudio.TestTools.UnitTesting.Assert`, `Microsoft.Testing.Platform.Builder`, `NUnitLite.AutoRun`): must be suppressed with no warnings and no added deps on their matching test rule kind.

---

### Task 1: Layered Resolution & Implicit Test-Framework Namespaces

**Files:**
- Modify: `RulesDotnet/dotnet/gazelle/resolve.go:64-205`
- Test: `RulesDotnet/dotnet/gazelle/resolve_test.go`

**Interfaces:**
- Consumes: `dotnetconfig.Config.ResolveOverride`, `resolve.RuleIndex.FindRulesByImportWithConfig`, `nuget.Index.Resolve`, `isSdkProvidedNamespace`, `parentNamespace` (all existing in `RulesDotnet/dotnet/gazelle/resolve.go`).
- Produces:
  - `func isTestFrameworkProvidedNamespace(ns, ruleKind string) bool` in `RulesDotnet/dotnet/gazelle/resolve.go`
  - `func (r *Resolver) resolveOverride(cfg *dotnetconfig.Config, imp string) (string, bool)` in `RulesDotnet/dotnet/gazelle/resolve.go`
  - `func (r *Resolver) resolveWorkspace(c *config.Config, ix *resolve.RuleIndex, imp string, own map[string]bool, from label.Label) ([]string, bool)` in `RulesDotnet/dotnet/gazelle/resolve.go`

- [ ] **Step 1: Write failing unit tests in `RulesDotnet/dotnet/gazelle/resolve_test.go`**

Add `TestResolveTestFrameworkNamespaces` covering:
1. Table-driven subtests for `csharp_nunit_test` (`NUnit.Framework`, `NUnit.Framework.Legacy`, `NUnit.Framework.Assert`, `NUnitLite`, `NUnitLite.AutoRun`), `csharp_xunit_test` (`Xunit`, `Xunit.Sdk`, `Xunit.Assert`), and `csharp_mstest_test` (`Microsoft.VisualStudio.TestTools.UnitTesting`, `Microsoft.VisualStudio.TestTools.UnitTesting.Assert`, `Microsoft.Testing.Platform`, `Microsoft.Testing.Platform.Builder`): asserts no log warning and empty `deps` even when `nuget_resolve.json` contains `NUnit` and `Xunit`.
2. Non-test rules (`csharp_library`, `csharp_binary`) importing `NUnit.Framework` (with `NUnit` in `nuget_resolve.json`) still resolve to `@nuget.net10.0//nunit`, and importing `Microsoft.VisualStudio.TestTools.UnitTesting` still emits an unresolved warning.
3. Explicit `# gazelle:dotnet_resolve NUnit.Framework @custom//nunit` wins on `csharp_nunit_test` for both exact `NUnit.Framework` and `using static` `NUnit.Framework.Assert`, producing `deps = ["@custom//nunit"]`.
4. Dot-boundary check: `XunitExtensions` in `csharp_xunit_test` and `NUnit.FrameworkExtra` in `csharp_nunit_test` are NOT suppressed (emit unresolved warnings).
5. Cross-framework mismatch: `Xunit` in `csharp_nunit_test` and `NUnit.Framework` in `csharp_mstest_test` are NOT suppressed (emit unresolved warnings when not in NuGet, or resolve normally).

- [ ] **Step 2: Run unit tests to verify the new tests fail**

Run: `bazel --output_user_root=/tmp/bazel-cache test @rules_dotnet//dotnet/gazelle:gazelle_test --test_output=errors`
Expected: FAIL on `TestResolveTestFrameworkNamespaces` (warnings emitted and/or duplicate `@nuget.net10.0//nunit` / `@nuget.net10.0//xunit` deps added).

- [ ] **Step 3: Implement layered resolution and `isTestFrameworkProvidedNamespace` in `RulesDotnet/dotnet/gazelle/resolve.go`**

Implement:
- `func hasNamespacePrefix(ns, base string) bool`: returns `ns == base || strings.HasPrefix(ns, base+".")`.
- `func isTestFrameworkProvidedNamespace(ns, ruleKind string) bool`:
  - `"csharp_nunit_test"`: `hasNamespacePrefix(ns, "NUnit.Framework") || hasNamespacePrefix(ns, "NUnitLite")`
  - `"csharp_xunit_test"`: `hasNamespacePrefix(ns, "Xunit")`
  - `"csharp_mstest_test"`: `hasNamespacePrefix(ns, "Microsoft.VisualStudio.TestTools.UnitTesting") || hasNamespacePrefix(ns, "Microsoft.Testing.Platform")`
  - default: `false`
- `func (r *Resolver) resolveOverride(cfg *dotnetconfig.Config, imp string) (string, bool)`: walks `ns := imp; ns != ""; ns = parentNamespace(ns)` and returns `cfg.ResolveOverride(ns)` on first hit.
- `func (r *Resolver) resolveWorkspace(c *config.Config, ix *resolve.RuleIndex, imp string, own map[string]bool, from label.Label) ([]string, bool)`:
  - Checks `ix.FindRulesByImportWithConfig` on `imp` first (preserving existing self-import filtering & repo/same-package relativization, returning `depLabels, true` on any match—even when all matches are self-imports so self-only does not fall back to NuGet).
  - If no workspace match on `imp` and `own[imp]` is true, returns `nil, true`.
  - Otherwise walks `ns := parentNamespace(imp); ns != ""; ns = parentNamespace(ns)` checking `ix.FindRulesByImportWithConfig` on `ns` and returning on first hit.
- Update `Resolver.Resolve` loop to check in exact order:
  1. `resolveOverride(cfg, imp)` → add label
  2. `resolveWorkspace(c, ix, imp, own, from)` → add labels
  3. `isTestFrameworkProvidedNamespace(imp, ru.Kind())` → `continue`
  4. NuGet (`len(cfg.TargetFrameworks()) > 0` → `r.lang.nugetIndex.Resolve(imp)` → add `cfg.NugetLabel(id)`)
  5. `isSdkProvidedNamespace(imp, ru.AttrString("project_sdk"))` → `continue`
  6. Unresolved warning / fatal error (`cfg.UnresolvedImports() == "error"`).
- Remove the now-unused `resolveNamespace` helper.

- [ ] **Step 4: Run unit tests to verify all pass**

Run: `bazel --output_user_root=/tmp/bazel-cache test @rules_dotnet//dotnet/gazelle:gazelle_test --test_output=errors`
Expected: PASS (all existing tests + `TestResolveTestFrameworkNamespaces` pass).

---

### Task 2: Update Gazelle Golden Testdata Expectations & Full Verification

**Files:**
- Modify: `RulesDotnet/dotnet/gazelle/testdata/mstest_tests/expectedStderr.txt`
- Modify: `RulesDotnet/dotnet/gazelle/testdata/nunit_tests/expectedStderr.txt`
- Modify: `RulesDotnet/dotnet/gazelle/testdata/xunit_tests/expectedStderr.txt`
- Modify: `RulesDotnet/dotnet/gazelle/testdata/test_with_binary/expectedStderr.txt`

**Interfaces:**
- Consumes: Task 1's `Resolver.Resolve` behavior in `RulesDotnet/dotnet/gazelle/resolve.go`.
- Produces: Updated golden `expectedStderr.txt` fixtures matching the new warning-free output for matching test rule kinds.

- [ ] **Step 1: Run the testdata integration suite to observe the exact expected-stderr diffs**

Run: `bazel --output_user_root=/tmp/bazel-cache test @rules_dotnet//dotnet/gazelle/testdata/... --test_output=errors`
Expected: FAIL only on `mstest_tests`, `nunit_tests`, `xunit_tests`, and `test_with_binary` because the `unresolved C# import` line is no longer emitted; `test_framework_forced` MUST still PASS (since `Xunit` in `csharp_nunit_test` still warns).

- [ ] **Step 2: Remove the obsolete `unresolved C# import` warning line from the 4 `expectedStderr.txt` files**

Update each of:
- `RulesDotnet/dotnet/gazelle/testdata/mstest_tests/expectedStderr.txt`
- `RulesDotnet/dotnet/gazelle/testdata/nunit_tests/expectedStderr.txt`
- `RulesDotnet/dotnet/gazelle/testdata/xunit_tests/expectedStderr.txt`
- `RulesDotnet/dotnet/gazelle/testdata/test_with_binary/expectedStderr.txt`

Keep line 1 (`gazelle: no nuget_resolve.json at %WORKSPACEPATH%/nuget_resolve.json; NuGet resolution is disabled`) and remove line 2 (the obsolete `unresolved C# import` warning). Do NOT modify `testdata/test_framework_forced/expectedStderr.txt`.

- [ ] **Step 3: Run the full `dotnet/gazelle` test suite**

Run: `bazel --output_user_root=/tmp/bazel-cache test @rules_dotnet//dotnet/gazelle/... --test_output=errors`
Expected: PASS (all unit tests and all `gazelle_generation_test` targets green).
