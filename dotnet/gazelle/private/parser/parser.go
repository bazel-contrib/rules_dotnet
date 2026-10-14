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
