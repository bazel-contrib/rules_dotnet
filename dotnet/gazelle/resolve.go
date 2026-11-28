package gazelle

import (
	"fmt"
	"log"
	"path/filepath"
	"sort"
	"strings"

	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/dotnetconfig"
	"github.com/bazel-contrib/rules_dotnet/dotnet/gazelle/private/parser"
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
	// refs are the identifier and dotted-name chains referenced in the rule's
	// sources outside comments, strings, using, and namespace directives.
	refs []string
	// internalTypes are the fully-qualified top-level internal type names
	// declared by the rule's sources (e.g. "Foo.Bar.Helper"), sorted.
	internalTypes []string
}

// consumerInfo holds the metadata a C# target needs to be checked as a
// consumer of another target's internal types.
type consumerInfo struct {
	assemblyName string
	usings       []string
	aliases      map[string]string
	own          []string
	refs         []string
}

// consumerKey identifies a workspace rule in Resolver.consumers independently
// of c.RepoName stamping.
type consumerKey struct {
	pkg  string
	name string
}

// Resolver satisfies resolve.Resolver for C#.
type Resolver struct {
	lang      *csharpLang
	consumers map[consumerKey]consumerInfo
}

// NewResolver creates the Resolver for l.
func NewResolver(lang *csharpLang) *Resolver {
	return &Resolver{
		lang:      lang,
		consumers: map[consumerKey]consumerInfo{},
	}
}

// Name implements resolve.Resolver.
func (*Resolver) Name() string { return languageName }

