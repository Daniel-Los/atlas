package parsers

import (
	"regexp"
	"strconv"
	"strings"
)

var (
	photonDownloadStartRe = regexp.MustCompile(`Starting download`)
	photonProgressRe      = regexp.MustCompile(`Download progress: ([\d.]+)%`)
	photonExtractRe       = regexp.MustCompile(`Extracting|Download complete`)
	photonReadyRe         = regexp.MustCompile(`Photon ready after`)
)

type PhotonParser struct {
	state Result
}

func NewPhotonParser() *PhotonParser {
	return &PhotonParser{}
}

func (p *PhotonParser) Feed(line string) Result {
	p.state.LastLogLine = line

	switch {
	case photonReadyRe.MatchString(line):
		p.state.Phase = "ready"
		p.state.Ready = true
		p.state.Progress = 1.0
	case photonExtractRe.MatchString(line):
		p.state.Phase = "extracting"
	case photonProgressRe.MatchString(line):
		p.state.Phase = "downloading"
		m := photonProgressRe.FindStringSubmatch(line)
		if len(m) == 2 {
			if pct, err := strconv.ParseFloat(strings.TrimSpace(m[1]), 64); err == nil {
				p.state.Progress = pct / 100.0
			}
		}
	case photonDownloadStartRe.MatchString(line):
		p.state.Phase = "downloading"
	}

	return p.state
}
