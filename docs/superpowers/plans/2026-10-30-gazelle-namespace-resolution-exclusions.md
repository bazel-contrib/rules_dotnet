# Gazelle Namespace Resolution and Output Exclusions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-subagent-driven-development (recommended) or superpowers-executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve every applicable workspace provider for C# namespace imports without reintroducing self-dependencies or NuGet fallback for self-only matches, and prevent C# rule generation in complete `bin` and `obj` directory segments.

**Architecture:** Change namespace resolution to return both a collection of dependency labels and an explicit handled/resolved result, preserving override precedence, workspace-over-NuGet precedence, manual dependencies, and sorted output. Add an early case-insensitive path-segment guard to `GenerateRules`, sharing the existing C#-only deletion-stub logic between output directories and directories with no remaining C# sources.

**Tech Stack:** Go 1.24.12, Bazel, Bazel Gazelle 0.51.3, Go unit tests, existing Gazelle generation tests.

**Repository:** `/home/jhobert/Projects/Gazelle/rules_dotnet`

**Baseline:** `b26f2f4`, clean worktree.

**Execution constraint:** Run every command from the repository root above. Do not edit or run mutating commands against `monorepo/monorepo`. The implementation retains one target per directory and does not parse `.csproj` files.

**Traversal limitation:** The `GenerateRules` guard excludes C# generation and cleans old generated C# rules, but it does not prevent Gazelle's generic walker from physically traversing `bin` or `obj`. Gazelle's walk exclusions are private/internal and are not configurable through the public language extension API.

**Golden-fixture decision:** Do not add a `dotnet/gazelle/testdata` fixture. Direct `GenerateRules` tests cover both generation suppression and existing-BUILD cleanup, while the existing golden suite remains part of final verification. No traversal behavior is being changed that would require a new integration fixture.

**Size:** 18 executable checkbox tasks in 5 task groups.

---

## File Map

| File | Change |
|---|---|
| `dotnet/gazelle/resolve_test.go` | Add regressions for multiple providers, deterministic sorting, own-plus-other providers, self-only NuGet suppression, and parent fallback when the parent is an own namespace. |
| `dotnet/gazelle/resolve.go` | Remove namespace-based suppression, collect every non-self workspace match, and distinguish unresolved namespaces from handled self-only matches. |
| `dotnet/gazelle/generate_test.go` | Add root, nested, mixed-case, substring, and existing-BUILD cleanup tests for output directories. |
| `dotnet/gazelle/generate.go` | Add the early `bin`/`obj` path guard and factor C#-only deletion stubs into a helper. |
| `dotnet/gazelle/BUILD.bazel` | Unchanged; no source files or external test dependencies are added. |
| `dotnet/gazelle/testdata/BUILD.bazel` | Unchanged; existing generation tests are run for regression coverage. |

## Task Group 1: Add Resolver Regression Tests

- [x] **Group status: Add resolver regression tests**

**Files:**
- Modify: `dotnet/gazelle/resolve_test.go`
- Test: `dotnet/gazelle/resolve_test.go`

- [x] **Task 1: Confirm the repository baseline**

  Run:

  ```bash
  git rev-parse --short HEAD && git status --short
  ```

  Expected: the first line is `b26f2f4`; there is no additional output, confirming a clean worktree. Stop if another repository or unexpected changes are present.

