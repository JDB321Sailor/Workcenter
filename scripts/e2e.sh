#!/usr/bin/env bash
#
# e2e.sh — bring Workcenter up to a state a human can verify by hand.
#
# The full Playwright suite is a later phase of the roadmap (Testing.md). Until
# then this script is the verification entry point: it builds the shell, starts
# it, deploys whatever the current phase can deploy, and prints the checks to
# perform in a browser.
#
# The contract grows with the roadmap phases:
#   Phase 2 (now)  build the shell + broker, serve it, verify the shell by hand.
#   Phase 3+       also bring up the stack from compose.yaml and print the
#                  subdomains, so the panes load real applications.
#   Phase 7        run the Playwright suite against the same stack.
#
# Usage: ./scripts/e2e.sh [options]
# Run with --help for the full list.

set -Eeuo pipefail

IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly RUN_DIR="${ROOT_DIR}/user-data/e2e"
readonly PID_DIR="${RUN_DIR}/pids"          # one pid file per port
readonly PID_FILE="${RUN_DIR}/workcenter.pid" # the last start, for compatibility
readonly LOG_FILE="${RUN_DIR}/workcenter.log"

PORT="${PORT:-4180}"
HOST="${HOST:-0.0.0.0}"
DO_BUILD=1
DO_DOWN=0
DO_CLEAN=0

# Coloured, prefixed output (standards.md S-SH-7).
info() { printf '\033[36mℹ\033[0m %s\n' "$*"; }
ok() { printf '\033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⚠\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[31m✖\033[0m %s\n' "$*" >&2; }

on_error() {
  fail "failed at ${BASH_SOURCE[0]}:${1} — command: ${2}"
  exit 1
}
trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR

usage() {
  cat <<'EOF'
Bring Workcenter up to a state a human can verify by hand.

Usage: ./scripts/e2e.sh [options]

Options:
  --port <port>   Port to serve the shell on (default: 4180, or $PORT).
  --host <host>   Address to bind (default: 0.0.0.0, or $HOST).
  --no-build      Skip the production build and serve the existing dist/.
  --down          Stop every Workcenter server of this checkout (and the stack, if one
                  is deployed), then report anything still holding the port.
  --clean         Stop everything and remove dist/ and the run directory.
  -h, --help      Show this help.

What it does, in order:
  1. Checks the toolchain and installs dependencies if they are missing.
  2. Builds the shell (unless --no-build).
  3. Starts the Workcenter server (shell + broker) and waits for /healthz.
  4. Brings up compose.yaml too, when the repository has one (Phase 3+).
  5. Prints the manual checks for the phase the repository is at.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        PORT="${2:?--port needs a value}"
        shift 2
        ;;
      --host)
        HOST="${2:?--host needs a value}"
        shift 2
        ;;
      --no-build)
        DO_BUILD=0
        shift
        ;;
      --down)
        DO_DOWN=1
        shift
        ;;
      --clean)
        DO_CLEAN=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        fail "unknown option: $1"
        usage >&2
        exit 2
        ;;
    esac
  done
}

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "$1 is required but was not found in PATH"
    exit 1
  fi
}

check_toolchain() {
  require_tool node
  require_tool yarn
  info "node $(node --version), yarn $(yarn --version)"
  if [[ ! -d "${ROOT_DIR}/node_modules" ]]; then
    info "installing dependencies (first run)"
    (cd "${ROOT_DIR}" && yarn install --frozen-lockfile)
  fi
}

# ---------------------------------------------------------------------------
# Server lifecycle
#
# A pid file is only a convenience: a server that was started by hand, or by a
# run whose pid file was since removed, is still a Workcenter server that --down
# must stop. So the script both reads its own records *and* sweeps the process
# table for `node server.js` running from this checkout. That sweep is what makes
# --down reliable — "the recorded pid is gone" is not the same as "no server is
# running", and treating those as the same left servers alive on their port.
# ---------------------------------------------------------------------------

pid_file_for_port() {
  printf '%s/workcenter-%s.pid' "${PID_DIR}" "$1"
}

# The process state from /proc/<pid>/stat: R, S, D, Z (zombie), and so on. A
# zombie has exited and holds no port, but `kill -0` still succeeds for it — this
# container's PID 1 does not reap, so the difference matters.
process_state() {
  sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1
}

