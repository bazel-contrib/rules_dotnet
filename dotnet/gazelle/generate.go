package gazelle

import (
	"github.com/bazelbuild/bazel-gazelle/language"
)

// GenerateRules implements language.Language. Rule generation is added on
// top of this skeleton in a later step; until then no rules are generated.
func (l *csharpLang) GenerateRules(args language.GenerateArgs) language.GenerateResult {
	return language.GenerateResult{}
}