- [x] **Task 2: Insert four failing resolver tests**

  In `dotnet/gazelle/resolve_test.go`, replace this exact string:

  ```go
  func TestResolveSamePackageWithRepoName(t *testing.T) {
  ```

  with this exact string:

  ```go
  func TestResolveCollectsAllWorkspaceProvidersDeterministically(t *testing.T) {
      l, c, _ := setupLang(t, net10Directive, "src", "src/app", "src/zeta", "src/alpha")

      ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
      // Index in reverse lexical order so the expected result also verifies
      // that final dependency output does not depend on match order.
      indexLibrary(t, l, c, ix, "src/zeta", "zeta", "Shared")
      indexLibrary(t, l, c, ix, "src/alpha", "alpha", "Shared")
      ix.Finish()

      r := rule.NewRule("csharp_library", "app")
      r.SetAttr("deps", []string{"//manual:dep"})
      input := resolveInput{imports: []string{"Shared"}, own: []string{"App"}}
      l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app"))

      got := r.AttrStrings("deps")
      want := []string{"//manual:dep", "//src/alpha:alpha", "//src/zeta:zeta"}
      if !reflect.DeepEqual(got, want) {
          t.Errorf("deps = %v, want %v", got, want)
      }
  }

  func TestResolveKeepsOtherProviderWhenOwnNamespaceMatches(t *testing.T) {
      l, c, _ := setupLang(t, net10Directive, "src", "src/calculator", "src/other")

      ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
      indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
      indexLibrary(t, l, c, ix, "src/other", "other", "Calculator")
      ix.Finish()

      r := rule.NewRule("csharp_library", "calculator")
      input := resolveInput{imports: []string{"Calculator"}, own: []string{"Calculator"}}
      l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator"))

      got := r.AttrStrings("deps")
      want := []string{"//src/other:other"}
      if !reflect.DeepEqual(got, want) {
          t.Errorf("deps = %v, want %v (self excluded by label, other provider retained)", got, want)
      }
  }

  func TestResolveSelfOnlyDoesNotFallBackToNuGet(t *testing.T) {
      l, c, dir := setupLang(t, net10Directive, "src", "src/calculator")
      writeFile(t, dir, "nuget_resolve.json", `{"version":1,"frameworks":{"net10.0":{"packages":[{"id":"Calculator"}]}}}`)
      idx, err := nuget.LoadIndex(filepath.Join(dir, "nuget_resolve.json"))
      if err != nil {
          t.Fatal(err)
      }
      l.nugetIndex = idx

      ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
      indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
      ix.Finish()

      r := rule.NewRule("csharp_library", "calculator")
      // Keep own different from the import so this test exercises target-label
      // self-filtering rather than the removed namespace-based shortcut.
      input := resolveInput{imports: []string{"Calculator"}, own: []string{"App"}}
      l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator"))

      if got := r.AttrStrings("deps"); len(got) != 0 {
          t.Errorf("deps = %v, want empty; self-only workspace match must not fall back to NuGet", got)
      }
  }

  func TestResolveParentNamespaceFallbackWithOwnParentNamespace(t *testing.T) {
      l, c, _ := setupLang(t, net10Directive, "src", "src/app", "src/acme")

      ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
      indexLibrary(t, l, c, ix, "src/acme", "acme", "Acme")
      ix.Finish()

      r := rule.NewRule("csharp_library", "app")
      input := resolveInput{
          imports: []string{"Acme.Widget.SomeType"},
          own:     []string{"Acme"},
      }
      l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app"))

      got := r.AttrStrings("deps")
      want := []string{"//src/acme:acme"}
      if !reflect.DeepEqual(got, want) {
          t.Errorf("deps = %v, want %v (own namespace must not suppress parent fallback)", got, want)
      }
  }

  func TestResolveSamePackageWithRepoName(t *testing.T) {
  ```

  No import changes are needed; the new tests use imports already present in this test file.

- [x] **Task 3: Run the new resolver tests and verify the intended failures**

  Run:

  ```bash
  go test ./dotnet/gazelle -run '^TestResolve(CollectsAllWorkspaceProvidersDeterministically|KeepsOtherProviderWhenOwnNamespaceMatches|SelfOnlyDoesNotFallBackToNuGet|ParentNamespaceFallbackWithOwnParentNamespace)$' -count=1 -v
  ```

  Expected: overall `FAIL`, with these key failure lines:

  ```text
  --- FAIL: TestResolveCollectsAllWorkspaceProvidersDeterministically
  --- FAIL: TestResolveKeepsOtherProviderWhenOwnNamespaceMatches
  --- FAIL: TestResolveSelfOnlyDoesNotFallBackToNuGet
  --- FAIL: TestResolveParentNamespaceFallbackWithOwnParentNamespace
  ```

  Confirm the respective assertions show a missing second workspace provider, a missing `//src/other:other`, an unexpected `@nuget.net10.0//calculator`, and a missing `//src/acme:acme`. These failures demonstrate that the tests exercise the current defects rather than passing through unrelated behavior.

## Task Group 2: Resolve All Non-Self Workspace Providers

- [x] **Group status: Resolve all non-self workspace providers**

**Files:**
- Modify: `dotnet/gazelle/resolve.go:74-163`
- Test: `dotnet/gazelle/resolve_test.go`

