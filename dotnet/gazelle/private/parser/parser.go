// Package parser extracts build metadata from C# source files: the declared
// namespace, using directives, test framework markers and entry points.
//
// It is a lightweight lexer/regex parser, not a full C# grammar. Comments
// and string literals are blanked before matching so markers inside them are
// ignored. Known limitation: interpolated strings ($"") are treated as
// opaque, so a quote inside an interpolation hole ends the string early;
// this can only cause false metadata in pathological sources.
package parser

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

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
	src = strings.TrimPrefix(src, "\uFEFF")
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
