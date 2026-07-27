#!/bin/sh
# Tests rel/overlays/bin/docker-entrypoint without needing root or a daemon:
# `id`, `chown` and `setpriv` are replaced by stubs on PATH that record how
# they were called.
set -eu

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd)"
ENTRYPOINT="$SCRIPT_DIR/../../rel/overlays/bin/docker-entrypoint"

failures=0
tests=0

fail() {
  failures=$((failures + 1))
  printf '  ✗ %s\n' "$1"
  [ $# -gt 1 ] && printf '    %s\n' "$2"
  return 0
}

pass() { printf '  ✓ %s\n' "$1"; }

assert_contains() {
  tests=$((tests + 1))
  if printf '%s' "$2" | grep -qF -- "$3"; then
    pass "$1"
  else
    fail "$1" "expected to contain: $3"
    printf '    actual: %s\n' "$2"
  fi
}

assert_not_contains() {
  tests=$((tests + 1))
  if printf '%s' "$2" | grep -qF -- "$3"; then
    fail "$1" "expected NOT to contain: $3"
    printf '    actual: %s\n' "$2"
  else
    pass "$1"
  fi
}

assert_status() {
  tests=$((tests + 1))
  if [ "$2" -eq "$3" ]; then
    pass "$1"
  else
    fail "$1" "expected exit $3, got $2"
  fi
}

# Build a sandbox: stub bin dir on PATH, a fake data dir, and a recorded log.
# $1 = uid reported by `id -u`; $2 = groups reported by `id -G`
setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  BIN="$SANDBOX/bin"
  DATA="$SANDBOX/data"
  LOG="$SANDBOX/calls.log"
  mkdir -p "$BIN" "$DATA"
  : > "$LOG"

  cat > "$BIN/id" <<EOF
#!/bin/sh
case "\$1" in
  -u) echo "$1" ;;
  -G) echo "$2" ;;
  *)  echo "$1" ;;
esac
EOF

  cat > "$BIN/chown" <<EOF
#!/bin/sh
echo "chown \$*" >> "$LOG"
EOF

  # setpriv records its args, then runs the trailing command so the rest of
  # the entrypoint still executes under the "dropped" identity.
  cat > "$BIN/setpriv" <<EOF
#!/bin/sh
echo "setpriv \$*" >> "$LOG"
while [ "\$1" != "--" ] && [ \$# -gt 0 ]; do shift; done
[ "\$1" = "--" ] && shift
exec "\$@"
EOF

  chmod +x "$BIN/id" "$BIN/chown" "$BIN/setpriv"
}

teardown_sandbox() { rm -rf "$SANDBOX"; }

# Run the entrypoint in the sandbox. Echoes stdout+stderr; sets RUN_STATUS.
run_entrypoint() {
  set +e
  RUN_OUTPUT="$(PATH="$BIN:$PATH" ATLAS_DATA_DIR="$DATA" "$@" \
    "$ENTRYPOINT" /bin/echo "app-started" 2>&1)"
  RUN_STATUS=$?
  set -e
  RUN_CALLS="$(cat "$LOG")"
}

printf '\n== running as root ==\n'
setup_sandbox 0 "0 999"
run_entrypoint env
assert_status "starts the app" "$RUN_STATUS" 0
assert_contains "execs the wrapped command" "$RUN_OUTPUT" "app-started"
assert_contains "chowns the data dir to the default uid" "$RUN_CALLS" "65534:65534"
assert_contains "drops privileges with setpriv" "$RUN_CALLS" "--reuid=65534"
assert_contains "drops to the matching gid" "$RUN_CALLS" "--regid=65534"
assert_contains "preserves the docker socket group" "$RUN_CALLS" "--groups=0,999"
teardown_sandbox

printf '\n== running as root with PUID/PGID (Unraid/Synology) ==\n'
setup_sandbox 0 "0 999"
run_entrypoint env PUID=99 PGID=100
assert_status "starts the app" "$RUN_STATUS" 0
assert_contains "chowns the data dir to PUID:PGID" "$RUN_CALLS" "chown -R 99:100"
assert_contains "drops to PUID" "$RUN_CALLS" "--reuid=99"
assert_contains "drops to PGID" "$RUN_CALLS" "--regid=100"
teardown_sandbox

printf '\n== already running as a non-root user (compose `user:`) ==\n'
setup_sandbox 65534 "65534 999"
run_entrypoint env
assert_status "starts the app" "$RUN_STATUS" 0
assert_contains "execs the wrapped command" "$RUN_OUTPUT" "app-started"
assert_not_contains "does not try to chown" "$RUN_CALLS" "chown"
assert_not_contains "does not try to drop privileges again" "$RUN_CALLS" "setpriv"
teardown_sandbox

printf '\n== non-root with an unwritable data dir (issue #23) ==\n'
setup_sandbox 65534 "65534 999"
chmod 500 "$DATA"
run_entrypoint env
assert_status "fails fast instead of crash-looping" "$RUN_STATUS" 1
assert_contains "names the unwritable path" "$RUN_OUTPUT" "$DATA"
assert_contains "explains it is an ownership problem" "$RUN_OUTPUT" "not writable"
assert_contains "points at the PUID/PGID knob" "$RUN_OUTPUT" "PUID"
assert_not_contains "does not start the app" "$RUN_OUTPUT" "app-started"
chmod 700 "$DATA"
teardown_sandbox

printf '\n%s tests, %s failures\n' "$tests" "$failures"
[ "$failures" -eq 0 ] || exit 1