- [x] **Task 4: Replace namespace suppression with handled-result resolution**

  In `dotnet/gazelle/resolve.go`, replace this exact block:

  ```go
      deps := map[string]bool{}
      for _, d := range ru.AttrStrings("deps") {
          deps[d] = true
      }

      own := map[string]bool{}
      for _, ns := range input.own {
          own[ns] = true
      }

      for _, imp := range input.imports {
          if own[imp] {
              continue
          }
          dep := r.resolveNamespace(c, ix, cfg, imp, from)
          if dep == "" {
              // `using static Foo.Bar.SomeType;` imports a type, not a
              // namespace: retry with the enclosing namespaces.
              for ns := parentNamespace(imp); ns != "" && !own[ns]; ns = parentNamespace(ns) {
                  if dep = r.resolveNamespace(c, ix, cfg, ns, from); dep != "" {
                      break
                  }
              }
          }
          if dep == "" {
              if imp == "System" || strings.HasPrefix(imp, "System.") {
                  // Provided by the base class library.
                  continue
              }
              msg := fmt.Sprintf("unresolved C# import %q for %s", imp, from)
              if cfg.UnresolvedImports() == "error" {
                  log.Fatalf("%s: set a '# gazelle:%s %s <label>' directive to resolve it", msg, dotnetconfig.DotnetResolve, imp)
              }
              log.Printf("warning: %s", msg)
              continue
          }
          deps[dep] = true
      }
  ```

  with this exact block:

  ```go
      deps := map[string]bool{}
      for _, d := range ru.AttrStrings("deps") {
          deps[d] = true
      }

      for _, imp := range input.imports {
          depLabels, resolved := r.resolveNamespace(c, ix, cfg, imp, from)
          if !resolved {
              // `using static Foo.Bar.SomeType;` imports a type, not a
              // namespace: retry with the enclosing namespaces.
              for ns := parentNamespace(imp); ns != ""; ns = parentNamespace(ns) {
                  depLabels, resolved = r.resolveNamespace(c, ix, cfg, ns, from)
                  if resolved {
                      break
                  }
              }
          }
          if !resolved {
              if imp == "System" || strings.HasPrefix(imp, "System.") {
                  // Provided by the base class library.
                  continue
              }
              msg := fmt.Sprintf("unresolved C# import %q for %s", imp, from)
              if cfg.UnresolvedImports() == "error" {
                  log.Fatalf("%s: set a '# gazelle:%s %s <label>' directive to resolve it", msg, dotnetconfig.DotnetResolve, imp)
              }
              log.Printf("warning: %s", msg)
              continue
          }
          for _, dep := range depLabels {
              deps[dep] = true
          }
      }
  ```

  Leave the existing final map-to-slice conversion, `sort.Strings(sorted)`, `deps` deletion, and `deps` assignment unchanged. This preserves manual dependencies, deduplication, and deterministic output.

