package parsers

import (
	"regexp"
	"strconv"
)

var (
	otpOSMRe          = regexp.MustCompile(`Loaded OSM|Parse OSM Ways|Parse OSM Nodes`)
	otpGTFSRe         = regexp.MustCompile(`Loaded GTFS|Reading entity: org\.onebusaway`)
	otpStreetGraphRe  = regexp.MustCompile(`Build street graph progress: ([\d,]+) of ([\d,]+) \((\d+)%\)`)
	otpTripPatternsRe = regexp.MustCompile(`build trip patterns|GenerateTripPatternsOperation`)
	otpGraphRe        = regexp.MustCompile(`Graph built|Graph saved|HierarchyBuilder`)

	otpReadyRe = regexp.MustCompile(`Started listening|Grizzly server started|Started application|Started.+in.+seconds`)
	otpServeRe = regexp.MustCompile(`GET /otp/`)
	otpErrorRe = regexp.MustCompile(`Parameter error|java\.lang\.OutOfMemoryError|Exception in thread`)
)

type OTPParser struct {
	state Result
}

func NewOTPParser() *OTPParser { return &OTPParser{} }

func (p *OTPParser) Feed(line string) Result {
	p.state.LastLogLine = line

	switch {
	case otpReadyRe.MatchString(line), otpServeRe.MatchString(line):
		p.state.Phase = "ready"
		p.state.Ready = true
		p.state.Progress = 1.0
	case otpErrorRe.MatchString(line):
		p.state.Phase = "error"
		p.state.Ready = false
	case otpStreetGraphRe.MatchString(line):
		p.state.Phase = "building-graph"
		m := otpStreetGraphRe.FindStringSubmatch(line)
		if len(m) == 4 {
			if pct, err := strconv.Atoi(m[3]); err == nil {
				p.state.Progress = 0.3 + (float64(pct)/100.0)*0.5
			}
		}
	case otpTripPatternsRe.MatchString(line):
		p.state.Phase = "trip-patterns"
		if p.state.Progress < 0.7 {
			p.state.Progress = 0.7
		}
	case otpGraphRe.MatchString(line):
		p.state.Phase = "saving-graph"
		if p.state.Progress < 0.9 {
			p.state.Progress = 0.9
		}
	case otpGTFSRe.MatchString(line):
		p.state.Phase = "loading-gtfs"
		if p.state.Progress < 0.5 {
			p.state.Progress = 0.5
		}
	case otpOSMRe.MatchString(line):
		p.state.Phase = "loading-osm"
		if p.state.Progress < 0.2 {
			p.state.Progress = 0.2
		}
	}

	return p.state
}
