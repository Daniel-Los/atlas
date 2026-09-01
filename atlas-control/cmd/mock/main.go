package main

import (
	"encoding/json"
	"flag"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"gopkg.in/yaml.v3"
)

type Scenario struct {
	Services []struct {
		Name     string `yaml:"name"`
		Timeline []struct {
			At       string  `yaml:"at"`
			Phase    string  `yaml:"phase"`
			Progress float64 `yaml:"progress"`
			Ready    bool    `yaml:"ready"`
		} `yaml:"timeline"`
	} `yaml:"services"`
}

func main() {
	scenarioPath := flag.String("scenario", "", "path to scripted YAML")
	addr := flag.String("addr", ":8090", "listen addr")
	flag.Parse()

	if *scenarioPath == "" {
		log.Fatal("--scenario is required")
	}

	raw, err := os.ReadFile(*scenarioPath)
	if err != nil {
		log.Fatal(err)
	}
	var s Scenario
	if err := yaml.Unmarshal(raw, &s); err != nil {
		log.Fatal(err)
	}

	var mu sync.Mutex
	state := map[string]map[string]any{}
	started := time.Now()

	for _, svc := range s.Services {
		go func(svc struct {
			Name     string `yaml:"name"`
			Timeline []struct {
				At       string  `yaml:"at"`
				Phase    string  `yaml:"phase"`
				Progress float64 `yaml:"progress"`
				Ready    bool    `yaml:"ready"`
			} `yaml:"timeline"`
		}) {
			for _, step := range svc.Timeline {
				d, _ := time.ParseDuration(step.At)
				time.Sleep(time.Until(started.Add(d)))
				mu.Lock()
				state[svc.Name] = map[string]any{
					"name": svc.Name, "phase": step.Phase, "progress": step.Progress, "ready": step.Ready,
				}
				mu.Unlock()
			}
		}(svc)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("ok\n"))
	})
	mux.HandleFunc("/status", func(w http.ResponseWriter, _ *http.Request) {
		mu.Lock()
		out := make([]map[string]any, 0, len(state))
		for _, v := range state {
			out = append(out, v)
		}
		mu.Unlock()
		json.NewEncoder(w).Encode(out)
	})
	mux.HandleFunc("/actions/", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusAccepted)
	})

	log.Printf("atlas-control --mock listening on %s", *addr)
	log.Fatal(http.ListenAndServe(*addr, mux))
}