- [x] **Task 5: Return every workspace label and an explicit handled result**

  In `dotnet/gazelle/resolve.go`, replace this exact function and its comment:

  ```go
  // resolveNamespace maps one imported namespace to a Bazel label, in order:
  // dotnet_resolve override, workspace rule index, NuGet package. It returns
  // "" when the namespace does not resolve.
  func (r *Resolver) resolveNamespace(c *config.Config, ix *resolve.RuleIndex, cfg *dotnetconfig.Config, ns string, from label.Label) string {
      if override, ok := cfg.ResolveOverride(ns); ok {
          return override
      }

      matches := ix.FindRulesByImportWithConfig(c, resolve.ImportSpec{Lang: languageName, Imp: ns}, languageName)
      for _, m := range matches {
          if m.IsSelfImport(from) {
              continue
          }
          l := m.Label
          if l.Repo == c.RepoName {
              // FindRulesByImportWithConfig stamps labels with the
              // workspace's canonical repo name. Drop it before the
              // same-package check so an in-workspace label relativizes
              // to ":name" and deduplicates against the generate-time
              // sibling dep instead of appearing twice in deps.
              l.Repo = ""
          }
          if l.Repo == "" && l.Pkg == from.Pkg {
              l = label.Label{Name: l.Name, Relative: true}
          }
          return l.String()
      }

      if len(cfg.TargetFrameworks()) > 0 {
          id, err := r.lang.nugetIndex.Resolve(ns)
          if err != nil {
              log.Fatalf("%v: set a '# gazelle:%s' directive to resolve the ambiguity", err, dotnetconfig.DotnetResolve)
          }
          if id != "" {
              return cfg.NugetLabel(id)
          }
      }

      return ""
  }
  ```

  with this exact function and comment:

  ```go
  // resolveNamespace maps one imported namespace to Bazel labels, in order:
  // dotnet_resolve override, workspace rule index, NuGet package. The boolean
  // reports whether the namespace was handled. A workspace match is handled
  // even when every matching rule is a self-import and no labels are returned.
  func (r *Resolver) resolveNamespace(c *config.Config, ix *resolve.RuleIndex, cfg *dotnetconfig.Config, ns string, from label.Label) ([]string, bool) {
      if override, ok := cfg.ResolveOverride(ns); ok {
          return []string{override}, true
      }

      matches := ix.FindRulesByImportWithConfig(c, resolve.ImportSpec{Lang: languageName, Imp: ns}, languageName)
      if len(matches) > 0 {
          deps := make([]string, 0, len(matches))
          for _, m := range matches {
              if m.IsSelfImport(from) {
                  continue
              }
              l := m.Label
              if l.Repo == c.RepoName {
                  // FindRulesByImportWithConfig stamps labels with the
                  // workspace's canonical repo name. Drop it before the
                  // same-package check so an in-workspace label relativizes
                  // to ":name" and deduplicates against the generate-time
                  // sibling dep instead of appearing twice in deps.
                  l.Repo = ""
              }
              if l.Repo == "" && l.Pkg == from.Pkg {
                  l = label.Label{Name: l.Name, Relative: true}
              }
              deps = append(deps, l.String())
          }
          return deps, true
      }

      if len(cfg.TargetFrameworks()) > 0 {
          id, err := r.lang.nugetIndex.Resolve(ns)
          if err != nil {
              log.Fatalf("%v: set a '# gazelle:%s' directive to resolve the ambiguity", err, dotnetconfig.DotnetResolve)
          }
          if id != "" {
              return []string{cfg.NugetLabel(id)}, true
          }
      }

      return nil, false
  }
  ```

  This preserves `dotnet_resolve` as one explicit label, retains workspace-over-NuGet precedence, and makes self-only workspace matches successfully handled with no dependency and no NuGet or parent fallback.

- [x] **Task 6: Format the resolver source and tests**

  Run:

  ```bash
  gofmt -w dotnet/gazelle/resolve.go dotnet/gazelle/resolve_test.go
  ```

  Expected: no output and exit status `0`.

- [x] **Task 7: Run all focused resolver tests**

  Run:

  ```bash
  go test ./dotnet/gazelle -run '^TestResolve' -count=1
  ```

  Expected: exit status `0` and:

  ```text
  ok      github.com/bazel-contrib/rules_dotnet/dotnet/gazelle
  ```

  This includes the new regressions and the existing `TestResolveSkipsSelfImport`, `TestResolveKeepsExistingDepsAndSimplifiesSamePackage`, `TestResolveOverride`, `TestResolveSamePackageWithRepoName`, `TestResolveTestAgainstSiblingBinary`, and `TestResolveNamespaces`. The last test retains coverage of `System` suppression and the ordinary unresolved-import path.

- [x] **Task 8: Commit the resolver correction**

  Run:

  ```bash
  git add dotnet/gazelle/resolve.go dotnet/gazelle/resolve_test.go && git commit -m "fix: resolve all C# namespace providers"
  ```

  Expected: a commit summary containing `fix: resolve all C# namespace providers` and `2 files changed`.

## Task Group 3: Add Output-Directory Generation Tests

- [x] **Group status: Add output-directory generation tests**

**Files:**
- Modify: `dotnet/gazelle/generate_test.go`
- Test: `dotnet/gazelle/generate_test.go`

