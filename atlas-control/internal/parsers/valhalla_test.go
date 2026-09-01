package parsers

import "testing"

func TestValhallaParsing(t *testing.T) {
	p := &ValhallaParser{}
	result := feedFixture(t, p, "valhalla-parse.log")

	if result.Phase != "parsing" {
		t.Errorf("phase = %q, want %q", result.Phase, "parsing")
	}
	if result.Ready {
		t.Errorf("ready = true, want false during parsing")
	}
}

func TestValhallaBuildingTiles(t *testing.T) {
	p := &ValhallaParser{}
	feedFixture(t, p, "valhalla-parse.log")
	feedFixture(t, p, "valhalla-admins.log")
	feedFixture(t, p, "valhalla-elevation.log")
	result := feedFixture(t, p, "valhalla-tiles.log")

	if result.Phase != "building-tiles" {
		t.Errorf("phase = %q, want %q", result.Phase, "building-tiles")
	}
}

func TestValhallaReady(t *testing.T) {
	p := &ValhallaParser{}
	feedFixture(t, p, "valhalla-tiles.log")
	result := feedFixture(t, p, "valhalla-ready.log")

	if result.Phase != "ready" {
		t.Errorf("phase = %q, want %q", result.Phase, "ready")
	}
	if !result.Ready {
		t.Errorf("ready = false, want true")
	}
}
