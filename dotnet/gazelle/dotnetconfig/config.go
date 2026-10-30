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
	// DotnetNullable sets the nullable attr of generated C# targets.
	// Valid values are "disable", "enable", "warnings" and "annotations".
	DotnetNullable = "dotnet_nullable"
	// DotnetImplicitUsings sets the implicit_usings attr of generated C# targets.
	// Valid values are "disable" and "enable".
	DotnetImplicitUsings = "dotnet_implicit_usings"
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
	repoRoot                 string
	targetFrameworks         []string
	nugetRepoPrefix          string
	resolves                 map[string]string
	testFramework            string
	generateBinary           bool
	projectSdk               string
	nullable                 string
	nullableConfigured       bool
	implicitUsings           bool
	implicitUsingsConfigured bool
	visibility               []string
	unresolvedImports        string
	nugetLockFile            string
}

// New returns the root Config with default values.
func New(repoRoot string) *Config {
	return &Config{
		repoRoot:                 repoRoot,
		nugetRepoPrefix:          "nuget.",
		resolves:                 map[string]string{},
		generateBinary:           true,
		projectSdk:               "default",
		nullable:                 "",
		nullableConfigured:       false,
		implicitUsings:           false,
		implicitUsingsConfigured: false,
		unresolvedImports:        "warn",
		nugetLockFile:            "nuget_resolve.json",
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

// Nullable returns the nullable value and whether a directive configured it.
// The empty, unconfigured state is distinct from the rule default "disable".
func (c *Config) Nullable() (string, bool) { return c.nullable, c.nullableConfigured }

// SetNullable validates and sets the nullable directive value.
func (c *Config) SetNullable(value string) error {
	switch value {
	case "disable", "enable", "warnings", "annotations":
		c.nullable = value
		c.nullableConfigured = true
		return nil
	}
	return fmt.Errorf("possible values are disable/enable/warnings/annotations, got %q", value)
}

// ImplicitUsings returns the boolean value and whether a directive configured it.
// False, false means unset; false, true means explicitly disabled.
func (c *Config) ImplicitUsings() (bool, bool) {
	return c.implicitUsings, c.implicitUsingsConfigured
}

// SetImplicitUsings validates and sets the implicit-usings directive value.
func (c *Config) SetImplicitUsings(value string) error {
	switch value {
	case "disable":
		c.implicitUsings = false
	case "enable":
		c.implicitUsings = true
	default:
		return fmt.Errorf("possible values are disable/enable, got %q", value)
	}
	c.implicitUsingsConfigured = true
	return nil
}

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

// NugetLockFile returns the nuget_resolve.json path relative to the repo root.
func (c *Config) NugetLockFile() string { return c.nugetLockFile }

// SetNugetLockFile sets the nuget_resolve.json path relative to the repo root.
func (c *Config) SetNugetLockFile(v string) { c.nugetLockFile = v }

// NugetLabel returns the label of a NuGet package:
// "@<repo prefix><first target framework>//<lowercase package id>".
// It must only be called when TargetFrameworks() is non-empty.
func (c *Config) NugetLabel(packageID string) string {
	return fmt.Sprintf("@%s%s//%s", c.nugetRepoPrefix, c.targetFrameworks[0], strings.ToLower(packageID))
}
