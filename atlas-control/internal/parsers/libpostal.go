package parsers

import "regexp"

var libpostalReadyRe = regexp.MustCompile(`STATUS listening on`)

type LibpostalParser struct {
	state Result
}

func NewLibpostalParser() *LibpostalParser {
	return &LibpostalParser{}
}

func (p *LibpostalParser) Feed(line string) Result {
	p.state.LastLogLine = line
	if libpostalReadyRe.MatchString(line) {
		p.state.Phase = "ready"
		p.state.Ready = true
		p.state.Progress = 1.0
	}
	return p.state
}
