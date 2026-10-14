package nuget

import (
	"os"
	"path/filepath"
	"testing"
)

const testLock = `{
  "version": 1,
  "dependencies": {
    "net10.0": {
      "Newtonsoft.Json": {
        "type": "Direct",
        "requested": "[13.0.3, )",
        "resolved": "13.0.3",
        "contentHash": "HrC5BXdl00IP9zeV+0Z848QWPAoCr9P3bDEZguI+gkLcBKAOxix/tLEAAHC+UvDNPv4a2d18lOReHMOagPa+zQ=="
      },
      "Microsoft.Testing.Platform": {
        "type": "Transitive",
        "resolved": "1.4.3"
      }
    }
  }
}`

func writeLock(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "packages.lock.json")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestLoadIndexAndResolve(t *testing.T) {
	idx, err := LoadIndex(writeLock(t, testLock))
	if err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		namespace string
		want      string
	}{
		{"Newtonsoft.Json", "newtonsoft.json"},
		{"Newtonsoft.Json.Linq", "newtonsoft.json"},
		{"Microsoft.Testing.Platform.Builder", "microsoft.testing.platform"},
		{"System", ""},
		{"Acme.Does.Not.Exist", ""},
	}
	for _, tc := range tests {
		got, err := idx.Resolve(tc.namespace)
		if err != nil {
			t.Fatalf("Resolve(%q) unexpected error: %v", tc.namespace, err)
		}
		if got != tc.want {
			t.Errorf("Resolve(%q) = %q, want %q", tc.namespace, got, tc.want)
		}
	}
}

func TestResolveAmbiguousCaseVariants(t *testing.T) {
	lock := `{"version": 1, "dependencies": {"net10.0": {"Contoso.Widget": {"type": "Direct"}, "contoso.widget": {"type": "Direct"}}}}`
	idx, err := LoadIndex(writeLock(t, lock))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := idx.Resolve("Contoso.Widget.Core"); err == nil {
		t.Fatal("Resolve() = nil error, want ambiguity error")
	}
}

func TestResolveNilIndex(t *testing.T) {
	var idx *Index
	got, err := idx.Resolve("Newtonsoft.Json")
	if err != nil || got != "" {
		t.Fatalf("nil index Resolve() = %q, %v; want \"\", nil", got, err)
	}
}

func TestLoadIndexInvalidJSON(t *testing.T) {
	if _, err := LoadIndex(writeLock(t, "not json")); err == nil {
		t.Fatal("LoadIndex() = nil error, want parse error")
	}
}
