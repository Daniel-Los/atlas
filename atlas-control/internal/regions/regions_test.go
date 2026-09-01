package regions

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadSingleRegion(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "berlin.env"),
		[]byte("PBF_URL=https://x/berlin.pbf\nPBF_NAME=berlin.osm.pbf"), 0644); err != nil {
		t.Fatal(err)
	}

	r, err := Load(dir, "berlin")
	if err != nil {
		t.Fatal(err)
	}
	if len(r.PBFURLs) != 1 || r.PBFURLs[0] != "https://x/berlin.pbf" {
		t.Fatalf("unexpected pbf urls: %v", r.PBFURLs)
	}
	if r.PBFName != "berlin.osm.pbf" {
		t.Fatalf("unexpected pbf name: %q", r.PBFName)
	}
}

func TestLoadMultiRegion(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "dach.env"),
		[]byte(`PBF_URLS="https://x/de.pbf https://x/at.pbf"`), 0644); err != nil {
		t.Fatal(err)
	}

	r, err := Load(dir, "dach")
	if err != nil {
		t.Fatal(err)
	}
	if len(r.PBFURLs) != 2 {
		t.Fatalf("want 2 urls, got %v", r.PBFURLs)
	}
}
