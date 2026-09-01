package parsers

import (
	"regexp"
	"strconv"
)

var (
	valhallaParseRe      = regexp.MustCompile(`Parsing relations`)
	valhallaAdminsRe     = regexp.MustCompile(`Building admin db`)
	valhallaElevationRe  = regexp.MustCompile(`downloading SRTM|Adding elevation`)
	valhallaTilesRe      = regexp.MustCompile(`building tiles|Running valhalla_build_tiles`)
	valhallaProgressRe   = regexp.MustCompile(`Build street graph progress: ([\d,]+) of ([\d,]+) \((\d+)%\)`)
	valhallaTilesReadyRe = regexp.MustCompile(`Tile build complete|Tile extract successfully loaded`)
	valhallaServeRe      = regexp.MustCompile(`valhalla_service|GET / HTTP|HTTP/[\d.]+\s+200`)
)

type ValhallaParser struct {
	state Result
}

func NewValhallaParser() *ValhallaParser { return &ValhallaParser{} }

func (p *ValhallaParser) Feed(line string) Result {
	p.state.LastLogLine = line

	switch {
	case valhallaTilesReadyRe.MatchString(line), valhallaServeRe.MatchString(line):
		p.state.Phase = "ready"
		p.state.Ready = true
		p.state.Progress = 1.0
	case valhallaProgressRe.MatchString(line):
		p.state.Phase = "building-tiles"
		m := valhallaProgressRe.FindStringSubmatch(line)
		if len(m) == 4 {
			if pct, err := strconv.Atoi(m[3]); err == nil {
				p.state.Progress = float64(pct) / 100.0
			}
		}
	case valhallaTilesRe.MatchString(line):
		p.state.Phase = "building-tiles"
		if p.state.Progress < 0.5 {
			p.state.Progress = 0.5
		}
	case valhallaElevationRe.MatchString(line):
		p.state.Phase = "building-elevation"
		if p.state.Progress < 0.4 {
			p.state.Progress = 0.4
		}
	case valhallaAdminsRe.MatchString(line):
		p.state.Phase = "building-admins"
		if p.state.Progress < 0.3 {
			p.state.Progress = 0.3
		}
	case valhallaParseRe.MatchString(line):
		p.state.Phase = "parsing"
		if p.state.Progress < 0.1 {
			p.state.Progress = 0.1
		}
	}

	return p.state
}
