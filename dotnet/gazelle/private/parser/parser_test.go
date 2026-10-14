package parser

import (
	"strings"
	"testing"
)

func TestBlankCommentsAndStrings(t *testing.T) {
	tests := []struct {
		name    string
		src     string
		want    string
		wantErr string
	}{
		{
			name: "line comment",
			src:  "using X; // using Y;\nnamespace Z;",
			want: "using X;            \nnamespace Z;",
		},
		{
			name: "block comment with newlines",
			src:  "a /* one\ntwo */ b",
			want: "a       \n       b",
		},
		{
			name: "double quoted string",
			src:  `var s = "namespace Fake;";` + "\nnamespace Real;",
			want: "var s =                  ;" + "\nnamespace Real;",
		},
		{
			name: "string with escaped quote",
			src:  `var s = "a\"b"; namespace R;`,
			want: `var s =       ; namespace R;`,
		},
		{
			name: "char literal",
			src:  "var c = 'x'; namespace R;",
			want: "var c =    ; namespace R;",
		},
		{
			name: "verbatim string with doubled quote",
			src:  `var s = @"a""b"; namespace R;`,
			want: `var s =        ; namespace R;`,
		},
		{
			name: "verbatim multiline string keeps newlines",
			src:  "var s = @\"one\ntwo\"; namespace R;",
			want: "var s =      \n    ; namespace R;",
		},
		{
			name: "interpolated string",
			src:  `var s = $"value: {x}"; namespace R;`,
			want: `var s =              ; namespace R;`,
		},
		{
			name: "raw string",
			src:  "var s = \"\"\"namespace Fake;\"\"\"; namespace R;",
			want: "var s =                      ; namespace R;",
		},
		{
			name: "verbatim identifier is not a string",
			src:  "var @class = 1; namespace R;",
			want: "var @class = 1; namespace R;",
		},
		{
			name:    "unterminated string",
			src:     `var s = "oops;`,
			wantErr: "unterminated string",
		},
		{
			name:    "unterminated block comment",
			src:     "a /* oops",
			wantErr: "unterminated block comment",
		},
		{
			name:    "unterminated raw string",
			src:     "var s = \"\"\"oops",
			wantErr: "unterminated raw string",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := blankCommentsAndStrings(tc.src)
			if tc.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
					t.Fatalf("blankCommentsAndStrings() error = %v, want substring %q", err, tc.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("blankCommentsAndStrings() unexpected error: %v", err)
			}
			if got != tc.want {
				t.Errorf("blankCommentsAndStrings()\n got: %q\nwant: %q", got, tc.want)
			}
		})
	}
}
