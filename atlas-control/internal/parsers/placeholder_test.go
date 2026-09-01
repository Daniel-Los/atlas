package parsers

import "testing"

func TestPlaceholderExtract(t *testing.T) {
	p := &PlaceholderParser{}
	result := feedFixture(t, p, "placeholder-extract.log")

	if result.Phase != "extracting" {
		t.Errorf("phase = %q, want %q", result.Phase, "extracting")
	}
	if result.Ready {
		t.Errorf("ready = true, want false during extract")
	}
}

func TestPlaceholderBuild(t *testing.T) {
	p := &PlaceholderParser{}
	feedFixture(t, p, "placeholder-extract.log")
	result := feedFixture(t, p, "placeholder-build.log")

	if result.Phase != "building" {
		t.Errorf("phase = %q, want %q", result.Phase, "building")
	}
	if result.Ready {
		t.Errorf("ready = true, want false during build")
	}
}

func TestPlaceholderReady(t *testing.T) {
	p := &PlaceholderParser{}
	feedFixture(t, p, "placeholder-extract.log")
	feedFixture(t, p, "placeholder-build.log")
	feedFixture(t, p, "placeholder-optimize.log")
	result := feedFixture(t, p, "placeholder-ready.log")

	if result.Phase != "ready" {
		t.Errorf("phase = %q, want %q", result.Phase, "ready")
	}
	if !result.Ready {
		t.Errorf("ready = false, want true")
	}
}
