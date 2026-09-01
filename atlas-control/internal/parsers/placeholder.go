package parsers

import "regexp"

var (
	placeholderExtractRe   = regexp.MustCompile(`Creating extract at`)
	placeholderBuildRe     = regexp.MustCompile(`populate fts`)
	placeholderOptimizeRe  = regexp.MustCompile(`optimize\.\.\.`)
	placeholderListeningRe = regexp.MustCompile(`\[placeholder\].*listening on`)
	placeholderRequestRe   = regexp.MustCompile(`\[placeholder\].*GET /`)
)

type PlaceholderParser struct {
	state Result
}

func NewPlaceholderParser() *PlaceholderParser { return &PlaceholderParser{} }

func (p *PlaceholderParser) Feed(line string) Result {
	p.state.LastLogLine = line

	switch {
	case placeholderListeningRe.MatchString(line), placeholderRequestRe.MatchString(line):
		p.state.Phase = "ready"
		p.state.Ready = true
		p.state.Progress = 1.0
	case placeholderOptimizeRe.MatchString(line):
		p.state.Phase = "optimizing"
		p.state.Progress = 0.9
	case placeholderBuildRe.MatchString(line):
		p.state.Phase = "building"
		p.state.Progress = 0.6
	case placeholderExtractRe.MatchString(line):
		p.state.Phase = "extracting"
		p.state.Progress = 0.2
	}

	return p.state
}