// Imports implements resolve.Resolver. Generated csharp_library and
// csharp_binary rules are indexed by the namespaces and fully-qualified types
// their sources declare. Hand-written csharp_library rules (without private
// attrs) are indexed by parsing their .cs srcs relative to the BUILD file's
// directory. All C# rules carrying consumer metadata are also indexed under
// nsConsumerLanguageName so providers with internal types can populate
// internals_visible_to during Resolve.
func (r *Resolver) Imports(c *config.Config, ru *rule.Rule, f *rule.File) []resolve.ImportSpec {
	kind := ru.Kind()
	if c != nil {
		if aliased, ok := c.AliasMap[kind]; ok {
			kind = aliased
		}
	}
	if !isCsharpKind(kind) {
		return nil
	}

	var namespaces, types []string
	var ci consumerInfo
	hasConsumer := false

	if kind == "csharp_library" || kind == "csharp_binary" {
		namespaces, _ = ru.PrivateAttr(namespacesKey).([]string)
		types, _ = ru.PrivateAttr(typesKey).([]string)
	}
	if attr, ok := ru.PrivateAttr(consumerInfoKey).(consumerInfo); ok {
		ci = attr
		hasConsumer = true
	}

	if !hasConsumer && f != nil {
		dir := filepath.Dir(f.Path)
		var parsed []*parser.File
		for _, src := range ru.AttrStrings("srcs") {
			if !strings.HasSuffix(src, ".cs") {
				continue
			}
			pf, err := parser.ParseFile(filepath.Join(dir, src))
			if err != nil {
				continue
			}
			parsed = append(parsed, pf)
		}
		if len(parsed) > 0 {
			parsedOwn := namespacesOf(parsed)
			if kind == "csharp_library" && len(namespaces) == 0 && len(types) == 0 {
				namespaces = parsedOwn
				types = typesOf(parsed)
			}
			ci = consumerInfo{
				usings:  usingNamespaces(parsed),
				aliases: usingAliases(parsed),
				own:     parsedOwn,
				refs:    referencedNames(parsed),
			}
			hasConsumer = true
		}
	}

	var consumerNamespaces []string
	if hasConsumer && f != nil {
		asmName := ru.AttrString("out")
		if asmName == "" {
			asmName = ru.Name()
		}
		ci.assemblyName = asmName
		if r.consumers == nil {
			r.consumers = map[consumerKey]consumerInfo{}
		}
		r.consumers[consumerKey{pkg: f.Pkg, name: ru.Name()}] = ci
		consumerNamespaces = consumerLookupNamespaces(ci)
	}

	if len(namespaces) == 0 && len(types) == 0 && len(consumerNamespaces) == 0 {
		return nil
	}
	specs := make([]resolve.ImportSpec, 0, len(namespaces)+len(types)+len(consumerNamespaces))
	for _, ns := range namespaces {
		specs = append(specs, resolve.ImportSpec{Lang: languageName, Imp: ns})
	}
	for _, typ := range types {
		specs = append(specs, resolve.ImportSpec{Lang: typeLanguageName, Imp: typ})
	}
	for _, ns := range consumerNamespaces {
		specs = append(specs, resolve.ImportSpec{Lang: nsConsumerLanguageName, Imp: ns})
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
		if overrides, ok := r.resolveOverride(cfg, imp); ok {
			for _, override := range overrides {
				deps[override] = true
			}
			continue
		}
		if depLabels, ok := r.findWorkspaceRules(c, ix, imp, from); ok {
			for _, dep := range depLabels {
				deps[dep] = true
			}
			continue
		}
		if own[imp] {
			continue
		}
		if isTestFrameworkProvidedNamespace(imp, ru.Kind()) {
			// Provided by the test rule macro's injected framework deps.
			continue
		}
		if len(cfg.TargetFrameworks()) > 0 {
			id, err := r.lang.nugetIndex.Resolve(imp)
			if err != nil {
				log.Fatalf("%v: set a '# gazelle:%s' directive to resolve the ambiguity", err, dotnetconfig.DotnetResolve)
			}
			if id != "" {
				deps[cfg.NugetLabel(id)] = true
				continue
			}
		}
		if depLabels, ok := r.resolveParentWorkspace(c, ix, imp, from); ok {
			for _, dep := range depLabels {
				deps[dep] = true
			}
			continue
		}
		if isSdkProvidedNamespace(imp, ru.AttrString("project_sdk")) {
			// Provided by the .NET SDK targeting pack.
			continue
		}
		msg := fmt.Sprintf("unresolved C# import %q for %s", imp, from)
		if cfg.UnresolvedImports() == "error" {
			log.Fatalf("%s: set a '# gazelle:%s %s <label>' directive to resolve it", msg, dotnetconfig.DotnetResolve, imp)
		}
		log.Printf("warning: %s", msg)
	}

	if len(input.refs) > 0 {
		scopes := enclosingScopes(input.own)
		checked := map[string]bool{}
		for _, ref := range input.refs {
			for _, prefix := range dotPrefixes(ref) {
				if checked[prefix] {
					continue
				}
				checked[prefix] = true
				for _, scope := range scopes {
					fq := prefix
					if scope != "" {
						fq = scope + "." + prefix
					} else if !strings.Contains(fq, ".") {
						continue
					}
					if depLabels, ok := r.findWorkspaceRulesBySpec(c, ix, resolve.ImportSpec{Lang: typeLanguageName, Imp: fq}, from); ok {
						for _, dep := range depLabels {
							deps[dep] = true
						}
						break
					}
				}
			}
		}
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

	if len(input.internalTypes) > 0 {
		ivt := map[string]bool{}
		for _, existing := range ru.AttrStrings("internals_visible_to") {
			ivt[existing] = true
		}
		for _, fqType := range input.internalTypes {
			dot := strings.LastIndex(fqType, ".")
			if dot <= 0 {
				continue
			}
			ns := fqType[:dot]
			typeName := fqType[dot+1:]
			for queryNs := ns; queryNs != ""; queryNs = parentNamespace(queryNs) {
				matches := ix.FindRulesByImportWithConfig(c, resolve.ImportSpec{Lang: nsConsumerLanguageName, Imp: queryNs}, languageName)
				for _, m := range matches {
					if m.IsSelfImport(from) {
						continue
					}
					ci, ok := r.consumers[consumerKey{pkg: m.Label.Pkg, name: m.Label.Name}]
					if !ok || ci.assemblyName == "" {
						continue
					}
					if consumerReferencesInternalType(ci, ns, typeName) {
						ivt[ci.assemblyName] = true
					}
				}
			}
		}
		sortedIvt := make([]string, 0, len(ivt))
		for a := range ivt {
			sortedIvt = append(sortedIvt, a)
		}
		sort.Strings(sortedIvt)
		ru.DelAttr("internals_visible_to")
		if len(sortedIvt) > 0 {
			ru.SetAttr("internals_visible_to", sortedIvt)
		}
	}
}

// resolveOverride walks imp and its enclosing namespaces to find an explicit
// # gazelle:dotnet_resolve override.
func (r *Resolver) resolveOverride(cfg *dotnetconfig.Config, imp string) ([]string, bool) {
	for ns := imp; ns != ""; ns = parentNamespace(ns) {
		if overrides, ok := cfg.ResolveOverride(ns); ok {
			return overrides, true
		}
	}
	return nil, false
}

// resolveParentWorkspace walks enclosing namespaces of imp in the RuleIndex
// for `using static` imports against workspace targets.
func (r *Resolver) resolveParentWorkspace(c *config.Config, ix *resolve.RuleIndex, imp string, from label.Label) ([]string, bool) {
	for ns := parentNamespace(imp); ns != ""; ns = parentNamespace(ns) {
		if depLabels, ok := r.findWorkspaceRules(c, ix, ns, from); ok {
			return depLabels, true
		}
	}
	return nil, false
}

func (r *Resolver) findWorkspaceRules(c *config.Config, ix *resolve.RuleIndex, ns string, from label.Label) ([]string, bool) {
	return r.findWorkspaceRulesBySpec(c, ix, resolve.ImportSpec{Lang: languageName, Imp: ns}, from)
}

func (r *Resolver) findWorkspaceRulesBySpec(c *config.Config, ix *resolve.RuleIndex, spec resolve.ImportSpec, from label.Label) ([]string, bool) {
	matches := ix.FindRulesByImportWithConfig(c, spec, languageName)
	if len(matches) == 0 {
		return nil, false
	}
	var depLabels []string
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
		depLabels = append(depLabels, l.String())
	}
	return depLabels, true
}

