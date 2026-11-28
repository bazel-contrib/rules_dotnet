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
	"sort"
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
	// Alias is the alias name for `using Alias = X.Y;`, or "" otherwise.
	Alias string
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
	// DeclaredTypes lists the sorted, deduplicated type names declared in the
	// file (class, struct, interface, enum, record, delegate).
	DeclaredTypes []string
	// InternalTypes lists the sorted, deduplicated top-level type names
	// declared without `public` (explicit `internal` or default-internal,
	// excluding `file`-scoped and nested types).
	InternalTypes []string
	// ReferencedNames lists the sorted, deduplicated identifier and
	// dot-separated name chains found outside comments, strings, using, and
	// namespace directives.
	ReferencedNames []string
}

var (
	namespaceRe      = regexp.MustCompile(`^namespace[ \t]+([A-Za-z_][A-Za-z0-9_.]*)(.*)`)
	globalUsingRe    = regexp.MustCompile(`^global[ \t]+(using[ \t]+.*)`)
	usingRe          = regexp.MustCompile(`^using\s+(static\s+)?(?:([A-Za-z_][A-Za-z0-9_]*)\s*=\s*)?([A-Za-z_][A-Za-z0-9_.]*)\s*;`)
	entryPointRe     = regexp.MustCompile(`\bstatic\s+(?:async\s+)?(?:void|int|Task|Task<int>|ValueTask|ValueTask<int>)\s+Main\s*\(`)
	typeDeclRe       = regexp.MustCompile(`\b(?:class|struct|interface|record|enum|delegate)\s+[A-Za-z_]`)
	typeDeclNameRe   = regexp.MustCompile(`\b(?:class|struct|interface|enum|record(?:[ \t]+(?:class|struct))?)[ \t]+([A-Za-z_][A-Za-z0-9_]*)`)
	delegateNameRe   = regexp.MustCompile(`\bdelegate[ \t]+(?:\([^)\n;]+\)|[^({\n;]+)[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?:<[^>]+>)?[ \t]*\(`)
	fileScopedRe     = regexp.MustCompile(`\bfile[ \t]+(?:(?:abstract|sealed|static|partial|readonly|ref|unsafe|new)[ \t]+)*(?:class|struct|interface|enum|record(?:[ \t]+(?:class|struct))?|delegate)\b`)
	publicTypeDeclRe = regexp.MustCompile(`\bpublic[ \t]+(?:(?:abstract|sealed|static|partial|readonly|ref|unsafe|new)[ \t]+)*(?:class|struct|interface|enum|record(?:[ \t]+(?:class|struct))?|delegate)\b`)
	refChainRe       = regexp.MustCompile(`\b[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*\b`)
)

