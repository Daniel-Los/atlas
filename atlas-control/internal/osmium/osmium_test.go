package osmium

import (
	"context"
	"strings"
	"testing"

	"github.com/dawarich-app/atlas/atlas-control/internal/dockerexec"
)

type mockRunner struct{ lastArgs []string }

func (m *mockRunner) Run(_ context.Context, name string, args ...string) (string, error) {
	_ = name
	m.lastArgs = args
	return "", nil
}

var _ dockerexec.Runner = &mockRunner{}

func TestMergeCommandLine(t *testing.T) {
	m := &mockRunner{}
	o := Osmium{Runner: m}
	_, _ = o.Merge(context.Background(), "/work/data/osm", []string{"a.pbf", "b.pbf"}, "current.osm.pbf")

	s := strings.Join(m.lastArgs, " ")
	if !strings.Contains(s, "osmium merge a.pbf b.pbf") {
		t.Fatalf("missing merge args: %s", s)
	}
	if !strings.Contains(s, "-O -o current.osm.pbf") {
		t.Fatalf("missing output flags: %s", s)
	}
}
