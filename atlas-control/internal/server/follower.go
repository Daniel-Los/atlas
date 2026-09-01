package server

import (
	"bufio"
	"context"
	"io"
	"io/fs"
	"log"
	"path/filepath"
	"sync"
	"time"

	"github.com/dawarich-app/atlas/atlas-control/internal/dockerexec"
	"github.com/dawarich-app/atlas/atlas-control/internal/parsers"
	"github.com/dawarich-app/atlas/atlas-control/internal/state"
)

const diskRefreshInterval = 30 * time.Second

var diskDirFor = map[string]string{
	"photon":      "photon",
	"placeholder": "placeholder",
	"valhalla":    "valhalla",
	"overpass":    "overpass",
	"otp":         "otp",
}

type diskCacheEntry struct {
	bytes int64
	at    time.Time
}

// LogFollower spawns a goroutine per enabled service that tails its docker logs,
// feeds each line into the service's Parser, and pushes updates into the Store.
type LogFollower struct {
	compose *dockerexec.DockerCompose
	store   *state.Store
	dataDir string

	mu      sync.Mutex
	cancels map[string]context.CancelFunc

	diskMu    sync.Mutex
	diskCache map[string]diskCacheEntry
}

// NewLogFollower constructs a LogFollower bound to a compose helper + state store.
func NewLogFollower(compose *dockerexec.DockerCompose, store *state.Store) *LogFollower {
	return &LogFollower{
		compose:   compose,
		store:     store,
		cancels:   map[string]context.CancelFunc{},
		diskCache: map[string]diskCacheEntry{},
	}
}

// WithDataDir attaches the data root used by refreshDisk to walk per-service
// directories. Returns the receiver so callers can chain at construction.
func (f *LogFollower) WithDataDir(dir string) *LogFollower {
	f.dataDir = dir
	return f
}

// Start begins following logs for the named service. Idempotent — calling
// Start twice for the same name is a no-op.
func (f *LogFollower) Start(name string) {
	parser := parserFor(name)
	if parser == nil {
		return
	}

	f.mu.Lock()
	if _, ok := f.cancels[name]; ok {
		f.mu.Unlock()
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	f.cancels[name] = cancel
	f.mu.Unlock()

	go f.run(ctx, name, parser)
}

// Stop cancels the goroutine following the named service. Safe to call when
// not running.
func (f *LogFollower) Stop(name string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if cancel, ok := f.cancels[name]; ok {
		cancel()
		delete(f.cancels, name)
	}
}

func (f *LogFollower) refreshDisk(name string) int64 {
	dir, ok := diskDirFor[name]
	if !ok {
		return 0
	}

	f.diskMu.Lock()
	if e, ok := f.diskCache[name]; ok && time.Since(e.at) < diskRefreshInterval {
		f.diskMu.Unlock()
		return e.bytes
	}
	f.diskMu.Unlock()

	abs := filepath.Join(f.dataDir, dir)
	var total int64
	_ = filepath.WalkDir(abs, func(_ string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		if info, ierr := d.Info(); ierr == nil {
			total += info.Size()
		}
		return nil
	})

	f.diskMu.Lock()
	f.diskCache[name] = diskCacheEntry{bytes: total, at: time.Now()}
	f.diskMu.Unlock()
	return total
}

func (f *LogFollower) run(ctx context.Context, name string, parser parsers.Parser) {
	defer func() {
		f.mu.Lock()
		delete(f.cancels, name)
		f.mu.Unlock()
	}()

	pr, pw := io.Pipe()
	go func() {
		defer pw.Close()
		if err := f.compose.LogsTail(ctx, name, pw); err != nil && ctx.Err() == nil {
			log.Printf("[follower:%s] logs tail exited: %v", name, err)
		}
	}()

	scanner := bufio.NewScanner(pr)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		if ctx.Err() != nil {
			return
		}
		line := scanner.Text()
		r := parser.Feed(line)
		f.store.Update(name, state.Update{
			Phase:       r.Phase,
			Progress:    r.Progress,
			LastLogLine: r.LastLogLine,
			Ready:       r.Ready,
			DiskBytes:   f.refreshDisk(name),
		})
	}
	if err := scanner.Err(); err != nil && ctx.Err() == nil {
		log.Printf("[follower:%s] scanner: %v", name, err)
	}
}

func parserFor(name string) parsers.Parser {
	switch name {
	case "photon":
		return &parsers.PhotonParser{}
	case "placeholder":
		return &parsers.PlaceholderParser{}
	case "libpostal":
		return &parsers.LibpostalParser{}
	case "valhalla":
		return &parsers.ValhallaParser{}
	case "overpass":
		return &parsers.OverpassParser{}
	case "otp":
		return &parsers.OTPParser{}
	case "whosonfirst":
		return &parsers.WhosonfirstParser{}
	}
	return nil
}