// enclosingScopes returns own namespaces, all their enclosing parent
// namespaces ordered deepest-first (then lexically), and "" (global scope)
// last, deduplicated.
func enclosingScopes(own []string) []string {
	seen := map[string]bool{}
	var scopes []string
	for _, ns := range own {
		for cur := ns; cur != ""; cur = parentNamespace(cur) {
			if !seen[cur] {
				seen[cur] = true
				scopes = append(scopes, cur)
			}
		}
	}
	sort.Slice(scopes, func(i, j int) bool {
		di := strings.Count(scopes[i], ".")
		dj := strings.Count(scopes[j], ".")
		if di != dj {
			return di > dj
		}
		return scopes[i] < scopes[j]
	})
	scopes = append(scopes, "")
	return scopes
}

// dotPrefixes returns all dot-delimited prefixes of chain:
// "A.B.C" -> ["A", "A.B", "A.B.C"].
func dotPrefixes(chain string) []string {
	var out []string
	for i := 0; i < len(chain); i++ {
		if chain[i] == '.' {
			out = append(out, chain[:i])
		}
	}
	out = append(out, chain)
	return out
}

// consumerLookupNamespaces returns the sorted, deduplicated namespaces under
// which a consumer should be indexed for reverse internals_visible_to lookup.
func consumerLookupNamespaces(ci consumerInfo) []string {
	seen := map[string]bool{}
	var out []string
	add := func(ns string) {
		if ns != "" && !seen[ns] {
			seen[ns] = true
			out = append(out, ns)
		}
	}
	for _, u := range ci.usings {
		add(u)
		// Also index parentNamespace(u) to catch `using static Ns.Type;`
		// or `using Alias = Ns.Type;`.
		add(parentNamespace(u))
	}
	for _, scope := range enclosingScopes(ci.own) {
		add(scope)
	}
	for _, ref := range ci.refs {
		if parent := parentNamespace(ref); parent != "" {
			for _, prefix := range dotPrefixes(parent) {
				add(prefix)
			}
		}
	}
	sort.Strings(out)
	return out
}

