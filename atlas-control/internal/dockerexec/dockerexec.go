package dockerexec

import (
	"context"
	"fmt"
	"io"
	"os/exec"
)

type Runner interface {
	Run(ctx context.Context, name string, args ...string) (string, error)
}

type ShellRunner struct{}

func (ShellRunner) Run(ctx context.Context, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %v failed: %w (output: %s)", name, args, err, string(out))
	}
	return string(out), nil
}

type DockerCompose struct {
	File       string
	ProjectDir string
	EnvFile    string
	Runner     Runner
}

func (d *DockerCompose) baseArgs() []string {
	args := []string{"compose", "-f", d.File}
	if d.ProjectDir != "" {
		args = append(args, "--project-directory", d.ProjectDir)
	}
	if d.EnvFile != "" {
		args = append(args, "--env-file", d.EnvFile)
	}
	return args
}

func (d *DockerCompose) Up(ctx context.Context, profile, service string) (string, error) {
	args := append(d.baseArgs(), "--profile", profile, "up", "-d", service)
	return d.Runner.Run(ctx, "docker", args...)
}

func (d *DockerCompose) Stop(ctx context.Context, service string) (string, error) {
	args := append(d.baseArgs(), "stop", service)
	return d.Runner.Run(ctx, "docker", args...)
}

func (d *DockerCompose) Restart(ctx context.Context, services ...string) (string, error) {
	args := append(d.baseArgs(), "restart")
	args = append(args, services...)
	return d.Runner.Run(ctx, "docker", args...)
}

// Pull fetches the image(s) for one or more services without touching containers.
// Pair with Up (or UpForceRecreate) to actually swap in the new image.
func (d *DockerCompose) Pull(ctx context.Context, services ...string) (string, error) {
	args := append(d.baseArgs(), "pull")
	args = append(args, services...)
	return d.Runner.Run(ctx, "docker", args...)
}

// UpForceRecreate runs `up -d --force-recreate` for a service inside a profile.
// Used after Pull to swap the running container onto the freshly-pulled image.
func (d *DockerCompose) UpForceRecreate(ctx context.Context, profile, service string) (string, error) {
	args := append(d.baseArgs(), "--profile", profile, "up", "-d", "--force-recreate", service)
	return d.Runner.Run(ctx, "docker", args...)
}

// LogsArgs builds the argv for `docker compose logs --no-color --tail=N` for
// a service. Exposed so handlers can both `LogsTail` (streaming) and one-shot
// invoke via the Runner without duplicating the arg construction.
func (d *DockerCompose) LogsArgs(service string, tail int) []string {
	args := append(d.baseArgs(), "logs", "--no-color", fmt.Sprintf("--tail=%d", tail), service)
	return args
}

func (d *DockerCompose) LogsTail(ctx context.Context, service string, w io.Writer) error {
	// Replay enough history that long-idle services (e.g. valhalla after build
	// is done and only serves requests sporadically) still surface their last
	// ready marker on follower attach.
	args := append(d.baseArgs(), "logs", "-f", "--no-color", "--tail=1000", service)
	cmd := exec.CommandContext(ctx, "docker", args...)
	cmd.Stdout = w
	cmd.Stderr = w
	return cmd.Run()
}
