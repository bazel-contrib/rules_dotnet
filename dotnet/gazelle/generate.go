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
		// Binaries advertise their namespaces like libraries do, so a
		// test (or another package) can resolve a using directive to the
		// binary target.
		r.SetPrivateAttr(namespacesKey, namespacesOf([]*parser.File{f}))
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
