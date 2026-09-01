package parsers

import "testing"

func TestOverpassDownloading(t *testing.T) {
	p := &OverpassParser{}
	result := feedFixture(t, p, "overpass-download.log")

	if result.Phase != "downloading" {
		t.Errorf("phase = %q, want %q", result.Phase, "downloading")
	}
	if result.Ready {
		t.Errorf("ready = true, want false during download")
	}
}

func TestOverpassIngesting(t *testing.T) {
	p := &OverpassParser{}
	feedFixture(t, p, "overpass-download.log")
	result := feedFixture(t, p, "overpass-ingest.log")

	if result.Phase != "ingesting" {
		t.Errorf("phase = %q, want %q", result.Phase, "ingesting")
	}
}

func TestOverpassReady(t *testing.T) {
	p := &OverpassParser{}
	feedFixture(t, p, "overpass-download.log")
	feedFixture(t, p, "overpass-ingest.log")
	result := feedFixture(t, p, "overpass-ready.log")

	if result.Phase != "ready" {
		t.Errorf("phase = %q, want %q", result.Phase, "ready")
	}
	if !result.Ready {
		t.Errorf("ready = false, want true")
	}
}