- [x] **Task 9: Insert output-path exclusion and cleanup tests**

  In `dotnet/gazelle/generate_test.go`, replace this exact string:

  ```go
  func TestGenerateTestInBinaryOnlyDirectory(t *testing.T) {
  ```

  with this exact string:

  ```go
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
              l, c, dir := setupLang(t, net10Directive, tc.rel)
              writeFile(t, filepath.Join(dir, filepath.FromSlash(tc.rel)), "Output.cs", calculatorSrc)

              res := generate(t, l, c, dir, tc.rel, "Output.cs")
              if len(res.Gen) != 0 || len(res.Imports) != 0 || len(res.Empty) != 0 {
                  t.Fatalf(
                      "GenerateRules() = %d gen, %d imports, %d empty; want 0, 0, 0",
                      len(res.Gen),
                      len(res.Imports),
                      len(res.Empty),
                  )
              }
          })
      }
  }

  func TestGenerateDoesNotSkipBinObjSubstrings(t *testing.T) {
      for _, rel := range []string{"src/binary", "src/object"} {
          t.Run(rel, func(t *testing.T) {
              l, c, dir := setupLang(t, net10Directive, rel)
              writeFile(t, filepath.Join(dir, filepath.FromSlash(rel)), "Calculator.cs", calculatorSrc)

              res := generate(t, l, c, dir, rel, "Calculator.cs")
              if len(res.Gen) != 1 || len(res.Imports) != 1 || len(res.Empty) != 0 {
                  t.Fatalf(
                      "GenerateRules() = %d gen, %d imports, %d empty; want 1, 1, 0",
                      len(res.Gen),
                      len(res.Imports),
                      len(res.Empty),
                  )
              }
              if got := res.Gen[0].Kind(); got != "csharp_library" {
                  t.Errorf("generated kind = %q, want csharp_library", got)
              }
          })
      }
  }

  func TestGenerateOutputDirDeletesOnlyExistingCsharpRules(t *testing.T) {
      l, c, dir := setupLang(t, net10Directive, "src/bin")
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
      // A valid source ensures this test fails on the old implementation rather
      // than passing through the existing no-source cleanup path.
      writeFile(t, filepath.Join(dir, "src", "bin"), "Generated.cs", calculatorSrc)

      res := l.GenerateRules(language.GenerateArgs{
          Config:       c,
          Dir:          filepath.Join(dir, "src", "bin"),
          Rel:          "src/bin",
          RegularFiles: []string{"Generated.cs"},
          File:         f,
      })
      if len(res.Gen) != 0 || len(res.Imports) != 0 || len(res.Empty) != 3 {
          t.Fatalf(
              "GenerateRules() = %d gen, %d imports, %d empty; want 0, 0, 3",
              len(res.Gen),
              len(res.Imports),
              len(res.Empty),
          )
      }

      want := []struct {
          kind string
          name string
      }{
          {kind: "csharp_library", name: "stale"},
          {kind: "csharp_binary", name: "old_program"},
          {kind: "csharp_nunit_test", name: "stale_test"},
      }
      for i, expected := range want {
          got := res.Empty[i]
          if got.Kind() != expected.kind || got.Name() != expected.name {
              t.Errorf(
                  "Empty[%d] = %s %s, want %s %s",
                  i,
                  got.Kind(),
                  got.Name(),
                  expected.kind,
                  expected.name,
              )
          }
      }
  }

  func TestGenerateTestInBinaryOnlyDirectory(t *testing.T) {
  ```

  The three C# deletion stubs and the assertion that there are exactly three prove that the existing `filegroup` is not marked for deletion. No new imports are required.

- [x] **Task 10: Run the output-path tests and verify the intended failures**

  Run:

  ```bash
  go test ./dotnet/gazelle -run '^TestGenerate(SkipsDotnetOutputDirectories|DoesNotSkipBinObjSubstrings|OutputDirDeletesOnlyExistingCsharpRules)$' -count=1 -v
  ```

  Expected: overall `FAIL`, with:

  ```text
  --- FAIL: TestGenerateSkipsDotnetOutputDirectories
  --- FAIL: TestGenerateOutputDirDeletesOnlyExistingCsharpRules
  ```

  All six exclusion subtests must fail because the current implementation generates a rule. The cleanup test must fail because the valid `Generated.cs` currently produces `Gen` and `Imports` rather than three `Empty` stubs.

  Also expect:

  ```text
  --- PASS: TestGenerateDoesNotSkipBinObjSubstrings
  ```

  The substring test is a characterization test that must remain passing after the guard is added.

## Task Group 4: Exclude Complete `bin` and `obj` Path Segments

- [x] **Group status: Exclude complete bin and obj path segments**

**Files:**
- Modify: `dotnet/gazelle/generate.go:85-117`
- Test: `dotnet/gazelle/generate_test.go`

