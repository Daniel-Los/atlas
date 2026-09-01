package state

import (
	"sync"
	"time"
)

type Service struct {
	Name           string    `json:"name"`
	ContainerState string    `json:"container_state"`
	Phase          string    `json:"phase"`
	Progress       float64   `json:"progress"`
	LastLogLine    string    `json:"last_log_line"`
	Ready          bool      `json:"ready"`
	DiskBytes      int64     `json:"disk_bytes"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type Update struct {
	ContainerState string
	Phase          string
	Progress       float64
	LastLogLine    string
	Ready          bool
	DiskBytes      int64
}

type Store struct {
	mu       sync.RWMutex
	services map[string]Service
}

func New() *Store {
	return &Store{services: map[string]Service{}}
}

func (s *Store) Update(name string, u Update) {
	s.mu.Lock()
	defer s.mu.Unlock()
	svc := s.services[name]
	svc.Name = name
	if u.ContainerState != "" {
		svc.ContainerState = u.ContainerState
	}
	if u.Phase != "" {
		svc.Phase = u.Phase
	}
	if u.Progress != 0 {
		svc.Progress = u.Progress
	}
	if u.LastLogLine != "" {
		svc.LastLogLine = u.LastLogLine
	}
	svc.Ready = u.Ready || svc.Ready
	if u.DiskBytes != 0 {
		svc.DiskBytes = u.DiskBytes
	}
	svc.UpdatedAt = time.Now()
	s.services[name] = svc
}

func (s *Store) Snapshot() []Service {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Service, 0, len(s.services))
	for _, svc := range s.services {
		out = append(out, svc)
	}
	return out
}
