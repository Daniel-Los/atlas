package parsers

import "regexp"

var (
	whosonfirstDownloadRe = regexp.MustCompile(`Downloading whosonfirst`)
	whosonfirstCompleteRe = regexp.MustCompile(`Download complete`)
)

type WhosonfirstParser struct {
	state Result
}

func (p *WhosonfirstParser) Feed(line string) Result {
	p.state.LastLogLine = line

	switch {
	case whosonfirstCompleteRe.MatchString(line):
		p.state.Phase = "complete"
		p.state.Ready = true
		p.state.Progress = 1.0
	case whosonfirstDownloadRe.MatchString(line):
		p.state.Phase = "downloading"
		p.state.Progress = 0.3
	}

	return p.state
}
