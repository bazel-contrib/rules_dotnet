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
	fs.StringVar(&cr.nugetLockFile, "dotnet_nuget_lock_file", "nuget_resolve.json",
		"Path of the nuget_resolve.json file, relative to the repository root.")
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
			log.Printf("no nuget_resolve.json at %s; NuGet resolution is disabled", lockPath)
		default:
			log.Fatalf("error loading %s: %v", lockPath, err)
		}
	}
	if len(cfg.TargetFrameworks()) == 0 {
		log.Fatalf("missing directive: add '# gazelle:%s <tfm>[,<tfm>...]' to the root BUILD file", dotnetconfig.DotnetTargetFrameworks)
	}
}
