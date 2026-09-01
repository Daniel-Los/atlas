package regions

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Region describes the OSM extract(s) and overpass diff feed for a named region.
// It mirrors the Rails RegionCatalog::Region struct.
type Region struct {
	Name     string
	PBFURLs  []string
	PBFName  string
	DiffURL  string
	GTFSURL  string
	GTFSName string
}

// Load reads <dir>/<name>.env and parses it into a Region.
func Load(dir, name string) (*Region, error) {
	raw, err := os.ReadFile(filepath.Join(dir, name+".env"))
	if err != nil {
		return nil, fmt.Errorf("region %q: %w", name, err)
	}
	kv := parse(string(raw))
	region := &Region{
		Name:     name,
		PBFName:  kv["PBF_NAME"],
		DiffURL:  kv["OVERPASS_DIFF_URL"],
		GTFSURL:  kv["GTFS_URL"],
		GTFSName: kv["GTFS_NAME"],
	}
	if urls := kv["PBF_URLS"]; urls != "" {
		region.PBFURLs = strings.Fields(urls)
	} else if u := kv["PBF_URL"]; u != "" {
		region.PBFURLs = []string{u}
	}
	return region, nil
}

func parse(content string) map[string]string {
	out := map[string]string{}
	for _, line := range strings.Split(content, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.Index(line, "=")
		if idx <= 0 {
			continue
		}
		k := line[:idx]
		v := strings.Trim(line[idx+1:], `"`)
		out[k] = v
	}
	return out
}
