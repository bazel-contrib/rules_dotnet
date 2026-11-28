# Gazelle: Automatic `internals_visible_to` Detection

## Intent & Why

When a C# project (such as `Agrifirm.Common`) is split into per-directory Bazel `csharp_library` targets, each directory compiles into a separate assembly. Types declared `internal` (or top-level types without `public`) that were previously accessible across folders — or from separate unit-test projects like `Agrifirm.Common.UnitTests` — fail to compile with `CS0122` unless the declaring target lists the consumer's assembly name in `internals_visible_to`.

## Goals

- Automatically detect top-level `internal` types (explicit `internal` or default-internal without `public`, excluding `file`-scoped types) in C# sources.
- Automatically add consumer assembly names (`out` if set, otherwise target `name`) to the declaring library's `internals_visible_to` attribute when another workspace target (library, binary, or test) references one of its `internal` types — whether via explicit `using`, implicit enclosing/sibling scope, or same-namespace split target.
- Support both cross-subdirectory consumers (e.g. `Mail/Utilities` → `Mail/Models/Requests` → `Mail`) and separate test projects (e.g. `Agrifirm.Common.UnitTests/...`).
- Preserve existing `internals_visible_to` entries (sibling tests generated in `GenerateRules` and manually maintained entries).

## Non-Goals & Anti-Goals

- **Non-goal:** Detecting `internal` members (methods/properties/constructors) on `public` types.
- **Non-goal:** Invoking Roslyn or the .NET SDK.
- **Anti-goal:** Mutating another package's `*rule.Rule` during `Resolve()` (each rule must only mutate its own `internals_visible_to` attribute).
- **Anti-goal:** Quadratic `|usings| × |refs|` index explosion in `RuleIndex`.

## Constraints

- Pure Go inside `RulesDotnet/dotnet/gazelle`, following Gazelle's `GenerateRules → Imports → Resolve → PostResolve` lifecycle.
- Deterministic sorted output in `internals_visible_to`.
- Compatible with existing unit tests and `c.AliasMap`.

## Approaches Considered

1. **Approach A: Full reverse `using × ref` index in `RuleIndex`**
   - Rejected due to quadratic `|usings| × |refs|` index growth per target and weaker handling of relative qualified names.
2. **Approach B (Chosen): Reverse namespace-consumer index in `RuleIndex` + exact ref check on `Resolver`**
   - Index each consumer under its imported/enclosing namespaces (`csharp_ns_consumer`) and store compact consumer metadata (`assemblyName`, `usings`, `own`, `refs`) on `Resolver` keyed by `(pkg, name)`. During `Resolve()` on a provider with `internal` types, look up candidate consumers via `RuleIndex` and add their assembly name to `internals_visible_to` only when they actually reference the `internal` type name in scope.
3. **Approach C: Mutate provider `*rule.Rule` from consumer's `Resolve()`**
   - Rejected because it violates Gazelle's per-rule isolation, breaks partial-tree runs, and conflicts with `PostResolve` merging.

## Design Details

### 1. Parser (`RulesDotnet/dotnet/gazelle/private/parser/parser.go`)
- Extend `parser.File` with `InternalTypes []string`: sorted, deduplicated top-level type names declared without `public` (i.e. explicit `internal` or no access modifier; `file`-scoped types remain excluded).

### 2. Generation & Rule Metadata (`constants.go`, `lang.go`, `generate.go`)
- Add `nsConsumerLanguageName = "csharp_ns_consumer"` and `consumerInfoKey = "csharp_consumer_info"` in `constants.go`.
- Add `"internals_visible_to": true` to `csharpKindInfo.ResolveAttrs` in `lang.go`.
- Define `consumerInfo` struct (`assemblyName string`, `usings []string`, `own []string`, `refs []string`).
- In `GenerateRules`:
  - Attach `consumerInfoKey` private attr to generated `csharp_library`, `csharp_binary`, and test rules (`csharp_nunit_test`, `csharp_xunit_test`, `csharp_mstest_test`), setting `assemblyName` to `out` if set on the existing/generated rule else `r.Name()`.
  - Pass `internalTypes` (fully-qualified `Namespace.TypeName`s, skipping unnamespaced files) in `resolveInput` for libraries and binaries.

### 3. Indexing & Resolution (`resolve.go`)
- Store `consumers map[consumerKey]consumerInfo` on `Resolver` (keyed by `{pkg, name}`).
- In `Imports(c, ru, f)`:
  - Resolve aliased kind via `c.AliasMap`.
  - For any C# rule (library, binary, or test) with `consumerInfoKey` — or hand-written `csharp_library` parsed from disk — record `consumerInfo` in `r.consumers[consumerKey{f.Pkg, ru.Name()}]` (using `ru.AttrString("out")` if non-empty, else `ru.Name()`) and emit `{Lang: nsConsumerLanguageName, Imp: ns}` for each namespace in `usings` (plus `parentNamespace(u)` for `using static`/type imports) and `enclosingScopes(own)` (excluding `""`).
- In `Resolve(c, ix, rc, ru, imports, from)`:
  - When `len(input.internalTypes) > 0`:
    - Start with existing `ru.AttrStrings("internals_visible_to")`.
    - For each `fqType` (`ns.typeName`) in `input.internalTypes`:
      - Query `ix` under `nsConsumerLanguageName` for `ns` and its `parentNamespace` ancestors.
      - For each non-self matched rule `B`, look up `ci := r.consumers[{B.Pkg, B.Name}]` and check whether `ci` references `ns.typeName` (either `typeName` via `ci.usings` / `ci.own` / enclosing scopes, or a relative/fully-qualified prefix matching `ns.typeName`).
      - If matched, add `ci.assemblyName` to the `internals_visible_to` set.
    - Write back sorted, deduplicated `internals_visible_to` if non-empty.

## Left to the Builder

- Exact helper decomposition for `consumerReferencesInternalType(ci consumerInfo, ns, typeName string) bool`.
- Unit test fixtures across `parser_test.go`, `generate_test.go`, and `resolve_test.go`.
