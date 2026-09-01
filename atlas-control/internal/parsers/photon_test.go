package parsers

import (
	"bufio"
	"math"
	"os"
	"path/filepath"
	"testing"
)

func feedFixture(t *testing.T, p Parser, fixture string) Result {
	t.Helper()
	path := filepath.Join("..", "..", "testdata", fixture)
	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("open fixture %s: %v", fixture, err)
	}
	defer f.Close()

	var last Result
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		last = p.Feed(scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		t.Fatalf("scan fixture %s: %v", fixture, err)
	}
	return last
}

func TestPhotonDownloadProgress(t *testing.T) {
	p := NewPhotonParser()
	result := feedFixture(t, p, "photon-download.log")

	if result.Phase != "downloading" {
		t.Errorf("phase = %q, want %q", result.Phase, "downloading")
	}
	if math.Abs(result.Progress-0.125) > 0.0001 {
		t.Errorf("progress = %v, want ~0.125", result.Progress)
	}
	if result.Ready {
		t.Errorf("ready = true, want false during download")
	}
}

func TestPhotonExtract(t *testing.T) {
	p := NewPhotonParser()
	feedFixture(t, p, "photon-download.log")
	result := feedFixture(t, p, "photon-extract.log")

	if result.Phase != "extracting" {
		t.Errorf("phase = %q, want %q", result.Phase, "extracting")
	}
	if result.Ready {
		t.Errorf("ready = true, want false during extract")
	}
}

func TestPhotonReady(t *testing.T) {
	p := NewPhotonParser()
	feedFixture(t, p, "photon-download.log")
	feedFixture(t, p, "photon-extract.log")
	result := feedFixture(t, p, "photon-ready.log")

	if result.Phase != "ready" {
		t.Errorf("phase = %q, want %q", result.Phase, "ready")
	}
	if !result.Ready {
		t.Errorf("ready = false, want true")
	}
}