- [x] **Task 11: Add the early output-path guard and shared cleanup helper**

  In `dotnet/gazelle/generate.go`, replace this exact block:

  ```go
  // GenerateRules implements language.Language.
  func (l *csharpLang) GenerateRules(args language.GenerateArgs) language.GenerateResult {
      cfg := getConfig(args.Config, args.Rel)
      if cfg == nil {
          return language.GenerateResult{}
      }

      var files []*parser.File
      for _, name := range args.RegularFiles {
          if !strings.HasSuffix(name, ".cs") {
              continue
          }
          f, err := parser.ParseFile(filepath.Join(args.Dir, name))
          if err != nil {
              log.Printf("warning: skipping unparseable file %s: %v", path.Join(args.Rel, name), err)
              continue
          }
          files = append(files, f)
      }
      if len(files) == 0 {
          // No C# sources left: existing csharp rules become empty so gazelle
          // deletes them.
          var empty []*rule.Rule
          if args.File != nil {
              for _, r := range args.File.Rules {
                  if isCsharpKind(r.Kind()) {
                      empty = append(empty, rule.NewRule(r.Kind(), r.Name()))
                  }
              }
          }
          return language.GenerateResult{Empty: empty}
      }
      sort.Slice(files, func(i, j int) bool { return files[i].Name < files[j].Name })
  ```

  with this exact block:

  ```go
  // isDotnetOutputPath reports whether rel contains a complete bin or obj
  // directory segment. Matching is case-insensitive for Windows output paths.
  func isDotnetOutputPath(rel string) bool {
      for _, segment := range strings.Split(filepath.ToSlash(rel), "/") {
          switch strings.ToLower(segment) {
          case "bin", "obj":
              return true
          }
      }
      return false
  }

  // emptyCsharpRules returns deletion stubs for existing C# rules only.
  func emptyCsharpRules(file *rule.File) []*rule.Rule {
      var empty []*rule.Rule
      if file != nil {
          for _, r := range file.Rules {
              if isCsharpKind(r.Kind()) {
                  empty = append(empty, rule.NewRule(r.Kind(), r.Name()))
              }
          }
      }
      return empty
  }

  // GenerateRules implements language.Language.
  func (l *csharpLang) GenerateRules(args language.GenerateArgs) language.GenerateResult {
      if isDotnetOutputPath(args.Rel) {
          return language.GenerateResult{Empty: emptyCsharpRules(args.File)}
      }

      cfg := getConfig(args.Config, args.Rel)
      if cfg == nil {
          return language.GenerateResult{}
      }

      var files []*parser.File
      for _, name := range args.RegularFiles {
          if !strings.HasSuffix(name, ".cs") {
              continue
          }
          f, err := parser.ParseFile(filepath.Join(args.Dir, name))
          if err != nil {
              log.Printf("warning: skipping unparseable file %s: %v", path.Join(args.Rel, name), err)
              continue
          }
          files = append(files, f)
      }
      if len(files) == 0 {
          // No C# sources left: existing csharp rules become empty so gazelle
          // deletes them.
          return language.GenerateResult{Empty: emptyCsharpRules(args.File)}
      }
      sort.Slice(files, func(i, j int) bool { return files[i].Name < files[j].Name })
  ```

  No import changes are needed because `strings`, `filepath`, `language`, and `rule` are already imported. The guard runs before configuration and source parsing, returns no `Gen` or `Imports`, and returns deletion stubs only when an existing BUILD file contains C# rules.

- [x] **Task 12: Format the generation source and tests**

  Run:

  ```bash
  gofmt -w dotnet/gazelle/generate.go dotnet/gazelle/generate_test.go
  ```

  Expected: no output and exit status `0`.

- [x] **Task 13: Run all focused generation tests**

  Run:

  ```bash
  go test ./dotnet/gazelle -run '^TestGenerate' -count=1
  ```

  Expected: exit status `0` and:

  ```text
  ok      github.com/bazel-contrib/rules_dotnet/dotnet/gazelle
  ```

  This must include passing root, nested, and mixed-case exclusion subtests; passing `binary` and `object` substring subtests; passing C#-only output-directory cleanup; and the existing `TestGenerateEmptyDirDeletesRules`, which verifies that factoring the no-source cleanup did not change its behavior.

