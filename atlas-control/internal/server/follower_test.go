package server

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/dawarich-app/atlas/atlas-control/internal/state"
)

func TestRefreshDiskSumsFiles(t *testing.T) {
	dataDir := t.TempDir()
	photonDir := filepath.Join(dataDir, "photon")
	if err := os.MkdirAll(filepath.Join(photonDir, "sub"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(photonDir, "a.bin"), make([]byte, 1000), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(photonDir, "sub", "b.bin"), make([]byte, 500), 0644); err != nil {
		t.Fatal(err)
	}

	f := NewLogFollower(nil, state.New())
	f.dataDir = dataDir

	got := f.refreshDisk("photon")
	if got != 1500 {
		t.Errorf("refreshDisk = %d, want 1500", got)
	}
}

func TestRefreshDiskCachesWithinThrottle(t *testing.T) {
	dataDir := t.TempDir()
	photonDir := filepath.Join(dataDir, "photon")
	if err := os.MkdirAll(photonDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(photonDir, "a.bin"), make([]byte, 100), 0644); err != nil {
		t.Fatal(err)
	}

	f := NewLogFollower(nil, state.New())
	f.dataDir = dataDir

	first := f.refreshDisk("photon")

	// Add more bytes; cached call should still return the old value.
	if err := os.WriteFile(filepath.Join(photonDir, "b.bin"), make([]byte, 200), 0644); err != nil {
		t.Fatal(err)
	}
	second := f.refreshDisk("photon")
	if second != first {
		t.Errorf("expected cached value %d on second call, got %d", first, second)
	}

	// Expire cache and verify fresh walk picks up new bytes.
	f.diskMu.Lock()
	entry := f.diskCache["photon"]
	entry.at = time.Now().Add(-time.Hour)
	f.diskCache["photon"] = entry
	f.diskMu.Unlock()

	third := f.refreshDisk("photon")
	if third != 300 {
		t.Errorf("expected fresh walk to return 300, got %d", third)
	}
}

func TestRefreshDiskUnknownServiceReturnsZero(t *testing.T) {
	f := NewLogFollower(nil, state.New())
	f.dataDir = t.TempDir()
	if got := f.refreshDisk("does-not-exist"); got != 0 {
		t.Errorf("unknown service should return 0, got %d", got)
	}
}
