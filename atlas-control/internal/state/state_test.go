package state

import (
	"sync"
	"testing"
)

func TestSnapshot(t *testing.T) {
	s := New()
	s.Update("photon", Update{Phase: "downloading", Progress: 0.5, LastLogLine: "foo"})
	snap := s.Snapshot()

	if len(snap) != 1 {
		t.Fatalf("want 1 entry, got %d", len(snap))
	}
	if snap[0].Name != "photon" || snap[0].Progress != 0.5 {
		t.Fatalf("unexpected snapshot: %+v", snap[0])
	}
}

func TestConcurrentUpdate(t *testing.T) {
	s := New()
	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			s.Update("photon", Update{Phase: "x", Progress: float64(i) / 100})
		}(i)
	}
	wg.Wait()
	if len(s.Snapshot()) != 1 {
		t.Fatalf("want 1 entry after concurrent updates")
	}
}
