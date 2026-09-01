package server

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/go-chi/chi/v5"
)

// updateRun tracks one in-flight or completed update attempt for a service.
// The Rails side polls /actions/services/{name}/update (or /status) to render
// progress; on completion it flips Service#last_update_status in the DB.
type updateRun struct {
	Service    string    `json:"service"`
	Kind       string    `json:"kind"`
	Status     string    `json:"status"` // running | success | failure
	StartedAt  time.Time `json:"started_at"`
	FinishedAt time.Time `json:"finished_at,omitempty"`
	DurationS  int       `json:"duration_s"`
	Error      string    `json:"error,omitempty"`
}

type updateBody struct {
	UpdateKind string `json:"update_kind"`
}

func validUpdateKind(k string) bool {
	switch k {
	case "image_only", "incremental", "full_refresh":
		return true
	default:
		return false
	}
}

func (h *handlers) updateService(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "name")

	var body updateBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "BAD_REQUEST", err.Error())
		return
	}
	if !validUpdateKind(body.UpdateKind) {
		writeError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid update_kind: "+body.UpdateKind)
		return
	}

	h.updatesMu.Lock()
	if existing, ok := h.updates[name]; ok && existing.Status == "running" {
		h.updatesMu.Unlock()
		writeError(w, http.StatusConflict, "ALREADY_RUNNING", "update already in progress for "+name)
		return
	}
	run := &updateRun{
		Service:   name,
		Kind:      body.UpdateKind,
		Status:    "running",
		StartedAt: time.Now().UTC(),
	}
	h.updates[name] = run
	h.updatesMu.Unlock()

	go h.runUpdate(context.Background(), name, body.UpdateKind, run)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"service": name,
		"kind":    body.UpdateKind,
		"status":  "running",
	})
}

func (h *handlers) updateStatus(w http.ResponseWriter, r *http.Request) {
	name := chi.URLParam(r, "name")
	h.updatesMu.RLock()
	run, ok := h.updates[name]
	h.updatesMu.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	if !ok {
		_ = json.NewEncoder(w).Encode(map[string]any{"status": "idle"})
		return
	}
	_ = json.NewEncoder(w).Encode(run)
}

func (h *handlers) runUpdate(ctx context.Context, name, kind string, run *updateRun) {
	start := time.Now()
	var err error

	switch kind {
	case "image_only":
		err = h.runImagePull(ctx, name)
	case "incremental":
		err = h.runIncremental(ctx, name)
	case "full_refresh":
		err = h.runFullRefresh(ctx, name)
	default:
		err = fmt.Errorf("unsupported update kind: %s", kind)
	}

	h.updatesMu.Lock()
	run.FinishedAt = time.Now().UTC()
	run.DurationS = int(time.Since(start).Seconds())
	if err != nil {
		run.Status = "failure"
		run.Error = err.Error()
		log.Printf("[update] %s (%s): %v", name, kind, err)
	} else {
		run.Status = "success"
		log.Printf("[update] %s (%s): success in %ds", name, kind, run.DurationS)
	}
	h.updatesMu.Unlock()
}

func (h *handlers) runImagePull(ctx context.Context, name string) error {
	if _, err := h.compose.Pull(ctx, name); err != nil {
		return fmt.Errorf("pull: %w", err)
	}
	profile := profileFor[name]
	if _, err := h.compose.UpForceRecreate(ctx, profile, name); err != nil {
		return fmt.Errorf("recreate: %w", err)
	}
	return nil
}

func (h *handlers) runIncremental(ctx context.Context, name string) error {
	// Diff-streamers (overpass, valhalla) self-apply minute diffs. Restarting
	// picks up any image-side fixes if a pull happened separately and is a
	// safe no-op if not.
	if _, err := h.compose.Restart(ctx, name); err != nil {
		return fmt.Errorf("restart: %w", err)
	}
	return nil
}

func (h *handlers) runFullRefresh(ctx context.Context, name string) error {
	switch name {
	case "photon":
		// Wipe data dir; container re-downloads Komoot bundle on next start.
		if err := wipeDirContents(filepath.Join(h.cfg.DataDir, "photon")); err != nil {
			return fmt.Errorf("wipe photon: %w", err)
		}
		if _, err := h.compose.UpForceRecreate(ctx, profileFor[name], name); err != nil {
			return fmt.Errorf("restart photon: %w", err)
		}
	case "placeholder":
		for _, sub := range []string{"whosonfirst", "placeholder"} {
			if err := wipeDirContents(filepath.Join(h.cfg.DataDir, sub)); err != nil {
				return fmt.Errorf("wipe %s: %w", sub, err)
			}
		}
		// Restart triggers placeholder build; the `make placeholder-data` flow
		// (WOF download + extract + build) remains the canonical fallback when
		// fully automated refresh is wired up.
		if _, err := h.compose.UpForceRecreate(ctx, profileFor[name], name); err != nil {
			return fmt.Errorf("restart placeholder: %w", err)
		}
	case "otp":
		// OTP rebuilds graph from staged GTFS + PBF when graph.obj is absent.
		_ = os.Remove(filepath.Join(h.cfg.DataDir, "otp", "graph.obj"))
		if _, err := h.compose.UpForceRecreate(ctx, profileFor[name], name); err != nil {
			return fmt.Errorf("restart otp: %w", err)
		}
	default:
		return fmt.Errorf("full_refresh not implemented for %s", name)
	}
	return nil
}

func wipeDirContents(path string) error {
	entries, err := os.ReadDir(path)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, e := range entries {
		if err := os.RemoveAll(filepath.Join(path, e.Name())); err != nil {
			return err
		}
	}
	return nil
}