// consumerReferencesInternalType reports whether ci references the internal
// type ns.typeName via its using directives, own/enclosing namespaces, or a
// relative/fully-qualified name.
func consumerReferencesInternalType(ci consumerInfo, ns, typeName string) bool {
	fq := ns + "." + typeName

	// Direct match via `using static Ns.Type;` or `using Alias = Ns.Type;`.
	directVisible := false
	for _, u := range ci.usings {
		if u == fq {
			return true
		}
		if u == ns {
			directVisible = true
		}
	}

	// Build candidate prefixes in ci.refs that would resolve to ns.typeName.
	wantPrefixes := map[string]bool{
		fq: true,
	}
	for alias, target := range ci.aliases {
		if target == ns {
			wantPrefixes[alias+"."+typeName] = true
		}
	}
	for _, scope := range enclosingScopes(ci.own) {
		if scope == "" {
			continue
		}
		if scope == ns {
			directVisible = true
		} else if strings.HasPrefix(ns, scope+".") {
			relNs := strings.TrimPrefix(ns, scope+".")
			wantPrefixes[relNs+"."+typeName] = true
		}
	}
	if directVisible {
		wantPrefixes[typeName] = true
	}

	for _, ref := range ci.refs {
		for _, prefix := range dotPrefixes(ref) {
			if wantPrefixes[prefix] {
				return true
			}
		}
	}
	return false
}

// hasNamespacePrefix reports whether ns equals base or is a dot-delimited
// sub-namespace (or static type import) under base.
func hasNamespacePrefix(ns, base string) bool {
	return ns == base || strings.HasPrefix(ns, base+".")
}

// isTestFrameworkProvidedNamespace reports whether ns is implicitly supplied
// by the test rule macro's injected framework dependencies for ruleKind.
func isTestFrameworkProvidedNamespace(ns, ruleKind string) bool {
	switch ruleKind {
	case "csharp_nunit_test":
		return hasNamespacePrefix(ns, "NUnit.Framework") || hasNamespacePrefix(ns, "NUnitLite")
	case "csharp_xunit_test":
		return hasNamespacePrefix(ns, "Xunit")
	case "csharp_mstest_test":
		return hasNamespacePrefix(ns, "Microsoft.VisualStudio.TestTools.UnitTesting") ||
			hasNamespacePrefix(ns, "Microsoft.Testing.Platform")
	default:
		return false
	}
}

// isWebBackedSdk reports whether projectSdk links against the
// Microsoft.AspNetCore.App targeting pack.
func isWebBackedSdk(projectSdk string) bool {
	switch projectSdk {
	case "web", "razor", "blazorwasm":
		return true
	default:
		return false
	}
}

// isWebSdkNamespace reports whether ns is a namespace provided by the
// Microsoft.AspNetCore.App shared framework.
func isWebSdkNamespace(ns string) bool {
	return ns == "Microsoft.AspNetCore" ||
		strings.HasPrefix(ns, "Microsoft.AspNetCore.") ||
		ns == "Microsoft.Net.Http.Headers" ||
		strings.HasPrefix(ns, "Microsoft.Net.Http.Headers.")
}

// isSdkProvidedNamespace reports whether ns is provided by the .NET SDK
// targeting packs for projectSdk (base class library, plus ASP.NET Core
// shared framework for web-backed SDKs).
func isSdkProvidedNamespace(ns, projectSdk string) bool {
	if ns == "System" || strings.HasPrefix(ns, "System.") {
		return true
	}
	if isWebBackedSdk(projectSdk) && isWebSdkNamespace(ns) {
		return true
	}
	return false
}

// parentNamespace strips the last dot segment: "A.B.C" -> "A.B", "A" -> "".
func parentNamespace(ns string) string {
	i := strings.LastIndex(ns, ".")
	if i < 0 {
		return ""
	}
	return ns[:i]
}
