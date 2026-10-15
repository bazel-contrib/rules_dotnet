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

// parentNamespace strips the last dot segment: "A.B.C" -> "A.B", "A" -> "".
func parentNamespace(ns string) string {
	i := strings.LastIndex(ns, ".")
	if i < 0 {
		return ""
	}
	return ns[:i]
}
