# Gazelle: Implicit Test-Framework Namespaces for C# Test Rules

**Date:** 2026-11-28
**Size:** Small change

## Intent & Why

The `csharp_nunit_test`, `csharp_xunit_test`, and `csharp_mstest_test` macros in `rules_dotnet` automatically inject their test framework NuGet dependencies from `@paket.rules_dotnet_nuget_packages` (see `dotnet/private/rules/csharp/{nunit,xunit,mstest}_test.bzl`).

Currently, `dotnet/gazelle`'s `Resolver` does not know that these macros supply those namespaces. As a result:
- `csharp_mstest_test` always emits `unresolved C# import "Microsoft.VisualStudio.TestTools.UnitTesting"` (even when `MSTest.TestFramework` is in `nuget_resolve.json`, because the package ID does not match the namespace).
- `csharp_nunit_test` and `csharp_xunit_test` emit unresolved warnings when `NUnit`/`Xunit` are absent from `nuget_resolve.json`, or—worse—add a duplicate `@nuget.<tfm>//nunit` / `@nuget.<tfm>//xunit` dependency alongside the macro-injected `@paket.rules_dotnet_nuget_packages//...` dependency when they *are* present.

## Goals, Non-Goals & Anti-Goals

- **Goals:**
  - Treat test-framework namespaces as implicitly provided for their corresponding test rule kinds (`csharp_nunit_test`, `csharp_xunit_test`, `csharp_mstest_test`), without adding duplicate deps or emitting unresolved-import warnings.
  - Preserve `# gazelle:dotnet_resolve` overrides so users can still explicitly map any namespace (including via `using static`).
  - Prevent `nuget_resolve.json` from adding duplicate test-framework deps to test rules.
- **Non-Goals:**
  - Changing how `csharp_library` or `csharp_binary` targets resolve test-framework namespaces (shared test-helper libraries do not receive the macro's injected deps and must still resolve them explicitly).
  - Changing the test macros themselves (`nunit_test.bzl`, `xunit_test.bzl`, `mstest_test.bzl`).
  - Solving general NuGet package-ID vs. namespace mismatches (out of scope).
- **Anti-Goals:**
  - Suppressing unrelated namespaces (e.g., NUnit namespaces inside a `csharp_mstest_test`).
  - Letting implicit test-framework suppression override an explicit `# gazelle:dotnet_resolve` directive, including for `using static` imports.

## Constraints

- Must work for exact namespace imports (`using NUnit.Framework;`), sub-namespaces (`using NUnit.Framework.Legacy;`), and `using static` (`using static Microsoft.VisualStudio.TestTools.UnitTesting.Assert;`).
- Must stay consistent with existing `dotnet/gazelle` tests and update the golden `testdata/*_tests/expectedStderr.txt` files where these warnings were previously expected.

## Approaches Considered

### Approach 1: Layered resolution order in `Resolver.Resolve` (Selected)
Split namespace lookup in `Resolver.Resolve` into explicit precedence layers per import:
1. `# gazelle:dotnet_resolve` override (walking `imp` and enclosing `parentNamespace`s)
2. Workspace `RuleIndex` (walking `imp` and enclosing `parentNamespace`s) and `own[imp]`
3. Implicit test-framework namespace check (`isTestFrameworkProvidedNamespace(imp, ru.Kind())`) → handled with no added dep
4. `nuget_resolve.json` lookup (prefix match)
5. `isSdkProvidedNamespace(imp, ru.AttrString("project_sdk"))`

- **Trade-offs:** Slightly larger refactor of `Resolve` (~20 lines), but precedence is completely unambiguous—in particular, `using static NUnit.Framework.Assert;` with `# gazelle:dotnet_resolve NUnit.Framework @custom//nunit` is guaranteed to honor the override before the test-framework check runs.

### Approach 2: Check inside `resolveNamespace` before NuGet
Pass `ru.Kind()` into `resolveNamespace` and check `isTestFrameworkProvidedNamespace(ns, ruleKind)` immediately before `nugetIndex.Resolve(ns)`.

- **Trade-offs:** Minimal diff, but breaks `using static` + `# gazelle:dotnet_resolve`: on the first iteration (`NUnit.Framework.Assert`), the prefix-based test-framework check would intercept before the outer `parentNamespace` loop checks `# gazelle:dotnet_resolve` for `NUnit.Framework`.

**Decision:** Approach 1, for unambiguous precedence with no `using static` edge cases.

## Decided Behavior

### Implicit namespaces per rule kind (exact or dot-prefix match)
- `csharp_nunit_test`: `NUnit.Framework`, `NUnitLite`
- `csharp_xunit_test`: `Xunit`
- `csharp_mstest_test`: `Microsoft.VisualStudio.TestTools.UnitTesting`, `Microsoft.Testing.Platform`
- All other rule kinds (`csharp_library`, `csharp_binary`, etc.): none.

### Resolution precedence
1. `# gazelle:dotnet_resolve` override (exact or enclosing namespace)
2. Workspace `RuleIndex` (exact or enclosing namespace) / `own` namespace
3. Implicit test-framework namespace for `ru.Kind()` (wins over `nuget_resolve.json`)
4. `nuget_resolve.json`
5. `.NET SDK` / Web SDK targeting pack (`isSdkProvidedNamespace`)
6. Unresolved warning / error (`dotnet_unresolved_imports`)

## Left to the Builder

- Exact helper function factoring in `dotnet/gazelle/resolve.go` (e.g., `resolveOverride`, `resolveWorkspace`, `isTestFrameworkProvidedNamespace`).
- Unit test organization in `dotnet/gazelle/resolve_test.go` and updates to `dotnet/gazelle/testdata/{mstest,nunit,xunit}_tests/expectedStderr.txt` (and any other affected testdata/e2e expectations).