- [x] **Task 14: Commit the output-directory exclusion**

  Run:

  ```bash
  git add dotnet/gazelle/generate.go dotnet/gazelle/generate_test.go && git commit -m "fix: exclude .NET output directories from Gazelle generation"
  ```

  Expected: a commit summary containing `fix: exclude .NET output directories from Gazelle generation` and `2 files changed`.

## Task Group 5: Run Focused and Full Gazelle Verification

- [x] **Group status: Run focused and full Gazelle verification**

**Files:**
- Verify: `dotnet/gazelle/resolve.go`
- Verify: `dotnet/gazelle/resolve_test.go`
- Verify: `dotnet/gazelle/generate.go`
- Verify: `dotnet/gazelle/generate_test.go`
- Verify: all existing targets under `dotnet/gazelle`, including `testdata`

- [x] **Task 15: Run the focused Bazel Go test**

  Run:

  ```bash
  bazel test --test_output=errors //dotnet/gazelle:gazelle_test
  ```

  Expected: exit status `0`, with these key lines:

  ```text
  //dotnet/gazelle:gazelle_test                                            PASSED
  ```

  There must be no `FAILED` or `ERROR` result. A cached `PASSED` result is acceptable.

- [x] **Task 16: Run the complete Go Gazelle package suite**

  Run:

  ```bash
  go test ./dotnet/gazelle/... -count=1
  ```

  Expected: exit status `0`, an `ok` line for every package with tests under `dotnet/gazelle`, and no `FAIL` line. This includes the main language tests and the private parser and NuGet packages.

- [x] **Task 17: Run the complete Bazel Gazelle suite**

  Run:

  ```bash
  bazel test --test_output=errors //dotnet/gazelle/...
  ```

  Expected: exit status `0`; `//dotnet/gazelle:gazelle_test` is `PASSED`; all applicable private-package tests are `PASSED`; and every discovered `//dotnet/gazelle/testdata:*` generation test is `PASSED`. There must be no `FAILED` or `ERROR` result.

  This is the primary full acceptance run. Do not substitute a Gazelle run against `monorepo/monorepo`, and do not update any monorepo source file.

- [x] **Task 18: Check the final patch and worktree**

  Run:

  ```bash
  git diff --check b26f2f4..HEAD && git status --short
  ```

  Expected: no output and exit status `0`. This confirms no whitespace errors in the two commits and no uncommitted files. The committed patch must contain only:

  ```text
  dotnet/gazelle/generate.go
  dotnet/gazelle/generate_test.go
  dotnet/gazelle/resolve.go
  dotnet/gazelle/resolve_test.go
  ```

---

## Self-Review and Audit Summary

- **Spec coverage:** All resolver defects are covered by four targeted tests and the explicit `([]string, bool)` resolution result. All output-directory requirements are covered by root, nested, mixed-case, substring, and existing-BUILD cleanup tests.
- **Self-only regression:** The self-only test deliberately uses `own: []string{"App"}` so it fails before the fix and proves that target-label filtering, rather than the old `own[imp]` shortcut, prevents NuGet fallback.
- **Cleanup-test strength:** The output-directory cleanup test writes a valid `Generated.cs`, ensuring it cannot pass accidentally through the existing no-source cleanup path.
- **Preserved behavior:** `dotnet_resolve` still returns exactly one explicit label; workspace matches still precede NuGet; manual dependencies and same-package simplification remain unchanged; final dependency sorting remains in `Resolve`; and the `System`/unresolved warning block is unchanged and exercised by existing tests.
- **Parent fallback:** The new loop removes both own-namespace suppression points and stops on `resolved`, including a handled self-only result with zero labels. The own-parent regression proves fallback can still reach another provider.
- **Path correctness:** The guard splits `filepath.ToSlash(args.Rel)` into complete segments and compares case-insensitively, so `bin`, `obj`, `BiN`, and `OBJ` match while `binary` and `object` do not.
- **Scope control:** No `.csproj` parsing, target-per-project restructuring, BUILD file edits, new test dependencies, golden fixtures, or monorepo mutations were introduced.
- **Execution audit:** Every source edit has an exact old string and replacement, every test has complete code, every command has expected success or expected RED output, and both components have separate commits followed by focused and full Go/Bazel verification.
- **Placeholder and consistency scan:** No unfinished steps or unresolved names remain. Helper names, test names, return signatures, file paths, commit file lists, and validation patterns are consistent throughout.
