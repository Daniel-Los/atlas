package server

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/dawarich-app/atlas/atlas-control/internal/state"
)

func postUpdate(t *testing.T, url, name, kind string) *http.Response {
	t.Helper()
	body, _ := json.Marshal(map[string]string{"update_kind": kind})
	res, err := http.Post(url+"/actions/services/"+name+"/update", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	return res
}

func waitForUpdateStatus(t *testing.T, url, name, want string) updateRun {
	t.Helper()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		res, err := http.Get(url + "/actions/services/" + name + "/update")
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(res.Body)
		res.Body.Close()
		var run updateRun
		if err := json.Unmarshal(body, &run); err == nil && run.Status == want {
			return run
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("timeout waiting for %s update status %q", name, want)
	return updateRun{}
}

func TestUpdateImageOnlyPullsAndRecreates(t *testing.T) {
	r := &stubRunner{}
	srv := httptest.NewServer(NewWithStore(Config{ComposeFile: "/work/compose.yml"}, state.New(), r))
	defer srv.Close()

	res := postUpdate(t, srv.URL, "caddy", "image_only")
	defer res.Body.Close()
	if res.StatusCode != http.StatusAccepted {
		t.Fatalf("want 202, got %d", res.StatusCode)
	}

	run := waitForUpdateStatus(t, srv.URL, "caddy", "success")
	if run.Kind != "image_only" {
		t.Errorf("want kind image_only, got %q", run.Kind)
	}

	// Expect: `docker compose pull caddy` then `docker compose --profile  up -d --force-recreate caddy`.
	joined := strings.Join(r.calls, "\n")
	if !strings.Contains(joined, "pull caddy") {
		t.Errorf("expected pull caddy in runner calls, got:\n%s", joined)
	}
	if !strings.Contains(joined, "--force-recreate caddy") {
		t.Errorf("expected force-recreate caddy in runner calls, got:\n%s", joined)
	}
}

func TestUpdateIncrementalRestartsService(t *testing.T) {
	r := &stubRunner{}
	srv := httptest.NewServer(NewWithStore(Config{ComposeFile: "/work/compose.yml"}, state.New(), r))
	defer srv.Close()

	res := postUpdate(t, srv.URL, "overpass", "incremental")
	defer res.Body.Close()
	if res.StatusCode != http.StatusAccepted {
		t.Fatalf("want 202, got %d", res.StatusCode)
	}

	run := waitForUpdateStatus(t, srv.URL, "overpass", "success")
	if run.Status != "success" {
		t.Errorf("want success, got %s (err=%s)", run.Status, run.Error)
	}

	joined := strings.Join(r.calls, "\n")
	if !strings.Contains(joined, "restart overpass") {
		t.Errorf("expected restart overpass, got:\n%s", joined)
	}
}

func TestUpdateRejectsInvalidKind(t *testing.T) {
	r := &stubRunner{}
	srv := httptest.NewServer(NewWithStore(Config{ComposeFile: "/work/compose.yml"}, state.New(), r))
	defer srv.Close()

	res := postUpdate(t, srv.URL, "photon", "bogus")
	defer res.Body.Close()
	if res.StatusCode != http.StatusBadRequest {
		t.Fatalf("want 400, got %d", res.StatusCode)
	}
}

func TestUpdateRejectsConcurrentRuns(t *testing.T) {
	// Slow runner so the first update is still "running" when we kick off the second.
	r := &slowRunner{delay: 200 * time.Millisecond}
	srv := httptest.NewServer(NewWithStore(Config{ComposeFile: "/work/compose.yml"}, state.New(), r))
	defer srv.Close()

	res1 := postUpdate(t, srv.URL, "overpass", "incremental")
	res1.Body.Close()
	if res1.StatusCode != http.StatusAccepted {
		t.Fatalf("first call: want 202, got %d", res1.StatusCode)
	}

	res2 := postUpdate(t, srv.URL, "overpass", "incremental")
	defer res2.Body.Close()
	if res2.StatusCode != http.StatusConflict {
		t.Fatalf("second call: want 409 conflict, got %d", res2.StatusCode)
	}
}

func TestUpdateStatusIdleWhenNoRun(t *testing.T) {
	srv := httptest.NewServer(NewWithStore(Config{ComposeFile: "/work/compose.yml"}, state.New(), &stubRunner{}))
	defer srv.Close()

	res, err := http.Get(srv.URL + "/actions/services/photon/update")
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	var got map[string]any
	_ = json.Unmarshal(body, &got)
	if got["status"] != "idle" {
		t.Errorf("want idle, got %v", got)
	}
}

// slowRunner introduces a fixed delay so concurrency tests can observe an
// in-flight update.
type slowRunner struct {
	delay time.Duration
}

func (s *slowRunner) Run(_ context.Context, _ string, _ ...string) (string, error) {
	time.Sleep(s.delay)
	return "ok", nil
}
