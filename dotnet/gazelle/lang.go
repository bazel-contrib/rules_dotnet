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
