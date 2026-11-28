# Gazelle: Implicit C# Type References & Hand-Written Split Targets

## Intent & Why

In C#, code inside a nested namespace (such as `Agrifirm.Common.HealthChecks.Dapr` or `Agrifirm.Common.Configuration`) can reference types in enclosing namespaces (`ICustomHealthCheck`, `CoreConstants`) and types in sibling/child namespaces via relative qualified names (`Tenant.Tenant`, `Common.Tenant.Tenant`) without explicit `using` directives.

Separately, packages that break circular dependencies with hand-written split `csharp_library` targets (such as `:tenant_enum` alongside `:tenant`, or `:constants` alongside `:agrifirm_common`) currently suffer from two Gazelle gaps:
1. `GenerateRules` puts all production `.cs` files into the default generated library, duplicating `srcs` that already belong to hand-written targets.
2. `Imports` only indexes Gazelle-generated rules, ignoring hand-written `csharp_library` targets.

## Goals

- Automatically add Bazel `deps` for implicit (non-`using`) workspace type references across:
  - the target's own namespace (covers same-namespace split targets like `:tenant` → `:tenant_enum`),
  - enclosing (parent) namespaces (e.g. `ICustomHealthCheck`, `CoreConstants`),
  - relative qualified names under own or enclosing namespaces (e.g. `Tenant.Tenant`, `Common.Tenant.Tenant`),
  - fully qualified names without `using` (e.g. `Agrifirm.Common.Tenant.Tenant`).
- Exclude `.cs` files already claimed by hand-written `csharp_library` targets in the same `BUILD.bazel` from the generated default `csharp_library`'s `srcs`.
- Index hand-written `csharp_library` targets so both namespace and type-level resolution can resolve to them.

## Non-Goals & Anti-Goals

- **Non-goal:** Resolving implicit non-`using` references against NuGet packages (workspace targets only).
- **Non-goal:** Changing explicit `using`-directive resolution (it remains namespace-based across all providers so C# extension methods keep working).
- **Non-goal:** Invoking Roslyn or the .NET SDK during Gazelle runs.
- **Anti-goal:** Blindly depending on parent namespaces regardless of whether any type is referenced (which would create circular dependencies with root packages like `//common/Agrifirm.Common:agrifirm_common`).

## Constraints

- Pure Go implementation inside `RulesDotnet/dotnet/gazelle`, building on the existing lightweight lexer/regex parser (`blankCommentsAndStrings`).
- Must remain deterministic and compatible with existing Gazelle unit tests (including synthetic `resolve_test.go` cases with no files on disk).

## Approaches Considered

1. **Approach A (Chosen): Type-level index + implicit scope resolution + manual target awareness**
   - Extract declared types and referenced identifier chains in `parser.go`, index `Namespace.TypeName` in `resolve.go` (for both generated and hand-written `csharp_library` targets), exclude hand-written `srcs` from the default library in `generate.go`, and resolve implicit references against own/enclosing/global scopes.
   - Trade-off: explicit `using` directives on split namespaces still pull in all providers of that namespace, keeping extension methods 100% safe.
2. **Approach B: Approach A + type-filtering on multi-provider `using` namespaces**
   - Would narrow explicit `using` directives on split namespaces by referenced types, falling back to all providers when no type matches.
   - Rejected because a file using both a type from `:constants` and an extension method from `:agrifirm_common` under `using Agrifirm.Common;` would falsely drop `:agrifirm_common`.
3. **Approach C: Roslyn-based external analyzer**
   - Rejected because it breaks the pure-Go design and adds SDK/runtime overhead to `gazelle`.

## Design Details

### 1. Parser (`RulesDotnet/dotnet/gazelle/private/parser/parser.go`)
- Extend `parser.File` with:
  - `DeclaredTypes []string`: deduplicated, sorted type names declared via `class`, `struct`, `interface`, `enum`, `record` (`record class`/`record struct`), and `delegate` (using horizontal whitespace after keywords to avoid matching `where T : class` constraints across lines).
  - `ReferencedNames []string`: deduplicated, sorted identifier and dot-separated chains (`[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*`) extracted from the comment/string-blanked source, skipping `using`/`namespace` lines and C# keywords.

### 2. Generation (`RulesDotnet/dotnet/gazelle/generate.go`)
- Inspect existing `csharp_library` rules in `args.File` whose name differs from `libName`; collect their `srcs` into a `claimedSrcs` set and exclude those files from the generated default library's `prodFiles`.
- Attach `typesKey` (`csharp_types`) private attribute (fully qualified `Namespace.TypeName` strings, or `TypeName` when namespace is empty) to generated `csharp_library` and `csharp_binary` rules.
- Pass `refs` (`ReferencedNames` union across the rule's sources) in `resolveInput`.

### 3. Indexing & Resolution (`RulesDotnet/dotnet/gazelle/constants.go`, `resolve.go`)
- Add `typeLanguageName = "csharp_type"` and `typesKey = "csharp_types"`.
- In `Imports()`:
  - For generated `csharp_library` and `csharp_binary` rules (with private attrs): emit `csharp` namespace specs and `csharp_type` specs.
  - For hand-written `csharp_library` rules (no `namespacesKey` private attr, non-empty `srcs`): parse `.cs` `srcs` relative to `filepath.Dir(f.Path)` (skipping missing/unparseable files) and emit both `csharp` and `csharp_type` specs.
- In `Resolve()`:
  - Keep existing `input.imports` resolution unchanged.
  - For implicit resolution: build scopes from each namespace in `input.own` and all its enclosing `parentNamespace` values, plus `""` (global scope). For each referenced chain in `input.refs`, test its dot-prefixes against `scope + "." + prefix` (or `prefix` for `""`) in the `csharp_type` index, adding matching workspace labels (excluding self) to `deps`.

## Left to the Builder

- Exact C# keyword exclusion list in `parser.go`.
- Test coverage structure across `parser_test.go`, `generate_test.go`, and `resolve_test.go`.
