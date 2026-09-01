package osmium

import (
	"context"

	"github.com/dawarich-app/atlas/atlas-control/internal/dockerexec"
)

type Osmium struct{ Runner dockerexec.Runner }

func (o *Osmium) Merge(ctx context.Context, dataDir string, sources []string, out string) (string, error) {
	args := []string{"run", "--rm",
		"-v", dataDir + ":/data",
		"-w", "/data",
		"stefda/osmium-tool",
		"osmium", "merge"}
	args = append(args, sources...)
	args = append(args, "-O", "-o", out)
	return o.Runner.Run(ctx, "docker", args...)
}

// ConvertToOsmBz2 reads a PBF file and writes an OSM-XML+bzip2 file alongside
// it. Required by wiktorn/overpass-api, which can't ingest .osm.pbf directly.
// `in` and `out` are paths relative to `dataDir`.
func (o *Osmium) ConvertToOsmBz2(ctx context.Context, dataDir, in, out string) (string, error) {
	args := []string{"run", "--rm",
		"-v", dataDir + ":/data",
		"-w", "/data",
		"stefda/osmium-tool",
		"osmium", "cat", in, "-o", out, "-O", "-f", "osm.bz2"}
	return o.Runner.Run(ctx, "docker", args...)
}
