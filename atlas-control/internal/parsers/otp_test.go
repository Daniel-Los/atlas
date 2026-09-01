package parsers

import "testing"

func TestOTPLoadingOSM(t *testing.T) {
	p := &OTPParser{}
	result := feedFixture(t, p, "otp-osm.log")

	if result.Phase != "loading-osm" {
		t.Errorf("phase = %q, want %q", result.Phase, "loading-osm")
	}
	if result.Ready {
		t.Errorf("ready = true, want false during OSM load")
	}
}

func TestOTPBuildingGraph(t *testing.T) {
	p := &OTPParser{}
	feedFixture(t, p, "otp-osm.log")
	feedFixture(t, p, "otp-gtfs.log")
	result := feedFixture(t, p, "otp-graph.log")

	if result.Phase != "building-graph" {
		t.Errorf("phase = %q, want %q", result.Phase, "building-graph")
	}
}

func TestOTPReady(t *testing.T) {
	p := &OTPParser{}
	feedFixture(t, p, "otp-graph.log")
	result := feedFixture(t, p, "otp-ready.log")

	if result.Phase != "ready" {
		t.Errorf("phase = %q, want %q", result.Phase, "ready")
	}
	if !result.Ready {
		t.Errorf("ready = false, want true")
	}
}
