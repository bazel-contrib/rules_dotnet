// Package nuget indexes the package IDs of a packages.lock.json file and
// resolves C# namespaces to package IDs by longest prefix match.
package nuget

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// lockFile mirrors the relevant structure of packages.lock.json:
// dependencies -> target framework -> package ID -> dependency entry.
// Only the package IDs (the map keys) are used.
type lockFile struct {
	Dependencies map[string]map[string]json.RawMessage `json:"dependencies"`
}

// Index resolves namespaces to NuGet package IDs. A nil *Index is valid and
// resolves nothing (used when no packages.lock.json exists).
type Index struct {
	// ids maps lowercased package IDs to their original forms. More than
	// one original form means the lock file lists case variants of the same
	// ID, which would collide in Bazel repo target names.
	ids map[string][]string
}

// LoadIndex reads packages.lock.json from path.
func LoadIndex(path string) (*Index, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var lf lockFile
	if err := json.Unmarshal(data, &lf); err != nil {
		return nil, fmt.Errorf("parsing %s: %w", path, err)
	}
	idx := &Index{ids: map[string][]string{}}
	for _, deps := range lf.Dependencies {
		for id := range deps {
			lower := strings.ToLower(id)
			idx.ids[lower] = appendUnique(idx.ids[lower], id)
		}
	}
	return idx, nil
}

// Resolve maps namespace to a NuGet package ID by longest dot-segment
// prefix match ("Newtonsoft.Json.Linq" -> "Newtonsoft.Json"). The returned
// ID is lowercased, matching the repo target names that the nuget hub
// repository generates. It returns "" when no package ID matches, and an
// error when the match is ambiguous (case variants of the same ID).
func (i *Index) Resolve(namespace string) (string, error) {
	if i == nil {
		return "", nil
	}
	for prefix := strings.ToLower(namespace); prefix != ""; prefix = parentPrefix(prefix) {
		originals, ok := i.ids[prefix]
		if !ok {
			continue
		}
		if len(originals) > 1 {
			return "", fmt.Errorf("namespace %q matches multiple package IDs (%s)", namespace, strings.Join(originals, ", "))
		}
		return prefix, nil
	}
	return "", nil
}

// parentPrefix strips the last dot segment: "A.B.C" -> "A.B", "A" -> "".
func parentPrefix(ns string) string {
	i := strings.LastIndex(ns, ".")
	if i < 0 {
		return ""
	}
	return ns[:i]
}

func appendUnique(s []string, v string) []string {
	for _, e := range s {
		if e == v {
			return s
		}
	}
	return append(s, v)
}