// csharpKeywords are reserved and common contextual C# keywords excluded from
// declared type names and single-segment referenced names.
var csharpKeywords = map[string]bool{
	"abstract": true, "as": true, "async": true, "await": true, "base": true,
	"bool": true, "break": true, "byte": true, "case": true, "catch": true,
	"char": true, "checked": true, "class": true, "const": true, "continue": true,
	"decimal": true, "default": true, "delegate": true, "do": true, "double": true,
	"dynamic": true, "else": true, "enum": true, "event": true, "explicit": true,
	"extern": true, "false": true, "file": true, "finally": true, "fixed": true,
	"float": true, "for": true, "foreach": true, "from": true, "get": true,
	"global": true, "goto": true, "if": true, "implicit": true, "in": true,
	"init": true, "int": true, "interface": true, "internal": true, "is": true,
	"let": true, "lock": true, "long": true, "nameof": true, "namespace": true,
	"new": true, "nint": true, "not": true, "notnull": true, "nuint": true,
	"null": true, "object": true, "operator": true, "or": true, "orderby": true,
	"out": true, "override": true, "params": true, "partial": true, "private": true,
	"protected": true, "public": true, "readonly": true, "record": true, "ref": true,
	"required": true, "return": true, "sbyte": true, "scoped": true, "sealed": true,
	"select": true, "set": true, "short": true, "sizeof": true, "stackalloc": true,
	"static": true, "string": true, "struct": true, "switch": true, "this": true,
	"throw": true, "true": true, "try": true, "typeof": true, "uint": true,
	"ulong": true, "unchecked": true, "unmanaged": true, "unsafe": true, "ushort": true,
	"using": true, "value": true, "var": true, "virtual": true, "void": true,
	"volatile": true, "when": true, "where": true, "while": true, "with": true,
	"yield": true,
}

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

	refSet := map[string]bool{}
	declaredSet := map[string]bool{}
	internalSet := map[string]bool{}
	braceDepth := 0
	topLevelDepth := 0
	var topLevelBuf strings.Builder

	flushTopLevel := func() {
		if topLevelBuf.Len() == 0 {
			return
		}
		segment := topLevelBuf.String()
		topLevelBuf.Reset()
		for _, stmt := range strings.Split(segment, ";") {
			if fileScopedRe.MatchString(stmt) {
				continue
			}
			isPublic := publicTypeDeclRe.MatchString(stmt)
			for _, m := range typeDeclNameRe.FindAllStringSubmatch(stmt, -1) {
				if !csharpKeywords[m[1]] {
					declaredSet[m[1]] = true
					if !isPublic {
						internalSet[m[1]] = true
					}
				}
			}
			for _, m := range delegateNameRe.FindAllStringSubmatch(stmt, -1) {
				if !csharpKeywords[m[1]] {
					declaredSet[m[1]] = true
					if !isPublic {
						internalSet[m[1]] = true
					}
				}
			}
		}
	}

	appendTopLevel := func(s string) {
		s = strings.TrimSpace(s)
		if s == "" {
			return
		}
		if topLevelBuf.Len() > 0 {
			topLevelBuf.WriteByte(' ')
		}
		topLevelBuf.WriteString(s)
	}

	for _, line := range strings.Split(blanked, "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") {
			flushTopLevel()
			continue
		}
		global := false
		if m := globalUsingRe.FindStringSubmatch(trimmed); m != nil {
			global = true
			trimmed = m[1]
		}
		if m := usingRe.FindStringSubmatch(trimmed); m != nil {
			flushTopLevel()
			f.Usings = append(f.Usings, Using{
				Alias:     m[2],
				Namespace: m[3],
				Static:    m[1] != "",
				Global:    global,
			})
			continue
		}
		if m := namespaceRe.FindStringSubmatch(trimmed); m != nil {
			flushTopLevel()
			if f.Namespace == "" {
				f.Namespace = m[1]
			}
			rest := strings.TrimSpace(m[2])
			if strings.HasPrefix(rest, ";") {
				topLevelDepth = braceDepth
				trimmed = strings.TrimSpace(strings.TrimPrefix(rest, ";"))
			} else {
				topLevelDepth = braceDepth + 1
				trimmed = rest
			}
			if trimmed == "" {
				continue
			}
		}
		for _, match := range refChainRe.FindAllString(trimmed, -1) {
			if !strings.Contains(match, ".") && csharpKeywords[match] {
				continue
			}
			refSet[match] = true
		}

		segStart := 0
		for i := 0; i < len(trimmed); i++ {
			switch trimmed[i] {
			case '{':
				if braceDepth == topLevelDepth {
					appendTopLevel(trimmed[segStart:i])
					flushTopLevel()
				}
				braceDepth++
				segStart = i + 1
			case '}':
				if braceDepth == topLevelDepth {
					appendTopLevel(trimmed[segStart:i])
					flushTopLevel()
				}
				if braceDepth > 0 {
					braceDepth--
				}
				segStart = i + 1
			case ';':
				if braceDepth == topLevelDepth {
					appendTopLevel(trimmed[segStart : i+1])
					flushTopLevel()
				}
				segStart = i + 1
			}
		}
		if braceDepth == topLevelDepth && segStart < len(trimmed) {
			appendTopLevel(trimmed[segStart:])
		}
	}
	flushTopLevel()

	if len(declaredSet) > 0 {
		f.DeclaredTypes = make([]string, 0, len(declaredSet))
		for name := range declaredSet {
			f.DeclaredTypes = append(f.DeclaredTypes, name)
		}
		sort.Strings(f.DeclaredTypes)
	}
	if len(internalSet) > 0 {
		f.InternalTypes = make([]string, 0, len(internalSet))
		for name := range internalSet {
			f.InternalTypes = append(f.InternalTypes, name)
		}
		sort.Strings(f.InternalTypes)
	}
	if len(refSet) > 0 {
		f.ReferencedNames = make([]string, 0, len(refSet))
		for ref := range refSet {
			f.ReferencedNames = append(f.ReferencedNames, ref)
		}
		sort.Strings(f.ReferencedNames)
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
