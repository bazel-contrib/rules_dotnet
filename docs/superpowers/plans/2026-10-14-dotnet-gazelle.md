# C# Gazelle Extension for rules_dotnet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-subagent-driven-development (recommended) or superpowers-executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Gazelle `language.Language` extension for C# in rules_dotnet that generates and maintains BUILD files for `.cs` sources, plus the `csharp_xunit_test` and `csharp_mstest_test` rules it needs, with an example and an e2e module proving the end-to-end workflow.

**Architecture:** Two parts. (1) Fase 0: `csharp_xunit_test` and `csharp_mstest_test` macros in `dotnet/private/rules/csharp/` following the existing `csharp_nunit_test` pattern (macro around `csharp_test` + framework NuGet deps + an entry-point shim). (2) A new Go module at the repo root with the extension in `dotnet/gazelle/`, mirroring `java/gazelle` in rules_jvm: a regex-based C# parser (`private/parser`), a `packages.lock.json` index (`private/nuget`), per-directory config (`dotnetconfig`), and the Gazelle `language.Language` implementation (`lang.go`, `configure.go`, `generate.go`, `resolve.go`). NuGet resolution maps namespaces to package IDs by longest prefix match and emits `@<repo_prefix><tfm>//<package-id-lowercase>` labels.

**Tech Stack:** Bazel 9 (bzlmod), Starlark, Go 1.24, rules_go 0.59.0, bazel-gazelle 0.51.3 (`gazelle_generation_test` for integration tests), Paket (rules_dotnet's own NuGet deps), `packages_lock` module extension (consumer NuGet deps).

**Spec:** `docs/superpowers/specs/2026-10-14-dotnet-gazelle-design.md` (approved). Reference implementation: `java/gazelle` in `/home/jhobert/Projects/Gazelle/rules_jvm`.

---

## Environment notes (read before running any command)

These workarounds are required in this development environment. Run the exports in **every new shell** before running `bazel` or `go` commands:

```bash
# Bazel fails inside the sandbox with "invalid registered toolchain
# '@local_jdk//:bootstrap_runtime_toolchain_definition' ... (Permission denied)"
# because /etc/java-openjdk is not readable. Point JAVA_HOME at Bazel's own JDK:
export JAVA_HOME="$(bazel info java-home 2>/dev/null)"

# ~/go is not writable in this sandbox. The module cache is already primed
# under /tmp/opencode/gopath (bazel-gazelle v0.51.3, rules_go v0.59.0,
# buildtools); proxy.golang.org is reachable for anything missing.
export GOPATH=/tmp/opencode/gopath
export GOCACHE=/tmp/opencode/gocache
```

Other environment facts:

- Work from the repo root: `/home/jhobert/Projects/Gazelle/rules_dotnet` (branch `feature/packages-lock`).
- `bazel` is bazelisk; `.bazelversion` pins Bazel 9.1.1. Local `go` is 1.27 (only used for `go test`/`go mod tidy`; Bazel builds use the rules_go 1.24.12 SDK).
- **Pre-existing gazelle drift:** running `bazel run //:gazelle` on the unmodified repo adds `bzl_library` targets in `dotnet/BUILD.bazel` and various `dotnet/private/tests/**/BUILD.bazel` files. That drift is unrelated to this feature. After every root gazelle run, revert it (each task commits its own changes first, so `git diff` only ever shows fresh drift):

```bash
git diff --name-only -- dotnet/BUILD.bazel dotnet/private | xargs -r git checkout --
```

- Commit style in this repo: imperative, "Add X" (e.g. `git log --oneline` shows "Add design doc for C# Gazelle extension"). Commit at the end of every task with `git add` of exactly the files listed in that task's commit step.

---

## File structure

New files (Fase 0, Starlark/C#):

| File | Responsibility |
|---|---|
| `dotnet/private/rules/csharp/xunit_test.bzl` | `csharp_xunit_test` macro (csharp_test + xunit deps + shim) |
| `dotnet/private/rules/csharp/mstest_test.bzl` | `csharp_mstest_test` macro (csharp_test + MSTest/MTP deps + shim) |
| `dotnet/private/rules/common/xunit/{BUILD.bazel,shim.cs}` | xunit v3 entry-point shim |
| `dotnet/private/rules/common/mstest/{BUILD.bazel,shim.cs}` | MSTest/Microsoft.Testing.Platform entry-point shim |
| `dotnet/private/tests/xunit_test/{BUILD.bazel,xunittest.cs}` | smoke test for `csharp_xunit_test` |
| `dotnet/private/tests/mstest_test/{BUILD.bazel,mstesttest.cs}` | smoke test for `csharp_mstest_test` |

New files (Gazelle extension, Go):

| File | Responsibility |
|---|---|
| `go.mod`, `go.sum` | Go module `github.com/bazel-contrib/rules_dotnet` (repo root) |
| `dotnet/gazelle/constants.go` | `languageName`, private-attr keys |
| `dotnet/gazelle/lang.go` | `csharpLang`, `NewLanguage()`, `Kinds()`, `Loads()`, `ApparentLoads()`, `Fix()` |
| `dotnet/gazelle/configure.go` | `Configurer`: CLI flag, directives, NuGet index loading |
| `dotnet/gazelle/generate.go` | `GenerateRules`: library/test/binary rule generation |
| `dotnet/gazelle/resolve.go` | `Resolver`: `Imports`/`Embeds`/`Resolve`, namespace→label logic |
| `dotnet/gazelle/dotnetconfig/config.go` | per-directory config + directive parsing/validation |
| `dotnet/gazelle/private/parser/parser.go` | lightweight C# parser (comment/string blanking + metadata) |
| `dotnet/gazelle/private/nuget/nuget.go` | `packages.lock.json` package-ID index, longest-prefix resolve |
| `*_test.go` next to each of the above | Go unit tests |
| `dotnet/gazelle/testdata/BUILD.bazel` + `testdata/<case>/**` | `gazelle_generation_test` integration fixtures (11 cases — Task 17 adds `test_with_binary`) |

New files (examples/e2e):

| File | Responsibility |
|---|---|
| `examples/gazelle_csharp/**` | example workspace content demonstrating `bazel run //gazelle_csharp:gazelle` |
| `e2e/gazelle_net10.0/**` | e2e module: run gazelle, then `bazel build //...` + `bazel test //...` |
| `e2e/gazelle_net10.0/src/CalculatorApp/ProgramTests.cs` | NUnit test calling `Program.Run()` from the sibling binary (Task 17) |

Modified files:

| File | Change |
|---|---|
| `paket.dependencies`, `paket.lock` | add xunit.v3/MSTest packages to group `rules_dotnet_nuget_packages` |
| `dotnet/defs.bzl` | export `csharp_xunit_test`, `csharp_mstest_test` |
| `dotnet/private/rules/csharp/BUILD.bazel` | `bzl_library` targets for the two new .bzl files |
| `MODULE.bazel` | gazelle → non-dev, add rules_go + go_sdk |
| `BUILD.bazel` (root) | add go language + `# gazelle:prefix` to `gazelle_bin` |
| `examples/MODULE.bazel` | add gazelle bazel_dep + packages_lock extension for the example |
| `.bazelci/presubmit.yml` | add `e2e/gazelle_net10.0` to the e2e matrix |
| `dotnet/gazelle/{generate.go,resolve.go,constants.go,generate_test.go,resolve_test.go}` (Task 17) | binaries carry the `csharp_namespaces` private attr and are indexed; test sibling dep falls back to the entry-point binary when no library exists |
| `e2e/gazelle_net10.0/src/CalculatorApp/{Program.cs,BUILD.bazel}` (Task 17) | `Program.cs` gains a public callable method with a real Calculator dependency; BUILD.bazel regenerated by the fixed generator |

## Directives reference (implemented by the extension)

| Directive | Meaning | Default |
|---|---|---|
| `dotnet_target_frameworks` | TFM(s) for generated targets, comma-separated. **Required at the repository root** (fatal if missing). | — |
| `dotnet_nuget_repo_prefix` | Repo prefix for NuGet labels | `nuget.` |
| `dotnet_resolve <namespace> <label>` | Manual namespace→label override. Repeatable. | — |
| `dotnet_test_framework` | Force framework of detected test files: `nunit`/`xunit`/`mstest` | auto-detect |
| `dotnet_generate_binary` | Generate `csharp_binary` for entry-point files: `true`/`false` | `true` |
| `dotnet_project_sdk` | `project_sdk` attr of generated targets | `default` |
| `dotnet_visibility` | Visibility entry for generated targets. Repeatable; first use replaces the default. | `//visibility:public` |
| `dotnet_unresolved_imports` | Unresolvable imports: `warn` or `error` | `warn` |

CLI flag: `-dotnet_nuget_lock_file` — path of `packages.lock.json` relative to the repo root (default `packages.lock.json`).

Note: the spec's directive table lists 5 directives; `dotnet_project_sdk`, `dotnet_visibility` and `dotnet_unresolved_imports` are added because the spec text requires `project_sdk`/`visibility` "via directives" and configurable unresolved-import handling.

## Generation and resolution semantics (normative)

- Per directory with `.cs` files: production files → one `csharp_library` named `sanitize(dir basename)`; test files grouped per detected framework → `csharp_<framework>_test` named `<lib>_<framework>_test`; entry-point files (with `dotnet_generate_binary true`) → one `csharp_binary` each, named `sanitize(file basename without .cs)`.
- `sanitize(name)`: lowercase, runs of `[^a-z0-9_-]` → `_`, trimmed of leading/trailing `_`; `unnamed` if empty.
- Entry-point files are excluded from library `srcs`. Test files are never in library `srcs`.
- Attr set order at generate time: `srcs`, `target_frameworks`, `project_sdk`, `visibility`, then `internals_visible_to` (library only, when sibling tests exist), then `deps` (test rules only, sibling dep `:<lib>`; since Task 17, when no library is generated and the directory contains exactly one entry-point file, the sibling dep is `:<sanitize(entry file basename)>` — the binary — instead; with several entry-point files and no library there is no sibling dep and resolution via using directives covers the dependency). Resolve re-sets `deps` last (union with existing values), so `deps` always appears last in output.
- `internals_visible_to` takes assembly names (= target names), e.g. `["calculator_nunit_test"]` — no colon.
- Resolve order per imported namespace: (1) `dotnet_resolve` override → (2) workspace rule index (`FindRulesByImportWithConfig`, skip self-imports, same-package labels become `:name`) → (3) NuGet longest-prefix match → label `@<prefix><tfm[0]>//<id-lowercase>` → (4) `System`/`System.*` skipped as base-class-library → (5) warn or error per `dotnet_unresolved_imports`. On failure of a direct match, enclosing namespaces are retried (covers `using static Foo.Bar.SomeType;`).
- NuGet index ambiguity (case-variant package IDs matching equally) is fatal with a message suggesting `dotnet_resolve`.
- Every generated `csharp_library` — and since Task 17 every generated `csharp_binary` — carries a private attr with its sources' namespaces; `Resolver.Imports` indexes those, so `using Foo.Bar;` in another package resolves to the library (or binary) target. Rules of other kinds, and binaries without the private attr (e.g. hand-written ones), are not indexed.

---

### Task 1: Fase 0 — add xUnit/MSTest NuGet packages to paket

The new test rules need xUnit v3 and MSTest packages from the repo's own paket group `rules_dotnet_nuget_packages` (framework net9.0), the same group that already provides `nunit`/`nunitlite`.

**Files:**
- Modify: `paket.dependencies` (group `rules_dotnet_nuget_packages`, lines 49–54)
- Modify: `paket.lock` (regenerated)

- [x] **Step 1: Add the packages to paket.dependencies**

Edit `paket.dependencies`. Old:

```
group rules_dotnet_nuget_packages
    framework: net9.0
    source https://api.nuget.org/v3/index.json

    nuget NUnit 3.14.0
    nuget NUnitLite 3.14.0
```

New:

```
group rules_dotnet_nuget_packages
    framework: net9.0
    source https://api.nuget.org/v3/index.json

    nuget NUnit 3.14.0
    nuget NUnitLite 3.14.0
    nuget xunit.v3.assert ~> 3.0
    nuget xunit.v3.core ~> 3.0
    nuget MSTest.TestAdapter ~> 3.8
    nuget MSTest.TestFramework ~> 3.8
    nuget Microsoft.Testing.Platform 2.5.1
```

`Microsoft.Testing.Platform` is exact-pinned to 2.5.1 like every other direct dependency in this file. The original plan text left it unpinned on the assumption that the adapter's `~> 3.8` constraint bounds it; code review found that is wrong (xunit.v3's `mtp-v1` bounds MTP only `>= 1.9.1`, unbounded above), so it was pinned after user approval (commits `8c22e28` + `d20d46a`).

- [x] **Step 2: Regenerate paket.lock**

Run (env exports from Environment notes assumed):

```bash
bazel run --run_env=BUILD_WORKING_DIRECTORY="$PWD" //tools/paket -- install
```

Expected: exit code 0, paket output ends with `Done` (or similar success line). Verify the lock changed:

```bash
git diff --stat paket.lock
```

Expected: `paket.lock | NNN +++...` with additions.

- [x] **Step 3: Verify the new package labels exist**

```bash
bazel query '@paket.rules_dotnet_nuget_packages//xunit.v3.core:all' '@paket.rules_dotnet_nuget_packages//xunit.v3.assert:all' '@paket.rules_dotnet_nuget_packages//mstest.testadapter:all' '@paket.rules_dotnet_nuget_packages//mstest.testframework:all' '@paket.rules_dotnet_nuget_packages//microsoft.testing.platform:all'
```

Expected: exit code 0 and at least one target line printed per package (e.g. `@paket.rules_dotnet_nuget_packages//xunit.v3.core:xunit.v3.core`).

- [x] **Step 4: Commit**

```bash
git add paket.dependencies paket.lock
git commit -m "Add xUnit v3 and MSTest packages to rules_dotnet_nuget_packages"
```

### Task 2: Fase 0 — `csharp_xunit_test` rule

Mirrors `csharp_nunit_test` (`dotnet/private/rules/csharp/nunit_test.bzl`): a macro around `csharp_test` that adds xUnit v3 deps and an entry-point shim. xUnit v3 is self-executing; the shim is a one-line `Main` delegating to its in-process console runner.

**Files:**
- Create: `dotnet/private/rules/common/xunit/BUILD.bazel`
- Create: `dotnet/private/rules/common/xunit/shim.cs`
- Create: `dotnet/private/rules/csharp/xunit_test.bzl`
- Modify: `dotnet/defs.bzl`
- Test: `dotnet/private/tests/xunit_test/BUILD.bazel`, `dotnet/private/tests/xunit_test/xunittest.cs`

- [x] **Step 1: Create the shim**

Create `dotnet/private/rules/common/xunit/BUILD.bazel`:

```python
exports_files(
    [
        "shim.cs",
    ],
    visibility = ["//visibility:public"],
)
```

Create `dotnet/private/rules/common/xunit/shim.cs` (note: tab indentation, mirroring `dotnet/private/rules/common/nunit/shim.cs`):

```csharp
internal static class XunitShim {
	public static int Main(string[] args) => Xunit.Runner.InProc.SystemConsole.ConsoleRunner.Run(args).GetAwaiter().GetResult();
}
```

`Xunit.Runner.InProc.SystemConsole.ConsoleRunner.Run` is the static entry point xunit.v3.core provides for self-executing test projects; it returns `ValueTask<int>`.

- [x] **Step 2: Create the macro**

Create `dotnet/private/rules/csharp/xunit_test.bzl`:

```python
"""
Rules for compiling and running xUnit tests.

This rule is a macro that has the same attributes as `csharp_test`
"""

load("//dotnet/private/rules/common:embed_sources.bzl", "embed_sources_or_flag")
load("//dotnet/private/rules/csharp:test.bzl", "csharp_test")

def csharp_xunit_test(**kwargs):
    # TODO: This should be user configurable
    deps = kwargs.pop("deps", []) + [
        Label("@paket.rules_dotnet_nuget_packages//xunit.v3.assert"),
        Label("@paket.rules_dotnet_nuget_packages//xunit.v3.core"),
    ]

    srcs = kwargs.pop("srcs", []) + [
        Label("//dotnet/private/rules/common/xunit:shim.cs"),
    ]

    csharp_test(
        embed_sources = embed_sources_or_flag(kwargs.pop("embed_sources", None)),
        srcs = srcs,
        deps = deps,
        **kwargs
    )
```

Both xunit packages are direct deps so the macro works with `--@rules_dotnet//dotnet/settings:strict_deps=true` (CI runs both settings).

> **Implemented (commit `44cafe0`):** two more direct deps were required — `xunit.v3.extensibility.core` (ships `xunit.v3.core.dll` incl. `FactAttribute`; `xunit.v3.core` 3.2.2 is a meta-package whose `lib/` contains only `_._`) and `xunit.v3.runner.inproc.console` (ships the shim's `ConsoleRunner`). Verified by spec review at the package/assembly level; smoke test passes under strict_deps.

- [x] **Step 3: Export from defs.bzl**

Edit `dotnet/defs.bzl`. Old:

```
load(
    "//dotnet/private/rules/csharp:test.bzl",
    _csharp_test = "csharp_test",
)
```

New:

```
load(
    "//dotnet/private/rules/csharp:test.bzl",
    _csharp_test = "csharp_test",
)
load(
    "//dotnet/private/rules/csharp:xunit_test.bzl",
    _csharp_xunit_test = "csharp_xunit_test",
)
```

Then, old:

```
csharp_nunit_test = _csharp_nunit_test
fsharp_nunit_test = _fsharp_nunit_test
```

New:

```
csharp_nunit_test = _csharp_nunit_test
csharp_xunit_test = _csharp_xunit_test
fsharp_nunit_test = _fsharp_nunit_test
```

- [x] **Step 4: Write the smoke test**

Create `dotnet/private/tests/xunit_test/BUILD.bazel`:

```python
load(
    "//dotnet:defs.bzl",
    "csharp_xunit_test",
)

csharp_xunit_test(
    name = "XunitTest",
    srcs = ["xunittest.cs"],
    target_frameworks = ["net9.0"],
)
```

Create `dotnet/private/tests/xunit_test/xunittest.cs`:

```csharp
using Xunit;

namespace XunitSmoke;

public sealed class BasicTests
{
    [Fact]
    public void Truth()
    {
        Assert.True(true);
    }
}
```

- [x] **Step 5: Run the smoke test**

Run (env exports assumed):

```bash
bazel test //dotnet/private/tests/xunit_test:XunitTest
```

Expected: `//dotnet/private/tests/xunit_test:XunitTest PASSED` and `Executed 1 out of 1 test: 1 test passes.`

If compilation of `shim.cs` fails with a missing `ConsoleRunner.Run` member, check the exact xunit.v3.core API with `bazel query @paket.rules_dotnet_nuget_packages//xunit.v3.core:all --output=build | head -50` and adjust the shim to the available runner entry point; keep the rest of this task unchanged.

- [x] **Step 6: Commit**

```bash
git add dotnet/private/rules/common/xunit dotnet/private/rules/csharp/xunit_test.bzl dotnet/defs.bzl dotnet/private/tests/xunit_test
git commit -m "Add csharp_xunit_test rule"
```

### Task 3: Fase 0 — `csharp_mstest_test` rule

Same pattern as Task 2, with a Microsoft.Testing.Platform-based shim. `AddMSTest` is an extension method in namespace `Microsoft.VisualStudio.TestTools.UnitTesting` (class `TestApplicationBuilderExtensions`, shipped in MSTest.TestAdapter).

> **Implemented (commit `4b0c334`) with a temporary workaround, superseded by Task 3b:** compilation revealed that `mstest.testadapter` 3.11.1 (like MSTest 4.x) ships **no `lib/` folder at all** — every assembly lives under `buildTransitive/<tfm>/` — and the paket→bazel pipeline only surfaces `lib/` assemblies, so `@paket.rules_dotnet_nuget_packages//mstest.testadapter` has an empty `libs` filegroup and the shim's `AddMSTest` is unavailable. As a stopgap, `dotnet/private/rules/common/mstest/BUILD.bazel` gained `import_library` wrappers (`mstest_testadapter`, `mstest_testframework_extensions`) whose canonical labels are hardcoded to `@@+paket+nuget.mstest.testadapter.v3.11.1//...` and `@@+paket+nuget.mstest.testframework.v3.11.1//...`, and the macro in `mstest_test.bzl` depends on `//dotnet/private/rules/common/mstest:mstest_testadapter` in addition to the three package labels. That is tech debt: it breaks on every version bump and may break for consumers. **Task 3b fixes the shared NuGet pipeline properly and removes the wrappers** — after Task 3b, `common/mstest/BUILD.bazel` contains only the `exports_files` shown in Step 1 below (no version-pinned labels), and the macro depends on the three package labels only.

**Files:**
- Create: `dotnet/private/rules/common/mstest/BUILD.bazel`
- Create: `dotnet/private/rules/common/mstest/shim.cs`
- Create: `dotnet/private/rules/csharp/mstest_test.bzl`
- Modify: `dotnet/defs.bzl`
- Modify: `dotnet/private/rules/csharp/BUILD.bazel`
- Test: `dotnet/private/tests/mstest_test/BUILD.bazel`, `dotnet/private/tests/mstest_test/mstesttest.cs`

- [x] **Step 1: Create the shim**

Create `dotnet/private/rules/common/mstest/BUILD.bazel`:

```python
exports_files(
    [
        "shim.cs",
    ],
    visibility = ["//visibility:public"],
)
```

Create `dotnet/private/rules/common/mstest/shim.cs` (tab indentation):

```csharp
using System.Threading.Tasks;
using Microsoft.Testing.Platform.Builder;
using Microsoft.VisualStudio.TestTools.UnitTesting;

internal static class MSTestShim {
	public static async Task<int> Main(string[] args) {
		var builder = await TestApplication.CreateBuilderAsync(args);
		builder.AddMSTest(() => new[] { typeof(MSTestShim).Assembly });
		using var app = await builder.BuildAsync();
		return await app.RunAsync();
	}
}
```

- [x] **Step 2: Create the macro**

Create `dotnet/private/rules/csharp/mstest_test.bzl`:

```python
"""
Rules for compiling and running MSTest tests.

This rule is a macro that has the same attributes as `csharp_test`
"""

load("//dotnet/private/rules/common:embed_sources.bzl", "embed_sources_or_flag")
load("//dotnet/private/rules/csharp:test.bzl", "csharp_test")

def csharp_mstest_test(**kwargs):
    # TODO: This should be user configurable
    deps = kwargs.pop("deps", []) + [
        Label("@paket.rules_dotnet_nuget_packages//microsoft.testing.platform"),
        Label("@paket.rules_dotnet_nuget_packages//mstest.testadapter"),
        Label("@paket.rules_dotnet_nuget_packages//mstest.testframework"),
    ]

    srcs = kwargs.pop("srcs", []) + [
        Label("//dotnet/private/rules/common/mstest:shim.cs"),
    ]

    csharp_test(
        embed_sources = embed_sources_or_flag(kwargs.pop("embed_sources", None)),
        srcs = srcs,
        deps = deps,
        **kwargs
    )
```

- [x] **Step 3: Export from defs.bzl**

Edit `dotnet/defs.bzl`. Old:

```
load(
    "//dotnet/private/rules/csharp:nunit_test.bzl",
    _csharp_nunit_test = "csharp_nunit_test",
)
```

New:

```
load(
    "//dotnet/private/rules/csharp:mstest_test.bzl",
    _csharp_mstest_test = "csharp_mstest_test",
)
load(
    "//dotnet/private/rules/csharp:nunit_test.bzl",
    _csharp_nunit_test = "csharp_nunit_test",
)
```

Then, old:

```
csharp_nunit_test = _csharp_nunit_test
csharp_xunit_test = _csharp_xunit_test
```

New:

```
csharp_mstest_test = _csharp_mstest_test
csharp_nunit_test = _csharp_nunit_test
csharp_xunit_test = _csharp_xunit_test
```

- [x] **Step 4: Add bzl_library targets for both new .bzl files**

Edit `dotnet/private/rules/csharp/BUILD.bazel`. Append after the existing `bzl_library(name = "nunit_test", ...)` block at the end of the file:

```python
bzl_library(
    name = "mstest_test",
    srcs = ["mstest_test.bzl"],  # keep
    visibility = [
        "//dotnet:__subpackages__",
    ],
    deps = [
        ":test",
    ],
)

bzl_library(
    name = "xunit_test",
    srcs = ["xunit_test.bzl"],  # keep
    visibility = [
        "//dotnet:__subpackages__",
    ],
    deps = [
        ":test",
    ],
)
```

This mirrors the hand-maintained `nunit_test` bzl_library (same deps, same `# keep` on srcs).

- [x] **Step 5: Write the smoke test**

Create `dotnet/private/tests/mstest_test/BUILD.bazel`:

```python
load(
    "//dotnet:defs.bzl",
    "csharp_mstest_test",
)

csharp_mstest_test(
    name = "MSTestTest",
    srcs = ["mstesttest.cs"],
    target_frameworks = ["net9.0"],
)
```

Create `dotnet/private/tests/mstest_test/mstesttest.cs`:

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MSTestSmoke;

[TestClass]
public sealed class BasicTests
{
    [TestMethod]
    public void Truth()
    {
        Assert.IsTrue(true);
    }
}
```

- [x] **Step 6: Run the smoke test**

Run (env exports assumed):

```bash
bazel test //dotnet/private/tests/mstest_test:MSTestTest
```

Expected: `//dotnet/private/tests/mstest_test:MSTestTest PASSED` and `Executed 1 out of 1 test: 1 test passes.`

- [x] **Step 7: Commit**

```bash
git add dotnet/private/rules/common/mstest dotnet/private/rules/csharp/mstest_test.bzl dotnet/private/rules/csharp/BUILD.bazel dotnet/defs.bzl dotnet/private/tests/mstest_test
git commit -m "Add csharp_mstest_test rule"
```

### Task 3b: Fix `buildTransitive`-only NuGet packages and drop the mstest workaround

Task 3's workaround exists because the shared NuGet pipeline (`dotnet/private/rules/nuget/nuget_archive.bzl` → generated archive targets → `nuget_package` in `dotnet/private/rules/nuget/package.bzl`) only surfaces assemblies under `lib/`, `ref/`, and `build/<tfm>/{lib,ref}/`. Packages such as `MSTest.TestAdapter` ship their assemblies under `buildTransitive/<tfm>/` only, so their package target gets an empty `libs` group. Both consumers of the pipeline — the paket extension (`dotnet/private/paket/extension.bzl`, generating `@paket.rules_dotnet_nuget_packages//...`) and the packages_lock extension (`dotnet/private/packages_lock/extension.bzl`) — go through the same `nuget_archive` spokes and `nuget_package`, so a single fix in `nuget_archive.bzl` covers both; neither extension needs changes.

**Design decision (made, with justification):** `buildTransitive/<tfm>/<assembly>.dll` files are collected into a new `buildTransitive` group and **merged into the `libs` dict** in `_group_package_files` — the same way F# typeprovider assemblies are merged in — so they flow through the existing `tfm_filegroup`/`_tfm_alias` framework-compatibility machinery exactly like `lib/<tfm>` assemblies. The alternatives were rejected:

- *File them into the existing `build` group (the `build/<tfm>/lib/` bucket)*: that bucket is unioned into the runtime `libs` group, but the compile `refs` group only falls back to the raw `lib/` dict (`ref_tfm_filegroup` → `_with_empty_entries(groups.libs, ...)`), so a `buildTransitive`-only package would still get **empty compile refs** — the shim's `AddMSTest` would not compile.
- *Fallback only when `lib/<tfm>` is empty*: wrong for `MSTest.TestFramework`, which ships `lib/net8.0/TestFramework.dll` **and** `buildTransitive/net8.0/TestFramework.Extensions.dll` — both are required at runtime, so `buildTransitive` assemblies must *add to* the lib group, not replace it.
- *A separate `build_transitive_libs` filegroup alongside `libs`*: forces every consumer (including `import_library` in `package.bzl`) to know about a second group, for no benefit — merging into `libs` makes the packages work through the unchanged `nuget_package`/`import_library` path.

Because the merge happens before the `libs` struct field is computed, compile-time references need no extra work: when a package ships no `ref/` folder, the archive's `refs` group already falls back to the `libs` group per-TFM (`ref_tfm_filegroup` in `nuget_archive.bzl`), so `AddMSTest` in `Microsoft.VisualStudio.TestPlatform.MSTest.TestAdapter.dll` becomes a compile reference automatically. Only DLLs **directly** under `buildTransitive/<tfm>/` count (exactly 3 path segments): platform-specific subfolders such as `buildTransitive/net6.0/winui/` and `buildTransitive/net9.0/uwp/`, the `_localization` folder, `.resources.dll` satellites, and props/targets are all ignored. `_._` placeholders and non-rules_dotnet TFMs (`uap10.0`) fall out of the existing `_normalize_tfm`/`.dll` checks. Consequence (same as the Task 3 workaround, which set `refs = libs`): for a package that ships both `lib/` and `buildTransitive/` assemblies, the `buildTransitive` ones also become compile references.

The repo has a purpose-built test suite for this pipeline: `dotnet/private/tests/nuget_resolution/` declares fixture packages as plain file lists (`tests.bzl`) and asserts what a build resolves out of them (`internal/`, driven by `nuget_resolution_tests()` in `BUILD.bazel`). New declarations are picked up automatically — no BUILD file changes needed.

This task produces two commits: the pipeline fix (with TDD tests), then the mstest simplification.

**Files:**
- Modify: `dotnet/private/tests/nuget_resolution/tests.bzl` (append 4 test declarations to `TESTS`)
- Modify: `dotnet/private/rules/nuget/nuget_archive.bzl` (`_process_build_transitive_file` + key routing + new `buildTransitive` group + merge into `libs`)
- Modify: `dotnet/private/rules/common/mstest/BUILD.bazel` (drop the `import_library` wrappers)
- Modify: `dotnet/private/rules/csharp/mstest_test.bzl` (drop the wrapper dep)

- [x] **Step 1: Write the failing resolution tests**

Append to `dotnet/private/tests/nuget_resolution/tests.bzl`, inside the `TESTS = [...]` list. Edit — old (the end of the list):

```python
        default_configuration = True,
        expected_libs = ["lib/netstandard2.0/A.dll"],
    ),
]
```

New:

```python
        default_configuration = True,
        expected_libs = ["lib/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "build_transitive_assemblies_are_added_to_the_lib_group",
        # What `MSTest.TestFramework` looks like at one framework: its own
        # assembly under `lib/net8.0/` plus `TestFramework.Extensions.dll`
        # under `buildTransitive/net8.0/`. Both end up next to the binary and
        # the compile group falls back to both (same as the Task 3
        # workaround's refs = libs).
        files = [
            "lib/net8.0/A.dll",
            "buildTransitive/net8.0/T.dll",
        ],
        expected_libs = ["buildTransitive/net8.0/T.dll", "lib/net8.0/A.dll"],
        expected_refs = ["buildTransitive/net8.0/T.dll", "lib/net8.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "a_package_of_only_build_transitive_assemblies_resolves",
        # What `MSTest.TestAdapter` looks like: no `lib/` folder at all. The
        # assemblies are the package's payload, so the compile group falls
        # back to them the same way it falls back to `lib` assemblies.
        files = [
            "buildTransitive/netstandard2.0/A.dll",
            "buildTransitive/net8.0/A.dll",
        ],
        expected_libs = ["buildTransitive/net8.0/A.dll"],
        expected_refs = ["buildTransitive/net8.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "build_transitive_assemblies_resolve_by_framework_compatibility",
        # A net6.0 build cannot use the net8.0 assemblies and lands on
        # netstandard2.0, through the same nearest-compatible-framework walk
        # as every other group.
        files = [
            "buildTransitive/netstandard2.0/A.dll",
            "buildTransitive/net8.0/A.dll",
        ],
        target_framework = "net6.0",
        expected_libs = ["buildTransitive/netstandard2.0/A.dll"],
        expected_refs = ["buildTransitive/netstandard2.0/A.dll"],
    ),
    nuget_resolution_test(
        name = "only_portable_build_transitive_assemblies_are_collected",
        # `MSTest.TestAdapter` ships `winui`/`uwp` subfolders and a
        # `_localization` folder under `buildTransitive/`; neither is a
        # portable framework folder.
        files = [
            "buildTransitive/net8.0/A.dll",
            "buildTransitive/net8.0/winui/W.dll",
            "buildTransitive/_localization/de/A.resources.dll",
        ],
        expected_libs = ["buildTransitive/net8.0/A.dll"],
        expected_refs = ["buildTransitive/net8.0/A.dll"],
    ),
]
```

- [x] **Step 2: Run the new tests to verify they fail**

Run (env exports from Environment notes assumed; the `@nuget_fixtures` repository refetches because `tests.bzl` changed — expected):

```bash
bazel test //dotnet/private/tests/nuget_resolution:build_transitive_assemblies_are_added_to_the_lib_group //dotnet/private/tests/nuget_resolution:a_package_of_only_build_transitive_assemblies_resolves //dotnet/private/tests/nuget_resolution:build_transitive_assemblies_resolve_by_framework_compatibility //dotnet/private/tests/nuget_resolution:only_portable_build_transitive_assemblies_are_collected
```

Expected: all 4 tests FAIL. Each test log contains an assertion failure of the form `Expected libs:` (or `Expected refs:`) listing the `buildTransitive/...` paths and an `Actual libs:` list without them (the groups resolve to nothing today).

- [x] **Step 3: Implement the pipeline fix in nuget_archive.bzl**

Edit `dotnet/private/rules/nuget/nuget_archive.bzl` — old (the tail of `_process_build_file`, which is where the new function goes):

```python
    groups["build"].setdefault(tfm, {"lib": [], "ref": []})[file_type].append(file)

def _process_typeprovider_file(groups, file):
```

New:

```python
    groups["build"].setdefault(tfm, {"lib": [], "ref": []})[file_type].append(file)

# `buildTransitive/<tfm>/<assembly>.dll`.
#
# `buildTransitive` is the transitively flowing variant of `build`, and some
# packages ship their assemblies there instead of under `lib` (`MSTest.
# TestAdapter` has no `lib/` folder at all). They are merged into the lib
# group in _group_package_files and resolve like `lib/<tfm>` assemblies.
# Only a DLL sitting directly under the framework folder counts; platform
# specific subfolders such as `buildTransitive/net6.0/winui` are not
# portable, and props/targets are not assemblies.
def _process_build_transitive_file(groups, file):
    parts = file.split("/")

    if len(parts) != 3:
        return

    tfm = _normalize_tfm(parts[1])

    if tfm == None:
        return

    # See https://github.com/bazel-contrib/rules_dotnet/issues/405
    if not file.endswith(".dll") or file.endswith(".resources.dll"):
        return

    groups["buildTransitive"].setdefault(tfm, []).append(file)

def _process_typeprovider_file(groups, file):
```

Then route the new key in `_process_key_and_file`. Old:

```python
    elif key == "build":
        _process_build_file(groups, file)
    elif key == "tools":
        _process_tools_file(groups, file)
```

New:

```python
    elif key == "build":
        _process_build_file(groups, file)
    elif key == "buildTransitive":
        _process_build_transitive_file(groups, file)
    elif key == "tools":
        _process_tools_file(groups, file)
```

Then register the new group in the groups dict in `_group_package_files`. Old:

```python
        "build": {},
        # See https://github.com/dotnet/sdk/blob/master/documentation/general/tool-nuget-package-format.md
```

New:

```python
        "build": {},
        # Assemblies some packages ship under buildTransitive/<TFM>/ instead
        # of lib/<TFM>/ (`MSTest.TestAdapter` has no lib/ folder at all).
        # They are merged into the lib group below.
        # Format: buildTransitive/<TFM>/<assembly>.dll
        "buildTransitive": {},
        # See https://github.com/dotnet/sdk/blob/master/documentation/general/tool-nuget-package-format.md
```

Then merge the group into `libs`, right after the typeproviders merge. Old:

```python
    for (tfm, files) in groups["typeproviders"].items():
        if libs.get(tfm):
            libs[tfm] = libs[tfm] + files
        else:
            libs[tfm] = files
```

New:

```python
    for (tfm, files) in groups["typeproviders"].items():
        if libs.get(tfm):
            libs[tfm] = libs[tfm] + files
        else:
            libs[tfm] = files

    # Assemblies under `buildTransitive/<tfm>/` stand in for `lib/<tfm>` ones,
    # so they join the lib group and resolve through it — the runtime ships
    # them next to the binary and the compile group falls back to them when
    # the package ships no `ref/` folder.
    for (tfm, files) in groups["buildTransitive"].items():
        libs[tfm] = libs.get(tfm, []) + files
```

Nothing else changes: the `libs` struct field feeds `_create_rid_tfm_select("libs_package", ...)`, `ref_tfm_filegroup` already falls back to `libs` when a package ships no `ref/`, and `package.bzl`/`import_library` consume the groups unchanged. No `build/` package behavior changes — the new group is separate.

- [x] **Step 4: Run the resolution tests to verify they pass**

```bash
bazel test //dotnet/private/tests/nuget_resolution/...
```

Expected: `Executed NNN tests: all pass.` — including the 4 new tests and every pre-existing one (this also proves packages with plain `lib/` layouts, e.g. the nunit-shaped fixtures, are unaffected).

- [x] **Step 5: Commit the pipeline fix**

```bash
git add dotnet/private/rules/nuget/nuget_archive.bzl dotnet/private/tests/nuget_resolution/tests.bzl
git commit -m "Fix NuGet packages that ship assemblies under buildTransitive only"
```

- [x] **Step 6: Remove the import_library workaround from the mstest rule**

Rewrite `dotnet/private/rules/common/mstest/BUILD.bazel` in full — new content (this is exactly what the file contained before commit `4b0c334` added the wrappers):

```python
exports_files(
    [
        "shim.cs",
    ],
    visibility = ["//visibility:public"],
)
```

Then simplify the macro. Edit `dotnet/private/rules/csharp/mstest_test.bzl` — old:

```python
    deps = kwargs.pop("deps", []) + [
        Label("@paket.rules_dotnet_nuget_packages//microsoft.testing.platform"),
        Label("@paket.rules_dotnet_nuget_packages//mstest.testadapter"),
        Label("@paket.rules_dotnet_nuget_packages//mstest.testframework"),
        # The adapter nupkg ships its assemblies under buildTransitive/ only,
        # so the package target above has empty libs. Import the DLLs
        # (Microsoft.VisualStudio.TestPlatform.MSTest.TestAdapter.dll provides
        # AddMSTest) through a wrapper that selects them per target framework.
        Label("//dotnet/private/rules/common/mstest:mstest_testadapter"),
    ]
```

New:

```python
    deps = kwargs.pop("deps", []) + [
        Label("@paket.rules_dotnet_nuget_packages//microsoft.testing.platform"),
        Label("@paket.rules_dotnet_nuget_packages//mstest.testadapter"),
        Label("@paket.rules_dotnet_nuget_packages//mstest.testframework"),
    ]
```

- [x] **Step 7: Verify the paket group end-to-end and that existing packages are unaffected**

The `@paket.rules_dotnet_nuget_packages` archive repositories refetch on the first command after Step 3's `.bzl` change — lines about refetching `+paket+nuget.mstest.testadapter.v3.11.1` and friends in the output are expected. Run (env exports assumed):

```bash
bazel test --@rules_dotnet//dotnet/settings:strict_deps=true //dotnet/private/tests/mstest_test:MSTestTest
bazel test --@rules_dotnet//dotnet/settings:strict_deps=false //dotnet/private/tests/mstest_test:MSTestTest
```

Expected: both end with `//dotnet/private/tests/mstest_test:MSTestTest PASSED` and `Executed 1 out of 1 test: 1 test passes.` — proving the version-independent `@paket.rules_dotnet_nuget_packages//mstest.testadapter` label now carries the `buildTransitive/` assemblies (compile ref for `AddMSTest` included, since strict_deps passes). Then the xunit smoke test (different packages, same pipeline) and representative pre-existing consumers — an nunit paket-group test and the packages_lock extension tests, which exercise the second consumer of the shared pipeline:

```bash
bazel test //dotnet/private/tests/xunit_test:XunitTest //dotnet/private/tests/framework_override_not_provided:ProgramTest //dotnet/private/tests/packages_lock/...
```

Expected: `//dotnet/private/tests/xunit_test:XunitTest PASSED`, `//dotnet/private/tests/framework_override_not_provided:ProgramTest PASSED`, and all `//dotnet/private/tests/packages_lock/...` targets PASSED.

- [x] **Step 8: Commit the simplification**

```bash
git add dotnet/private/rules/common/mstest/BUILD.bazel dotnet/private/rules/csharp/mstest_test.bzl
git commit -m "Simplify csharp_mstest_test deps after the buildTransitive fix"
```

### Task 4: Go/Gazelle bootstrap in the root module

rules_dotnet currently has no Go code and uses gazelle only as a dev-dependency for bzl files. This task turns gazelle + rules_go into regular (non-dev) dependencies — consumers need `@rules_dotnet//dotnet/gazelle` to build in their own workspaces, and dev-dependencies of a non-root module are ignored by bzlmod — and adds the Go plugin to the repo's own `gazelle_bin` so it generates BUILD files for the new Go code.

**Files:**
- Modify: `MODULE.bazel`
- Modify: `BUILD.bazel` (root)
- Create: `go.mod`

- [x] **Step 1: Make gazelle a non-dev dependency and add rules_go**

Edit `MODULE.bazel`. Old:

```
bazel_dep(name = "bazel_skylib", version = "1.7.1")
bazel_dep(name = "platforms", version = "1.0.0")
bazel_dep(name = "bazel_lib", version = "3.0.0")
bazel_dep(name = "rules_shell", version = "0.5.0")
```

New:

```
bazel_dep(name = "bazel_skylib", version = "1.7.1")
bazel_dep(name = "platforms", version = "1.0.0")
bazel_dep(name = "bazel_lib", version = "3.0.0")
bazel_dep(name = "rules_shell", version = "0.5.0")
bazel_dep(name = "gazelle", version = "0.51.3", repo_name = "bazel_gazelle")
bazel_dep(name = "rules_go", version = "0.59.0")

go_sdk = use_extension("@rules_go//go:extensions.bzl", "go_sdk")
go_sdk.download(version = "1.24.12")
```

Then remove the dev-dependency declaration. Old:

```
# Dev dependencies
bazel_dep(name = "rules_pkg", version = "1.1.0", dev_dependency = True)
bazel_dep(name = "gazelle", version = "0.51.3", dev_dependency = True, repo_name = "bazel_gazelle")
bazel_dep(name = "bazel_skylib_gazelle_plugin", version = "1.9.0", dev_dependency = True)
```

New:

```
# Dev dependencies
bazel_dep(name = "rules_pkg", version = "1.1.0", dev_dependency = True)
bazel_dep(name = "bazel_skylib_gazelle_plugin", version = "1.9.0", dev_dependency = True)
```

- [x] **Step 2: Add the Go language to gazelle_bin and set the Go prefix**

Edit `BUILD.bazel` (root). Old:

```
gazelle_binary(
    name = "gazelle_bin",
    languages = ["@bazel_skylib_gazelle_plugin//bzl"],
)
```

New:

```
# gazelle:prefix github.com/bazel-contrib/rules_dotnet
gazelle_binary(
    name = "gazelle_bin",
    languages = [
        "@bazel_gazelle//language/go",
        "@bazel_skylib_gazelle_plugin//bzl",
    ],
)
```

- [x] **Step 3: Create go.mod**

Create `go.mod` at the repo root:

```
module github.com/bazel-contrib/rules_dotnet

go 1.24.12
```

Deliberately without a `require` on bazel-gazelle yet: no Go file imports it until Task 9, and `go mod tidy` would drop an unused require. Task 9 adds it.

- [x] **Step 4: Verify gazelle still runs and generates nothing new**

Run (env exports assumed):

```bash
bazel run //:gazelle
```

Expected: exit code 0. Then check what changed:

```bash
git status --porcelain
```

Expected output shows two groups of changes: (1) this task's own edits (`M MODULE.bazel`, `M BUILD.bazel`, `?? go.mod`) and (2) optionally modifications under `dotnet/BUILD.bazel` and/or `dotnet/private/**/BUILD.bazel` (pre-existing bzl-plugin drift, see Environment notes). Critically, **no new BUILD files for Go code** may appear (there are no `.go` files yet). Revert the drift, leaving this task's edits untouched:

```bash
git diff --name-only -- dotnet/BUILD.bazel dotnet/private | xargs -r git checkout --
git status --porcelain
```

Expected: only `M MODULE.bazel`, `M BUILD.bazel` and `?? go.mod` remain.

- [x] **Step 5: Commit**

```bash
git add MODULE.bazel BUILD.bazel go.mod
git commit -m "Add Go and rules_go bootstrap for the Gazelle extension"
```

### Task 5: C# parser — comment/string blanking (TDD)

The parser is a lightweight lexer, not a C# grammar. First component: `blankCommentsAndStrings`, which replaces comments and string/char literals with spaces (preserving newlines) so later regex matching never sees markers inside literals. Unterminated literals are a parse error; the caller (generate phase) skips such files with a warning.

**Files:**
- Create: `dotnet/gazelle/private/parser/parser.go`
- Test: `dotnet/gazelle/private/parser/parser_test.go`

- [x] **Step 1: Write the failing tests**

Create `dotnet/gazelle/private/parser/parser_test.go`:

```go
package parser

import (
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
```

- [x] **Step 2: Run the test to verify it fails**

Run (env exports assumed):

```bash
go test ./dotnet/gazelle/private/parser/
```

Expected: FAIL with `undefined: blankCommentsAndStrings` (build failure).

- [x] **Step 3: Implement blankCommentsAndStrings**

Create `dotnet/gazelle/private/parser/parser.go`:

```go
// Package parser extracts build metadata from C# source files: the declared
// namespace, using directives, test framework markers and entry points.
//
// It is a lightweight lexer/regex parser, not a full C# grammar. Comments
// and string literals are blanked before matching so markers inside them are
// ignored. Known limitation: interpolated strings ($"") are treated as
// opaque, so a quote inside an interpolation hole ends the string early;
// this can only cause false metadata in pathological sources.
package parser

import "fmt"

// blankCommentsAndStrings returns src with comments and string/char literals
// replaced by spaces, preserving newlines so line numbers stay stable. An
// error is returned for unterminated literals or block comments.
func blankCommentsAndStrings(src string) (string, error) {
	out := []byte(src)
	n := len(src)

	blank := func(start, end int) {
		for j := start; j < end; j++ {
			if out[j] != '\n' {
				out[j] = ' '
			}
		}
	}

	i := 0

	// scanString blanks a normal, verbatim (@"") or interpolated ($"")
	// string. i is at the first prefix character or at the opening quote.
	// Verbatim strings allow newlines and escape a quote by doubling it;
	// other strings use backslash escapes.
	scanString := func(verbatim bool) error {
		start := i
		for i < n && src[i] != '"' {
			i++
		}
		i++ // past the opening quote
		for {
			if i >= n {
				return fmt.Errorf("unterminated string at offset %d", start)
			}
			c := src[i]
			if c == '\n' && !verbatim {
				return fmt.Errorf("unterminated string at offset %d", start)
			}
			if c == '\\' && !verbatim {
				i += 2
				continue
			}
			if c == '"' {
				if verbatim && i+1 < n && src[i+1] == '"' {
					i += 2
					continue
				}
				i++
				blank(start, i)
				return nil
			}
			i++
		}
	}

	// scanRawString blanks a raw string literal whose opening delimiter is a
	// run of q quotes; the closing delimiter is a run of at least q quotes.
	scanRawString := func(q int) error {
		start := i
		for i < n && src[i] != '"' {
			i++
		}
		i += q // past the opening quotes
		for {
			if i >= n {
				return fmt.Errorf("unterminated raw string at offset %d", start)
			}
			if src[i] != '"' {
				i++
				continue
			}
			run := 0
			for i+run < n && src[i+run] == '"' {
				run++
			}
			if run >= q {
				i += q
				blank(start, i)
				return nil
			}
			i += run
		}
	}

	for i = 0; i < n; {
		c := src[i]
		switch {
		case c == '/' && i+1 < n && src[i+1] == '/':
			start := i
			for i < n && src[i] != '\n' {
				i++
			}
			blank(start, i)
		case c == '/' && i+1 < n && src[i+1] == '*':
			start := i
			i += 2
			for i+1 < n && !(src[i] == '*' && src[i+1] == '/') {
				i++
			}
			if i+1 >= n {
				return "", fmt.Errorf("unterminated block comment at offset %d", start)
			}
			i += 2
			blank(start, i)
		case c == '\'':
			start := i
			i++
			for {
				if i >= n || src[i] == '\n' {
					return "", fmt.Errorf("unterminated char literal at offset %d", start)
				}
				if src[i] == '\\' {
					i += 2
					continue
				}
				if src[i] == '\'' {
					i++
					break
				}
				i++
			}
			blank(start, i)
		case c == '"' || c == '@' || c == '$':
			// Count @/$ prefix characters, then the opening quote run.
			prefixes := 0
			verbatim := false
			for i+prefixes < n && (src[i+prefixes] == '@' || src[i+prefixes] == '$') {
				if src[i+prefixes] == '@' {
					verbatim = true
				}
				prefixes++
			}
			if i+prefixes >= n || src[i+prefixes] != '"' {
				// @ or $ that does not start a string, e.g. a verbatim
				// identifier like @class.
				i++
				continue
			}
			quotes := 0
			for i+prefixes+quotes < n && src[i+prefixes+quotes] == '"' {
				quotes++
			}
			var err error
			if quotes >= 3 {
				err = scanRawString(quotes)
			} else {
				err = scanString(verbatim)
			}
			if err != nil {
				return "", err
			}
		default:
			i++
		}
	}
	return string(out), nil
}
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
go test ./dotnet/gazelle/private/parser/
```

Expected: `ok  	github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/parser` and `PASS`.

- [x] **Step 5: Commit**

```bash
git add dotnet/gazelle/private/parser/parser.go dotnet/gazelle/private/parser/parser_test.go
git commit -m "Add C# comment and string blanking for the Gazelle parser"
```

### Task 6: C# parser — metadata extraction (TDD)

Add `Parse`/`ParseFile` on top of the blanking from Task 5: namespace, usings (static/alias/global), test-framework detection (precedence nunit > xunit > mstest) and entry-point detection.

**Files:**
- Modify: `dotnet/gazelle/private/parser/parser.go`
- Modify: `dotnet/gazelle/private/parser/parser_test.go`

- [x] **Step 1: Append the failing tests**

Append to the end of `dotnet/gazelle/private/parser/parser_test.go`:

```go
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
```

Also update the imports of `parser_test.go`. Old:

```go
import (
	"strings"
	"testing"
)
```

New:

```go
import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
go test ./dotnet/gazelle/private/parser/
```

Expected: FAIL with `undefined: Parse`, `undefined: ParseFile`, `undefined: FrameworkNone` (build failure).

- [x] **Step 3: Implement Parse and ParseFile**

Edit `dotnet/gazelle/private/parser/parser.go`. Old:

```go
import "fmt"
```

New:

```go
import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)
```

Then append to the end of `parser.go`:

```go
// Framework identifies a detected test framework.
type Framework string

const (
	FrameworkNone   Framework = ""
	FrameworkNUnit  Framework = "nunit"
	FrameworkXUnit  Framework = "xunit"
	FrameworkMSTest Framework = "mstest"
)

// Using is a single using directive.
type Using struct {
	// Namespace is the imported namespace. For `using static X.Y.Z;` it is
	// X.Y.Z; for `using A = X.Y;` it is X.Y.
	Namespace string
	// Static is true for `using static`.
	Static bool
	// Global is true for `global using`.
	Global bool
}

// File is the parse result of one .cs file.
type File struct {
	// Name is the base name of the file.
	Name string
	// Namespace is the declared namespace, "" when the file declares none
	// (e.g. top-level statements).
	Namespace string
	// Usings lists the using directives in source order.
	Usings []Using
	// Framework is the detected test framework, FrameworkNone when no test
	// markers were found.
	Framework Framework
	// HasEntryPoint is true for a `static ... Main(` method or top-level
	// statements.
	HasEntryPoint bool
}

var (
	namespaceRe  = regexp.MustCompile(`^namespace\s+([A-Za-z_][A-Za-z0-9_.]*)`)
	usingRe      = regexp.MustCompile(`^using\s+(static\s+)?(?:[A-Za-z_][A-Za-z0-9_]*\s*=\s*)?([A-Za-z_][A-Za-z0-9_.]*)\s*;`)
	entryPointRe = regexp.MustCompile(`\bstatic\s+(?:async\s+)?(?:void|int|Task|Task<int>|ValueTask|ValueTask<int>)\s+Main\s*\(`)
	typeDeclRe   = regexp.MustCompile(`\b(?:class|struct|interface|record|enum|delegate)\s+[A-Za-z_]`)
)

// frameworkMarkers is ordered by detection precedence: a file is attributed
// to the first framework whose using directive or attributes appear.
var frameworkMarkers = []struct {
	framework Framework
	using     string
	attrRe    *regexp.Regexp
}{
	{FrameworkNUnit, "NUnit.Framework", regexp.MustCompile(`\[(Test|TestFixture|TestCase|TestCaseSource|SetUp|TearDown)[\(\]]`)},
	{FrameworkXUnit, "Xunit", regexp.MustCompile(`\[(Fact|Theory)[\(\]]`)},
	{FrameworkMSTest, "Microsoft.VisualStudio.TestTools.UnitTesting", regexp.MustCompile(`\[(TestClass|TestMethod|DataTestMethod)[\(\]]`)},
}

// ParseFile reads and parses the .cs file at path.
func ParseFile(path string) (*File, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return Parse(filepath.Base(path), string(data))
}

// Parse parses C# source text. name is the file's base name, used in errors.
func Parse(name, src string) (*File, error) {
	blanked, err := blankCommentsAndStrings(src)
	if err != nil {
		return nil, fmt.Errorf("%s: %w", name, err)
	}

	f := &File{Name: name, Framework: FrameworkNone}

	for _, line := range strings.Split(blanked, "\n") {
		trimmed := strings.TrimSpace(line)
		global := false
		if strings.HasPrefix(trimmed, "global using ") {
			global = true
			trimmed = strings.TrimPrefix(trimmed, "global ")
		}
		if m := usingRe.FindStringSubmatch(trimmed); m != nil {
			f.Usings = append(f.Usings, Using{
				Namespace: m[2],
				Static:    m[1] != "",
				Global:    global,
			})
			continue
		}
		if f.Namespace == "" {
			if m := namespaceRe.FindStringSubmatch(trimmed); m != nil {
				f.Namespace = m[1]
			}
		}
	}

	usingSet := map[string]bool{}
	for _, u := range f.Usings {
		usingSet[u.Namespace] = true
	}
	for _, marker := range frameworkMarkers {
		if usingSet[marker.using] || marker.attrRe.MatchString(blanked) {
			f.Framework = marker.framework
			break
		}
	}

	switch {
	case entryPointRe.MatchString(blanked):
		f.HasEntryPoint = true
	case f.Namespace == "" && !typeDeclRe.MatchString(blanked):
		// Top-level statements: code outside any namespace or type
		// declaration. Lines that are using directives or attributes (e.g.
		// [assembly: ...]) do not count as statements.
		for _, line := range strings.Split(blanked, "\n") {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" || strings.HasPrefix(trimmed, "using ") ||
				strings.HasPrefix(trimmed, "global using ") || strings.HasPrefix(trimmed, "[") {
				continue
			}
			f.HasEntryPoint = true
			break
		}
	}

	return f, nil
}
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
go test ./dotnet/gazelle/private/parser/
```

Expected: `PASS` and `ok  	github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/parser`.

- [x] **Step 5: Commit**

```bash
git add dotnet/gazelle/private/parser/parser.go dotnet/gazelle/private/parser/parser_test.go
git commit -m "Add C# metadata extraction to the Gazelle parser"
```

### Task 7: NuGet index from packages.lock.json (TDD)

The `nuget` package indexes every package ID in `packages.lock.json` (Direct and Transitive dependencies alike) and resolves a namespace to a package ID by longest dot-segment prefix match.

**Files:**
- Create: `dotnet/gazelle/private/nuget/nuget.go`
- Test: `dotnet/gazelle/private/nuget/nuget_test.go`

- [x] **Step 1: Write the failing tests**

Create `dotnet/gazelle/private/nuget/nuget_test.go`:

```go
package nuget

import (
	"os"
	"path/filepath"
	"testing"
)

const testLock = `{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "Newtonsoft.Json": {
        "type": "Direct",
        "requested": "[13.0.3, )",
        "resolved": "13.0.3",
        "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
      },
      "Microsoft.Testing.Platform": {
        "type": "Transitive",
        "resolved": "1.4.3"
      }
    }
  }
}`

func writeLock(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "packages.lock.json")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadIndexAndResolve(t *testing.T) {
	idx, err := LoadIndex(writeLock(t, testLock))
	if err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		namespace string
		want      string
	}{
		{"Newtonsoft.Json", "newtonsoft.json"},
		{"Newtonsoft.Json.Linq", "newtonsoft.json"},
		{"Microsoft.Testing.Platform.Builder", "microsoft.testing.platform"},
		{"System", ""},
		{"Acme.Does.Not.Exist", ""},
	}
	for _, tc := range tests {
		got, err := idx.Resolve(tc.namespace)
		if err != nil {
			t.Fatalf("Resolve(%q) unexpected error: %v", tc.namespace, err)
		}
		if got != tc.want {
			t.Errorf("Resolve(%q) = %q, want %q", tc.namespace, got, tc.want)
		}
	}
}

func TestResolveAmbiguousCaseVariants(t *testing.T) {
	lock := `{"version": 1, "dependencies": {"net10.0": {"Contoso.Widget": {"type": "Direct"}, "contoso.widget": {"type": "Direct"}}}}`
	idx, err := LoadIndex(writeLock(t, lock))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := idx.Resolve("Contoso.Widget.Core"); err == nil {
		t.Fatal("Resolve() = nil error, want ambiguity error")
	}
}

func TestResolveNilIndex(t *testing.T) {
	var idx *Index
	got, err := idx.Resolve("Newtonsoft.Json")
	if err != nil || got != "" {
		t.Fatalf("nil index Resolve() = %q, %v; want \"\", nil", got, err)
	}
}

func TestLoadIndexInvalidJSON(t *testing.T) {
	if _, err := LoadIndex(writeLock(t, "not json")); err == nil {
		t.Fatal("LoadIndex() = nil error, want parse error")
	}
}
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
go test ./dotnet/gazelle/private/nuget/
```

Expected: FAIL with `undefined: LoadIndex` and `undefined: Index` (build failure).

- [x] **Step 3: Implement the index**

Create `dotnet/gazelle/private/nuget/nuget.go`:

```go
// Package nuget indexes the package IDs of a packages.lock.json file and
// resolves C# namespaces to package IDs by longest prefix match.
package nuget

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// lockFile mirrors the relevant structure of packages.lock.json:
// dependencies -> target framework -> package ID -> dependency entry.
// Only the package IDs (the map keys) are used.
type lockFile struct {
	Dependencies map[string]map[string]json.RawMessage `json:"dependencies"`
}

// Index resolves namespaces to NuGet package IDs. A nil *Index is valid and
// resolves nothing (used when no packages.lock.json exists).
type Index struct {
	// ids maps lowercased package IDs to their original forms. More than
	// one original form means the lock file lists case variants of the same
	// ID, which would collide in Bazel repo target names.
	ids map[string][]string
}

// LoadIndex reads packages.lock.json from path.
func LoadIndex(path string) (*Index, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var lf lockFile
	if err := json.Unmarshal(data, &lf); err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}
	idx := &Index{ids: map[string][]string{}}
	for _, deps := range lf.Dependencies {
		for id := range deps {
			lower := strings.ToLower(id)
			idx.ids[lower] = appendUnique(idx.ids[lower], id)
		}
	}
	return idx, nil
}

// Resolve maps namespace to a NuGet package ID by longest dot-segment
// prefix match ("Newtonsoft.Json.Linq" -> "Newtonsoft.Json"). The returned
// ID is lowercased, matching the repo target names that the nuget hub
// repository generates. It returns "" when no package ID matches, and an
// error when the match is ambiguous (case variants of the same ID).
func (i *Index) Resolve(namespace string) (string, error) {
	if i == nil {
		return "", nil
	}
	for prefix := strings.ToLower(namespace); prefix != ""; prefix = parentPrefix(prefix) {
		originals, ok := i.ids[prefix]
		if !ok {
			continue
		}
		if len(originals) > 1 {
			return "", fmt.Errorf("namespace %q matches multiple package IDs (%s)", namespace, strings.Join(originals, ", "))
		}
		return prefix, nil
	}
	return "", nil
}

// parentPrefix strips the last dot segment: "A.B.C" -> "A.B", "A" -> "".
func parentPrefix(ns string) string {
	i := strings.LastIndex(ns, ".")
	if i < 0 {
		return ""
	}
	return ns[:i]
}

func appendUnique(s []string, v string) []string {
	for _, e := range s {
		if e == v {
			return s
		}
	}
	return append(s, v)
}
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
go test ./dotnet/gazelle/private/nuget/
```

Expected: `PASS` and `ok  	github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/nuget`.

- [x] **Step 5: Commit**

```bash
git add dotnet/gazelle/private/nuget/nuget.go dotnet/gazelle/private/nuget/nuget_test.go
git commit -m "Add packages.lock.json NuGet index for the Gazelle extension"
```

### Task 8: dotnetconfig — per-directory configuration (TDD)

The `dotnetconfig` package holds the directive-driven configuration for one Bazel package, with inheritance down the directory tree (mirroring `javaconfig` in rules_jvm). It is stdlib-only, so it still builds before the gazelle dependency is added in Task 9.

**Files:**
- Create: `dotnet/gazelle/dotnetconfig/config.go`
- Test: `dotnet/gazelle/dotnetconfig/config_test.go`

- [x] **Step 1: Write the failing tests**

Create `dotnet/gazelle/dotnetconfig/config_test.go`:

```go
package dotnetconfig

import (
	"reflect"
	"testing"
)

func TestDefaults(t *testing.T) {
	c := New("/repo")
	if got := c.NugetRepoPrefix(); got != "nuget." {
		t.Errorf("NugetRepoPrefix() = %q, want %q", got, "nuget.")
	}
	if !c.GenerateBinary() {
		t.Error("GenerateBinary() = false, want true")
	}
	if got := c.ProjectSdk(); got != "default" {
		t.Errorf("ProjectSdk() = %q, want %q", got, "default")
	}
	if got := c.UnresolvedImports(); got != "warn" {
		t.Errorf("UnresolvedImports() = %q, want %q", got, "warn")
	}
	if got := c.NugetLockFile(); got != "packages.lock.json" {
		t.Errorf("NugetLockFile() = %q, want %q", got, "packages.lock.json")
	}
	if got := c.Visibility(); !reflect.DeepEqual(got, []string{"//visibility:public"}) {
		t.Errorf("Visibility() = %v, want [//visibility:public]", got)
	}
	if got := c.TargetFrameworks(); len(got) != 0 {
		t.Errorf("TargetFrameworks() = %v, want empty", got)
	}
	if got := c.TestFramework(); got != "" {
		t.Errorf("TestFramework() = %q, want empty", got)
	}
}

func TestNewChildInheritsAndIsolates(t *testing.T) {
	root := New("/repo")
	root.SetTargetFrameworks("net10.0")
	root.AddVisibility("//visibility:private")
	if err := root.AddResolve("Acme.Widget @acme//widget"); err != nil {
		t.Fatal(err)
	}

	child := root.NewChild()
	if got := child.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net10.0"}) {
		t.Errorf("child TargetFrameworks() = %v, want [net10.0]", got)
	}
	if got := child.Visibility(); !reflect.DeepEqual(got, []string{"//visibility:private"}) {
		t.Errorf("child Visibility() = %v, want [//visibility:private]", got)
	}
	if lbl, ok := child.ResolveOverride("Acme.Widget"); !ok || lbl != "@acme//widget" {
		t.Errorf("child ResolveOverride() = %q, %v; want @acme//widget, true", lbl, ok)
	}

	// Mutating the child must not leak into the parent.
	child.SetTargetFrameworks("net9.0")
	child.AddVisibility("//other:__pkg__")
	if err := child.AddResolve("Other.Ns //other"); err != nil {
		t.Fatal(err)
	}
	if got := root.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net10.0"}) {
		t.Errorf("root TargetFrameworks() = %v after child mutation, want [net10.0]", got)
	}
	if got := root.Visibility(); !reflect.DeepEqual(got, []string{"//visibility:private"}) {
		t.Errorf("root Visibility() = %v after child mutation, want [//visibility:private]", got)
	}
	if _, ok := root.ResolveOverride("Other.Ns"); ok {
		t.Error("root ResolveOverride(Other.Ns) = true after child mutation, want false")
	}
}

func TestAddResolveValidation(t *testing.T) {
	c := New("/repo")
	if err := c.AddResolve("justonefield"); err == nil {
		t.Error("AddResolve(justonefield) = nil error, want error")
	}
	if err := c.AddResolve("a b c"); err == nil {
		t.Error("AddResolve(a b c) = nil error, want error")
	}
	if err := c.AddResolve("Ns //label"); err != nil {
		t.Errorf("AddResolve(Ns //label) = %v, want nil", err)
	}
}

func TestSetTestFrameworkValidation(t *testing.T) {
	c := New("/repo")
	for _, fw := range []string{"nunit", "xunit", "mstest"} {
		if err := c.SetTestFramework(fw); err != nil {
			t.Errorf("SetTestFramework(%q) = %v, want nil", fw, err)
		}
	}
	if err := c.SetTestFramework("junit"); err == nil {
		t.Error("SetTestFramework(junit) = nil error, want error")
	}
}

func TestSetUnresolvedImportsValidation(t *testing.T) {
	c := New("/repo")
	for _, v := range []string{"warn", "error"} {
		if err := c.SetUnresolvedImports(v); err != nil {
			t.Errorf("SetUnresolvedImports(%q) = %v, want nil", v, err)
		}
	}
	if err := c.SetUnresolvedImports("fail"); err == nil {
		t.Error("SetUnresolvedImports(fail) = nil error, want error")
	}
}

func TestSetTargetFrameworks(t *testing.T) {
	c := New("/repo")
	c.SetTargetFrameworks("net10.0, net9.0")
	if got := c.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net10.0", "net9.0"}) {
		t.Errorf("TargetFrameworks() = %v, want [net10.0 net9.0]", got)
	}
	// Reset semantics: a later directive replaces the list.
	c.SetTargetFrameworks("net8.0")
	if got := c.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net8.0"}) {
		t.Errorf("TargetFrameworks() = %v after reset, want [net8.0]", got)
	}
}

func TestNugetLabel(t *testing.T) {
	c := New("/repo")
	c.SetTargetFrameworks("net10.0")
	if got := c.NugetLabel("Newtonsoft.Json"); got != "@nuget.net10.0//newtonsoft.json" {
		t.Errorf("NugetLabel() = %q, want @nuget.net10.0//newtonsoft.json", got)
	}
	c.SetNugetRepoPrefix("custom.")
	if got := c.NugetLabel("Newtonsoft.Json"); got != "@custom.net10.0//newtonsoft.json" {
		t.Errorf("NugetLabel() = %q, want @custom.net10.0//newtonsoft.json", got)
	}
}

func TestParentForPackage(t *testing.T) {
	root := New("/repo")
	cfgs := Configs{"": root}
	if got := cfgs.ParentForPackage("src"); got != root {
		t.Error("ParentForPackage(src) != root config")
	}
	child := root.NewChild()
	cfgs["src"] = child
	if got := cfgs.ParentForPackage("src/app"); got != child {
		t.Error("ParentForPackage(src/app) != child config")
	}
}
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
go test ./dotnet/gazelle/dotnetconfig/
```

Expected: FAIL with `undefined: New`, `undefined: Configs` (build failure).

- [x] **Step 3: Implement dotnetconfig**

Create `dotnet/gazelle/dotnetconfig/config.go`:

```go
// Package dotnetconfig holds the per-directory configuration of the C#
// Gazelle extension: directive values, inherited down the directory tree.
package dotnetconfig

import (
	"fmt"
	"maps"
	"path"
	"strings"
)

// Directive names.
const (
	// DotnetTargetFrameworks sets the target framework(s) of generated
	// targets. Comma-separated. Required at the repository root.
	DotnetTargetFrameworks = "dotnet_target_frameworks"
	// DotnetNugetRepoPrefix sets the repository prefix of NuGet labels.
	// Defaults to "nuget.".
	DotnetNugetRepoPrefix = "dotnet_nuget_repo_prefix"
	// DotnetResolve maps a namespace to a Bazel label:
	// "# gazelle:dotnet_resolve <namespace> <label>". Repeatable.
	DotnetResolve = "dotnet_resolve"
	// DotnetTestFramework forces the test framework of detected test files:
	// "nunit", "xunit" or "mstest". Empty means auto-detect.
	DotnetTestFramework = "dotnet_test_framework"
	// DotnetGenerateBinary toggles csharp_binary generation: "true"/"false".
	// Defaults to "true".
	DotnetGenerateBinary = "dotnet_generate_binary"
	// DotnetProjectSdk sets the project_sdk attr of generated targets.
	// Defaults to "default".
	DotnetProjectSdk = "dotnet_project_sdk"
	// DotnetVisibility adds a visibility entry to generated targets.
	// Repeatable. Defaults to "//visibility:public".
	DotnetVisibility = "dotnet_visibility"
	// DotnetUnresolvedImports controls unresolved imports: "warn" or "error".
	// Defaults to "warn".
	DotnetUnresolvedImports = "dotnet_unresolved_imports"
)

// Configs maps Bazel package paths to their Config.
type Configs map[string]*Config

// ParentForPackage returns the Config of the parent Bazel package.
func (c *Configs) ParentForPackage(pkg string) *Config {
	dir := path.Dir(pkg)
	if dir == "." {
		dir = ""
	}
	return (map[string]*Config)(*c)[dir]
}

// Config is the extension configuration for one Bazel package.
type Config struct {
	repoRoot          string
	targetFrameworks  []string
	nugetRepoPrefix   string
	resolves          map[string]string
	testFramework     string
	generateBinary    bool
	projectSdk        string
	visibility        []string
	unresolvedImports string
	nugetLockFile     string
}

// New returns the root Config with default values.
func New(repoRoot string) *Config {
	return &Config{
		repoRoot:          repoRoot,
		nugetRepoPrefix:   "nuget.",
		resolves:          map[string]string{},
		generateBinary:    true,
		projectSdk:        "default",
		unresolvedImports: "warn",
		nugetLockFile:     "packages.lock.json",
	}
}

// NewChild returns a child Config that inherits all values. Maps and lists
// are cloned so child changes never leak into the parent.
func (c *Config) NewChild() *Config {
	child := *c
	child.targetFrameworks = append([]string(nil), c.targetFrameworks...)
	child.resolves = maps.Clone(c.resolves)
	child.visibility = append([]string(nil), c.visibility...)
	return &child
}

// TargetFrameworks returns the configured target frameworks.
func (c *Config) TargetFrameworks() []string { return c.targetFrameworks }

// SetTargetFrameworks parses a comma-separated list of TFMs, replacing any
// previously set list.
func (c *Config) SetTargetFrameworks(value string) {
	c.targetFrameworks = nil
	for _, tfm := range strings.Split(value, ",") {
		if tfm = strings.TrimSpace(tfm); tfm != "" {
			c.targetFrameworks = append(c.targetFrameworks, tfm)
		}
	}
}

// NugetRepoPrefix returns the repository prefix for NuGet labels.
func (c *Config) NugetRepoPrefix() string { return c.nugetRepoPrefix }

// SetNugetRepoPrefix sets the repository prefix for NuGet labels.
func (c *Config) SetNugetRepoPrefix(prefix string) { c.nugetRepoPrefix = prefix }

// AddResolve parses "<namespace> <label>" and records the override.
func (c *Config) AddResolve(value string) error {
	parts := strings.Fields(value)
	if len(parts) != 2 {
		return fmt.Errorf("expected \"<namespace> <label>\", got %q", value)
	}
	c.resolves[parts[0]] = parts[1]
	return nil
}

// ResolveOverride returns the label override for namespace, if any.
func (c *Config) ResolveOverride(namespace string) (string, bool) {
	l, ok := c.resolves[namespace]
	return l, ok
}

// TestFramework returns the forced test framework, "" for auto-detect.
func (c *Config) TestFramework() string { return c.testFramework }

// SetTestFramework validates and sets the forced test framework.
func (c *Config) SetTestFramework(value string) error {
	switch value {
	case "nunit", "xunit", "mstest":
		c.testFramework = value
		return nil
	}
	return fmt.Errorf("possible values are nunit/xunit/mstest, got %q", value)
}

// GenerateBinary returns whether csharp_binary rules are generated.
func (c *Config) GenerateBinary() bool { return c.generateBinary }

// SetGenerateBinary sets whether csharp_binary rules are generated.
func (c *Config) SetGenerateBinary(v bool) { c.generateBinary = v }

// ProjectSdk returns the project_sdk attr value for generated targets.
func (c *Config) ProjectSdk() string { return c.projectSdk }

// SetProjectSdk sets the project_sdk attr value for generated targets.
func (c *Config) SetProjectSdk(v string) { c.projectSdk = v }

// AddVisibility appends a visibility entry.
func (c *Config) AddVisibility(v string) { c.visibility = append(c.visibility, v) }

// Visibility returns the configured visibility, defaulting to public.
func (c *Config) Visibility() []string {
	if len(c.visibility) == 0 {
		return []string{"//visibility:public"}
	}
	return c.visibility
}

// UnresolvedImports returns "warn" or "error".
func (c *Config) UnresolvedImports() string { return c.unresolvedImports }

// SetUnresolvedImports validates and sets unresolved-import handling.
func (c *Config) SetUnresolvedImports(value string) error {
	switch value {
	case "warn", "error":
		c.unresolvedImports = value
		return nil
	}
	return fmt.Errorf("possible values are warn/error, got %q", value)
}

// NugetLockFile returns the packages.lock.json path relative to the repo root.
func (c *Config) NugetLockFile() string { return c.nugetLockFile }

// SetNugetLockFile sets the packages.lock.json path relative to the repo root.
func (c *Config) SetNugetLockFile(v string) { c.nugetLockFile = v }

// NugetLabel returns the label of a NuGet package:
// "@<repo prefix><first target framework>//<lowercase package id>".
// It must only be called when TargetFrameworks() is non-empty.
func (c *Config) NugetLabel(packageID string) string {
	return fmt.Sprintf("@%s%s//%s", c.nugetRepoPrefix, c.targetFrameworks[0], strings.ToLower(packageID))
}
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
go test ./dotnet/gazelle/dotnetconfig/
```

Expected: `PASS` and `ok  	github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/dotnetconfig`.

- [x] **Step 5: Commit**

```bash
git add dotnet/gazelle/dotnetconfig/config.go dotnet/gazelle/dotnetconfig/config_test.go
git commit -m "Add dotnetconfig for the Gazelle extension"
```

### Task 9: Language wiring — lang/configure/resolve (TDD)

The `dotnet/gazelle` package ties everything together: `NewLanguage()` returns the `language.Language` implementation Gazelle looks for. This task adds `constants.go`, `lang.go`, `configure.go`, `resolve.go` (with a stub `GenerateRules`, replaced in Task 10), adds the bazel-gazelle dependency to `go.mod`, and generates the first BUILD files for the Go code.

**Files:**
- Create: `dotnet/gazelle/constants.go`
- Create: `dotnet/gazelle/lang.go`
- Create: `dotnet/gazelle/configure.go`
- Create: `dotnet/gazelle/resolve.go`
- Create: `dotnet/gazelle/generate.go` (stub; full implementation in Task 10)
- Test: `dotnet/gazelle/lang_test.go`, `dotnet/gazelle/resolve_test.go`
- Modify: `go.mod`; create: `go.sum` (via `go mod tidy`)
- Create (generated by gazelle): `dotnet/gazelle/BUILD.bazel`, `dotnet/gazelle/dotnetconfig/BUILD.bazel`, `dotnet/gazelle/private/parser/BUILD.bazel`, `dotnet/gazelle/private/nuget/BUILD.bazel`

- [x] **Step 1: Write the failing tests**

Create `dotnet/gazelle/lang_test.go`:

```go
package gazelle

import (
	"reflect"
	"testing"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

func TestNewLanguageKindsAndLoads(t *testing.T) {
	l := NewLanguage()
	kinds := l.Kinds()
	for _, want := range []string{
		"csharp_library",
		"csharp_binary",
		"csharp_test",
		"csharp_nunit_test",
		"csharp_xunit_test",
		"csharp_mstest_test",
	} {
		if _, ok := kinds[want]; !ok {
			t.Errorf("Kinds() missing %q", want)
		}
	}
	loads := l.Loads()
	if len(loads) != 1 || loads[0].Name != "@rules_dotnet//dotnet:defs.bzl" {
		t.Errorf("Loads() = %+v, want a single load from @rules_dotnet//dotnet:defs.bzl", loads)
	}
}

func TestApparentLoads(t *testing.T) {
	l := NewLanguage().(*csharpLang)

	loads := l.ApparentLoads(func(module string) string {
		if module == "rules_dotnet" {
			return "my_dotnet"
		}
		return ""
	})
	if len(loads) != 1 || loads[0].Name != "@my_dotnet//dotnet:defs.bzl" {
		t.Errorf("ApparentLoads() = %+v, want @my_dotnet//dotnet:defs.bzl", loads)
	}

	loads = l.ApparentLoads(func(string) string { return "" })
	if len(loads) != 1 || loads[0].Name != "@rules_dotnet//dotnet:defs.bzl" {
		t.Errorf("ApparentLoads() fallback = %+v, want @rules_dotnet//dotnet:defs.bzl", loads)
	}
}

func TestImportsIndexesLibraryNamespaces(t *testing.T) {
	l := NewLanguage().(*csharpLang)
	res := l.Resolver
	f := rule.EmptyFile("src/calculator/BUILD.bazel", "src/calculator")

	lib := rule.NewRule("csharp_library", "calculator")
	lib.SetPrivateAttr(namespacesKey, []string{"Calculator", "Calculator.Util"})
	specs := res.Imports(config.New(), lib, f)
	if len(specs) != 2 {
		t.Fatalf("Imports() = %v, want 2 specs", specs)
	}
	for i, want := range []string{"Calculator", "Calculator.Util"} {
		if specs[i].Lang != "csharp" || specs[i].Imp != want {
			t.Errorf("specs[%d] = %+v, want {Lang: csharp, Imp: %s}", i, specs[i], want)
		}
	}

	if got := res.Imports(config.New(), rule.NewRule("csharp_binary", "b"), f); got != nil {
		t.Errorf("Imports(csharp_binary) = %v, want nil", got)
	}
}

func TestConfigureInheritance(t *testing.T) {
	_, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/app")
	cfg := getConfig(c, "src/app")
	if cfg == nil {
		t.Fatal("no config for src/app")
	}
	if got := cfg.TargetFrameworks(); !reflect.DeepEqual(got, []string{"net10.0"}) {
		t.Errorf("TargetFrameworks() = %v, want [net10.0]", got)
	}
}
```

Create `dotnet/gazelle/resolve_test.go`:

```go
package gazelle

import (
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"testing"

	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/nuget"
	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// setupLang returns a language instance configured for the root (with the
// given directives) and for each package in rels, plus the temp repo root.
func setupLang(t *testing.T, rootDirectives string, rels ...string) (*csharpLang, *config.Config, string) {
	t.Helper()
	dir := t.TempDir()
	c := config.New()
	c.RepoRoot = dir
	l := NewLanguage().(*csharpLang)

	f, err := rule.LoadData(filepath.Join(dir, "BUILD.bazel"), "", []byte(rootDirectives))
	if err != nil {
		t.Fatal(err)
	}
	l.Configure(c, "", f)
	for _, rel := range rels {
		l.Configure(c, rel, nil)
	}
	return l, c, dir
}

func writeFile(t *testing.T, dir, name, content string) {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// indexLibrary indexes a csharp_library named name in package pkg providing
// the given namespaces.
func indexLibrary(t *testing.T, l *csharpLang, c *config.Config, ix *resolve.RuleIndex, pkg, name string, namespaces ...string) {
	t.Helper()
	f := rule.EmptyFile(pkg+"/BUILD.bazel", pkg)
	r := rule.NewRule("csharp_library", name)
	r.SetPrivateAttr(namespacesKey, namespaces)
	ix.AddRule(c, r, f)
}

func TestResolveNamespaces(t *testing.T) {
	l, c, dir := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/app")
	writeFile(t, dir, "packages.lock.json", `{"version": 1, "dependencies": {"net10.0": {"Newtonsoft.Json": {"type": "Direct", "resolved": "13.0.3"}}}}`)
	idx, err := nuget.LoadIndex(filepath.Join(dir, "packages.lock.json"))
	if err != nil {
		t.Fatal(err)
	}
	l.nugetIndex = idx

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_binary", "program")
	input := resolveInput{
		imports: []string{"Calculator", "Newtonsoft.Json.Linq", "System", "Acme.Does.Not.Exist"},
		own:     []string{"App"},
	}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "program"))

	got := r.AttrStrings("deps")
	want := []string{"//src/calculator", "@nuget.net10.0//newtonsoft.json"}
	sort.Strings(want)
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v", got, want)
	}
}

func TestResolveOverride(t *testing.T) {
	l, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n# gazelle:dotnet_resolve Acme.Widget @acme//widget\n", "src", "src/app")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	ix.Finish()

	r := rule.NewRule("csharp_library", "app")
	input := resolveInput{imports: []string{"Acme.Widget"}, own: []string{"App"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app"))

	if got := r.AttrStrings("deps"); !reflect.DeepEqual(got, []string{"@acme//widget"}) {
		t.Errorf("deps = %v, want [@acme//widget]", got)
	}
}

func TestResolveKeepsExistingDepsAndSimplifiesSamePackage(t *testing.T) {
	l, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/calculator")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_nunit_test", "calculator_nunit_test")
	r.SetAttr("deps", []string{":calculator", "//manual:dep"})
	input := resolveInput{imports: []string{"Calculator"}, own: []string{"Calculator.Tests"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator_nunit_test"))

	got := r.AttrStrings("deps")
	want := []string{"//manual:dep", ":calculator"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v", got, want)
	}
}

func TestResolveSkipsSelfImport(t *testing.T) {
	l, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/calculator")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_library", "calculator")
	input := resolveInput{imports: []string{"Calculator"}, own: []string{"Calculator"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator"))

	if got := r.AttrStrings("deps"); len(got) != 0 {
		t.Errorf("deps = %v, want empty", got)
	}
}
```

- [x] **Step 2: Add the bazel-gazelle dependency and tidy**

Edit `go.mod`. Old:

```
module github.com/bazel-contrib/rules_dotnet

go 1.24.12
```

New:

```
module github.com/bazel-contrib/rules_dotnet

go 1.24.12

require github.com/bazelbuild/bazel-gazelle v0.51.3
```

Run (env exports assumed):

```bash
go mod tidy
```

Expected: exit code 0, `go.sum` created, and the require line kept in `go.mod` (possibly with added `// indirect` requires). Verify:

```bash
grep "bazel-gazelle v0.51.3" go.mod go.sum | head -3
```

Expected: at least one matching line in each of `go.mod` and `go.sum`.

- [x] **Step 3: Run the tests to verify they fail**

```bash
go test ./dotnet/gazelle/
```

Expected: FAIL — a build failure, because `dotnet/gazelle` has no non-test Go files yet and the test files reference not-yet-existing symbols (`NewLanguage`, `csharpLang`, `namespacesKey`, `resolveInput`, `getConfig`). Any error of the form "no non-test Go files" or "undefined: ..." confirms the red state.

- [x] **Step 4: Implement constants.go, lang.go and generate.go stub**

Create `dotnet/gazelle/constants.go`:

```go
package gazelle

// languageName is the name of this Gazelle language extension and the prefix
// of the rule kinds it generates.
const languageName = "csharp"

// namespacesKey is the private attribute under which generated csharp_library
// rules carry the namespaces their sources declare, so that Imports can
// index them.
const namespacesKey = "csharp_namespaces"
```

Create `dotnet/gazelle/lang.go`:

```go
// Package gazelle implements a Gazelle language extension for C#: it
// generates and maintains BUILD files for rules_dotnet's csharp rules.
package gazelle

import (
	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/dotnetconfig"
	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/nuget"
	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/language"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// csharpLang is the language.Language implementation for C#.
type csharpLang struct {
	config.Configurer
	language.BaseLifecycleManager
	resolve.Resolver

	// nugetIndex resolves namespaces to NuGet package IDs. It is loaded once
	// from packages.lock.json during Configure of the repository root and is
	// nil when the file does not exist.
	nugetIndex *nuget.Index
}

// NewLanguage is the entry point Gazelle looks for in a language extension.
func NewLanguage() language.Language {
	l := &csharpLang{}
	l.Configurer = NewConfigurer(l)
	l.Resolver = NewResolver(l)
	return l
}

var csharpKindInfo = rule.KindInfo{
	NonEmptyAttrs:  map[string]bool{"srcs": true, "deps": true},
	MergeableAttrs: map[string]bool{"srcs": true},
	ResolveAttrs:   map[string]bool{"deps": true},
}

// csharpKinds are all rule kinds this extension generates or maintains.
var csharpKinds = []string{
	"csharp_library",
	"csharp_binary",
	"csharp_test",
	"csharp_nunit_test",
	"csharp_xunit_test",
	"csharp_mstest_test",
}

// defsBzlSymbols are the symbols this extension loads from defs.bzl, sorted.
var defsBzlSymbols = []string{
	"csharp_binary",
	"csharp_library",
	"csharp_mstest_test",
	"csharp_nunit_test",
	"csharp_test",
	"csharp_xunit_test",
}

// Kinds implements language.Language.
func (l *csharpLang) Kinds() map[string]rule.KindInfo {
	kinds := map[string]rule.KindInfo{}
	for _, kind := range csharpKinds {
		kinds[kind] = csharpKindInfo
	}
	return kinds
}

// Loads implements language.Language.
func (l *csharpLang) Loads() []rule.LoadInfo {
	return []rule.LoadInfo{{
		Name:    "@rules_dotnet//dotnet:defs.bzl",
		Symbols: defsBzlSymbols,
	}}
}

// ApparentLoads implements language.ModuleAwareLanguage.
func (l *csharpLang) ApparentLoads(moduleToApparentName func(string) string) []rule.LoadInfo {
	apparent := moduleToApparentName("rules_dotnet")
	if apparent == "" {
		apparent = "rules_dotnet"
	}
	return []rule.LoadInfo{{
		Name:    "@" + apparent + "//dotnet:defs.bzl",
		Symbols: defsBzlSymbols,
	}}
}

// Fix implements language.Language.
func (l *csharpLang) Fix(c *config.Config, f *rule.File) {}

// getConfig returns the dotnetconfig for a package, or nil when the
// extension has not been configured for it.
func getConfig(c *config.Config, pkg string) *dotnetconfig.Config {
	cfgs, ok := c.Exts[languageName].(dotnetconfig.Configs)
	if !ok {
		return nil
	}
	return cfgs[pkg]
}
```

Create `dotnet/gazelle/generate.go` (stub; Task 10 replaces the function body):

```go
package gazelle

import (
	"github.com/bazelbuild/bazel-gazelle/language"
)

// GenerateRules implements language.Language. Rule generation is added on
// top of this skeleton in a later step; until then no rules are generated.
func (l *csharpLang) GenerateRules(args language.GenerateArgs) language.GenerateResult {
	return language.GenerateResult{}
}
```

- [x] **Step 5: Implement configure.go**

Create `dotnet/gazelle/configure.go`:

```go
package gazelle

import (
	"flag"
	"log"
	"os"
	"path/filepath"

	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/dotnetconfig"
	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/nuget"
	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// Configurer satisfies config.Configurer for the C# extension.
type Configurer struct {
	lang *csharpLang

	// nugetLockFile is the value of the -dotnet_nuget_lock_file flag.
	nugetLockFile string
}

// NewConfigurer creates the Configurer for l.
func NewConfigurer(lang *csharpLang) *Configurer {
	return &Configurer{lang: lang}
}

// RegisterFlags implements config.Configurer.
func (cr *Configurer) RegisterFlags(fs *flag.FlagSet, cmd string, c *config.Config) {
	fs.StringVar(&cr.nugetLockFile, "dotnet_nuget_lock_file", "packages.lock.json",
		"Path of the packages.lock.json file, relative to the repository root.")
}

// CheckFlags implements config.Configurer.
func (cr *Configurer) CheckFlags(fs *flag.FlagSet, c *config.Config) error {
	cfgs := cr.initRootConfig(c)
	cfgs[""].SetNugetLockFile(cr.nugetLockFile)
	return nil
}

// KnownDirectives implements config.Configurer.
func (cr *Configurer) KnownDirectives() []string {
	return []string{
		dotnetconfig.DotnetTargetFrameworks,
		dotnetconfig.DotnetNugetRepoPrefix,
		dotnetconfig.DotnetResolve,
		dotnetconfig.DotnetTestFramework,
		dotnetconfig.DotnetGenerateBinary,
		dotnetconfig.DotnetProjectSdk,
		dotnetconfig.DotnetVisibility,
		dotnetconfig.DotnetUnresolvedImports,
	}
}

func (cr *Configurer) initRootConfig(c *config.Config) dotnetconfig.Configs {
	if _, exists := c.Exts[languageName]; !exists {
		c.Exts[languageName] = dotnetconfig.Configs{
			"": dotnetconfig.New(c.RepoRoot),
		}
	}
	return c.Exts[languageName].(dotnetconfig.Configs)
}

// Configure implements config.Configurer.
func (cr *Configurer) Configure(c *config.Config, rel string, f *rule.File) {
	cfgs := cr.initRootConfig(c)
	cfg, exists := cfgs[rel]
	if !exists {
		parent := cfgs.ParentForPackage(rel)
		if parent == nil {
			log.Fatalf("no dotnet config found for parent of package %s", rel)
		}
		cfg = parent.NewChild()
		cfgs[rel] = cfg
	}

	if f != nil {
		for _, d := range f.Directives {
			switch d.Key {
			case dotnetconfig.DotnetTargetFrameworks:
				cfg.SetTargetFrameworks(d.Value)
			case dotnetconfig.DotnetNugetRepoPrefix:
				cfg.SetNugetRepoPrefix(d.Value)
			case dotnetconfig.DotnetResolve:
				if err := cfg.AddResolve(d.Value); err != nil {
					log.Fatalf("invalid value for directive %q: %s: %v", dotnetconfig.DotnetResolve, d.Value, err)
				}
			case dotnetconfig.DotnetTestFramework:
				if err := cfg.SetTestFramework(d.Value); err != nil {
					log.Fatalf("invalid value for directive %q: %v", dotnetconfig.DotnetTestFramework, err)
				}
			case dotnetconfig.DotnetGenerateBinary:
				switch d.Value {
				case "true":
					cfg.SetGenerateBinary(true)
				case "false":
					cfg.SetGenerateBinary(false)
				default:
					log.Fatalf("invalid value for directive %q: %s: possible values are true/false", dotnetconfig.DotnetGenerateBinary, d.Value)
				}
			case dotnetconfig.DotnetProjectSdk:
				cfg.SetProjectSdk(d.Value)
			case dotnetconfig.DotnetVisibility:
				cfg.AddVisibility(d.Value)
			case dotnetconfig.DotnetUnresolvedImports:
				if err := cfg.SetUnresolvedImports(d.Value); err != nil {
					log.Fatalf("invalid value for directive %q: %v", dotnetconfig.DotnetUnresolvedImports, err)
				}
			}
		}
	}

	if rel != "" {
		return
	}

	// Root package: load the NuGet index once and require target frameworks.
	if cr.lang.nugetIndex == nil {
		lockPath := filepath.Join(c.RepoRoot, cfg.NugetLockFile())
		index, err := nuget.LoadIndex(lockPath)
		switch {
		case err == nil:
			cr.lang.nugetIndex = index
		case os.IsNotExist(err):
			log.Printf("no packages.lock.json at %s; NuGet resolution is disabled", lockPath)
		default:
			log.Fatalf("error loading %s: %v", lockPath, err)
		}
	}
	if len(cfg.TargetFrameworks()) == 0 {
		log.Fatalf("missing directive: add '# gazelle:%s <tfm>[,<tfm>...]' to the root BUILD file", dotnetconfig.DotnetTargetFrameworks)
	}
}
```

- [x] **Step 6: Implement resolve.go**

Create `dotnet/gazelle/resolve.go`:

```go
package gazelle

import (
	"fmt"
	"log"
	"sort"
	"strings"

	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/dotnetconfig"
	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/label"
	"github.com/bazelbuild/bazel-gazelle/repo"
	"github.com/bazelbuild/bazel-gazelle/resolve"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

// resolveInput carries a generated rule's imports from the generate phase to
// the resolve phase (via language.GenerateResult.Imports).
type resolveInput struct {
	// imports are the namespaces imported by the rule's sources, sorted.
	imports []string
	// own are the namespaces declared by the rule's sources, sorted.
	own []string
}

// Resolver satisfies resolve.Resolver for C#.
type Resolver struct {
	lang *csharpLang
}

// NewResolver creates the Resolver for l.
func NewResolver(lang *csharpLang) *Resolver {
	return &Resolver{lang: lang}
}

// Name implements resolve.Resolver.
func (*Resolver) Name() string { return languageName }

// Imports implements resolve.Resolver. Every generated csharp_library is
// indexed by the namespaces its sources declare; other rules are not
// indexed.
func (r *Resolver) Imports(c *config.Config, ru *rule.Rule, f *rule.File) []resolve.ImportSpec {
	if ru.Kind() != "csharp_library" {
		return nil
	}
	namespaces, _ := ru.PrivateAttr(namespacesKey).([]string)
	specs := make([]resolve.ImportSpec, 0, len(namespaces))
	for _, ns := range namespaces {
		specs = append(specs, resolve.ImportSpec{Lang: languageName, Imp: ns})
	}
	return specs
}

// Embeds implements resolve.Resolver. C# rules do not embed.
func (*Resolver) Embeds(r *rule.Rule, from label.Label) []label.Label { return nil }

// Resolve implements resolve.Resolver. It unions the resolved labels into
// the rule's deps attribute, preserving labels that are already there (the
// sibling dep set at generate time, and manually maintained deps).
func (r *Resolver) Resolve(c *config.Config, ix *resolve.RuleIndex, rc *repo.RemoteCache, ru *rule.Rule, imports interface{}, from label.Label) {
	input, ok := imports.(resolveInput)
	if !ok {
		return
	}
	cfg := getConfig(c, from.Pkg)
	if cfg == nil {
		log.Fatalf("no dotnet config found for package %s", from.Pkg)
	}

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

	sorted := make([]string, 0, len(deps))
	for d := range deps {
		sorted = append(sorted, d)
	}
	sort.Strings(sorted)
	ru.DelAttr("deps")
	if len(sorted) > 0 {
		ru.SetAttr("deps", sorted)
	}
}

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
		switch {
		case l.Repo == "" && l.Pkg == from.Pkg:
			l = label.Label{Name: l.Name, Relative: true}
		case l.Repo == c.RepoName:
			l.Repo = ""
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

// parentNamespace strips the last dot segment: "A.B.C" -> "A.B", "A" -> "".
func parentNamespace(ns string) string {
	i := strings.LastIndex(ns, ".")
	if i < 0 {
		return ""
	}
	return ns[:i]
}
```

- [x] **Step 7: Run the tests to verify they pass**

```bash
go mod tidy && go test ./dotnet/gazelle/...
```

Expected: `go mod tidy` makes no changes (exit 0); all four packages report `ok` (gazelle, dotnetconfig, nuget, parser) with `PASS`.

- [x] **Step 8: Generate BUILD files for the Go code**

Run (env exports assumed):

```bash
bazel run //:gazelle
```

Expected: exit code 0. Verify the generated BUILD files:

```bash
git status --porcelain
```

Expected new files: `dotnet/gazelle/BUILD.bazel`, `dotnet/gazelle/dotnetconfig/BUILD.bazel`, `dotnet/gazelle/private/nuget/BUILD.bazel`, `dotnet/gazelle/private/parser/BUILD.bazel`. Possibly modified: `dotnet/BUILD.bazel`, `dotnet/private/**/BUILD.bazel` (pre-existing drift).

Check key content of the main generated file:

```bash
grep -e 'importpath = "github.com/bazel-contrib/rules_dotnet/dotnet/gazelle"' -e '"@bazel_gazelle//language",' -e '"@bazel_gazelle//resolve",' -e 'embed = \[":gazelle"\]' dotnet/gazelle/BUILD.bazel
```

Expected: all four patterns print a match line (the go_library `gazelle` with the gazelle framework deps, and a `go_test` embedding it). The bazel-gazelle deps must appear as `@bazel_gazelle//<pkg>` with no `:go_default_library` suffix.

Revert the pre-existing drift (see Environment notes):

```bash
git diff --name-only -- dotnet/BUILD.bazel dotnet/private | xargs -r git checkout --
```

- [x] **Step 9: Run the Go tests under Bazel**

```bash
bazel test //dotnet/gazelle/...
```

Expected: 4 test targets pass: `//dotnet/gazelle:gazelle_test`, `//dotnet/gazelle/dotnetconfig:dotnetconfig_test`, `//dotnet/gazelle/private/nuget:nuget_test`, `//dotnet/gazelle/private/parser:parser_test`.

- [x] **Step 10: Commit**

```bash
git add go.mod go.sum dotnet/gazelle
git commit -m "Add Gazelle language wiring for C# (configure and resolve)"
```

### Task 10: Rule generation (TDD)

> **Known limitation (user-approved, after review of commit `7dea2e6`):** a directory whose basename equals an entry-point file's basename (e.g. `hello/hello.cs` with other production files) generates a `csharp_library` and a `csharp_binary` with the same name; Bazel fails loudly at load time. Multi-framework-per-directory grouping also lacks a dedicated unit test (covered indirectly by integration fixtures). Both are accepted for v1.

Replace the `GenerateRules` stub with the real generator: one `csharp_library` per directory, framework-specific test rules with sibling deps and `internals_visible_to`, and `csharp_binary` for entry-point files.

**Files:**
- Modify: `dotnet/gazelle/generate.go`
- Test: `dotnet/gazelle/generate_test.go`

- [x] **Step 1: Write the failing tests**

Create `dotnet/gazelle/generate_test.go`:

```go
package gazelle

import (
	"path/filepath"
	"reflect"
	"testing"

	"github.com/bazelbuild/bazel-gazelle/config"
	"github.com/bazelbuild/bazel-gazelle/language"
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
```

- [x] **Step 2: Run the tests to verify they fail**

```bash
go test ./dotnet/gazelle/ -run TestGenerate
```

Expected: FAIL, e.g. `TestGenerateLibrary: GenerateRules() = 0 rules, 0 imports; want 1, 1` (the stub generates nothing).

- [x] **Step 3: Implement GenerateRules**

Replace the entire contents of `dotnet/gazelle/generate.go` with:

```go
package gazelle

import (
	"log"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/parser"
	"github.com/bazelbuild/bazel-gazelle/language"
	"github.com/bazelbuild/bazel-gazelle/rule"
)

var invalidTargetCharsRe = regexp.MustCompile(`[^a-z0-9_-]+`)

// sanitizeName converts a directory or file base name into a Bazel target
// name: lowercase, runs of characters outside [a-z0-9_-] become "_", and
// leading/trailing "_" are trimmed.
func sanitizeName(name string) string {
	name = invalidTargetCharsRe.ReplaceAllString(strings.ToLower(name), "_")
	name = strings.Trim(name, "_")
	if name == "" {
		return "unnamed"
	}
	return name
}

// frameworkOrder fixes the output order of test rules for determinism.
var frameworkOrder = []parser.Framework{
	parser.FrameworkNUnit,
	parser.FrameworkXUnit,
	parser.FrameworkMSTest,
}

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

	dirName := path.Base(args.Rel)
	if dirName == "." || dirName == "/" || dirName == "" {
		dirName = filepath.Base(args.Dir)
	}
	libName := sanitizeName(dirName)

	var prodFiles []*parser.File
	testFiles := map[parser.Framework][]*parser.File{}
	var entryFiles []*parser.File

	for _, f := range files {
		switch {
		case f.Framework != parser.FrameworkNone:
			fw := f.Framework
			if cfg.TestFramework() != "" {
				fw = parser.Framework(cfg.TestFramework())
			}
			testFiles[fw] = append(testFiles[fw], f)
		case f.HasEntryPoint && cfg.GenerateBinary():
			entryFiles = append(entryFiles, f)
		default:
			prodFiles = append(prodFiles, f)
		}
	}

	testTargetNames := map[parser.Framework]string{}
	for _, fw := range frameworkOrder {
		if len(testFiles[fw]) > 0 {
			testTargetNames[fw] = libName + "_" + string(fw) + "_test"
		}
	}

	var res language.GenerateResult

	if len(prodFiles) > 0 {
		lib := rule.NewRule("csharp_library", libName)
		lib.SetAttr("srcs", namesOf(prodFiles))
		lib.SetAttr("target_frameworks", cfg.TargetFrameworks())
		lib.SetAttr("project_sdk", cfg.ProjectSdk())
		lib.SetAttr("visibility", cfg.Visibility())
		if len(testTargetNames) > 0 {
			var ivt []string
			for _, fw := range frameworkOrder {
				if name, ok := testTargetNames[fw]; ok {
					ivt = append(ivt, name)
				}
			}
			lib.SetAttr("internals_visible_to", ivt)
		}
		lib.SetPrivateAttr(namespacesKey, namespacesOf(prodFiles))
		res.Gen = append(res.Gen, lib)
		res.Imports = append(res.Imports, resolveInput{
			imports: usingNamespaces(prodFiles),
			own:     namespacesOf(prodFiles),
		})
	}

	for _, fw := range frameworkOrder {
		files := testFiles[fw]
		if len(files) == 0 {
			continue
		}
		r := rule.NewRule(testKindFor(fw), testTargetNames[fw])
		r.SetAttr("srcs", namesOf(files))
		r.SetAttr("target_frameworks", cfg.TargetFrameworks())
		r.SetAttr("project_sdk", cfg.ProjectSdk())
		r.SetAttr("visibility", cfg.Visibility())
		if len(prodFiles) > 0 {
			r.SetAttr("deps", []string{":" + libName})
		}
		res.Gen = append(res.Gen, r)
		res.Imports = append(res.Imports, resolveInput{
			imports: usingNamespaces(files),
			own:     namespacesOf(files),
		})
	}

	for _, f := range entryFiles {
		name := sanitizeName(strings.TrimSuffix(f.Name, ".cs"))
		r := rule.NewRule("csharp_binary", name)
		r.SetAttr("srcs", []string{f.Name})
		r.SetAttr("target_frameworks", cfg.TargetFrameworks())
		r.SetAttr("project_sdk", cfg.ProjectSdk())
		r.SetAttr("visibility", cfg.Visibility())
		res.Gen = append(res.Gen, r)
		res.Imports = append(res.Imports, resolveInput{
			imports: usingNamespaces([]*parser.File{f}),
			own:     namespacesOf([]*parser.File{f}),
		})
	}

	return res
}

func isCsharpKind(kind string) bool {
	for _, k := range csharpKinds {
		if k == kind {
			return true
		}
	}
	return false
}

func testKindFor(fw parser.Framework) string {
	switch fw {
	case parser.FrameworkNUnit:
		return "csharp_nunit_test"
	case parser.FrameworkXUnit:
		return "csharp_xunit_test"
	default:
		return "csharp_mstest_test"
	}
}

// usingNamespaces returns the sorted, deduplicated namespaces imported by files.
func usingNamespaces(files []*parser.File) []string {
	seen := map[string]bool{}
	var out []string
	for _, f := range files {
		for _, u := range f.Usings {
			if !seen[u.Namespace] {
				seen[u.Namespace] = true
				out = append(out, u.Namespace)
			}
		}
	}
	sort.Strings(out)
	return out
}

// namespacesOf returns the sorted, deduplicated namespaces declared by files.
func namespacesOf(files []*parser.File) []string {
	seen := map[string]bool{}
	var out []string
	for _, f := range files {
		if f.Namespace != "" && !seen[f.Namespace] {
			seen[f.Namespace] = true
			out = append(out, f.Namespace)
		}
	}
	sort.Strings(out)
	return out
}

// namesOf returns the base names of files, which are already sorted by name.
func namesOf(files []*parser.File) []string {
	out := make([]string, len(files))
	for i, f := range files {
		out[i] = f.Name
	}
	return out
}
```

- [x] **Step 4: Run the tests to verify they pass**

```bash
go test ./dotnet/gazelle/...
```

Expected: all packages `ok`, `PASS`.

- [x] **Step 5: Regenerate BUILD files and test under Bazel**

Run (env exports assumed):

```bash
bazel run //:gazelle
bazel test //dotnet/gazelle/...
```

Expected: gazelle updates `dotnet/gazelle/BUILD.bazel` (generate_test.go joins the `go_test` srcs); all 4 test targets pass. Then revert pre-existing drift:

```bash
git diff --name-only -- dotnet/BUILD.bazel dotnet/private | xargs -r git checkout --
```

- [x] **Step 6: Commit**

```bash
git add dotnet/gazelle
git commit -m "Add C# rule generation to the Gazelle extension"
```

### Task 11: Integration test harness + library/binary fixtures

Gazelle's `gazelle_generation_test` runs the real gazelle binary in a fixture directory and compares every generated `BUILD.bazel` against a committed `BUILD.out`. This task adds the harness and the first two cases; Tasks 12–13 add the rest.

Fixture conventions (same as rules_jvm): a directory is a test case when it contains a `MODULE.bazel` file (content irrelevant — keep it empty); `BUILD.in` is the pre-existing BUILD file (only directive comments in our cases); `BUILD.out` is the expected result.

> **Corrections applied in Task 11 (commit `6d30a35`) — standing rules for ALL fixtures in Tasks 11–13:**
> 1. The stderr-capture file must be named `expectedStderr.txt` (all-lowercase "err" — verified in gazelle v2 `testtools/files.go:172`; the spelling `expectedStdErr.txt` used below is silently ignored and any stderr output then fails the test). Every fixture **without** a `packages.lock.json` needs this file with exactly one line:
>    `gazelle: no packages.lock.json at %WORKSPACEPATH%/packages.lock.json; NuGet resolution is disabled`
> 2. Golden `BUILD.out` files must list `project_sdk = "default",` **before** `target_frameworks = [...]` — gazelle v2 prints attributes by `NamePriority` then alphabetically, so no other order is printable. Where the goldens below show the opposite order, swap those two lines when creating the files.

**Files:**
- Create: `dotnet/gazelle/testdata/BUILD.bazel`
- Create: `dotnet/gazelle/testdata/lib/{MODULE.bazel,BUILD.in,BUILD.out}`
- Create: `dotnet/gazelle/testdata/lib/src/Calculator/{Calculator.cs,BUILD.out}`
- Create: `dotnet/gazelle/testdata/binary/{MODULE.bazel,BUILD.in,BUILD.out}`
- Create: `dotnet/gazelle/testdata/binary/src/Hello/{Program.cs,BUILD.out}`

- [x] **Step 1: Create the harness**

Create `dotnet/gazelle/testdata/BUILD.bazel`:

```python
load("@bazel_gazelle//:def.bzl", "gazelle_binary", "gazelle_generation_test")

# It is important not to add any BUILD.bazel files in any subdirectory of
# this one: BUILD.in/BUILD.out are the fixtures and are picked up as test
# data. The exclude directive keeps a root `bazel run //:gazelle` out of the
# fixture directories, while this file itself stays visible to gazelle so
# testdata/** is not globbed into the parent package.
# gazelle:exclude *

gazelle_binary(
    name = "gazelle",
    languages = ["//dotnet/gazelle"],
    visibility = ["//visibility:private"],
)

# A directory is a test case if it contains a MODULE.bazel file.
TEST_CASE_DIRS = sorted({
    marker_file.rsplit("/", 1)[0]: None
    for marker_file in glob(["**/MODULE.bazel"])
}.keys())

[
    gazelle_generation_test(
        name = test_dir,
        gazelle_binary = ":gazelle",
        gazelle_timeout_seconds = 60,
        test_data = glob([test_dir + "/**"]),
    )
    for test_dir in TEST_CASE_DIRS
]
```

- [x] **Step 2: Create the `lib` fixture (library only)**

Create an empty file `dotnet/gazelle/testdata/lib/MODULE.bazel` (0 bytes — it only marks the directory as a test case).

Create `dotnet/gazelle/testdata/lib/BUILD.in`:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/lib/BUILD.out` with the same content:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/lib/src/Calculator/Calculator.cs`:

```csharp
namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;
}
```

Create `dotnet/gazelle/testdata/lib/src/Calculator/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "calculator",
    srcs = ["Calculator.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
)
```

- [x] **Step 3: Create the `binary` fixture (entry point only)**

Create an empty file `dotnet/gazelle/testdata/binary/MODULE.bazel`.

Create `dotnet/gazelle/testdata/binary/BUILD.in` and `dotnet/gazelle/testdata/binary/BUILD.out`, both with:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/binary/src/Hello/Program.cs`:

```csharp
using System;

Console.WriteLine("Hello, world!");
```

Create `dotnet/gazelle/testdata/binary/src/Hello/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary")

csharp_binary(
    name = "program",
    srcs = ["Program.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
)
```

Note: `using System;` resolves to nothing (base class library) and top-level statements make this a binary; there is no library because the entry-point file is the only source.

- [x] **Step 4: Run the fixture tests**

Run (env exports assumed):

```bash
bazel test //dotnet/gazelle/testdata:lib //dotnet/gazelle/testdata:binary
```

Expected: both targets `PASSED`.

If a test fails, the failure output prints a diff between the actual generated BUILD.bazel and BUILD.out, plus a command line to update fixtures. Do not blindly regenerate: an unexpected diff means the generator deviates from this plan — fix the generator, not the fixture.

- [x] **Step 5: Commit**

```bash
git add dotnet/gazelle/testdata
git commit -m "Add Gazelle generation test harness with library and binary cases"
```

### Task 12: Integration fixtures — test frameworks

One fixture per test framework: a library with a sibling test file. Each verifies framework detection, test target naming, the sibling dep and `internals_visible_to`.

**Files:**
- Create: `dotnet/gazelle/testdata/nunit_tests/{MODULE.bazel,BUILD.in,BUILD.out}`
- Create: `dotnet/gazelle/testdata/nunit_tests/src/Calculator/{Calculator.cs,CalculatorTests.cs,BUILD.out}`
- Create: `dotnet/gazelle/testdata/xunit_tests/...` (same layout)
- Create: `dotnet/gazelle/testdata/mstest_tests/...` (same layout)

- [x] **Step 1: Create the `nunit_tests` fixture**

Create empty `dotnet/gazelle/testdata/nunit_tests/MODULE.bazel`. Create `BUILD.in` and `BUILD.out` in the same directory, both:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/nunit_tests/src/Calculator/Calculator.cs`:

```csharp
namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;
}
```

Create `dotnet/gazelle/testdata/nunit_tests/src/Calculator/CalculatorTests.cs`:

```csharp
using Calculator;
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
```

Create `dotnet/gazelle/testdata/nunit_tests/src/Calculator/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library", "csharp_nunit_test")

csharp_library(
    name = "calculator",
    srcs = ["Calculator.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    internals_visible_to = ["calculator_nunit_test"],
)

csharp_nunit_test(
    name = "calculator_nunit_test",
    srcs = ["CalculatorTests.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = [":calculator"],
)
```

The `using NUnit.Framework;` import does not resolve (no packages.lock.json in this fixture) — it produces a warning, not a dep; the `csharp_nunit_test` macro injects the real NUnit deps.

- [x] **Step 2: Create the `xunit_tests` fixture**

Create empty `dotnet/gazelle/testdata/xunit_tests/MODULE.bazel`. Create `BUILD.in` and `BUILD.out` there, both:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/xunit_tests/src/Calculator/Calculator.cs` with the same content as the nunit fixture's `Calculator.cs` (copy it):

```csharp
namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;
}
```

Create `dotnet/gazelle/testdata/xunit_tests/src/Calculator/CalculatorTests.cs`:

```csharp
using Calculator;
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
```

Create `dotnet/gazelle/testdata/xunit_tests/src/Calculator/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library", "csharp_xunit_test")

csharp_library(
    name = "calculator",
    srcs = ["Calculator.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    internals_visible_to = ["calculator_xunit_test"],
)

csharp_xunit_test(
    name = "calculator_xunit_test",
    srcs = ["CalculatorTests.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = [":calculator"],
)
```

- [x] **Step 3: Create the `mstest_tests` fixture**

Create empty `dotnet/gazelle/testdata/mstest_tests/MODULE.bazel`. Create `BUILD.in` and `BUILD.out` there, both:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/mstest_tests/src/Calculator/Calculator.cs`:

```csharp
namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;
}
```

Create `dotnet/gazelle/testdata/mstest_tests/src/Calculator/CalculatorTests.cs`:

```csharp
using Calculator;
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
```

Create `dotnet/gazelle/testdata/mstest_tests/src/Calculator/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library", "csharp_mstest_test")

csharp_library(
    name = "calculator",
    srcs = ["Calculator.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    internals_visible_to = ["calculator_mstest_test"],
)

csharp_mstest_test(
    name = "calculator_mstest_test",
    srcs = ["CalculatorTests.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = [":calculator"],
)
```

- [x] **Step 4: Run the fixture tests**

```bash
bazel test //dotnet/gazelle/testdata:nunit_tests //dotnet/gazelle/testdata:xunit_tests //dotnet/gazelle/testdata:mstest_tests
```

Expected: all three `PASSED`.

- [x] **Step 5: Commit**

```bash
git add dotnet/gazelle/testdata
git commit -m "Add test framework fixtures to the Gazelle generation tests"
```

### Task 13: Integration fixtures — resolution and directives

Five cases covering: NuGet resolution, workspace-cross-package resolution, `dotnet_resolve`, forced test framework, and disabled binary generation.

**Files:**
- Create: `dotnet/gazelle/testdata/nuget_dep/**`
- Create: `dotnet/gazelle/testdata/workspace_dep/**`
- Create: `dotnet/gazelle/testdata/resolve_override/**`
- Create: `dotnet/gazelle/testdata/test_framework_forced/**`
- Create: `dotnet/gazelle/testdata/generate_binary_disabled/**`

- [x] **Step 1: Create the `nuget_dep` fixture**

Create empty `dotnet/gazelle/testdata/nuget_dep/MODULE.bazel`. Create `BUILD.in` and `BUILD.out` there, both:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/nuget_dep/packages.lock.json` (same content as `e2e/net10.0_packages_lock/basic_csharp/packages.lock.json`):

```json
{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "Newtonsoft.Json": {
        "type": "Direct",
        "requested": "[13.0.3, )",
        "resolved": "13.0.3",
        "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
      }
    }
  }
}
```

Create `dotnet/gazelle/testdata/nuget_dep/src/Store/Store.cs`:

```csharp
using Newtonsoft.Json;

namespace Store;

public static class Serializer
{
    public static string ToJson(object value) => JsonConvert.SerializeObject(value);
}
```

Create `dotnet/gazelle/testdata/nuget_dep/src/Store/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "store",
    srcs = ["Store.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = ["@nuget.net10.0//newtonsoft.json"],
)
```

- [x] **Step 2: Create the `workspace_dep` fixture**

Create empty `dotnet/gazelle/testdata/workspace_dep/MODULE.bazel`. Create `BUILD.in` and `BUILD.out` there, both:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/workspace_dep/src/Calculator/Calculator.cs`:

```csharp
namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;
}
```

Create `dotnet/gazelle/testdata/workspace_dep/src/Calculator/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "calculator",
    srcs = ["Calculator.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
)
```

Create `dotnet/gazelle/testdata/workspace_dep/src/App/Program.cs`:

```csharp
using Calculator;

namespace App;

public static class Program
{
    public static void Main(string[] args)
    {
        System.Console.WriteLine(Arithmetic.Add(2, 3));
    }
}
```

Create `dotnet/gazelle/testdata/workspace_dep/src/App/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary")

csharp_binary(
    name = "program",
    srcs = ["Program.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = ["//src/Calculator:calculator"],
)
```

The binary's `using Calculator;` resolves through the workspace index to the sibling library in another package; the label stays absolute because the packages differ.

- [x] **Step 3: Create the `resolve_override` fixture**

Create empty `dotnet/gazelle/testdata/resolve_override/MODULE.bazel`. Create `BUILD.in` and `BUILD.out` there, both:

```
# gazelle:dotnet_target_frameworks net10.0
# gazelle:dotnet_resolve Acme.Widget @acme//widget
```

Create `dotnet/gazelle/testdata/resolve_override/src/App/App.cs`:

```csharp
using Acme.Widget;

namespace App;

public static class Gadget
{
    public static int Run() => 0;
}
```

Create `dotnet/gazelle/testdata/resolve_override/src/App/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "app",
    srcs = ["App.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = ["@acme//widget"],
)
```

- [x] **Step 4: Create the `test_framework_forced` fixture**

Create empty `dotnet/gazelle/testdata/test_framework_forced/MODULE.bazel`. Create `BUILD.in` and `BUILD.out` there, both:

```
# gazelle:dotnet_target_frameworks net10.0
# gazelle:dotnet_test_framework nunit
```

Create `dotnet/gazelle/testdata/test_framework_forced/src/Calculator/Calculator.cs`:

```csharp
namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;
}
```

Create `dotnet/gazelle/testdata/test_framework_forced/src/Calculator/CalculatorTests.cs` (note: xunit markers, forced to nunit):

```csharp
using Calculator;
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
```

Create `dotnet/gazelle/testdata/test_framework_forced/src/Calculator/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library", "csharp_nunit_test")

csharp_library(
    name = "calculator",
    srcs = ["Calculator.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    internals_visible_to = ["calculator_nunit_test"],
)

csharp_nunit_test(
    name = "calculator_nunit_test",
    srcs = ["CalculatorTests.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = [":calculator"],
)
```

- [x] **Step 5: Create the `generate_binary_disabled` fixture**

Create empty `dotnet/gazelle/testdata/generate_binary_disabled/MODULE.bazel`. Create `BUILD.in` and `BUILD.out` there, both:

```
# gazelle:dotnet_target_frameworks net10.0
# gazelle:dotnet_generate_binary false
```

Create `dotnet/gazelle/testdata/generate_binary_disabled/src/App/Program.cs`:

```csharp
using System;

namespace App;

public static class Program
{
    public static void Main(string[] args)
    {
        Console.WriteLine("hi");
    }
}
```

Create `dotnet/gazelle/testdata/generate_binary_disabled/src/App/BUILD.out`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library")

csharp_library(
    name = "app",
    srcs = ["Program.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
)
```

With binary generation disabled the entry-point file becomes a normal library source.

- [x] **Step 6: Run all fixture tests**

```bash
bazel test //dotnet/gazelle/testdata/...
```

Expected: all 10 test targets pass (`binary`, `generate_binary_disabled`, `lib`, `mstest_tests`, `nuget_dep`, `nunit_tests`, `resolve_override`, `test_framework_forced`, `workspace_dep`, `xunit_tests`).

- [x] **Step 7: Commit**

```bash
git add dotnet/gazelle/testdata
git commit -m "Add resolution and directive fixtures to the Gazelle generation tests"
```

### Task 13b: Fix duplicate same-package dep when the repo name is non-empty (TDD)

Found while implementing Task 14 (Bazel failed with `Label '//gazelle_csharp/src/Calculator:calculator' is duplicated in the 'deps' attribute`). Root cause: `resolve.RuleIndex.AddRule` stamps every indexed label with the workspace's canonical repo name (`label.New(c.RepoName, f.Pkg, r.Name())`, gazelle v0.51.3 `resolve/index.go:164`), but gazelle's unit-test harness uses `config.New()`, which leaves `RepoName` empty — so every test written so far exercises only the empty-repo path.

In a real workspace (non-empty `c.RepoName`), `resolveNamespace` in `dotnet/gazelle/resolve.go` (committed in `99ca0f3`) does this: the same-package branch (`case l.Repo == "" && l.Pkg == from.Pkg`) never matches because the indexed label carries the repo name; the second branch strips the repo but keeps the explicit form, so the function returns the string `//gazelle_csharp/src/Calculator:calculator`. `Resolve()` then unions that string with the `:calculator` dep that `generate.go` already set on the test rule — two spellings of the same label in a string-keyed set — producing `deps = [":calculator", "//gazelle_csharp/src/Calculator:calculator"]`.

Fix: in `resolveNamespace`, clear the repo of a label that belongs to the workspace's own repo **before** the same-package check. Same-package labels then relativize to `:name` (string) and deduplicate against the generate-time sibling dep; other-package labels keep the canonical `//pkg` / `//pkg:pkg` string produced by `label.String()` after clearing `Repo`.

**Files:**
- Modify: `dotnet/gazelle/resolve.go` (`resolveNamespace`, the label-simplification switch)
- Test: `dotnet/gazelle/resolve_test.go` (append one failing test)

- [x] **Step 1: Read the current code and test helpers**

Read `dotnet/gazelle/resolve.go` — the target is `resolveNamespace` near the end of the file; note the `switch` that handles `m.Label` after `FindRulesByImportWithConfig`. Read `dotnet/gazelle/resolve_test.go` — `setupLang` (builds a `config.Config` with empty `RepoName`), `indexLibrary` (indexes a `csharp_library` into a `resolve.RuleIndex`), and `TestResolveKeepsExistingDepsAndSimplifiesSamePackage` (the empty-repo version of the scenario this task reproduces with a non-empty repo name) show the fixture pattern to mirror.

- [x] **Step 2: Write the failing test**

Append to the end of `dotnet/gazelle/resolve_test.go`:

```go
func TestResolveSamePackageWithRepoName(t *testing.T) {
	l, c, _ := setupLang(t, "# gazelle:dotnet_target_frameworks net10.0\n", "src", "src/calculator")
	// Simulate a real workspace: RuleIndex.AddRule stamps every indexed
	// label with c.RepoName, which gazelle's test harness leaves empty.
	c.RepoName = "rules_dotnet_examples"

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	indexLibrary(t, l, c, ix, "src/calculator", "calculator", "Calculator")
	ix.Finish()

	r := rule.NewRule("csharp_nunit_test", "calculator_nunit_test")
	r.SetAttr("deps", []string{":calculator"})
	input := resolveInput{imports: []string{"Calculator"}, own: []string{"Calculator.Tests"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/calculator", "calculator_nunit_test"))

	got := r.AttrStrings("deps")
	want := []string{":calculator"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v", got, want)
	}
}
```

No new imports are needed — `reflect`, `resolve`, `label`, and `rule` are already imported in the file.

- [x] **Step 3: Run the test to verify it fails**

Run (env exports from Environment notes assumed, plus `CGO_ENABLED=0`):

```bash
export GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache CGO_ENABLED=0
go test ./dotnet/gazelle/ -run TestResolveSamePackageWithRepoName -v
```

Expected: FAIL with `deps = [//src/calculator :calculator], want [:calculator]` — both spellings of the same label appear in `deps` (`//` sorts before `:`), which is exactly the union that made Bazel fail in Task 14.

- [x] **Step 4: Fix `resolveNamespace`**

Edit `dotnet/gazelle/resolve.go`. Old:

```go
		l := m.Label
		switch {
		case l.Repo == "" && l.Pkg == from.Pkg:
			l = label.Label{Name: l.Name, Relative: true}
		case l.Repo == c.RepoName:
			l.Repo = ""
		}
		return l.String()
```

New:

```go
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
```

Behavior notes: when `c.RepoName` is `""` (unit harness, and the Task 12/13 fixtures) the first `if` is a no-op — the empty-repo path is byte-for-byte unchanged. When the label belongs to another repo (e.g. an external repo in the index), `l.Repo` stays set and neither branch relativizes it, same as before. When the label is in the workspace's own repo, `label.String()` on the repo-less label prints the canonical `//pkg` or `//pkg:pkg` form (it shortens `//pkg:pkg` to `//pkg` when the target name equals the package's last segment).

- [x] **Step 5: Run all Go tests**

```bash
go test ./dotnet/gazelle/...
```

Expected: all four packages report `ok` — the new `TestResolveSamePackageWithRepoName` passes, and every pre-existing test (`TestResolveNamespaces`, `TestResolveOverride`, `TestResolveKeepsExistingDepsAndSimplifiesSamePackage`, `TestResolveSkipsSelfImport`, and all Task 10 generate tests) stays green, proving the empty-repo behavior of Tasks 9/12/13 is unchanged.

- [x] **Step 6: Run the tests under Bazel, including the Task 12/13 fixtures**

```bash
export JAVA_HOME="$(bazel info java-home 2>/dev/null)"
bazel test //dotnet/gazelle/...
```

Expected: all targets pass — the 4 Go unit-test targets and all 10 `gazelle_generation_test` fixtures from Tasks 11–13 (`binary`, `generate_binary_disabled`, `lib`, `mstest_tests`, `nuget_dep`, `nunit_tests`, `resolve_override`, `test_framework_forced`, `workspace_dep`, `xunit_tests`). The fixtures run gazelle with an empty repo name, so they re-verify the unchanged empty-repo path end to end.

- [x] **Step 7: Commit**

```bash
git add dotnet/gazelle/resolve.go dotnet/gazelle/resolve_test.go
git commit -m "Fix duplicate same-package deps when the repo name is non-empty"
```

### Task 14: Example — examples/gazelle_csharp

> **Status: BLOCKED mid-implementation.** The corrections below were verified while implementing this task and exist only as uncommitted working-tree changes (`examples/BUILD.bazel`, `examples/MODULE.bazel`, `examples/gazelle_csharp/`). The step content below is unchanged — where a correction conflicts with a step, the correction wins.
>
> - **A (required) — the `dotnet_target_frameworks` directive must be at the *walk root*.** The examples repo root is `examples/`; `bazel run //gazelle_csharp:gazelle` walks from there, and gazelle configures the parent directories of the target too, so `configure.go` fatals at `rel == ""` when the root has no frameworks. `examples/BUILD.bazel` exists but is empty — add `# gazelle:dotnet_target_frameworks net10.0` to it. The directive inside `examples/gazelle_csharp/BUILD.bazel` (Step 2) may stay as documentation, but the root directive is the load-bearing one.
> - **C (required) — `Program.cs` needs `using System;`.** rules_dotnet has no implicit usings; without it the binary fails to compile with CS0103 (`Console` does not exist). Prepend `using System;` to `examples/gazelle_csharp/src/CalculatorApp/Program.cs`.
> - **D (environment, optional) — cgo fails under the nono sandbox** (`/usr/include` is denied). Workaround: add `bazel_dep(name = "rules_go", version = "0.59.0")` plus the `go_sdk.download(version = "1.24.12")` extension stanza (same as the root `MODULE.bazel`) to `examples/MODULE.bazel`, and pass `--@rules_go//go/config:pure` on the bazel command lines in Steps 5–6 (no `.bazelrc` change). The rules_go dep is required for the flag to resolve; the pure flag itself is likely only needed in this sandbox (CI/unsandboxed users can omit it).
> - **Golden attribute order (verified against gazelle output):** generated BUILD files print `project_sdk = "default",` **before** `target_frameworks = [...]` (gazelle sorts by NamePriority, then alphabetically: `project_sdk` < `target_frameworks`). `src/Calculator/BUILD.bazel` additionally sorts `internals_visible_to` before `project_sdk` and always prints `deps` last. Order every committed BUILD file in Steps 4 accordingly.
> - **Task 13b dependency:** after Task 13b lands, the generated `examples/gazelle_csharp/src/Calculator/BUILD.bazel` must contain `deps = [":calculator"]` **exactly once** in the `csharp_nunit_test` — the duplicate `//gazelle_csharp/src/Calculator:calculator` spelling is the bug Task 13b fixes, so run Task 13b before Step 5 and regenerate/verify the BUILD files with the fixed gazelle binary.
> - Task 16 Step 5's expected commit count increases by one (17 new commits on `feature/packages-lock`, not 16) because Task 13b adds a commit.

A small multi-directory C# "solution" (library + binary + NUnit and xUnit tests) with a `packages.lock.json`, a gazelle target, and the generated BUILD files committed. It demonstrates the consumer workflow: `bazel run //gazelle_csharp:gazelle`.

The BUILD files are written by hand below; the idempotency check in Step 5 proves they match the generator output exactly.

**Files:**
- Modify: `examples/MODULE.bazel`
- Create: `examples/gazelle_csharp/{BUILD.bazel,packages.lock.json}`
- Create: `examples/gazelle_csharp/src/Calculator/{BUILD.bazel,Calculator.cs,CalculatorTests.cs}`
- Create: `examples/gazelle_csharp/src/CalculatorApp/{BUILD.bazel,Program.cs}`
- Create: `examples/gazelle_csharp/tests/CalculatorXunitTests/{BUILD.bazel,CalculatorTests.cs}`

- [x] **Step 1: Wire gazelle and packages_lock into examples/MODULE.bazel**

Edit `examples/MODULE.bazel`. Old:

```
# A second lock file, showing that a package group is addressed by its name.
paket_example = use_extension("@rules_dotnet//dotnet:paket.bzl", "paket")
paket_example.parse(
    dependencies = "//paket:paket.dependencies",
    lock = "//paket:paket.lock",
)
use_repo(paket_example, "paket.main", "paket.othergroup")
```

New:

```
# A second lock file, showing that a package group is addressed by its name.
paket_example = use_extension("@rules_dotnet//dotnet:paket.bzl", "paket")
paket_example.parse(
    dependencies = "//paket:paket.dependencies",
    lock = "//paket:paket.lock",
)
use_repo(paket_example, "paket.main", "paket.othergroup")

# Gazelle for //gazelle_csharp, demonstrating the C# Gazelle extension.
# rules_go and the Go SDK come transitively from rules_dotnet.
bazel_dep(name = "gazelle", version = "0.51.3", repo_name = "bazel_gazelle")

packages_lock = use_extension("@rules_dotnet//dotnet:packages_lock.bzl", "packages_lock")
packages_lock.parse(lock = "//gazelle_csharp:packages.lock.json")
use_repo(packages_lock, "nuget.net10.0")
```

- [x] **Step 2: Create the example root files**

Create `examples/gazelle_csharp/BUILD.bazel`:

```python
load("@bazel_gazelle//:def.bzl", "gazelle", "gazelle_binary")

package(default_visibility = ["//visibility:public"])

# gazelle:dotnet_target_frameworks net10.0

gazelle_binary(
    name = "gazelle_bin",
    languages = ["@rules_dotnet//dotnet/gazelle"],
)

# Regenerate the BUILD files in this directory tree:
# bazel run //gazelle_csharp:gazelle
gazelle(
    name = "gazelle",
    extra_args = [
        "-dotnet_nuget_lock_file=gazelle_csharp/packages.lock.json",
        "gazelle_csharp",
    ],
    gazelle = "gazelle_bin",
)
```

The `gazelle_csharp` positional arg restricts the run to this subtree when executed from the examples root. The lock-file flag path is relative to the examples root.

Create `examples/gazelle_csharp/packages.lock.json`:

```json
{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "Newtonsoft.Json": {
        "type": "Direct",
        "requested": "[13.0.3, )",
        "resolved": "13.0.3",
        "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
      }
    }
  }
}
```

- [x] **Step 3: Create the sources**

Create `examples/gazelle_csharp/src/Calculator/Calculator.cs`:

```csharp
using Newtonsoft.Json;

namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;

    public static string ResultToJson(int value) => JsonConvert.SerializeObject(new { result = value });
}
```

Create `examples/gazelle_csharp/src/Calculator/CalculatorTests.cs`:

```csharp
using Calculator;
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
```

Create `examples/gazelle_csharp/src/CalculatorApp/Program.cs`:

```csharp
using Calculator;

Console.WriteLine(Arithmetic.ResultToJson(Arithmetic.Add(2, 3)));
```

Create `examples/gazelle_csharp/tests/CalculatorXunitTests/CalculatorTests.cs`:

```csharp
using Calculator;
using Xunit;

namespace CalculatorXunitTests;

public sealed class ArithmeticXunitTests
{
    [Fact]
    public void ResultSerializesToJson()
    {
        Assert.Equal("{\"result\":5}", Arithmetic.ResultToJson(Arithmetic.Add(2, 3)));
    }
}
```

- [x] **Step 4: Create the (generated) BUILD files**

Create `examples/gazelle_csharp/src/Calculator/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library", "csharp_nunit_test")

csharp_library(
    name = "calculator",
    srcs = ["Calculator.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    internals_visible_to = ["calculator_nunit_test"],
    deps = ["@nuget.net10.0//newtonsoft.json"],
)

csharp_nunit_test(
    name = "calculator_nunit_test",
    srcs = ["CalculatorTests.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = [":calculator"],
)
```

Create `examples/gazelle_csharp/src/CalculatorApp/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary")

csharp_binary(
    name = "program",
    srcs = ["Program.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = ["//gazelle_csharp/src/Calculator:calculator"],
)
```

Create `examples/gazelle_csharp/tests/CalculatorXunitTests/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_xunit_test")

csharp_xunit_test(
    name = "calculatorxunittests_xunit_test",
    srcs = ["CalculatorTests.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = ["//gazelle_csharp/src/Calculator:calculator"],
)
```

Note: the `using Xunit;`/`using NUnit.Framework;` imports intentionally do not resolve via NuGet (the frameworks come from the rule macros), so gazelle logs warnings for them during a run but generates no deps.

- [x] **Step 5: Run gazelle and verify idempotency**

Run from the `examples/` directory (env exports assumed):

```bash
cd examples
bazel run //gazelle_csharp:gazelle
git status --porcelain -- gazelle_csharp
```

Expected: exit code 0 for the run, and **empty** `git status` output — the committed BUILD files are exactly what gazelle generates.

Troubleshooting: if the build of `//gazelle_csharp:gazelle_bin` fails with a missing Go SDK/toolchain, add `bazel_dep(name = "rules_go", version = "0.59.0")` plus the `go_sdk` extension stanza (as in the root MODULE.bazel) to `examples/MODULE.bazel` — transitive toolchain registration from rules_dotnet is expected to make this unnecessary, so treat needing it as a defect to note in the commit message.

- [x] **Step 6: Build and test the example**

```bash
bazel build //gazelle_csharp/...
bazel test //gazelle_csharp/...
```

Expected: build succeeds; both test targets pass (`//gazelle_csharp/src/Calculator:calculator_nunit_test` and `//gazelle_csharp/tests/CalculatorXunitTests:calculatorxunittests_xunit_test`).

- [x] **Step 7: Commit**

```bash
git add examples/MODULE.bazel examples/gazelle_csharp
git commit -m "Add gazelle_csharp example demonstrating the C# Gazelle extension"
```

### Task 15: E2E module — e2e/gazelle_net10.0

A standalone Bazel module (same shape as `e2e/net10.0_packages_lock`) with `local_path_override` to the repo, committed gazelle-generated BUILD files, and CI wiring. CI builds and tests `//...`; the task itself verifies `bazel run //:gazelle` is idempotent.

**Files:**
- Create: `e2e/gazelle_net10.0/{.bazelrc,.bazelversion,internal_dev_deps.bzl,MODULE.bazel,BUILD.bazel,packages.lock.json}`
- Create: `e2e/gazelle_net10.0/src/Calculator/{BUILD.bazel,Calculator.cs,CalculatorTests.cs}`
- Create: `e2e/gazelle_net10.0/src/CalculatorApp/{BUILD.bazel,Program.cs}`
- Create: `e2e/gazelle_net10.0/tests/CalculatorXunitTests/{BUILD.bazel,CalculatorTests.cs}`
- Modify: `.bazelci/presubmit.yml`

- [x] **Step 1: Create the module scaffolding**

Copy `.bazelrc`, `.bazelversion` and `internal_dev_deps.bzl` from `e2e/net10.0_packages_lock` verbatim:

```bash
cp e2e/net10.0_packages_lock/.bazelrc e2e/net10.0_packages_lock/.bazelversion e2e/net10.0_packages_lock/internal_dev_deps.bzl e2e/gazelle_net10.0/
```

(run after creating the `e2e/gazelle_net10.0` directory with `mkdir -p`). For reference, `.bazelversion` must contain exactly `9.1.1` and `internal_dev_deps.bzl` must contain:

```python
"""Module extension for internal dev_dependency=True setup."""

load("@bazel_ci_rules//:rbe_repo.bzl", "rbe_preconfig")

def _internal_dev_deps_impl(mctx):
    _ = mctx  # @unused

    rbe_preconfig(
        name = "buildkite_config",
        toolchain = "ubuntu2204",
    )

internal_dev_deps = module_extension(
    implementation = _internal_dev_deps_impl,
    doc = "This extension creates internal rules_dotnet dev dependencies.",
)
```

Create `e2e/gazelle_net10.0/MODULE.bazel`:

```python
"rules_dotnet C# Gazelle extension e2e"

module(
    name = "e2e_gazelle_net10_0",
    version = "0.0.0",
    compatibility_level = 1,
)

bazel_dep(name = "rules_dotnet", version = "0.0.0")
local_path_override(
    module_name = "rules_dotnet",
    path = "../..",
)

bazel_dep(name = "gazelle", version = "0.51.3", repo_name = "bazel_gazelle")

dotnet = use_extension("@rules_dotnet//dotnet:extensions.bzl", "dotnet")
dotnet.toolchain(dotnet_version = "10.0.401")
use_repo(dotnet, "dotnet_toolchains")

register_toolchains("@dotnet_toolchains//:all")

packages_lock = use_extension("@rules_dotnet//dotnet:packages_lock.bzl", "packages_lock")
packages_lock.parse(lock = "//:packages.lock.json")
use_repo(packages_lock, "nuget.net10.0")

# Only needed to make the Bazel CI RBE config work. Not needed for using rules_dotnet.
bazel_dep(name = "bazel_ci_rules", version = "1.0.0", dev_dependency = True)
bazel_dep(name = "platforms", version = "0.0.10", dev_dependency = True)

internal_dev_deps = use_extension("//:internal_dev_deps.bzl", "internal_dev_deps", dev_dependency = True)
use_repo(internal_dev_deps, "buildkite_config")
```

Create `e2e/gazelle_net10.0/packages.lock.json` with the same content as in Task 14 Step 2 (Newtonsoft.Json 13.0.3 for net10.0):

```json
{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "Newtonsoft.Json": {
        "type": "Direct",
        "requested": "[13.0.3, )",
        "resolved": "13.0.3",
        "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
      }
    }
  }
}
```

Create `e2e/gazelle_net10.0/BUILD.bazel`:

```python
load("@bazel_gazelle//:def.bzl", "gazelle", "gazelle_binary")

package(default_visibility = ["//visibility:public"])

# gazelle:dotnet_target_frameworks net10.0

gazelle_binary(
    name = "gazelle_bin",
    languages = ["@rules_dotnet//dotnet/gazelle"],
)

# Regenerate the BUILD files in this module:
# bazel run //:gazelle
gazelle(
    name = "gazelle",
    gazelle = "gazelle_bin",
)
```

- [x] **Step 2: Create the sources**

Create `e2e/gazelle_net10.0/src/Calculator/Calculator.cs`:

```csharp
using Newtonsoft.Json;

namespace Calculator;

public static class Arithmetic
{
    public static int Add(int a, int b) => a + b;

    public static string ResultToJson(int value) => JsonConvert.SerializeObject(new { result = value });
}
```

Create `e2e/gazelle_net10.0/src/Calculator/CalculatorTests.cs`:

```csharp
using Calculator;
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
```

Create `e2e/gazelle_net10.0/src/CalculatorApp/Program.cs`:

```csharp
using Calculator;

Console.WriteLine(Arithmetic.ResultToJson(Arithmetic.Add(2, 3)));
```

Create `e2e/gazelle_net10.0/tests/CalculatorXunitTests/CalculatorTests.cs`:

```csharp
using Calculator;
using Xunit;

namespace CalculatorXunitTests;

public sealed class ArithmeticXunitTests
{
    [Fact]
    public void ResultSerializesToJson()
    {
        Assert.Equal("{\"result\":5}", Arithmetic.ResultToJson(Arithmetic.Add(2, 3)));
    }
}
```

- [x] **Step 3: Create the (generated) BUILD files**

Create `e2e/gazelle_net10.0/src/Calculator/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_library", "csharp_nunit_test")

csharp_library(
    name = "calculator",
    srcs = ["Calculator.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    internals_visible_to = ["calculator_nunit_test"],
    deps = ["@nuget.net10.0//newtonsoft.json"],
)

csharp_nunit_test(
    name = "calculator_nunit_test",
    srcs = ["CalculatorTests.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = [":calculator"],
)
```

Create `e2e/gazelle_net10.0/src/CalculatorApp/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary")

csharp_binary(
    name = "program",
    srcs = ["Program.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = ["//src/Calculator:calculator"],
)
```

Create `e2e/gazelle_net10.0/tests/CalculatorXunitTests/BUILD.bazel`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_xunit_test")

csharp_xunit_test(
    name = "calculatorxunittests_xunit_test",
    srcs = ["CalculatorTests.cs"],
    target_frameworks = ["net10.0"],
    project_sdk = "default",
    visibility = ["//visibility:public"],
    deps = ["//src/Calculator:calculator"],
)
```

- [x] **Step 4: Run gazelle and verify idempotency**

Run from `e2e/gazelle_net10.0` (env exports assumed; run `export JAVA_HOME="$(bazel info java-home 2>/dev/null)"` again in this directory):

```bash
cd e2e/gazelle_net10.0
bazel run //:gazelle
git status --porcelain .
```

Expected: exit code 0 for the run, and **empty** `git status` output — no modifications to the files created in Steps 1–3, proving the committed BUILD files match the generator output exactly. The same Go-toolchain troubleshooting note as Task 14 Step 5 applies here.

- [x] **Step 5: Build and test the module**

```bash
bazel build //...
bazel test //...
```

Expected: build succeeds; both test targets pass (`//src/Calculator:calculator_nunit_test` and `//tests/CalculatorXunitTests:calculatorxunittests_xunit_test`).

- [x] **Step 6: Add the module to CI**

Edit `.bazelci/presubmit.yml`. Old:

```
  e2e_working_directory: ["e2e/net8.0", "e2e/net9.0", "e2e/net10.0", "e2e/web_sdk"]
```

New:

```
  e2e_working_directory: ["e2e/net8.0", "e2e/net9.0", "e2e/net10.0", "e2e/web_sdk", "e2e/gazelle_net10.0"]
```

- [x] **Step 7: Commit**

```bash
git add e2e/gazelle_net10.0 .bazelci/presubmit.yml
git commit -m "Add gazelle_net10.0 e2e module for the C# Gazelle extension"
```

### Task 16: Final validation

> **Outcome (all steps executed):** Steps 1–3 and 5 pass. Step 4 (`bazel build //...`) surfaced one plan gap, fixed post-review in commit `2bac84a` (the `defs` bzl_library in `dotnet/BUILD.bazel` lacked the two new rule deps — never listed in this plan's File structure). Two remaining `//...` failures are pre-existing environmental issues unrelated to this branch: `//dotnet/private/tests/dotnet_tool:csharpier_output` (sandbox HOME unreadable; its dependent `diff_test_main` must be excluded with it) and a flaky Roslyn generator load in `//dotnet/private/tools/nuget_pack:nuget_pack` (passes on retry). Commit-count reconciliation: 20 code commits + 18 plan-status/planning commits.

Full-tree verification that everything works together and nothing regressed.

**Files:** none (verification only).

- [x] **Step 1: Verify root gazelle run is idempotent**

Run (env exports assumed):

```bash
bazel run //:gazelle
git diff --name-only -- dotnet/BUILD.bazel dotnet/private | xargs -r git checkout --
git status --porcelain
```

Expected: after the drift revert, `git status --porcelain` is empty — all feature files are committed and gazelle regenerates them byte-identically.

- [x] **Step 2: Run all Go tests**

```bash
go test ./dotnet/gazelle/...
```

Expected: `ok` for all four packages (gazelle, dotnetconfig, nuget, parser).

- [x] **Step 3: Run all Bazel tests for the feature**

```bash
bazel test //dotnet/gazelle/... //dotnet/private/tests/xunit_test/... //dotnet/private/tests/mstest_test/...
```

Expected: all targets pass — 4 Go test targets, 10 `gazelle_generation_test` targets, and the 2 rule smoke tests.

- [x] **Step 4: Verify the whole repo still builds**

```bash
bazel build //...
```

Expected: exit code 0. This compiles the Go extension via rules_go, builds every bzl_library (including the two new ones) and all existing rule tests.

- [x] **Step 5: Review the final diff**

```bash
git log --oneline -17
git diff --stat $(git merge-base HEAD origin/main 2>/dev/null || echo HEAD~16) -- | tail -5
```

Expected: one commit per task (16 new commits on `feature/packages-lock`), and the cumulative diff touches only the files listed in this plan's File structure section. If anything is left uncommitted, inspect and either commit or revert it.

### Task 17: e2e — NUnit test for CalculatorApp (entry-point-only directory)

Give the e2e `CalculatorApp` a **callable public method with a real dependency on the Calculator library**, add an NUnit test that calls it, and fix the generator so the BUILD it emits for a directory containing only an entry-point file plus a test file is valid. The earlier rename idea is **cancelled** — no directory, file, or target is renamed; names stay exactly what the generator produces.

**Verified generator gap (checked against the committed code, not assumed):** `dotnet/gazelle/generate.go` sets the test's sibling dep only when production files exist (`if len(prodFiles) > 0 { r.SetAttr("deps", []string{":" + libName}) }`), so in `src/CalculatorApp` (entry-point file + test file, no production files) the test gets **no sibling dep at all** — the suspected dangling `:<dirname-sanitized>` dep does not literally occur. The build is still broken in effect: `Resolver.Imports` indexes only `csharp_library`, so the binary's namespace is invisible to resolution; the test's `using CalculatorApp;` produces only an unresolved-import warning, and the test target then fails to compile (`Program` does not exist). Fix, no workaround:

1. Generated `csharp_binary` rules carry the `csharp_namespaces` private attr, and `Resolver.Imports` indexes `csharp_binary` too (returning nil when the attr is absent, so hand-written binaries are still not indexed — this keeps the existing `TestImportsIndexesLibraryNamespaces` assertion green).
2. The test sibling dep prefers the library when one is generated; otherwise, when the directory contains **exactly one** entry-point file, it is `:<sanitize(entry file basename)>`; with several entry-point files and no library there is no sibling dep (namespace resolution via using directives covers the dep, which is also what disambiguates which binary).
3. `internals_visible_to` is **not** set on the binary — the tested method is public, so it is unnecessary. (Verified: `csharp_binary` does support the attr, `dotnet/private/rules/csharp/binary.bzl`, and returns the same compile/runtime providers as a library, so a `csharp_nunit_test` may dep on it.)

**Design note on the C# shape:** `Program.cs` switches from top-level statements to an explicit `public static class Program` with `public static string Run()` plus `public static void Main`. This is required, not stylistic: top-level statements cannot coexist with an explicit `Main` (CS0017, multiple entry points), and the parser's top-level-statement heuristic is suppressed by any type declaration (`typeDeclRe`), so only an explicit `Main` keeps the file classified as an entry point — the directory stays a binary directory, which is exactly the gap under test.

Two commits: the generator fix (TDD, unit tests + integration fixture), then the e2e changes.

**Files:**
- Modify: `dotnet/gazelle/generate.go` (binary carries the namespaces private attr; test sibling-dep fallback)
- Modify: `dotnet/gazelle/resolve.go` (`Imports` indexes `csharp_binary`)
- Modify: `dotnet/gazelle/constants.go` (doc comment)
- Test: `dotnet/gazelle/generate_test.go`, `dotnet/gazelle/resolve_test.go`
- Create: `dotnet/gazelle/testdata/test_with_binary/{MODULE.bazel,BUILD.in,BUILD.out,expectedStderr.txt,src/App/{Program.cs,ProgramTests.cs,BUILD.out}}`
- Modify: `e2e/gazelle_net10.0/src/CalculatorApp/Program.cs`
- Create: `e2e/gazelle_net10.0/src/CalculatorApp/ProgramTests.cs`
- Modify (regenerated by gazelle): `e2e/gazelle_net10.0/src/CalculatorApp/BUILD.bazel`

- [x] **Step 1: Add the failing Go unit tests**

Edit `dotnet/gazelle/generate_test.go`. Old (the `programSrc` const and its tail):

```go
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
```

New:

```go
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
```

Then append to the end of `dotnet/gazelle/generate_test.go`:

```go
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
```

Edit `dotnet/gazelle/resolve_test.go` — append to the end of the file (all needed packages are already imported there):

```go
func TestImportsIndexesBinaryNamespaces(t *testing.T) {
	l := NewLanguage().(*csharpLang)
	res := l.Resolver
	f := rule.EmptyFile("src/app/BUILD.bazel", "src/app")

	bin := rule.NewRule("csharp_binary", "program")
	bin.SetPrivateAttr(namespacesKey, []string{"App"})
	specs := res.Imports(config.New(), bin, f)
	if len(specs) != 1 || specs[0].Lang != "csharp" || specs[0].Imp != "App" {
		t.Errorf("Imports(csharp_binary) = %v, want [{csharp App}]", specs)
	}

	// A binary without the private attr (e.g. hand-written) is not indexed.
	if got := res.Imports(config.New(), rule.NewRule("csharp_binary", "tool"), f); got != nil {
		t.Errorf("Imports(csharp_binary without namespaces) = %v, want nil", got)
	}

	// Test rules are never indexed.
	test := rule.NewRule("csharp_nunit_test", "app_nunit_test")
	test.SetPrivateAttr(namespacesKey, []string{"App.Tests"})
	if got := res.Imports(config.New(), test, f); got != nil {
		t.Errorf("Imports(csharp_nunit_test) = %v, want nil", got)
	}
}

func TestResolveTestAgainstSiblingBinary(t *testing.T) {
	l, c, _ := setupLang(t, net10Directive, "src", "src/app")

	ix := resolve.NewRuleIndex(func(r *rule.Rule, pkgRel string) resolve.Resolver { return l.Resolver })
	f := rule.EmptyFile("src/app/BUILD.bazel", "src/app")
	bin := rule.NewRule("csharp_binary", "program")
	bin.SetPrivateAttr(namespacesKey, []string{"App"})
	ix.AddRule(c, bin, f)
	ix.Finish()

	r := rule.NewRule("csharp_nunit_test", "app_nunit_test")
	input := resolveInput{imports: []string{"App"}, own: []string{"App.Tests"}}
	l.Resolver.Resolve(c, ix, nil, r, input, label.New("", "src/app", "app_nunit_test"))

	got := r.AttrStrings("deps")
	want := []string{":program"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("deps = %v, want %v (same-package binary label, relativized)", got, want)
	}
}
```

- [x] **Step 2: Run the tests to verify they fail**

Run (env exports from Environment notes assumed, plus `CGO_ENABLED=0`):

```bash
export GOPATH=/tmp/opencode/gopath GOCACHE=/tmp/opencode/gocache CGO_ENABLED=0
go test ./dotnet/gazelle/ -run 'TestGenerateTestInBinaryOnlyDirectory|TestImportsIndexesBinaryNamespaces|TestResolveTestAgainstSiblingBinary' -v
```

Expected: all three FAIL —
- `TestGenerateTestInBinaryOnlyDirectory`: `test deps = [], want [:program] ...` (no sibling dep today) and `binary private namespaces = [], want [App]`.
- `TestImportsIndexesBinaryNamespaces`: `Imports(csharp_binary) = [], want [{csharp App}]`.
- `TestResolveTestAgainstSiblingBinary`: `deps = [], want [:program]` (the binary is not indexed, so `using App;` cannot resolve).

- [x] **Step 3: Fix the generator — sibling dep fallback and binary namespaces**

Edit `dotnet/gazelle/generate.go`. Old (inside the test-rule loop):

```go
		r.SetAttr("visibility", cfg.Visibility())
		if len(prodFiles) > 0 {
			r.SetAttr("deps", []string{":" + libName})
		}
		res.Gen = append(res.Gen, r)
```

New:

```go
		r.SetAttr("visibility", cfg.Visibility())
		switch {
		case len(prodFiles) > 0:
			r.SetAttr("deps", []string{":" + libName})
		case len(entryFiles) == 1:
			// No library in this directory: the test targets the
			// entry-point binary instead. With several entry-point files
			// the sibling is ambiguous; resolution via using directives
			// covers the dep then.
			name := sanitizeName(strings.TrimSuffix(entryFiles[0].Name, ".cs"))
			r.SetAttr("deps", []string{":" + name})
		}
		res.Gen = append(res.Gen, r)
```

Then, in the entry-file loop. Old:

```go
		r.SetAttr("srcs", []string{f.Name})
		r.SetAttr("target_frameworks", cfg.TargetFrameworks())
		r.SetAttr("project_sdk", cfg.ProjectSdk())
		r.SetAttr("visibility", cfg.Visibility())
		res.Gen = append(res.Gen, r)
```

New:

```go
		r.SetAttr("srcs", []string{f.Name})
		r.SetAttr("target_frameworks", cfg.TargetFrameworks())
		r.SetAttr("project_sdk", cfg.ProjectSdk())
		r.SetAttr("visibility", cfg.Visibility())
		// Binaries advertise their namespaces like libraries do, so a
		// test (or another package) can resolve a using directive to the
		// binary target.
		r.SetPrivateAttr(namespacesKey, namespacesOf([]*parser.File{f}))
		res.Gen = append(res.Gen, r)
```

- [x] **Step 4: Index binary namespaces in the resolver**

Edit `dotnet/gazelle/resolve.go`. Old:

```go
// Imports implements resolve.Resolver. Every generated csharp_library is
// indexed by the namespaces its sources declare; other rules are not
// indexed.
func (r *Resolver) Imports(c *config.Config, ru *rule.Rule, f *rule.File) []resolve.ImportSpec {
	if ru.Kind() != "csharp_library" {
		return nil
	}
	namespaces, _ := ru.PrivateAttr(namespacesKey).([]string)
	specs := make([]resolve.ImportSpec, 0, len(namespaces))
```

New:

```go
// Imports implements resolve.Resolver. Every generated csharp_library and
// csharp_binary is indexed by the namespaces its sources declare; other
// rules — and binaries without the private attr, e.g. hand-written ones —
// are not indexed.
func (r *Resolver) Imports(c *config.Config, ru *rule.Rule, f *rule.File) []resolve.ImportSpec {
	if ru.Kind() != "csharp_library" && ru.Kind() != "csharp_binary" {
		return nil
	}
	namespaces, _ := ru.PrivateAttr(namespacesKey).([]string)
	if len(namespaces) == 0 {
		return nil
	}
	specs := make([]resolve.ImportSpec, 0, len(namespaces))
```

Edit `dotnet/gazelle/constants.go`. Old:

```go
// namespacesKey is the private attribute under which generated csharp_library
// rules carry the namespaces their sources declare, so that Imports can
// index them.
```

New:

```go
// namespacesKey is the private attribute under which generated csharp_library
// and csharp_binary rules carry the namespaces their sources declare, so that
// Imports can index them.
```

- [x] **Step 5: Run all Go tests to verify they pass**

```bash
go test ./dotnet/gazelle/...
```

Expected: `ok` for all four packages (gazelle, dotnetconfig, nuget, parser), `PASS`. In particular the pre-existing `TestImportsIndexesLibraryNamespaces` stays green: its `csharp_binary` assertion constructs a binary without the private attr, which the `len(namespaces) == 0` guard still maps to nil.

- [x] **Step 6: Add the `test_with_binary` integration fixture**

Mirrors the e2e scenario: a directory with only an entry-point file and an NUnit test file. Follows the standing fixture rules from Task 11 (the `expectedStderr.txt` name, and `project_sdk` before `target_frameworks` in goldens).

Create an empty file `dotnet/gazelle/testdata/test_with_binary/MODULE.bazel` (0 bytes — it only marks the directory as a test case).

Create `dotnet/gazelle/testdata/test_with_binary/BUILD.in`:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/test_with_binary/BUILD.out` with the same content:

```
# gazelle:dotnet_target_frameworks net10.0
```

Create `dotnet/gazelle/testdata/test_with_binary/expectedStderr.txt` (two lines — the no-lock-file message and the unresolved NUnit import warning, exactly as in the `nunit_tests` fixture but with this fixture's label):

```
gazelle: no packages.lock.json at %WORKSPACEPATH%/packages.lock.json; NuGet resolution is disabled
gazelle: warning: unresolved C# import "NUnit.Framework" for //src/App:app_nunit_test
```

Create `dotnet/gazelle/testdata/test_with_binary/src/App/Program.cs`:

```csharp
using System;

namespace App;

public static class Program
{
    public static int Run() => 0;

    public static void Main(string[] args)
    {
        Console.WriteLine(Run());
    }
}
```

Create `dotnet/gazelle/testdata/test_with_binary/src/App/ProgramTests.cs`:

```csharp
using App;
using NUnit.Framework;

namespace App.Tests;

[TestFixture]
public sealed class ProgramTests
{
    [Test]
    public void RunWorks()
    {
        Assert.AreEqual(0, Program.Run());
    }
}
```

Create `dotnet/gazelle/testdata/test_with_binary/src/App/BUILD.out`. Note the rule order: the directory starts without a BUILD file, so rules are written in generation order — test rules are generated **before** binaries in `GenerateRules`:

```python
load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary", "csharp_nunit_test")

csharp_nunit_test(
    name = "app_nunit_test",
    srcs = ["ProgramTests.cs"],
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
    deps = [":program"],
)

csharp_binary(
    name = "program",
    srcs = ["Program.cs"],
    project_sdk = "default",
    target_frameworks = ["net10.0"],
    visibility = ["//visibility:public"],
)
```

The binary has no `deps`: its only import is `using System;` (base class library). The test's `deps = [":program"]` comes from the generate-time sibling dep; `using App;` also resolves to `:program` through the index and deduplicates against it in the resolve phase.

- [x] **Step 7: Run the fixture test, then the whole gazelle suite under Bazel**

Run (env exports assumed; run `export JAVA_HOME="$(bazel info java-home 2>/dev/null)"` first):

```bash
bazel test //dotnet/gazelle/testdata:test_with_binary
```

Expected: `//dotnet/gazelle/testdata:test_with_binary PASSED`. If it fails, the failure output prints a diff between the actual generated BUILD.bazel and BUILD.out. An unexpected diff means the generator deviates from this plan — fix the generator, not the fixture. (Exception: if the *only* difference is the order of the two rules, the generation-order assumption in Step 6 was wrong; regenerate the golden with the update command printed by the test and note it in the commit message.)

Then the full suite (all 14 pre-existing targets must stay green):

```bash
bazel test //dotnet/gazelle/...
```

Expected: 15 targets pass — the 4 Go test targets (`gazelle_test`, `dotnetconfig_test`, `nuget_test`, `parser_test`) and 11 `gazelle_generation_test` fixtures (`binary`, `generate_binary_disabled`, `lib`, `mstest_tests`, `nuget_dep`, `nunit_tests`, `resolve_override`, `test_framework_forced`, `test_with_binary`, `workspace_dep`, `xunit_tests`).

- [x] **Step 8: Verify root gazelle idempotency and commit the generator fix**

Run (env exports assumed, from the repo root):

```bash
bazel run //:gazelle
git status --porcelain
```

Expected: the only changes are this task's own files (`dotnet/gazelle/generate.go`, `resolve.go`, `constants.go`, `generate_test.go`, `resolve_test.go`, and the new `testdata/test_with_binary/` directory), plus optionally the pre-existing bzl drift under `dotnet/BUILD.bazel` / `dotnet/private/**` (see Environment notes). No BUILD file under `dotnet/gazelle` changes — the task adds no new Go files, and `testdata/BUILD.bazel` picks the new fixture up via its `glob(["**/MODULE.bazel"])`. Revert the drift:

```bash
git diff --name-only -- dotnet/BUILD.bazel dotnet/private | xargs -r git checkout --
```

Commit:

```bash
git add dotnet/gazelle/generate.go dotnet/gazelle/resolve.go dotnet/gazelle/constants.go dotnet/gazelle/generate_test.go dotnet/gazelle/resolve_test.go dotnet/gazelle/testdata/test_with_binary
git commit -m "Fix Gazelle test sibling deps in entry-point-only directories"
```

- [x] **Step 9: Rewrite the e2e Program.cs with a callable method**

Rewrite `e2e/gazelle_net10.0/src/CalculatorApp/Program.cs` in full — new content:

```csharp
using System;
using Calculator;

namespace CalculatorApp;

public static class Program
{
    public static string Run() => Arithmetic.ResultToJson(Arithmetic.Add(2, 3));

    public static void Main(string[] args)
    {
        Console.WriteLine(Run());
    }
}
```

`Run()` carries the real dependency on the Calculator library (`Arithmetic.ResultToJson`/`Arithmetic.Add`); `Main` keeps the file an entry point so the generator still emits `csharp_binary` (see the design note in the task header). The file declares namespace `CalculatorApp`, which the binary now advertises through the namespaces private attr.

- [x] **Step 10: Create the e2e NUnit test**

Create `e2e/gazelle_net10.0/src/CalculatorApp/ProgramTests.cs`:

```csharp
using CalculatorApp;
using NUnit.Framework;

namespace CalculatorApp.Tests;

[TestFixture]
public sealed class ProgramTests
{
    [Test]
    public void RunReturnsSerializedResult()
    {
        Assert.AreEqual("{\"result\":5}", Program.Run());
    }
}
```

- [x] **Step 11: Regenerate the e2e BUILD file and verify idempotency**

Run from `e2e/gazelle_net10.0` (env exports assumed; run `export JAVA_HOME="$(bazel info java-home 2>/dev/null)"` again in this directory; `--@rules_go//go/config:pure` is the sandbox cgo workaround from Task 14 correction D):

```bash
cd e2e/gazelle_net10.0
export JAVA_HOME="$(bazel info java-home 2>/dev/null)"
bazel run --@rules_go//go/config:pure //:gazelle
git status --porcelain .
```

Expected: exit code 0, and exactly three status lines — `M src/CalculatorApp/BUILD.bazel`, `M src/CalculatorApp/Program.cs`, `?? src/CalculatorApp/ProgramTests.cs`. Verify the BUILD diff:

```bash
git diff src/CalculatorApp/BUILD.bazel
```

Expected diff (the binary rule is unchanged; gazelle's merger appends unmatched generated rules at the end of the file, so the new test rule lands **after** the binary):

```diff
-load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary")
+load("@rules_dotnet//dotnet:defs.bzl", "csharp_binary", "csharp_nunit_test")
 
 csharp_binary(
     name = "program",
     srcs = ["Program.cs"],
     project_sdk = "default",
     target_frameworks = ["net10.0"],
     visibility = ["//visibility:public"],
     deps = ["//src/Calculator:calculator"],
 )
+
+csharp_nunit_test(
+    name = "calculatorapp_nunit_test",
+    srcs = ["ProgramTests.cs"],
+    project_sdk = "default",
+    target_frameworks = ["net10.0"],
+    visibility = ["//visibility:public"],
+    deps = [":program"],
+)
```

If the diff differs in any other way, stop — the generator output deviates from this plan; fix the generator, never hand-edit the BUILD file. Idempotency is the acceptance criterion, so verify a second run is a no-op on the file content:

```bash
cp src/CalculatorApp/BUILD.bazel /tmp/opencode/build_after_run1.bazel
bazel run --@rules_go//go/config:pure //:gazelle
diff /tmp/opencode/build_after_run1.bazel src/CalculatorApp/BUILD.bazel
git status --porcelain .
```

Expected: `diff` prints nothing (exit code 0), and `git status --porcelain .` still shows exactly the same three lines.

- [x] **Step 12: Build and test the e2e module**

```bash
bazel build --@rules_go//go/config:pure //...
bazel test --@rules_go//go/config:pure //...
```

Expected: build exit code 0; test summary `Executed 3 out of 3 tests: 3 tests pass.` with all three PASSED:
- `//src/Calculator:calculator_nunit_test`
- `//src/CalculatorApp:calculatorapp_nunit_test` (the new test — proves the test-on-binary dependency compiles and runs)
- `//tests/CalculatorXunitTests:calculatorxunittests_xunit_test`

- [x] **Step 13: Commit the e2e changes**

Run from the repo root:

```bash
cd /home/jhobert/Projects/Gazelle/rules_dotnet
git add e2e/gazelle_net10.0/src/CalculatorApp
git commit -m "Add e2e NUnit test for the CalculatorApp entry-point directory"
```

---

## Self-review notes (for the implementer)

Assumptions baked into this plan, flagged for awareness:

1. **gazelle and rules_go are non-dev dependencies** of rules_dotnet. The spec says "dev-dependencies", but bzlmod ignores dev-dependencies of non-root modules, which would break `gazelle_binary(languages = ["@rules_dotnet//dotnet/gazelle"])` in consumer workspaces. This was verified experimentally.
2. **Three directives beyond the spec's table** (`dotnet_project_sdk`, `dotnet_visibility`, `dotnet_unresolved_imports`) exist because the spec text requires project_sdk/visibility "via directives" and configurable unresolved-import handling.
3. **NuGet labels use the first configured TFM** (`tfm[0]`) when building `@<prefix><tfm>//<id>` labels, matching the single-tfm `packages.lock.json` files used by the packages_lock extension today.
4. **Resolve preserves existing deps**: the resolve phase unions resolved labels into `deps` rather than replacing them, which keeps the generate-time sibling dep and any manually maintained deps; `# keep` semantics on other attrs are unaffected.
5. The xunit shim relies on `Xunit.Runner.InProc.SystemConsole.ConsoleRunner.Run` (xunit.v3.core) and the MSTest shim on `TestApplication.CreateBuilderAsync` + the `AddMSTest` extension in `Microsoft.VisualStudio.TestTools.UnitTesting`; both were verified to compile against the pinned package versions. Task 2 Step 5 has a fallback instruction if the xunit API differs.

