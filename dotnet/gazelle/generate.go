package gazelle

import (
	"log"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/dotnetconfig"
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

// setNullableAndImplicitUsingsAttrs writes only explicitly configured values
// and returns exactly those attribute names for the existing-rule merge below.
func setNullableAndImplicitUsingsAttrs(r *rule.Rule, cfg *dotnetconfig.Config) map[string]bool {
	configured := map[string]bool{}
	if value, isConfigured := cfg.Nullable(); isConfigured {
		r.SetAttr("nullable", value)
		configured["nullable"] = true
	}
	if value, isConfigured := cfg.ImplicitUsings(); isConfigured {
		r.SetAttr("implicit_usings", value)
		configured["implicit_usings"] = true
	}
	return configured
}

// mergeScalarAttrs applies explicit directives (nullable, implicit_usings,
// project_sdk) and safe auto-detected project_sdk upgrades ("default" -> "web")
// to the one existing rule matched by kind and name. Gazelle otherwise
// preserves existing non-mergeable scalars. A stub containing only the
// attributes to update keeps other attributes untouched and delegates # keep
// handling to MergeRules.
func mergeScalarAttrs(generated *rule.Rule, file *rule.File, cfg *dotnetconfig.Config, aliasedKinds map[string]string) {
	if file == nil {
		return
	}

	var existing *rule.Rule
	for _, candidate := range file.Rules {
		if candidate.Name() != generated.Name() {
			continue
		}
		kindMatches := candidate.Kind() == generated.Kind() || aliasedKinds[candidate.Kind()] == generated.Kind()
		if !kindMatches || existing != nil {
			// Match the normal merger's ambiguous-name behavior: do not update
			// any candidate when there is no unique kind-and-name match.
			return
		}
		existing = candidate
	}
	if existing == nil {
		return
	}

	override := rule.NewRule(generated.Kind(), generated.Name())
	mergeable := setNullableAndImplicitUsingsAttrs(override, cfg)

	genSdk := generated.AttrString("project_sdk")
	existingSdk := existing.AttrString("project_sdk")
	if cfg.ProjectSdkConfigured() || (genSdk == "web" && (existingSdk == "" || existingSdk == "default")) {
		override.SetAttr("project_sdk", genSdk)
		mergeable["project_sdk"] = true
	}

	if len(mergeable) > 0 {
		rule.MergeRules(override, existing, mergeable, file.Path)
	}
}

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
		// No C# sources left: existing csharp rules become empty so gazelle deletes them.
		return language.GenerateResult{Empty: emptyCsharpRules(args.File)}
	}
	sort.Slice(files, func(i, j int) bool { return files[i].Name < files[j].Name })

	dirName := path.Base(args.Rel)
	if dirName == "." || dirName == "/" || dirName == "" {
		dirName = filepath.Base(args.Dir)
	}
	libName := sanitizeName(dirName)

	claimed := claimedManualSrcs(args.File, libName, args.Config.AliasMap)

	var prodFiles []*parser.File
	testFiles := map[parser.Framework][]*parser.File{}
	var entryFiles []*parser.File

	for _, f := range files {
		if claimed[f.Name] {
			continue
		}
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
		lib.SetAttr("project_sdk", l.projectSdkFor(cfg, prodFiles))
		lib.SetAttr("visibility", cfg.Visibility())
		setNullableAndImplicitUsingsAttrs(lib, cfg)
		if len(testTargetNames) > 0 {
			var ivt []string
			for _, fw := range frameworkOrder {
				if name, ok := testTargetNames[fw]; ok {
					ivt = append(ivt, name)
				}
			}
			lib.SetAttr("internals_visible_to", ivt)
		}
		libUsings := usingNamespaces(prodFiles)
		libOwn := namespacesOf(prodFiles)
		libRefs := referencedNames(prodFiles)
		lib.SetPrivateAttr(namespacesKey, libOwn)
		lib.SetPrivateAttr(typesKey, typesOf(prodFiles))
		lib.SetPrivateAttr(consumerInfoKey, consumerInfo{
			usings:  libUsings,
			aliases: usingAliases(prodFiles),
			own:     libOwn,
			refs:    libRefs,
		})
		res.Gen = append(res.Gen, lib)
		res.Imports = append(res.Imports, resolveInput{
			imports:       libUsings,
			own:           libOwn,
			refs:          libRefs,
			internalTypes: internalTypesOf(prodFiles),
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
		r.SetAttr("project_sdk", l.projectSdkFor(cfg, files))
		r.SetAttr("visibility", cfg.Visibility())
		setNullableAndImplicitUsingsAttrs(r, cfg)
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
		testUsings := usingNamespaces(files)
		testOwn := namespacesOf(files)
		testRefs := referencedNames(files)
		r.SetPrivateAttr(consumerInfoKey, consumerInfo{
			usings:  testUsings,
			aliases: usingAliases(files),
			own:     testOwn,
			refs:    testRefs,
		})
		res.Gen = append(res.Gen, r)
		res.Imports = append(res.Imports, resolveInput{
			imports: testUsings,
			own:     testOwn,
			refs:    testRefs,
		})
	}

	for _, f := range entryFiles {
		name := sanitizeName(strings.TrimSuffix(f.Name, ".cs"))
		r := rule.NewRule("csharp_binary", name)
		r.SetAttr("srcs", []string{f.Name})
		r.SetAttr("target_frameworks", cfg.TargetFrameworks())
		r.SetAttr("project_sdk", l.projectSdkFor(cfg, []*parser.File{f}))
		r.SetAttr("visibility", cfg.Visibility())
		setNullableAndImplicitUsingsAttrs(r, cfg)
		// Binaries advertise their namespaces like libraries do, so a
		// test (or another package) can resolve a using directive to the
		// binary target.
		binFiles := []*parser.File{f}
		binUsings := usingNamespaces(binFiles)
		binOwn := namespacesOf(binFiles)
		binRefs := referencedNames(binFiles)
		r.SetPrivateAttr(namespacesKey, binOwn)
		r.SetPrivateAttr(typesKey, typesOf(binFiles))
		r.SetPrivateAttr(consumerInfoKey, consumerInfo{
			usings:  binUsings,
			aliases: usingAliases(binFiles),
			own:     binOwn,
			refs:    binRefs,
		})
		res.Gen = append(res.Gen, r)
		res.Imports = append(res.Imports, resolveInput{
			imports:       binUsings,
			own:           binOwn,
			refs:          binRefs,
			internalTypes: internalTypesOf(binFiles),
		})
	}

	for _, generated := range res.Gen {
		mergeScalarAttrs(generated, args.File, cfg, args.Config.AliasMap)
	}
	return res
}

// hasResolveOverride reports whether ns or any enclosing namespace has an
// explicit dotnet_resolve override, matching Resolver.Resolve's parent walk.
func hasResolveOverride(cfg *dotnetconfig.Config, ns string) bool {
	for cur := ns; cur != ""; cur = parentNamespace(cur) {
		if _, ok := cfg.ResolveOverride(cur); ok {
			return true
		}
	}
	return false
}

// projectSdkFor returns the project_sdk value for a generated target. An
// explicit dotnet_project_sdk directive always wins; otherwise, targets whose
// sources import an ASP.NET Core shared-framework namespace not declared by
// the target itself and not backed by a resolve override or NuGet package are
// upgraded to "web".
func (l *csharpLang) projectSdkFor(cfg *dotnetconfig.Config, files []*parser.File) string {
	if cfg.ProjectSdkConfigured() {
		return cfg.ProjectSdk()
	}
	own := map[string]bool{}
	for _, ns := range namespacesOf(files) {
		own[ns] = true
	}
	for _, imp := range usingNamespaces(files) {
		if !isWebSdkNamespace(imp) || own[imp] {
			continue
		}
		if hasResolveOverride(cfg, imp) {
			continue
		}
		if id, err := l.nugetIndex.Resolve(imp); err == nil && id != "" {
			continue
		}
		return "web"
	}
	return cfg.ProjectSdk()
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

// claimedManualSrcs returns the set of .cs file names already listed in srcs
// of existing hand-written csharp_library rules in file (any csharp_library
// whose name differs from the generated default libName).
func claimedManualSrcs(file *rule.File, libName string, aliasedKinds map[string]string) map[string]bool {
	claimed := map[string]bool{}
	if file == nil {
		return claimed
	}
	for _, r := range file.Rules {
		kind := r.Kind()
		if kind != "csharp_library" && aliasedKinds[kind] != "csharp_library" {
			continue
		}
		if r.Name() == libName {
			continue
		}
		for _, src := range r.AttrStrings("srcs") {
			claimed[src] = true
		}
	}
	return claimed
}

// typesOf returns the sorted, deduplicated fully-qualified type names declared
// by files ("Namespace.TypeName"). Files without a declared namespace are
// skipped so unnamespaced helper types (e.g. in top-level-statement binaries)
// do not pollute the global scope for the entire workspace.
func typesOf(files []*parser.File) []string {
	seen := map[string]bool{}
	var out []string
	for _, f := range files {
		if f.Namespace == "" {
			continue
		}
		for _, t := range f.DeclaredTypes {
			fq := f.Namespace + "." + t
			if !seen[fq] {
				seen[fq] = true
				out = append(out, fq)
			}
		}
	}
	sort.Strings(out)
	return out
}

// internalTypesOf returns the sorted, deduplicated fully-qualified top-level
// internal type names declared by files ("Namespace.TypeName"), skipping files
// without a declared namespace and excluding partial types that are declared
// public in another file of the same target.
func internalTypesOf(files []*parser.File) []string {
	publicTypes := map[string]bool{}
	for _, f := range files {
		if f.Namespace == "" {
			continue
		}
		fileInternal := map[string]bool{}
		for _, t := range f.InternalTypes {
			fileInternal[t] = true
		}
		for _, t := range f.DeclaredTypes {
			if !fileInternal[t] {
				publicTypes[f.Namespace+"."+t] = true
			}
		}
	}

	seen := map[string]bool{}
	var out []string
	for _, f := range files {
		if f.Namespace == "" {
			continue
		}
		for _, t := range f.InternalTypes {
			fq := f.Namespace + "." + t
			if publicTypes[fq] {
				continue
			}
			if !seen[fq] {
				seen[fq] = true
				out = append(out, fq)
			}
		}
	}
	sort.Strings(out)
	return out
}

// usingAliases returns a map of alias -> target namespace from `using A = Ns;`
// directives across files.
func usingAliases(files []*parser.File) map[string]string {
	var out map[string]string
	for _, f := range files {
		for _, u := range f.Usings {
			if u.Alias != "" {
				if out == nil {
					out = map[string]string{}
				}
				out[u.Alias] = u.Namespace
			}
		}
	}
	return out
}

// referencedNames returns the sorted, deduplicated union of ReferencedNames
// across files.
func referencedNames(files []*parser.File) []string {
	seen := map[string]bool{}
	var out []string
	for _, f := range files {
		for _, ref := range f.ReferencedNames {
			if !seen[ref] {
				seen[ref] = true
				out = append(out, ref)
			}
		}
	}
	sort.Strings(out)
	return out
}
