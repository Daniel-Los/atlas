package parsers

import "testing"

func TestLibpostalReady(t *testing.T) {
	p := NewLibpostalParser()
	result := feedFixture(t, p, "libpostal-ready.log")

	if result.Phase != "ready" {
		t.Errorf("phase = %q, want %q", result.Phase, "ready")
	}
	if !result.Ready {
		t.Errorf("ready = false, want true")
	}
	if result.Progress != 1.0 {
		t.Errorf("progress = %v, want 1.0", result.Progress)
	}
}
