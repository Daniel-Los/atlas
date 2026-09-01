package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/dawarich-app/atlas/atlas-control/internal/dockerexec"
	"github.com/dawarich-app/atlas/atlas-control/internal/state"
)

type stubRunner struct {
	calls []string
	err   error
}

func (s *stubRunner) Run(_ context.Context, name string, args ...string) (string, error) {
	s.calls = append(s.calls, name+" "+strings.Join(args, " "))
	return "ok", s.err
}

var _ dockerexec.Runner = &stubRunner{}

func TestHealthEndpoint(t *testing.T) {
	srv := httptest.NewServer(New(Config{}))
	defer srv.Close()
	res, err := http.Get(srv.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != 200 {
		t.Fatalf("want 200, got %d", res.StatusCode)
	}
}

func TestStatusReturnsSnapshot(t *testing.T) {
	s := state.New()
	s.Update("photon", state.Update{Phase: "ready", Ready: true})
	srv := httptest.NewServer(NewWithStore(Config{}, s, &stubRunner{}))
	defer srv.Close()

	res, err := http.Get(srv.URL + "/status")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	var got []state.Service
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 || got[0].Name != "photon" {
		t.Fatalf("unexpected snapshot: %s", body)
	}
}

func TestEnableInvokesDockerUp(t *testing.T) {
	r := &stubRunner{}
	srv := httptest.NewServer(NewWithStore(Config{ComposeFile: "/work/compose.yml"}, state.New(), r))
	defer srv.Close()

	res, err := http.Post(srv.URL+"/actions/services/photon/enable", "application/json", nil)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != 202 {
		t.Fatalf("want 202, got %d", res.StatusCode)
	}
	if len(r.calls) == 0 || !strings.Contains(r.calls[0], "up -d photon") {
		t.Fatalf("expected docker compose up -d photon, got %v", r.calls)
	}
}

func TestApplyRegionsCallsOsmium(t *testing.T) {
	dataDir := t.TempDir()
	regionsDir := t.TempDir()

	pbfSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprint(w, "fake pbf bytes")
	}))
	defer pbfSrv.Close()

	envContent := "PBF_URL=" + pbfSrv.URL + "/berlin.pbf\nPBF_NAME=berlin.osm.pbf\n"
	if err := os.WriteFile(filepath.Join(regionsDir, "berlin.env"), []byte(envContent), 0644); err != nil {
		t.Fatal(err)
	}

	r := &stubRunner{}
	cfg := Config{
		ComposeFile: "/work/compose.yml",
		DataDir:     dataDir,
		RegionsDir:  regionsDir,
	}
	srv := httptest.NewServer(NewWithStore(cfg, state.New(), r))
	defer srv.Close()

	body, _ := json.Marshal(map[string]any{"regions": []string{"berlin"}})
	res, err := http.Post(srv.URL+"/actions/regions", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != 202 {
		respBody, _ := io.ReadAll(res.Body)
		t.Fatalf("want 202, got %d (body: %s)", res.StatusCode, respBody)
	}

	// Single-region path: a symlink should point at the downloaded source PBF.
	// The handler returns 202 immediately and runs the work in a goroutine, so
	// poll briefly for the symlink to materialize.
	current := filepath.Join(dataDir, "osm", "current.osm.pbf")
	deadline := time.Now().Add(2 * time.Second)
	for {
		if _, err := os.Lstat(current); err == nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("expected current.osm.pbf symlink within deadline")
		}
		time.Sleep(20 * time.Millisecond)
	}

	// Consuming services should be restarted (best-effort, runner call observed).
	foundRestart := false
	for i := 0; i < 50; i++ {
		for _, c := range r.calls {
			if strings.Contains(c, "restart valhalla overpass otp") {
				foundRestart = true
				break
			}
		}
		if foundRestart {
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if !foundRestart {
		t.Fatalf("expected docker compose restart call, got %v", r.calls)
	}
}
