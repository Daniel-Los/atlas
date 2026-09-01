package parsers

import "regexp"

var (
	overpassDownloadRe = regexp.MustCompile(`Downloading planet`)
	overpassIngestRe   = regexp.MustCompile(`compiled \d+ blocks`)
	overpassErrorRe    = regexp.MustCompile(`Failed to process planet file|bzip2 error|Parse error at`)
	overpassReadyRe    = regexp.MustCompile(`Server started|fcgiwrap.*listening|nginx.*ready`)
	overpassServeRe    = regexp.MustCompile(`GET /api/`)
)

type OverpassParser struct {
	state Result
}

func NewOverpassParser() *OverpassParser { return &OverpassParser{} }

func (p *OverpassParser) Feed(line string) Result {
	p.state.LastLogLine = line

	switch {
	case overpassReadyRe.MatchString(line), overpassServeRe.MatchString(line):
		p.state.Phase = "ready"
		p.state.Ready = true
		p.state.Progress = 1.0
	case overpassErrorRe.MatchString(line):
		p.state.Phase = "error"
		p.state.Ready = false
	case overpassIngestRe.MatchString(line):
		p.state.Phase = "ingesting"
		p.state.Progress = 0.6
	case overpassDownloadRe.MatchString(line):
		p.state.Phase = "downloading"
		p.state.Progress = 0.2
	}

	return p.state
}
