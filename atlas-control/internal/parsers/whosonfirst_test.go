package parsers

import "testing"

func TestWhosonfirstDownloading(t *testing.T) {
	p := &WhosonfirstParser{}
	result := feedFixture(t, p, "whosonfirst-download.log")

	if result.Phase != "downloading" {
		t.Errorf("phase = %q, want %q", result.Phase, "downloading")
	}
	if result.Ready {
		t.Errorf("ready = true, want false during download")
	}
}

func TestWhosonfirstComplete(t *testing.T) {
	p := &WhosonfirstParser{}
	feedFixture(t, p, "whosonfirst-download.log")
	result := feedFixture(t, p, "whosonfirst-complete.log")

	if result.Phase != "complete" {
		t.Errorf("phase = %q, want %q", result.Phase, "complete")
	}
	if !result.Ready {
		t.Errorf("ready = false, want true at complete")
	}
}