# Every Workcenter server of this checkout, from the process table. A process
# qualifies when it is `node server.js`, it belongs to this checkout — its working
# directory is the repository root, which is how `start_server` launches it, or it
# was started with the absolute path to this checkout's server.js — and it has not
# already exited. A server of a different checkout is not claimed, and never
# signalled.
our_server_pids() {
  local pid
  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$' || true); do
    [[ -r "/proc/${pid}/cmdline" ]] || continue
    [[ "$(process_state "${pid}")" == "Z" ]] && continue
    node -e '
      const fs = require("fs");
      const [pid, root] = process.argv.slice(1);
      let argv;
      try { argv = fs.readFileSync(`/proc/${pid}/cmdline`, "utf8").split("\0").filter(Boolean); } catch { process.exit(1); }
      const base = (p) => (p || "").split("/").pop();
      if (base(argv[0]) !== "node") process.exit(1);
      const script = argv[1] || "";
      if (base(script) !== "server.js") process.exit(1);
      let cwd = "";
      try { cwd = fs.readlinkSync(`/proc/${pid}/cwd`); } catch { /* keep looking */ }
      const mine = cwd === root || script === `${root}/server.js`;
      process.exit(mine ? 0 : 1);
    ' "${pid}" "${ROOT_DIR}" >/dev/null 2>&1 || continue
    printf '%s\n' "${pid}"
  done
}

