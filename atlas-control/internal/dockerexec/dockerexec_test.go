package dockerexec

import (
	"context"
	"errors"
	"strings"
	"testing"
)

type mockRunner struct {
	lastName string
	lastArgs []string
	output   string
	err      error
}

func (m *mockRunner) Run(_ context.Context, name string, args ...string) (string, error) {
	m.lastName = name
	m.lastArgs = args
	return m.output, m.err
}

var _ Runner = &mockRunner{}

func TestUpCallsCorrectArgs(t *testing.T) {
	m := &mockRunner{output: "ok"}
	dc := DockerCompose{File: "/work/compose.yml", Runner: m}
	if _, err := dc.Up(context.Background(), "geocoding", "photon"); err != nil {
		t.Fatal(err)
	}
	if m.lastName != "docker" {
		t.Fatalf("want docker, got %s", m.lastName)
	}
	if len(m.lastArgs) < 2 || m.lastArgs[0] != "compose" || m.lastArgs[1] != "-f" {
		t.Fatalf("want first args to be 'compose -f', got %v", m.lastArgs)
	}
	if !strings.Contains(strings.Join(m.lastArgs, " "), "--profile geocoding up -d photon") {
		t.Fatalf("missing flags: %v", m.lastArgs)
	}
}

func TestStopPropagatesError(t *testing.T) {
	m := &mockRunner{err: errors.New("boom")}
	dc := DockerCompose{File: "/work/compose.yml", Runner: m}
	if _, err := dc.Stop(context.Background(), "photon"); err == nil {
		t.Fatal("want error")
	}
}
