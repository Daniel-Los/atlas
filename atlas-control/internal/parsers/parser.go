package parsers

type Result struct {
	Phase       string
	Progress    float64
	LastLogLine string
	Ready       bool
}

type Parser interface {
	Feed(line string) Result
}