# The pids this script recorded, oldest records first, ignoring stale ones.
recorded_pids() {
  local file
  for file in "${PID_FILE}" "${PID_DIR}"/*.pid; do
    [[ -f "${file}" ]] || continue
    local pid
    pid="$(cat "${file}" 2>/dev/null || true)"
    [[ -n "${pid}" ]] && printf '%s\n' "${pid}"
  done
}

is_our_server() {
  local pid="$1" candidate
  [[ -n "${pid}" ]] || return 1
  # Compared in the shell rather than through `grep -q`: that pipeline is killed
  # by SIGPIPE as soon as grep matches, and `pipefail` turns the 141 into a
  # failure — which read as "not our server" and let a live server survive a
  # --down.
  for candidate in $(our_server_pids); do
    [[ "${candidate}" == "${pid}" ]] && return 0
  done
  return 1
}

stop_pid() {
  local pid="$1" reason="$2"
  is_our_server "${pid}" || return 1
  info "stopping the Workcenter server (pid ${pid}${reason})"
  kill "${pid}" 2>/dev/null || true
  local _ state
  for _ in $(seq 1 20); do
    state="$(process_state "${pid}")"
    # Gone, or exited and waiting to be reaped: either way it holds no port.
    [[ -z "${state}" || "${state}" == "Z" ]] && return 0
    sleep 0.25
  done
  warn "pid ${pid} ignored SIGTERM; sending SIGKILL"
  kill -9 "${pid}" 2>/dev/null || true
  sleep 0.2
  return 0
}

# True when something is listening on the port, whoever started it.
port_answers() {
  node -e '
    const net = require("net");
    const socket = net.connect(Number(process.argv[1]), "127.0.0.1");
    const done = (code) => { socket.destroy(); process.exit(code); };
    socket.on("connect", () => done(0));
    socket.on("error", () => done(1));
    setTimeout(() => done(1), 1000);
  ' "$1" >/dev/null 2>&1
}

# Names the process behind a listening port, so "still up" is never a mystery.
port_owner() {
  node -e '
    const fs = require("fs");
    const port = Number(process.argv[1]);
    const hex = port.toString(16).toUpperCase().padStart(4, "0");
    const inodes = new Set();
    for (const table of ["/proc/net/tcp", "/proc/net/tcp6"]) {
      let text;
      try { text = fs.readFileSync(table, "utf8"); } catch { continue; }
      text.split("\n").slice(1).forEach((line) => {
        const fields = line.trim().split(/\s+/);
        if (fields.length < 10) return;
        const [address, state] = [fields[1], fields[3]];
        if (state !== "0A") return;                       // LISTEN
        if (!address.endsWith(`:${hex}`)) return;
        inodes.add(fields[9]);
      });
    }
    if (!inodes.size) process.exit(1);
    for (const pid of fs.readdirSync("/proc").filter((d) => /^[0-9]+$/.test(d))) {
      let fds;
      try { fds = fs.readdirSync(`/proc/${pid}/fd`); } catch { continue; }
      for (const fd of fds) {
        let target;
        try { target = fs.readlinkSync(`/proc/${pid}/fd/${fd}`); } catch { continue; }
        const match = /^socket:\[(\d+)\]$/.exec(target);
        if (!match || !inodes.has(match[1])) continue;
        let cmd = "";
        try { cmd = fs.readFileSync(`/proc/${pid}/cmdline`, "utf8").split("\0").filter(Boolean).join(" "); } catch {}
        process.stdout.write(`${pid} ${cmd}\n`);
        process.exit(0);
      }
    }
    process.exit(1);
  ' "$1" 2>/dev/null || true
}

# Stops every Workcenter server of this checkout and reports what is left on the
# port. Idempotent: a second run says so rather than failing.
stop_server() {
  local stopped=0 pid
  local -a candidates=()
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && candidates+=("${pid}")
  done < <(recorded_pids; our_server_pids)
  for pid in "${candidates[@]}"; do
    if stop_pid "${pid}" ""; then
      stopped=1
    fi
  done
  # Clear the records only once nothing of ours is left, so a failed stop keeps
  # the pid for the next attempt instead of losing track of a live server. The
  # directory itself stays: a start that follows a stop still writes into it.
  local remaining
  remaining="$(our_server_pids | tr '\n' ' ' | sed 's/ $//')"
  if [[ -z "${remaining}" ]]; then
    rm -f "${PID_FILE}"
    rm -f "${PID_DIR}"/*.pid 2>/dev/null || true
  else
    warn "a Workcenter server survived the stop (pid ${remaining}); its pid was kept for the next --down"
  fi
  if [[ "${stopped}" -eq 1 ]]; then
    ok "server stopped"
  else
    info "no Workcenter server of this checkout is running"
  fi
  if port_answers "${PORT}"; then
    local owner
    owner="$(port_owner "${PORT}")"
    if [[ -n "${remaining}" ]]; then
      warn "port ${PORT} is still held by pid ${owner:-?} — the Workcenter server this run could not stop"
    else
      warn "something else is still listening on ${PORT}${owner:+ (pid ${owner})}"
      warn "it is not a Workcenter server from ${ROOT_DIR}; stop it where it was started"
    fi
  fi
}

# The full-stack composition arrives in roadmap Phase 3. Until it exists the
# harness serves the shell directly, which needs nothing but node.
compose_file() {
  for candidate in compose.yaml compose.yml; do
    if [[ -f "${ROOT_DIR}/${candidate}" ]]; then
      printf '%s' "${ROOT_DIR}/${candidate}"
      return 0
    fi
  done
  return 1
}

stop_stack() {
  local compose
  if ! compose="$(compose_file)"; then
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    warn "a compose file exists but docker is not available; skipping the stack"
    return 0
  fi
  info "stopping the compose stack (volumes are kept)"
  (cd "${ROOT_DIR}" && docker compose -f "${compose}" down)
}

build_shell() {
  if [[ "${DO_BUILD}" -eq 0 ]]; then
    info "skipping the build (--no-build)"
    if [[ ! -f "${ROOT_DIR}/dist/index.html" ]]; then
      warn "dist/index.html is missing; the server will serve the initialization page only"
    fi
    return 0
  fi
  info "building the shell"
  (cd "${ROOT_DIR}" && yarn build >/dev/null)
  ok "build complete"
}

start_server() {
  mkdir -p "${RUN_DIR}" "${PID_DIR}"
  # Adopt a server this script already started, but only when it serves the port
  # that was asked for — otherwise a run for 4195 would silently hand back 4180.
  local pid
  for pid in $(our_server_pids); do
    if pid_serves_port "${pid}" "${PORT}"; then
      info "the Workcenter server for port ${PORT} is already running (pid ${pid})"
      printf '%s' "${pid}" >"$(pid_file_for_port "${PORT}")"
      printf '%s' "${pid}" >"${PID_FILE}"
      return 0
    fi
  done
  # Servers left over from an earlier run are stopped rather than accumulated:
  # starting a second instance is what used to orphan the first one.
  if [[ -n "$(our_server_pids)" ]]; then
    warn "a Workcenter server from an earlier run is still up; stopping it first"
    stop_server
  fi
  info "starting the Workcenter server on ${HOST}:${PORT}"
  local started=""
  # A stop in the lines above may have cleared the pid directory's contents; make
  # sure the directory is there before writing into it.
  mkdir -p "${PID_DIR}"
  (
    cd "${ROOT_DIR}"
    HOST="${HOST}" PORT="${PORT}" nohup node server.js >"${LOG_FILE}" 2>&1 &
    echo $! >"$(pid_file_for_port "${PORT}")"
    echo $! >"${PID_FILE}"
  )
  started="$(cat "$(pid_file_for_port "${PORT}")" 2>/dev/null || true)"
  if [[ -z "${started}" ]] || ! is_our_server "${started}"; then
    fail "the server did not start; see ${LOG_FILE}"
    exit 1
  fi
  wait_for_health
}

# True when the given pid is listening on the given port.
pid_serves_port() {
  local pid="$1" port="$2"
  local owner
  owner="$(port_owner "${port}")"
  [[ -n "${owner}" && "${owner%% *}" == "${pid}" ]]
}

wait_for_health() {
  local url="http://127.0.0.1:${PORT}/healthz"
  for _ in $(seq 1 40); do
    if node -e "
      fetch(process.argv[1]).then((r) => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1));
    " "${url}" >/dev/null 2>&1; then
      ok "the shell answers at ${url}"
      return 0
    fi
    sleep 0.5
  done
  fail "the shell did not become healthy; see ${LOG_FILE}"
  tail -n 20 "${LOG_FILE}" >&2 || true
  exit 1
}

deploy_stack() {
  local compose
  if ! compose="$(compose_file)"; then
    info "no compose.yaml yet: this phase deploys the shell and the broker only"
    info "the panes show their diagnostic card until the applications are deployed (roadmap Phase 3)"
    return 0
  fi
  if ! command -v docker >/dev/null 2>&1; then
    warn "compose.yaml exists but docker is not available; serving the shell only"
    return 0
  fi
  info "bringing the stack up from ${compose}"
  (cd "${ROOT_DIR}" && docker compose -f "${compose}" up -d)
  ok "stack started"
}

container_hint() {
  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi
  printf '\n  Container alternative for the shell alone:\n'
  printf '    docker compose -f docker-compose.yml up -d --build   # serves on port 4000\n'
}

print_manual_checks() {
  local host_ip
  host_ip="$(node -e "
    const os = require('os');
    const nets = os.networkInterfaces();
    const addresses = Object.values(nets).flat().filter((n) => n && n.family === 'IPv4' && !n.internal);
    process.stdout.write(addresses.length ? addresses[0].address : 'localhost');
  " 2>/dev/null || printf 'localhost')"

  cat <<EOF

$(printf '\033[1mWorkcenter is up for manual verification\033[0m')

  Open:  http://localhost:${PORT}/
         http://${host_ip}:${PORT}/        (from another machine on the network)
  Logs:  ${LOG_FILE}
  Stop:  ./scripts/e2e.sh --down

$(printf '\033[1mPhase 2 checklist — the shell\033[0m')

  [ ] The rail shows the Workcenter wordmark, three application buttons, a search
      field, the sidebar body and the user menu, in that order.
  [ ] Files is active, its button carries the accent underline and the sidebar
      shows the Files navigator.
  [ ] Clicking Chat and Mail swaps the sidebar and the pane; Alt+1/2/3 do the same.
  [ ] Each application button has exactly one status indicator beneath it, and a
      centred STATUS label under the row.
  [ ] A pane that cannot load names what failed and offers Retry and Open in new
      tab — never a blank frame.
  [ ] The sidebar filter narrows the active application's rows; Escape clears it;
      Ctrl/Cmd+K focuses it.
  [ ] The ⋯ menu in a pane's top-right offers Reload, Open in new tab and Copy
      link (plus Show health detail for an administrator).
  [ ] /files, /chat and /mail are deep-linkable: reloading each restores that pane.
  [ ] Switching away from a pane and back preserves what was on screen.
  [ ] The brand header reads "Workcenter - Admin" for an administrator and
      "Workcenter - User" for everyone else, and the word disappears when the
      rail is collapsed.
  [ ] The user row shows the initials, the name stacked first-over-last (a long
      name is cut at 14 characters a line), the sun/moon button and the
      language button, and the menu holds identity, the admin links
      (administrator only) and Sign out last.
  [ ] Dark is the default; the sun in dark mode switches to light and the moon
      in light mode switches back, repainting the shell instantly with no reload.
  [ ] The language button shows a rounded flag and the two-letter code; opening
      it shows a flag, the language in its own characters and spelling, and its
      English name; choosing one translates the shell and sets <html lang>.
  [ ] Collapsing the rail leaves the initials button alone; opening it shows the
      full-size menu with the mode and language controls still reachable.
  [ ] With no broker, a mode change reports that the panes could not be
      reached rather than pretending it worked.

$(printf '\033[1mWhat needs the rest of the stack\033[0m')

  - A real Files, Chat or Mail pane needs roadmap Phase 3 (compose + Traefik).
  - The panes changing appearance needs Phase 5 (identity) and Phase 6 (the
    broker's per-user credentials); the shell half of the bridge is in place.
  - Playwright takes over these checks in Phase 7; see Testing.md.
EOF
  container_hint
  printf '\n'
}

main() {
  parse_args "$@"
  check_toolchain

  if [[ "${DO_CLEAN}" -eq 1 ]]; then
    stop_server
    stop_stack
    if [[ -n "$(our_server_pids)" ]]; then
      fail "a Workcenter server survived the stop; refusing to delete its records"
      exit 1
    fi
    info "removing dist/ and the run directory"
    rm -rf "${ROOT_DIR}/dist" "${RUN_DIR}"
    ok "clean"
    exit 0
  fi

  if [[ "${DO_DOWN}" -eq 1 ]]; then
    stop_server
    stop_stack
    ok "everything stopped"
    exit 0
  fi

  build_shell
  start_server
  deploy_stack
  print_manual_checks
}

main "$@"
