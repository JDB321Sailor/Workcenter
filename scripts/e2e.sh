#!/usr/bin/env bash
#
# Workcenter end-to-end harness.
#
# A person is the test runner (Testing.md §6): this script builds and deploys the
# stack, checks everything a machine can check without a browser, then prints the
# checklist for what only a person can judge. From Phase 3 it deploys the real
# thing -- the Docker stack, behind Traefik -- rather than serving the shell on
# its own.
#
#   ./scripts/e2e.sh                 # build the image, deploy the stack, run the checks
#   ./scripts/e2e.sh --no-build      # reuse the image already built
#   ./scripts/e2e.sh --shell-only    # no Docker: serve the built shell on the host
#   ./scripts/e2e.sh --down          # stop everything and leave only the images
#   ./scripts/e2e.sh --hosts         # report whether a browser can reach the stack
#   ./scripts/e2e.sh --dry-run       # print what it would do, in order
#   ./scripts/e2e.sh --help
#
# It never runs as root, and refuses to: everything it creates would belong to
# root and the next run would need root to replace. The privileged, one-time setup
# — /etc/hosts, the trust store, and the ownership of the state the containers
# leave behind — is `scripts/setup-testing.sh`.
#
# Design rules this script follows:
#   - It never publishes an application to the host. Traefik is the only ingress,
#     and in the test profile it binds to 127.0.0.1 only, so the unauthenticated
#     phase is reachable by this machine and nothing else (production.md §7).
#   - It pulls an image only when the tag is not already present, so a repeat run
#     is fast and works offline once the images are there.
#   - `--down` removes what the run created: containers, networks, volumes, the
#     generated .env, certificates and runtime directories. Only the images stay.
#   - Every command and its output is logged under user-data/e2e/logs/<run>/.

set -Eeuo pipefail

IFS=$'\n\t'

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# The local certificate authority, shared with `scripts/setup-testing.sh`. Sourced
# here rather than inside a function because `ensure_env_file` — one of the first
# things a run does — needs it, and because the *same* generator has to have made
# the certificate the setup script installed into a browser's trust store.
# shellcheck source=lib/localca.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/localca.sh"
readonly RUN_DIR="${ROOT_DIR}/user-data/e2e"
readonly RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly LOG_DIR="${RUN_DIR}/logs/${RUN_ID}"
readonly MANIFEST="${RUN_DIR}/created-${RUN_ID}.manifest"
# Files a run overwrote, and where their previous contents were put. See
# `record_backup`.
readonly BACKUPS="${RUN_DIR}/backups-${RUN_ID}.manifest"

# The sockets Traefik itself binds in the test profile. Mailcow publishes its own web
# ports and cannot be stopped from doing so (IN-6.4), so these are reserved by name
# rather than by hoping nothing is listening: Mailcow is configured *before* Traefik
# starts, when 80 and 443 are genuinely free and about to stop being.
readonly TRAEFIK_HTTP_PORT="${TRAEFIK_HTTP_PORT:-80}"
readonly TRAEFIK_HTTPS_PORT="${TRAEFIK_HTTPS_PORT:-443}"
readonly TRAEFIK_DASHBOARD_PORT="${TRAEFIK_DASHBOARD_PORT:-8080}"
readonly COMPOSE_TEST_FILE="${ROOT_DIR}/compose.test.yaml"
readonly SHELL_PID_FILE="${RUN_DIR}/workcenter.pid"
readonly SHELL_LOG_FILE="${RUN_DIR}/workcenter.log"
readonly COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-workcenter}"

PORT="${PORT:-4180}"
HOST="${HOST:-0.0.0.0}"
MODE="stack"          # stack | shell-only
DO_BUILD=1
DO_DOWN=0
DO_CLEAN=0
DO_PULL=1
DO_HOSTS=0
DO_TRUST_CERT=0
# The browser preflight runs on every normal run: the point of the harness is that a
# person can open the result, and a deploy that cannot be opened has not been
# verified. `--no-browser` is for a machine with no browser and no interest in one.
DO_BROWSER=1
DO_KEEP=0
DO_DRY_RUN=0
DO_PIN=0
DO_BUMP=0
SECRETS_CHANGED=0
MAX_RESTARTS="${MAX_RESTARTS:-2}"
ZULIP_VERSION_ARG=""
ZULIP_COMMIT_ARG=""
WITH_MAILCOW=1
# Zulip's first start runs migrations behind a 300 s health start period, so the
# default budget is generous on purpose.
WAIT_TIMEOUT="${WAIT_TIMEOUT:-900}"
# Authentik's first start is a full migration of its own schema, and it is waited
# for **before** the rest of the stack is created — see `wait_for_authentik`. It is
# a separate budget from WAIT_TIMEOUT because it is a separate wait.
AUTHENTIK_READY_TIMEOUT="${AUTHENTIK_READY_TIMEOUT:-900}"

# Coloured, prefixed output (standards.md S-SH-7).
info() { printf '\033[36mℹ\033[0m %s\n' "$*"; }
ok() { printf '\033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⚠\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[31m✖\033[0m %s\n' "$*" >&2; }
step() { CURRENT_STAGE="$*"; printf '\n\033[1m%s\033[0m\n' "$*"; }

log_note() {
  [[ -d "${LOG_DIR}" ]] || return 0
  { printf '%s' "$(date -u +%H:%M:%SZ)"; printf ' %s' "$@"; printf '\n'; } >>"${LOG_DIR}/harness.log"
}

# Every external command goes through this, so the log holds what ran. `--dry-run`
# prints instead of running.
run() {
  log_note "run: $*"
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would run:'
    printf ' %s' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

on_error() {
  local line="$1" command="$2"
  fail "failed at ${BASH_SOURCE[0]}:${line}"
  fail "  command: ${command}"
  [[ -d "${LOG_DIR}" ]] && warn "  logs: ${LOG_DIR}"
  # A failure while the stack is being brought up leaves containers behind. Stop
  # them with the same teardown --down uses, then say what state Docker is in.
  if [[ "${DEPLOY_ACTIVE}" -eq 1 && "${DO_KEEP}" -eq 0 ]]; then
    deploy_failure_report "${line}" "${command}"
  fi
  exit 1
}

deploy_failure_report() {
  local line="$1" command="$2"
  printf '\n' >&2
  fail '──────────────── critical error ────────────────'
  fail "stage:   ${CURRENT_STAGE}"
  fail "command: ${command}"
  fail "line:    ${BASH_SOURCE[0]}:${line}"
  local crash="" printed_crash=0
  for crash in "${LOG_DIR}"/*-crash.log; do
    [[ -f "${crash}" ]] || continue
    printed_crash=1
    fail "the container reported (${crash##*/}):"
    tail -n 20 "${crash}" | sed 's/^/    /' >&2
    fail "  full log: ${crash}"
  done
  if [[ -f "${LOG_DIR}/unhealthy.log" && -s "${LOG_DIR}/unhealthy.log" ]]; then
    fail 'the failing container reported:'
    sed -n '1,12p' "${LOG_DIR}/unhealthy.log" | sed 's/^/    /' >&2
    fail "  full evidence: ${LOG_DIR}/unhealthy.log"
  elif [[ "${printed_crash}" -eq 0 && -f "${LOG_DIR}/up.log" ]]; then
    fail 'the last lines from the deployment:'
    tail -n 8 "${LOG_DIR}/up.log" | sed 's/^/    /' >&2
  fi
  printf '\n' >&2
  warn 'tearing the stack down so nothing is left running half-deployed'
  DEPLOY_ACTIVE=0
  stack_down
  printf '\n' >&2
  warn 'the Docker stack was torn down: containers, networks and volumes for'
  warn "project ${COMPOSE_PROJECT} are gone, the run directory holds the logs, and the images"
  warn 'are kept so the next run does not download them again.'
  warn 'Fix the cause above and re-run; pass --keep to inspect a failed stack instead.'
  printf '\n' >&2
}
trap 'on_error "${LINENO}" "${BASH_COMMAND}"' ERR

usage() {
  cat <<'EOF'
Deploy and verify Workcenter with Docker, then print the manual checklist.

Usage: ./scripts/e2e.sh [options]

Modes:
  (default)         Build the Workcenter image and deploy the whole stack with
                    Traefik, run the automated checks, print the manual ones.
  --shell-only      No Docker: serve the built shell on this host (the Phase 2
                    path, still useful for a quick look at the UI).
  --down            Stop the stack and the shell server, remove everything the
                    run created, and verify only the images remain.
  --clean           --down, then remove dist/, the run directory and the
                    Workcenter images.

Options:
  --port <port>     Host port for --shell-only (default: 4180, or $PORT).
  --host <host>     Bind address for --shell-only (default: 0.0.0.0, or $HOST).
  --no-build        Reuse the existing Workcenter image / dist.
  --no-pull         Never pull an application image, even when it is missing.
  --no-mailcow      Do not bring Mailcow up (it needs its own bootstrap first).
  --pin             Do not look for a newer Zulip release; keep the pinned one.
  --bump-zulip-pin  Rewrite the committed Zulip pin - the image tag in the two
                    .env.example files, the docker-zulip tag, and the recorded
                    release commit - to the latest GitHub release, or to
                    --zulip-version, then exit. Zulip is not built: this moves the
                    tag the deployment pulls. The Markdown specification set is not
                    rewritten: it records the release the application was built
                    against, and a version claim in prose needs a review.
  --hosts           Report whether this machine is ready to reach the stack from a
                    browser, and exit. The same check runs automatically before every
                    deploy — see --no-browser.
  --no-browser      Skip the browser preflight. A normal run refuses to start unless
                    `scripts/setup-testing.sh` has prepared the machine, because a
                    deploy nobody can open has not been verified; on a machine with
                    no browser, and no intention of using one, this drops the
                    requirement and the run proceeds.
  --trust-cert      Ensure the local certificate exists, report where it is, and exit.
                    Trusting it is `sudo ./scripts/setup-testing.sh --trust-cert` — it
                    writes to system stores, which need root.
  --keep            Leave the stack and the logs in place when the run finishes.
  --wait <seconds>  How long to wait for services to report healthy (default 900).
                    A container that restarts more than $MAX_RESTARTS times fails the run
                    immediately, because a crash loop is not a slow start.
  --keep            Also keep a failed stack running for inspection; without it a
                    deploy failure tears the stack down and reports the state.
  --dry-run         Print the commands instead of running them.
  -h, --help        Print this help.

What it does, in order:
  1. Validates dependencies: docker, the compose v2 plugin (2.20+), a live daemon.
  2. Generates .env from .env.example when it is missing, and the local certificate.
  3. Writes the shell's own configuration and the framing origin for this run.
  4. Reports the pinned Zulip release, and pulls each image that is not present.
  5. Builds the Workcenter image, logging the build and reporting failures.
  6. Deploys the stack: Traefik plus the applications, bound to 127.0.0.1.
  7. Waits for every service healthcheck, then runs the automated checks.
  8. Prints the manual checklist for the phase the repository is at.
EOF
}

CURRENT_STAGE="startup"
DEPLOY_ACTIVE=0

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --shell-only) MODE="shell-only"; shift ;;
      --port) PORT="${2:?--port needs a value}"; shift 2 ;;
      --host) HOST="${2:?--host needs a value}"; shift 2 ;;
      --no-build) DO_BUILD=0; shift ;;
      --no-pull) DO_PULL=0; shift ;;
      --no-mailcow) WITH_MAILCOW=0; shift ;;
      --pin) DO_PIN=1; shift ;;
      --bump-zulip-pin) DO_BUMP=1; shift ;;
      --zulip-version) ZULIP_VERSION_ARG="${2:?--zulip-version needs a value}"; shift 2 ;;
      --zulip-commit) ZULIP_COMMIT_ARG="${2:?--zulip-commit needs a value}"; shift 2 ;;
      --hosts) DO_HOSTS=1; shift ;;
      --trust-cert) DO_TRUST_CERT=1; shift ;;
      --no-browser) DO_BROWSER=0; shift ;;
      --keep) DO_KEEP=1; shift ;;
      --wait) WAIT_TIMEOUT="${2:?--wait needs a value}"; shift 2 ;;
      --down) DO_DOWN=1; shift ;;
      --clean) DO_CLEAN=1; DO_DOWN=1; shift ;;
      --dry-run) DO_DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "unknown option: $1"; usage >&2; exit 2 ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# Dependencies
#
# A failed dependency is reported with what to do about it: this script is the
# first thing a new operator runs.
# ---------------------------------------------------------------------------
require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "$1 is required but not installed"
    [[ -n "${2:-}" ]] && fail "  $2"
    exit 1
  fi
}

check_dependencies() {
  step 'Dependencies'
  require_tool node 'install Node 24: https://nodejs.org'
  info "node $(node --version)"

  # Teardown must work when Docker is broken or absent: that is precisely when a
  # left-over stack needs clearing. It checks for the CLI only, and the teardown
  # itself reports what it could not reach.
  if [[ "${DO_DOWN}" -eq 1 ]]; then
    if command -v docker >/dev/null 2>&1; then
      info "docker $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',') (teardown)"
    else
      warn 'docker is not installed: only the shell server can be stopped'
    fi
    return 0
  fi

  if [[ "${MODE}" == "shell-only" ]]; then
    require_tool yarn 'run: corepack enable'
    info "yarn $(yarn --version)"
    return 0
  fi

  require_tool docker 'install Docker Engine: https://docs.docker.com/engine/install/'
  if ! docker compose version >/dev/null 2>&1; then
    fail 'the docker compose v2 plugin is required (v2.20 or newer: this stack uses `include:`)'
    fail '  install: https://docs.docker.com/compose/install/linux/'
    exit 1
  fi
  local compose_version major minor client_version
  compose_version="$(docker compose version --short 2>/dev/null || echo 0)"
  major="${compose_version%%.*}"
  minor="$(printf '%s' "${compose_version}" | cut -d. -f2)"
  # The client version is readable without a daemon, which is what makes it
  # usable in a diagnostic message when the daemon is the thing that is wrong.
  client_version="$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo '?')"
  info "docker ${client_version}, compose ${compose_version}"
  if [[ "${major:-0}" -lt 2 || ( "${major:-0}" -eq 2 && "${minor:-0}" -lt 20 ) ]]; then
    fail "docker compose ${compose_version} is too old; 2.20+ is required for include:"
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    fail 'the Docker daemon is not reachable'
    fail '  start it (systemctl start docker) or check DOCKER_HOST and your group membership'
    exit 1
  fi
  local storage
  storage="$(docker info --format '{{.Driver}}' 2>/dev/null || echo '?')"
  info "daemon reachable, storage driver ${storage}"
  # An `if`, not `[[ ... ]] && warn`: as the last statement of this function the
  # `&&` list would make the function return 1 whenever the driver is *not* vfs
  # (the left-hand test's status becomes the function's), and `set -e` would then
  # abort the whole run with an ERR trap pointing at this line. A warning must
  # never be fatal.
  if [[ "${storage}" == "vfs" ]]; then
    warn 'the vfs storage driver copies every layer: builds are slower and use more disk'
  fi
}

# ---------------------------------------------------------------------------
# Generated state
#
# Anything this script creates is recorded in a manifest, so --down removes
# exactly what the run produced and nothing the operator brought with them.
# ---------------------------------------------------------------------------
record_created() { printf '%s\n' "$*" >>"${MANIFEST}"; }

# ---------------------------------------------------------------------------
# Backups — for the files a run must *modify* rather than create
#
# `MANIFEST` records what a run created, and `--down` deletes those. That is not
# enough for Mailcow: it is configured by its own configurator, which rewrites
# `mailcow.conf` in place, and the file has to come back exactly as it was or the
# next run starts from a half-configured Mailcow. So anything a run overwrites is
# copied aside first and restored by `--down`.
# ---------------------------------------------------------------------------
record_backup() {
  local path="$1" store
  [[ -e "${path}" ]] || return 0
  store="${RUN_DIR}/backup-$(printf '%s' "${path}" | md5sum | cut -c1-12)"
  cp -a "${path}" "${store}" 2>/dev/null || return 0
  printf '%s\t%s\n' "${path}" "${store}" >>"${BACKUPS}"
}

prepare_run_dir() {
  mkdir -p "${LOG_DIR}"
  : >"${LOG_DIR}/harness.log"
  : >"${MANIFEST}"
  : >"${BACKUPS}"
  info "run directory: ${LOG_DIR}"
}

ensure_env_file() {
  step 'Configuration'
  if [[ -f "${ROOT_DIR}/.env" ]]; then
    info '.env exists: leaving it alone'
  else
    [[ -f "${ROOT_DIR}/.env.example" ]] || { fail '.env.example is missing'; exit 1; }
    run cp "${ROOT_DIR}/.env.example" "${ROOT_DIR}/.env"
    record_created "${ROOT_DIR}/.env"
    if [[ "${DO_DRY_RUN}" -eq 0 ]]; then
      # Two values the example cannot know: where this checkout is, and a key for
      # the broker vault. Both are written with sed so the rest of the file stays
      # exactly as the operator-readable example.
      sed -i "s|^FILEBROWSER_SOURCE_PATH=.*|FILEBROWSER_SOURCE_PATH=${ROOT_DIR}/Filebrowser/data/files|" "${ROOT_DIR}/.env"
      if command -v openssl >/dev/null 2>&1; then
        if grep -q '^BROKER_VAULT_KEY=$' "${ROOT_DIR}/.env"; then
          sed -i "s|^BROKER_VAULT_KEY=.*|BROKER_VAULT_KEY=$(openssl rand -base64 32)|" "${ROOT_DIR}/.env"
        fi
        # One secret, two names: FileBrowser signs with FILEBROWSER_ONLYOFFICE_SECRET
        # and ONLYOFFICE verifies with JWT_SECRET, so the two values must be
        # byte-identical (IN-4.2). Generate once and write it to both lines.
        if grep -q '^FILEBROWSER_ONLYOFFICE_SECRET=replace-me' "${ROOT_DIR}/.env"; then
          OFFICE_SECRET="$(openssl rand -base64 32)"
          sed -i "s|^FILEBROWSER_ONLYOFFICE_SECRET=.*|FILEBROWSER_ONLYOFFICE_SECRET=${OFFICE_SECRET}|" "${ROOT_DIR}/.env"
          sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${OFFICE_SECRET}|" "${ROOT_DIR}/.env"
        fi
      fi
      ok 'generated .env from .env.example (source path and vault key filled in)'
    fi
  fi

  # Traefik needs three paths that are runtime state, never committed (P-16, P-24).
  # acme.json must exist as a *file* before the first start: Docker creates a
  # missing bind-mount source as a directory, which Traefik cannot use.
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would create: Traefik/{certs,logs,acme.json}\n'
  else
  mkdir -p "${ROOT_DIR}/Traefik/certs" "${ROOT_DIR}/Traefik/logs"
  if [[ ! -f "${ROOT_DIR}/Traefik/acme.json" ]]; then
    install -m 600 /dev/null "${ROOT_DIR}/Traefik/acme.json" 2>/dev/null \
      || : >"${ROOT_DIR}/Traefik/acme.json"
    record_created "${ROOT_DIR}/Traefik/acme.json"
  fi
  fi

  # The local profile needs a certificate: Traefik serves it as the default when no
  # ACME resolver answers, and there is no DNS name to validate here. It has to name
  # every hostname this run serves — not only the shell's — because the shell reaches
  # the applications through Traefik by those names and *verifies* what it is given.
  #
  # The generation itself is `scripts/lib/localca.sh`, shared with
  # `scripts/setup-testing.sh`. That is not tidiness: a certificate generated by two
  # programs is two certificates, and the browser trusts whichever one the setup
  # script installed while the stack serves the other. The setup script creates it
  # **before** this ever runs; here it is only a fallback for a machine where nobody
  # ran the setup script and nobody is going to open a browser.
  localca_ensure
  if [[ "${LOCALCA_CREATED}" -eq 1 ]]; then
    record_created "${ROOT_DIR}/Traefik/certs/local-ca.crt" \
      "${ROOT_DIR}/Traefik/certs/local-ca.key" \
      "${ROOT_DIR}/Traefik/certs/local.crt" "${ROOT_DIR}/Traefik/certs/local.key"
  fi
}

# The stack bind-mounts host directories that an operator's checkout may not have
# yet. Create only the ones that are missing, and record those: --down removes what
# the run created and never touches a directory the operator already had.
# Every application folder ships its own .env.example, and a compose file included
# by the root composition interpolates from its own directory's .env (compose-go
# loads it as a default, with the root environment winning). Generate the missing
# ones, and record them so --down removes what this run created.
ensure_app_env_files() {
  step 'Application configuration'
  local folder example created=0
  # Authentik is in the list because it is an application folder like the others:
  # it owns `Authentik/.env`, and Compose loads that file for the compose file it
  # includes (Authentik/compose.yaml).
  for folder in Traefik Filebrowser OnlyOffice Zulip Authentik; do
    example="${ROOT_DIR}/${folder}/.env.example"
    [[ -f "${example}" ]] || continue
    if [[ -f "${ROOT_DIR}/${folder}/.env" ]]; then
      info "${folder}/.env exists: leaving it alone"
      continue
    fi
    if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
      printf '   would run: cp %s %s\n' "${example}" "${ROOT_DIR}/${folder}/.env"
      continue
    fi
    cp "${example}" "${ROOT_DIR}/${folder}/.env"
    record_created "${ROOT_DIR}/${folder}/.env"
    created=$((created + 1))
  done
  ok "generated ${created} application .env file(s)"
}

# ---------------------------------------------------------------------------
# Identity secrets
#
# Two files have to agree before the first bring-up, and neither can be committed
# (P-16, O-13.1):
#
#   * `Authentik/.env` — the database password, the signing key and the bootstrap
#     credentials Authentik reads on its **first** boot only.
#     `ensure_app_env_files` has already copied the template; this fills in the
#     values that must not stay placeholders.
#   * the root `.env` — one OIDC client pair per application. The secrets are
#     generated here, written **into** Authentik by `scripts/lib/authentik.sh`,
#     and read by the applications from these same lines, so the two ends cannot
#     disagree and no secret is ever copied by hand (production.md §5.5.3).
#
# Both are generated once and then left alone: changing them on a later run would
# invalidate every session and force a re-provision, which is the opposite of the
# convergence the harness asserts.
ensure_identity_secrets() {
  step 'Identity secrets'
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would generate: Authentik/.env bootstrap values and the OIDC client secrets in .env\n'
    return 0
  fi
  require_tool openssl 'needed to generate the identity secrets'

  local auth_env="${ROOT_DIR}/Authentik/.env"
  if [[ -f "${auth_env}" ]]; then
    local key
    for key in PG_PASS AUTHENTIK_SECRET_KEY AUTHENTIK_BOOTSTRAP_TOKEN; do
      if grep -qE "^${key}=(replace-with.*|)$" "${auth_env}"; then
        sed -i "s|^${key}=.*|${key}=$(openssl rand -hex 32)|" "${auth_env}"
      fi
    done
    if grep -qE '^AUTHENTIK_BOOTSTRAP_PASSWORD=$' "${auth_env}"; then
      sed -i "s|^AUTHENTIK_BOOTSTRAP_PASSWORD=.*|AUTHENTIK_BOOTSTRAP_PASSWORD=${AUTHENTIK_BOOTSTRAP_PASSWORD}|" "${auth_env}"
    fi
    # The file is the single source of truth for this password, and the export has
    # to agree with it. Compose interpolates `${AUTHENTIK_BOOTSTRAP_PASSWORD}` from
    # the **shell environment first** and only then from `.env`, so an earlier
    # default left exported here overrides the file: the provider gets bootstrapped
    # with one password while every reader of the file — including the console check
    # — uses the other, and the only visible symptom is a sign-in that re-prompts
    # forever. Re-exporting what the file now holds removes the second value.
    AUTHENTIK_BOOTSTRAP_PASSWORD="$(sed -n 's/^AUTHENTIK_BOOTSTRAP_PASSWORD=//p' "${auth_env}" | head -1)"
    export AUTHENTIK_BOOTSTRAP_PASSWORD
    # The identity hostname is derived from this run's base domain like every other
    # host, so the template's `auth.example.com` never reaches the stack.
    sed -i "s|^AUTHENTIK_HOST=.*|AUTHENTIK_HOST=${AUTHENTIK_HOST}|" "${auth_env}"
    sed -i "s|^AUTHENTIK_TAG=.*|AUTHENTIK_TAG=$(sed -n 's/^AUTHENTIK_TAG=//p' "${ROOT_DIR}/.env" | head -1)|" "${auth_env}"
    chmod 600 "${auth_env}"
    ok 'Authentik/.env carries bootstrap credentials'
  else
    warn 'Authentik/.env is missing: the identity provider cannot start'
  fi

  local app var
  for app in WORKCENTER FILEBROWSER ZULIP MAILCOW; do
    var="${app}_OIDC_CLIENT_SECRET"
    if grep -qE "^${var}=$" "${ROOT_DIR}/.env"; then
      sed -i "s|^${var}=.*|${var}=$(openssl rand -hex 32)|" "${ROOT_DIR}/.env"
    fi
  done
  ok 'OIDC client secrets generated (one per application)'
}

# ---------------------------------------------------------------------------
# The shell's identity in the deployment's configuration
#
# Two files the operator owns name the shell itself, and both are committed with
# `example.com`, which setup.sh rewrites in place for a deployment
# (production.md §5.4). The harness must not modify either, so it writes a copy of
# each carrying this run's addresses and compose.test.yaml mounts the copies over
# the originals:
#
#   * user-data/conf.yml — every pane address, and the address the broker probes
#     for the switcher's status indicators (src/utils/apps/urls.js, broker.md
#     §3.4). Left alone, the test shell embeds https://filebrowser.example.com —
#     hosts that do not resolve here — and reports every application unreachable
#     while the applications answer normally through Traefik.
#   * Traefik/dynamic/middlewares.yml — the framing allow-list. Traefik *sets*
#     that header, so it is the one a browser enforces and it overwrites whatever
#     a backend sends ("Traefik *sets* this header rather than merging it"). Left
#     alone, every pane is blocked from being framed by the shell's real origin,
#     and the broker reports each application as refusing to be framed.
# ---------------------------------------------------------------------------
ensure_shell_config() {
  step 'Shell configuration'
  local source="${ROOT_DIR}/user-data/conf.yml"
  local target="${ROOT_DIR}/user-data/conf.test.yml"
  if [[ ! -f "${source}" ]]; then
    warn "no ${source#"${ROOT_DIR}/"}: the shell has no application addresses to map"
  elif [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would write: %s (this run'"'"'s application addresses)\n' "${target#"${ROOT_DIR}/"}"
  else
    # Only the three committed example.com addresses are replaced; anything else in
    # the file — theme, opening method, the inert OIDC block — is carried through
    # byte for byte, so the test shell behaves like the deployed one.
    sed -e "s|^\( *url: *\)https://filebrowser\.example\.com$|\1https://${FILEBROWSER_HOST}|" \
        -e "s|^\( *url: *\)https://chat\.example\.com$|\1https://${CHAT_HOST}|" \
        -e "s|^\( *url: *\)https://mail\.example\.com/SOGo$|\1https://${MAIL_HOST}/SOGo|" \
        "${source}" >"${target}"
    record_created "${target}"
    local mapped=0 want
    for want in "https://${FILEBROWSER_HOST}" "https://${CHAT_HOST}" "https://${MAIL_HOST}/SOGo"; do
      grep -qF "${want}" "${target}" && mapped=$((mapped + 1))
    done
    if [[ "${mapped}" -eq 3 ]]; then
      ok "wrote ${target#"${ROOT_DIR}/"} with this run's application addresses"
    else
      warn "only ${mapped} of 3 application addresses in ${source#"${ROOT_DIR}/"} use the committed example.com defaults"
      warn 'the test shell keeps whatever that file names for the rest'
    fi
  fi

  local mw_source="${ROOT_DIR}/Traefik/dynamic/middlewares.yml"
  local mw_target="${ROOT_DIR}/Traefik/dynamic/middlewares.test.yml"
  if [[ ! -f "${mw_source}" ]]; then
    warn "no ${mw_source#"${ROOT_DIR}/"}: the framing origin is not mapped"
  elif [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would write: %s (frame-ancestors %s)\n' "${mw_target#"${ROOT_DIR}/"}" "${BASE_URL}"
  else
    sed -e "s|frame-ancestors https://example\.com|frame-ancestors ${BASE_URL}|" \
      "${mw_source}" >"${mw_target}"
    record_created "${mw_target}"
    if grep -qF "frame-ancestors ${BASE_URL}" "${mw_target}"; then
      ok "wrote ${mw_target#"${ROOT_DIR}/"} with ${BASE_URL} as the framing origin"
    else
      warn "${mw_source#"${ROOT_DIR}/"} does not carry the committed example.com framing origin"
      warn 'the test shell will keep whatever origin that file names'
    fi
  fi
}

# ---------------------------------------------------------------------------
# The identity configuration the applications read
#
# Everything here follows one rule: the committed file is the template and stays
# untouched, and the run writes a copy that compose.test.yaml mounts over the
# original. That is what keeps `example.com` out of the running stack without
# editing a file the operator owns.
#
#   * user-data/conf.test.yml         — the shell's OIDC client switched on
#   * Filebrowser/config.test.yaml    — the Files pane's OIDC client
#   * Traefik/dynamic/dashboard.test.yml — the dashboard behind forward auth
#
# Each is generated *before* `stack_up`, because two of the three are read once at
# startup and a container that started before the write would have to be
# recreated to see it (IN-3.6).
# ---------------------------------------------------------------------------
ensure_identity_config() {
  step 'Identity configuration'

  local admin_group="${WORKCENTER_ADMIN_GROUP:-workspaceadmin}"
  local user_group="${WORKCENTER_USER_GROUP:-workspaceusers}"

  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would write: user-data/conf.test.yml, Filebrowser/config.test.yaml, Traefik/dynamic/dashboard.test.yml\n'
    return 0
  fi

  local workcenter_secret filebrowser_secret
  workcenter_secret="$(sed -n 's/^WORKCENTER_OIDC_CLIENT_SECRET=//p' "${ROOT_DIR}/.env" | head -1)"
  filebrowser_secret="$(sed -n 's/^FILEBROWSER_OIDC_CLIENT_SECRET=//p' "${ROOT_DIR}/.env" | head -1)"

  # --- the shell ------------------------------------------------------------
  # `enableOidc` is the switch the shell reads (src/utils/auth/OidcAuth.js), and
  # `adminGroup` is what turns a `groups` claim into `isAdmin` — server-side in
  # services/utils/auth-oidc.js and in the browser. The endpoint is the bare
  # per-application issuer, which is what the committed file already carries for
  # example.com, so only the host has to change.
  local conf="${ROOT_DIR}/user-data/conf.test.yml"
  if [[ -f "${conf}" ]]; then
    sed -i -e 's|^\( *\)enableOidc: false$|\1enableOidc: true|' \
           -e "s|^\( *endpoint: *\)https://auth\.example\.com/application/o/workcenter/$|\1https://${AUTHENTIK_HOST}/application/o/workcenter/|" \
           -e "s|^\( *postLogoutRedirectUri: *\)https://example\.com$|\1https://${WORKCENTER_HOST}|" \
           -e "s|^\( *adminGroup: *\).*|\1${admin_group}|" \
           "${conf}"
    if grep -q '^ *enableOidc: true$' "${conf}"; then
      ok "shell OIDC enabled (issuer https://${AUTHENTIK_HOST}/application/o/workcenter/, admin group ${admin_group})"
    else
      warn 'could not enable OIDC in the shell configuration'
    fi
  fi

  # --- the Files pane -------------------------------------------------------
  # FileBrowser runs provider discovery at startup and stops if it fails, so the
  # copy has to exist — with a real issuer and a real secret — before `up`.
  local fb_source="${ROOT_DIR}/Filebrowser/config.yaml"
  local fb_target="${ROOT_DIR}/Filebrowser/config.test.yaml"
  if [[ -f "${fb_source}" ]]; then
    # Only the FIRST `enabled: false` is flipped: the OIDC block comes before the
    # password block, and turning password login on as well would defeat the point
    # of the test.
    sed -e '0,/^\( *\)enabled: false$/s//\1enabled: true/' \
        -e "s|^\( *issuerUrl: *\).*|\1\"https://${AUTHENTIK_HOST}/application/o/filebrowser/\"|" \
        -e "s|^\( *clientSecret: *\).*|\1\"${filebrowser_secret}\"|" \
        -e "s|^\( *adminGroup: *\).*|\1\"${admin_group}\"|" \
        -e "s|^\( *- *\)\"workspaceusers\"$|\1\"${user_group}\"|" \
        -e "s|^\( *logoutRedirectUrl: *\).*|\1\"https://${AUTHENTIK_HOST}/application/o/filebrowser/end-session/\"|" \
        "${fb_source}" >"${fb_target}"
    record_created "${fb_target}"
    if grep -q '^ *enabled: true$' "${fb_target}" && grep -qF "${AUTHENTIK_HOST}" "${fb_target}"; then
      ok 'Files OIDC enabled with the run'"'"'s issuer and client secret'
    else
      warn 'could not fully enable OIDC in the FileBrowser configuration'
    fi
  fi

  # --- the Traefik dashboard ------------------------------------------------
  # P-20 and IN-7.8: the dashboard router carries the forward-auth middleware, and
  # a second router serves `/outpost.goauthentik.io/` on the same host at a higher
  # priority so the browser can reach the outpost that is challenging it. The
  # outpost router itself is a label on the Authentik server container
  # (Authentik/compose.yaml), which is where the service it targets is defined.
  local dash_source="${ROOT_DIR}/Traefik/dynamic/dashboard.yml"
  local dash_target="${ROOT_DIR}/Traefik/dynamic/dashboard.test.yml"
  if [[ -f "${dash_source}" ]]; then
    sed -e "s|Host(\`traefik\.example\.com\`)|Host(\`${TRAEFIK_HOST}\`)|" \
        -e 's|^\( *\)# \(middlewares:\)$|\1\2|' \
        -e 's|^\( *\)# \( *- authentik@file.*\)$|\1\2|' \
        "${dash_source}" >"${dash_target}"
    record_created "${dash_target}"
    if grep -q 'authentik@file' "${dash_target}"; then
      ok "dashboard behind Authentik forward auth on ${TRAEFIK_HOST}"
    else
      warn 'could not attach the forward-auth middleware to the dashboard'
    fi
  fi

  # --- the forward-auth middleware itself -----------------------------------
  # The committed `middlewares.yml` already carries the block, commented out, with
  # the address IN-7.8 specifies — it is the documentation of what a deployment
  # writes. Activating it is therefore an uncomment rather than an append, which
  # also keeps the generated file's structure identical to the committed one:
  # appending would have to guess the indentation that puts `authentik` under
  # `middlewares:` rather than inside the key that happens to follow it.
  local mw="${ROOT_DIR}/Traefik/dynamic/middlewares.test.yml"
  if [[ -f "${mw}" ]]; then
    sed -i \
      -e 's|^\(    \)\(# \)\(authentik:\)$|\1\3|' \
      -e 's|^\(    \)\(# \)\(  forwardAuth:\)$|\1\3|' \
      -e 's|^\(    \)\(# \)\(    address:.*\)$|\1\3|' \
      -e 's|^\(    \)\(# \)\(    trustForwardHeader:.*\)$|\1\3|' \
      -e 's|^\(    \)\(# \)\(    maxResponseBodySize:.*\)$|\1\3|' \
      "${mw}"
    if grep -qE '^    authentik:$' "${mw}" && grep -q 'forwardAuth' "${mw}"; then
      ok 'forward-auth middleware points at the embedded outpost'
    else
      warn 'could not activate the forward-auth middleware; the dashboard will not be protected'
    fi
  fi
}

# ---------------------------------------------------------------------------
# The Chat pane's identity configuration
#
# Zulip's OIDC settings have exactly one home: `ZULIP_CUSTOM_SETTINGS` in
# `Zulip/.env`. `SOCIAL_AUTH_OIDC_ENABLED`, `_CLIENT_ID`, `_SECRET` and `_URL` do
# not exist in Zulip at all (IN-5.6), and the IdP dictionary has to travel through
# `ZULIP_CUSTOM_SETTINGS` rather than an environment variable of its own (IN-5.5).
#
# Two details are easy to get wrong and are asserted below:
#
#   * `oidc_url` is the **base path with no trailing slash** (O-4.1). A trailing
#     slash makes python-social-auth append the discovery path twice.
#   * the redirect URI is `https://<chat host>/complete/oidc/` and nothing else
#     (O-6.5) — Zulip never redirects to the bare hostname, and registering only
#     the host produces `invalid redirect URI` on the first sign-in.
#
# The values are rewritten on every run rather than only on a fresh checkout: the
# client secret is generated per deployment, and a Zulip that kept an old one
# would fail at the token exchange with no obvious cause.
# ---------------------------------------------------------------------------
ensure_zulip_identity() {
  step 'Chat identity configuration'
  local env="${ROOT_DIR}/Zulip/.env"
  if [[ ! -f "${env}" ]]; then
    warn 'Zulip/.env is missing: the Chat pane has no OIDC configuration'
    return 0
  fi
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would write: Zulip/.env OIDC block (oidc_url https://%s/application/o/zulip)\n' "${AUTHENTIK_HOST}"
    return 0
  fi

  local client_id client_secret
  client_id="$(sed -n 's/^ZULIP_OIDC_CLIENT_ID=//p' "${ROOT_DIR}/.env" | head -1)"
  client_secret="$(sed -n 's/^ZULIP_OIDC_CLIENT_SECRET=//p' "${ROOT_DIR}/.env" | head -1)"

  sed -i \
    -e "s|^\( *\)'oidc_url': .*|\1'oidc_url': 'https://${AUTHENTIK_HOST}/application/o/zulip',|" \
    -e "s|REPLACE_WITH_THE_AUTHENTIK_CLIENT_ID|${client_id}|g" \
    -e "s|REPLACE_WITH_THE_AUTHENTIK_CLIENT_SECRET|${client_secret}|g" \
    "${env}"

  if grep -qF "'oidc_url': 'https://${AUTHENTIK_HOST}/application/o/zulip'" "${env}" \
      && ! grep -q 'REPLACE_WITH_THE_AUTHENTIK' "${env}"; then
    ok "Chat OIDC enabled (oidc_url https://${AUTHENTIK_HOST}/application/o/zulip, no trailing slash)"
  else
    warn 'could not fully write the Zulip OIDC block'
  fi
}

# ---------------------------------------------------------------------------
# What Authentik has to contain
## Every object Phase 4 needs is created here by `scripts/lib/authentik.sh` — the
# same library `setup.sh` will source — so the harness and the installer cannot
# drift apart. The library is idempotent by construction (production.md P-40:
# every object is looked up by its unique key before it is created), which is what
# lets this run on every invocation rather than only on a fresh instance.
#
# The three accounts are the fixtures Testing.md §7.1 fixes: an administrator in
# both groups, an ordinary member of `workspaceusers`, and somebody in no group at
# all. The last one is what makes the negative checks real — "the dashboard is
# admin-only" means nothing if the only accounts that ever try are ones that are
# supposed to get in.
#
# Membership is *set*, not added to. The exit criteria invite an operator to
# remove somebody from `workspaceusers` and watch them lose access; the next run
# must put the fixture back to the documented shape.
# ---------------------------------------------------------------------------
ensure_authentik_identity() {
  step 'Authentik provisioning'
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would provision: 2 groups, 3 scope mappings, 4 OIDC providers + applications,\n'
    printf '                    the traefik-dashboard proxy provider, outpost membership, icons\n'
    printf '   would create:    %s, %s, %s\n' \
      "${AUTHENTIK_TEST_ADMIN_EMAIL}" "${AUTHENTIK_TEST_USER_EMAIL}" "${AUTHENTIK_TEST_OUTSIDER_EMAIL}"
    return 0
  fi

  # The OIDC client pairs live in the root `.env` (OIDC.md §9). They are read
  # explicitly rather than by sourcing the file, because `.env` is written for
  # Compose and is not guaranteed to be shell-quotable.
  local key
  for key in WORKCENTER_OIDC_CLIENT_ID WORKCENTER_OIDC_CLIENT_SECRET \
             FILEBROWSER_OIDC_CLIENT_ID FILEBROWSER_OIDC_CLIENT_SECRET \
             ZULIP_OIDC_CLIENT_ID ZULIP_OIDC_CLIENT_SECRET \
             MAILCOW_OIDC_CLIENT_ID MAILCOW_OIDC_CLIENT_SECRET; do
    export "${key}=$(sed -n "s/^${key}=//p" "${ROOT_DIR}/.env" | head -1)"
  done

  export AUTHENTIK_BASE_URL="${AUTHENTIK_URL}"
  AUTHENTIK_TOKEN="$(sed -n 's/^AUTHENTIK_BOOTSTRAP_TOKEN=//p' "${ROOT_DIR}/Authentik/.env" | head -1)"
  export AUTHENTIK_TOKEN
  # The `akadmin` password belongs to the deployment, not to this script: it is
  # read on Authentik's **first** boot only, so a value already in the file is the
  # one that exists. `ensure_identity_secrets` only fills a blank line, and this
  # reads back whatever ended up there — otherwise the console check would test a
  # password the provider has never seen, and fail for the wrong reason.
  local akadmin_password
  akadmin_password="$(sed -n 's/^AUTHENTIK_BOOTSTRAP_PASSWORD=//p' "${ROOT_DIR}/Authentik/.env" | head -1)"
  if [[ -n "${akadmin_password}" ]]; then
    export AUTHENTIK_BOOTSTRAP_PASSWORD="${akadmin_password}"
  fi
  # Reached the same way every other check reaches the stack: the deployment's own
  # hostname, resolved to the loopback Traefik, with the harness CA.
  AUTHENTIK_CURL_EXTRA=(--insecure --resolve "${AUTHENTIK_HOST}:443:127.0.0.1")
  export AUTHENTIK_CURL_EXTRA
  export ROOT_DIR

  # shellcheck source=lib/authentik.sh
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/lib/authentik.sh"

  authentik_wait_ready || return 1
  authentik_provision || return 1

  authentik_ensure_user "${AUTHENTIK_TEST_ADMIN_EMAIL}" "${AUTHENTIK_TEST_ADMIN_EMAIL}" \
    'Workcenter Test Admin' "${AUTHENTIK_TEST_ADMIN_PASSWORD}" \
    "${WORKCENTER_USER_GROUP}" "${WORKCENTER_ADMIN_GROUP}" || return 1
  ok "identity ${AUTHENTIK_TEST_ADMIN_EMAIL}: ${WORKCENTER_USER_GROUP}, ${WORKCENTER_ADMIN_GROUP}"

  authentik_ensure_user "${AUTHENTIK_TEST_USER_EMAIL}" "${AUTHENTIK_TEST_USER_EMAIL}" \
    'Workcenter Test User' "${AUTHENTIK_TEST_USER_PASSWORD}" \
    "${WORKCENTER_USER_GROUP}" || return 1
  ok "identity ${AUTHENTIK_TEST_USER_EMAIL}: ${WORKCENTER_USER_GROUP}"

  authentik_ensure_user "${AUTHENTIK_TEST_OUTSIDER_EMAIL}" "${AUTHENTIK_TEST_OUTSIDER_EMAIL}" \
    'Workcenter Test Outsider' "${AUTHENTIK_TEST_OUTSIDER_PASSWORD}" || return 1
  ok "identity ${AUTHENTIK_TEST_OUTSIDER_EMAIL}: no group (the denial fixture)"
}

# ---------------------------------------------------------------------------
# Mailcow's identity configuration
#
# Mailcow keeps its identity provider in its **database**, not in a file, so it is
# the one application configured over an API rather than by writing configuration.
# The calls are the ones docs/research/mailcow-automation-feasibility.md §4
# verified end to end, and they are what production.md §5.7 describes for
# setup.sh: the identity provider, the domain, and a mailbox on the OIDC identity
# source.
#
# Two Mailcow behaviours shape this:
#
#   * **No upsert.** `add/domain` answers `domain_exists` on a second run, and that
#     is convergence, not failure — so the reply is inspected rather than trusted.
#   * **One identity provider at a time.** Mailcow refuses to change the provider
#     while mailboxes use another (`authsource_in_use`), which is why Generic-OIDC
#     and LDAP are mutually exclusive (production.md §3.3, `MAILCOW_AUTHSOURCE`).
ensure_mailcow_identity() {
  step 'Mail identity configuration'
  if [[ "${WITH_MAILCOW}" -eq 0 ]]; then
    info 'skipping Mailcow (--no-mailcow)'
    return 0
  fi
  local conf="${ROOT_DIR}/Mailcow/mailcow.conf"
  if [[ ! -f "${conf}" ]]; then
    warn 'Mailcow is not initialised: the Mail pane has no identity configuration'
    return 0
  fi
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would configure: Mailcow Generic-OIDC, the mail domain and an OIDC mailbox\n'
    return 0
  fi

  local api_key secret mail_domain mailbox
  api_key="$(sed -n 's/^API_KEY=//p' "${conf}" | head -1)"
  secret="$(sed -n 's/^MAILCOW_OIDC_CLIENT_SECRET=//p' "${ROOT_DIR}/.env" | head -1)"
  mail_domain="${MAILCOW_DOMAIN:-${BASE_DOMAIN}}"
  # The address the **SSO button signs in as**, which is the identity provider's
  # test fixture and not the deployment's own address. Mailcow matches a login to a
  # mailbox by exact address, so provisioning the wrong one produces `Login failed`
  # with nothing in Mailcow's own log to explain it.
  mailbox="${MAILCOW_MAILBOX:-${AUTHENTIK_TEST_ADMIN_EMAIL}}"
  identity_domain="${mailbox##*@}"

  if [[ -z "${api_key}" ]]; then
    warn 'Mailcow/mailcow.conf has no API_KEY: cannot configure it without one'
    return 0
  fi

  _mailcow_api() {
    local path="$1" body="${2:-}"
    local -a args=(-sS --insecure --resolve "${MAIL_HOST}:443:127.0.0.1"
      -H "X-API-Key: ${api_key}" -H 'Content-Type: application/json')
    [[ -n "${body}" ]] && args+=(--data-binary "${body}")
    curl "${args[@]}" "https://${MAIL_HOST}/api/v1/${path}" 2>/dev/null || true
  }

  # --- the identity provider -------------------------------------------------
  #
  # `login_provisioning` is Mailcow's "Auto-create users on login", and the
  # integration guide requires it for anyone who has no mailbox yet.
  #
  # **`mappers` and `templates` are not optional**, and leaving them out does not
  # degrade gracefully — it kills the callback with a TypeError before any of the
  # login logic runs:
  #
  #   array_search(): Argument #2 ($haystack) must be of type array, null given
  #   /web/inc/functions.inc.php:2916  ← array_search($info['mailcow_template'], $iam_settings['mappers'])
  #
  # The pair maps the **value of the `mailcow_template` claim** onto a Mailcow
  # mailbox template, position by position: `mappers` holds the claim values,
  # `templates` the template names, and Mailcow writes neither unless the two have
  # equal length. So `["default"]` ↔ `["Default"]` says "a user whose claim is
  # `default` gets the `Default` template" — which is what the `mailcow_template`
  # scope mapping in the provider returns.
  local idp
  idp="$(_mailcow_api edit/identity-provider "$(jq -nc --arg s "${secret}" \
    --arg base "${AUTHENTIK_URL}/application/o" --arg redirect "https://${MAIL_HOST}" \
    '{items: ["identity-provider"], attr: {
        authsource: "generic-oidc",
        authorize_url: ($base + "/authorize/"),
        token_url: ($base + "/token/"),
        userinfo_url: ($base + "/userinfo/"),
        client_id: "mailcow",
        client_secret: $s,
        redirect_url: $redirect,
        client_scopes: "openid profile email mailcow_template",
        default_template: "Default",
        mappers: ["default"],
        templates: ["Default"],
        login_provisioning: true}}')")"
  if grep -q '"type":"success"' <<<"${idp}"; then
    ok 'Mail identity provider: Generic-OIDC against Authentik'
  else
    warn "could not configure Mailcow's identity provider: $(head -c 160 <<<"${idp}")"
  fi

  # --- the domains -----------------------------------------------------------
  # Two of them, and the second is the one that matters for sign-in.
  #
  # Mailcow only accepts a login for an address in a domain it hosts, and the
  # identity provider's test accounts live at the **fixture** domain
  # (`Testing.md` §7.1: `admin@wc.test`, `user@wc.test`), which is deliberately not
  # the deployment's own. Provisioning only `workcenter.local` therefore created a
  # mailbox nobody could ever sign in as, and the SSO button answered
  # `Login failed` with nothing in Mailcow's log to say why.
  #
  # `domain_exists` is the idempotent case: the DKIM key was generated on the run
  # that created it, and Mailcow answers with the same success shape.
  local dom
  for dom in "${mail_domain}" "${identity_domain}"; do
    local added
    added="$(_mailcow_api add/domain "$(jq -nc --arg d "${dom}" \
      '{domain: $d, description: "Workcenter", aliases: "400", mailboxes: "10",
        defquota: "3072", maxquota: "10240", quota: "10240", active: "1",
        restart_sogo: "1", gal: "0"}')")"
    if grep -qE '"type":"success"|domain_exists' <<<"${added}"; then
      ok "Mail domain: ${dom}"
    else
      warn "could not add the mail domain ${dom}: $(head -c 160 <<<"${added}")"
    fi
  done

  # --- a mailbox on the OIDC identity source ---------------------------------
  # `authsource` is what makes the mailbox sign in through Authentik rather than
  # with a Mailcow password (O-7.2). IMAP and SMTP cannot use OIDC at all, so the
  # mail protocols still need an app password (IN-6.10) — that is the documented
  # fallback, not an omission.
  #
  # The mailbox **is the identity provider's address**, not the deployment's: it is
  # the account the SSO button signs in as, and Mailcow matches the two by exact
  # address.
  local mb
  mb="$(_mailcow_api add/mailbox "$(jq -nc --arg m "${mailbox}" \
    '{local_part: ($m | split("@")[0]), domain: ($m | split("@")[1]),
      name: "Workcenter Admin", authsource: "generic-oidc", quota: "3072", active: "1",
      password: "", password2: "", force_pw_update: "0",
      tls_enforce_in: "0", tls_enforce_out: "0"}')")"
  if _mailcow_api get/mailbox "${mailbox}" | grep -q '"username"'; then
    # Already there — but it may still be on the local identity source from an
    # earlier run, in which case SSO is refused and password login is not.
    _mailcow_api edit/mailbox "$(jq -nc --arg m "${mailbox}" \
      '{items: [$m], attr: {authsource: "generic-oidc"}}')" >/dev/null
    ok "Mail mailbox: ${mailbox} on the Generic-OIDC identity source"
  # `object_exists` is the idempotent answer, exactly as `domain_exists` is above:
  # Mailcow has no upsert, so a re-run that races its own lookup — or finds the
  # mailbox by a route this check did not take — gets a refusal for the state it
  # wanted. Reporting that as a failure is how a correctly provisioned mailbox
  # printed a warning on every run after the first.
  elif grep -qE '"type":"success"|object_exists' <<<"${mb}"; then
    ok "Mail mailbox: ${mailbox} on the Generic-OIDC identity source"
  else
    warn "could not add the mailbox ${mailbox}: $(head -c 160 <<<"${mb}")"
  fi

  # --- the administrator's own password --------------------------------------
  # Mailcow's **admin page** is not an OIDC surface. It authenticates against the
  # `admin` table, which is deliberately separate from mailboxes — the SSO identity
  # `admin@wc.test` is a *mailbox*, and the documented integration says so: enabling
  # Generic-OIDC does not touch the local administrator login, and `check_login` only
  # diverts to the provider for `keycloak`/`ldap`. Mailcow generates that account a
  # password nobody knows, so the admin page is unreachable until one is set — which
  # is indistinguishable, from the outside, from "the password is wrong".
  #
  # It is set to a known value for a test run and printed with the other accounts,
  # under its own heading, so it is not mistaken for the SSO identity.
  local adm
  adm="$(_mailcow_api edit/admin "$(jq -nc --arg p "${MAILCOW_ADMIN_PASSWORD}" \
    '{items: ["admin"], attr: {password: $p, password2: $p}}')")"
  if grep -qE '"type":"success"|admin_modified' <<<"${adm}"; then
    ok 'Mail administrator password set (the admin page is local, not OIDC)'
  else
    warn "could not set the Mailcow administrator password: $(head -c 160 <<<"${adm}")"
  fi
}

ensure_mount_points() {
  step 'Mount points'
  local dirs=(
    "${ROOT_DIR}/Filebrowser/data"
    "${ROOT_DIR}/Filebrowser/office-cache"
    "${FILEBROWSER_SOURCE_PATH:-${ROOT_DIR}/Filebrowser/data/files}"
    "${ROOT_DIR}/OnlyOffice/data"
    "${ROOT_DIR}/OnlyOffice/logs"
    "${ROOT_DIR}/OnlyOffice/lib"
    "${ROOT_DIR}/OnlyOffice/db"
    "${ROOT_DIR}/Zulip/data"
    "${ROOT_DIR}/Zulip/database"
    "${ROOT_DIR}/Zulip/rabbitmq"
    "${ROOT_DIR}/Zulip/redis"
    # **Not `Mailcow/data`.** It looks like the other bind-mount targets and is not:
    # the upstream clone ships the configuration templates, the web tree and the
    # `ssl-example` assets under it, and Mailcow's own configurator writes into all
    # three. Creating it here is harmless; *recording* it here means `--down` deletes
    # a Mailcow that can never be configured again — which is exactly what happened,
    # and it is silent until the next `generate_config.sh` fails on
    # `data/assets/ssl-example/key.pem`.
    # Authentik's state, and every one of these has to exist *before* the first
    # `up`. Docker creates a missing bind-mount source itself — as a **root-owned
    # directory** — and the Authentik containers run as their own non-root uids, so
    # the server then dies during its tenant migration with
    # `PermissionError: [Errno 13] Permission denied: '/media/public'`.
    "${ROOT_DIR}/Authentik/data"
    "${ROOT_DIR}/Authentik/data/postgres"
    "${ROOT_DIR}/Authentik/data/media"
    "${ROOT_DIR}/Authentik/data/certs"
    "${ROOT_DIR}/Authentik/data/templates"
  )
  local dir created=0
  for dir in "${dirs[@]}"; do
    [[ -n "${dir}" ]] || continue
    if [[ ! -d "${dir}" ]]; then
      if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
        printf '   would create: %s\n' "${dir}"
        continue
      fi
      mkdir -p "${dir}"
      record_created "${dir}"
      created=$((created + 1))
    fi
  done
  # FileBrowser and the broker run as uid 1000 (the image is not root), and both
  # write these directories; the Authentik **server image also declares uid 1000**
  # (`Config.User`), and it writes `/media`, `/certs` and `/templates` — which is
  # the migration that fails with `Permission denied: '/media/public'` when those
  # are owned by anybody else.
  #
  # The harness cannot `chown` — that needs root, and it deliberately never has it
  # — so it *checks* instead and says what to do. On the common case, where the
  # person running this is uid 1000, there is nothing to do at all: the directories
  # this script creates are already owned by the uid the containers run as. When
  # the uid differs, `scripts/setup-testing.sh --ownership` is the one command that
  # fixes it, which beats a privileged call buried inside a test run.
  if [[ "${DO_DRY_RUN}" -eq 0 ]]; then
    local dir expected=1000
    for dir in "${ROOT_DIR}/Filebrowser/data" "${ROOT_DIR}/Filebrowser/office-cache" \
               "${FILEBROWSER_SOURCE_PATH:-}" \
               "${ROOT_DIR}/Authentik/data/media" \
               "${ROOT_DIR}/Authentik/data/certs" \
               "${ROOT_DIR}/Authentik/data/templates"; do
      [[ -n "${dir}" && -d "${dir}" ]] || continue
      if [[ "$(stat -c %u "${dir}" 2>/dev/null || echo "${expected}")" -ne "${expected}" ]]; then
        warn "${dir#"${ROOT_DIR}/"} is not owned by uid ${expected}, which is what FileBrowser runs as"
        info 'fix it with:  sudo ./scripts/setup-testing.sh --ownership'
      fi
    done
  fi
  ok "created ${created} missing mount point(s)"
}

set_compose_env() {
  # Local testing: no ACME (no DNS), loopback publishing, no OIDC yet (Phase 4).
  export TRAEFIK_CERT_RESOLVER="${TRAEFIK_CERT_RESOLVER:-}"
  export WORKCENTER_HOST="${WORKCENTER_HOST:-workcenter.local}"
  export FILEBROWSER_HOST="${FILEBROWSER_HOST:-filebrowser.workcenter.local}"
  export CHAT_HOST="${CHAT_HOST:-chat.workcenter.local}"
  export MAIL_HOST="${MAIL_HOST:-mail.workcenter.local}"
  export OFFICE_HOST="${OFFICE_HOST:-office.workcenter.local}"
  # The identity host and the dashboard host. Both are part of the deployment's
  # seven names (production.md §5.4); the dashboard's is also the one the
  # forward-auth router is built on, so it has to exist as a variable here rather
  # than stay at the `traefik.example.com` the committed dynamic configuration
  # carries.
  export AUTHENTIK_HOST="${AUTHENTIK_HOST:-auth.workcenter.local}"
  export TRAEFIK_HOST="${TRAEFIK_HOST:-traefik.workcenter.local}"
  export BASE_URL="${BASE_URL:-https://${WORKCENTER_HOST}}"
  export AUTHENTIK_URL="${AUTHENTIK_URL:-https://${AUTHENTIK_HOST}}"
  # The base domain the applications derive their own hostnames from. In this
  # profile the shell answers on the base domain itself, so it is the shell's
  # hostname; Mailcow reads it from its own `.env` to build its Traefik rule and
  # its `frame-ancestors` allow-list.
  export BASE_DOMAIN="${BASE_DOMAIN:-${WORKCENTER_HOST}}"
  # Mailcow's configurator asks for a timezone, and one of its four prompts. The
  # host's own is the right answer; `UTC` is what is left when it cannot be read.
  if [[ -z "${MAILCOW_TZ:-}" ]]; then
    if [[ -r /etc/timezone ]]; then
      MAILCOW_TZ="$(head -1 /etc/timezone)"
    elif [[ -L /etc/localtime ]]; then
      MAILCOW_TZ="$(readlink /etc/localtime | sed -n 's|.*zoneinfo/||p')"
    fi
    export MAILCOW_TZ="${MAILCOW_TZ:-UTC}"
  fi
  # The built-in `akadmin` account, read by Authentik on its very first boot and
  # never again (I-AK-2). A known password is what lets the run prove the admin
  # dashboard is reachable; blank would have Authentik generate one and print it
  # once, which the harness cannot read back.
  export AUTHENTIK_BOOTSTRAP_EMAIL="${AUTHENTIK_BOOTSTRAP_EMAIL:-akadmin@${WORKCENTER_HOST}}"
  export AUTHENTIK_BOOTSTRAP_PASSWORD="${AUTHENTIK_BOOTSTRAP_PASSWORD:-TestAkadmin123!}"
  # One setting is not a hostname of its own but must agree with the ones above,
  # or Zulip answers on an address no router matches: SETTING_EXTERNAL_HOST is what
  # Zulip believes its own address is — its nginx `server_name`, the host in the
  # links it renders, and the host its Traefik router rule matches
  # (Zulip/compose.yaml). production.md §5.4 keeps it equal to CHAT_HOST in a
  # deployment, so the test profile keeps them equal too; otherwise Zulip answers
  # on the example.com name its generated .env was copied from, and chat.<test
  # domain> gets Traefik's no-router 404.
  #
  # The origin allowed to frame the Chat pane is not an environment variable: it is
  # the `frame-ancestors` value in Traefik/dynamic/middlewares.yml, which
  # `ensure_shell_config` writes for the run from BASE_URL (IN-5.8, §8.4).
  export SETTING_EXTERNAL_HOST="${SETTING_EXTERNAL_HOST:-${CHAT_HOST}}"
  # A known Files admin login for the test run. FileBrowser Quantum's built-in
  # admin username is always `admin`; `FILEBROWSER_ADMIN_PASSWORD` is the only
  # admin setting it reads from the environment (IN-3.26). `admin` is five
  # characters, which is exactly its own `auth.methods.password.minLength`, so it
  # is accepted; an empty value would leave the pinned version's default, which is
  # also `admin`, and the deterministic value is what lets the harness print the
  # login and assert it before the manual walk (IN-3.26).
  export FILEBROWSER_ADMIN_PASSWORD="${FILEBROWSER_ADMIN_PASSWORD:-admin}"
  # The Chat admin login for the test run (IN-5.31). Zulip authenticates by
  # **email**, so the account is `admin@<shell host>` rather than `admin`, and it
  # enforces its own password policy — PASSWORD_MIN_LENGTH is 8 with a zxcvbn
  # guess floor (zproject/default_settings.py), so `admin` is refused with
  # PasswordTooWeakError however it is set. `admin1234` is the shortest obvious
  # extension of `admin` that passes. `ensure_zulip_admin` creates the account
  # with Zulip's own management commands; `print_test_accounts` prints it.
  export ZULIP_ADMIN_EMAIL="${ZULIP_ADMIN_EMAIL:-admin@${WORKCENTER_HOST}}"
  export ZULIP_ADMIN_PASSWORD="${ZULIP_ADMIN_PASSWORD:-admin1234}"
  # Mailcow's **admin page** password. Not an OIDC credential: that page
  # authenticates against Mailcow's own `admin` table, which is separate from
  # mailboxes by design, and Mailcow generates it a password nobody knows.
  export MAILCOW_ADMIN_PASSWORD="${MAILCOW_ADMIN_PASSWORD:-admin1234}"
  export MAILCOW_ADMIN_USER="${MAILCOW_ADMIN_USER:-admin}"
  # The group model (OIDC.md §3, O-3.1). The applications read these from the root
  # `.env`; the harness needs them too, because the identities it creates and the
  # bindings it checks are keyed on them.
  export WORKCENTER_USER_GROUP="${WORKCENTER_USER_GROUP:-workspaceusers}"
  export WORKCENTER_ADMIN_GROUP="${WORKCENTER_ADMIN_GROUP:-workspaceadmin}"

  # --- the identities Phase 4 signs in with --------------------------------
  # Testing.md §7.1 fixes three accounts and what each one is for: an admin in
  # both groups, a plain member of `workspaceusers`, and somebody in no group at
  # all. The third is what makes the negative checks meaningful — without it,
  # "the dashboard is protected" is only ever tested against accounts that are
  # *supposed* to get in.
  #
  # The password policy is Authentik's own default, which requires ten characters
  # and refuses the account name; these satisfy it and are deliberately obvious,
  # because they are printed with the rest of the run's credentials.
  export AUTHENTIK_TEST_ADMIN_EMAIL="${AUTHENTIK_TEST_ADMIN_EMAIL:-admin@wc.test}"
  export AUTHENTIK_TEST_ADMIN_PASSWORD="${AUTHENTIK_TEST_ADMIN_PASSWORD:-TestAdmin123!}"
  export AUTHENTIK_TEST_USER_EMAIL="${AUTHENTIK_TEST_USER_EMAIL:-user@wc.test}"
  export AUTHENTIK_TEST_USER_PASSWORD="${AUTHENTIK_TEST_USER_PASSWORD:-TestUser123!}"
  export AUTHENTIK_TEST_OUTSIDER_EMAIL="${AUTHENTIK_TEST_OUTSIDER_EMAIL:-outsider@wc.test}"
  export AUTHENTIK_TEST_OUTSIDER_PASSWORD="${AUTHENTIK_TEST_OUTSIDER_PASSWORD:-TestOutsider123!}"
}

# ---------------------------------------------------------------------------
# Let a container read a file this script generated
#
# A file secret is a *bind mount* under Compose, not a Swarm object: the file
# arrives inside the container with the host's ownership and mode, and the long
# syntax's `uid`, `gid` and `mode` keys are ignored. `docker compose` says so
# itself, on every `up`:
#
#     secrets `uid`, `gid` and `mode` are not supported, they will be ignored
#
# So a 0600 file owned by root is unreadable to any container that does not run
# as root — and two of this deployment's containers read one of these files:
#
#   * Zulip's memcached is `USER memcache` (uid 11211, from the image's own
#     `adduser -D -u 11211 -G memcache memcache`). It builds its SASL database
#     from zulip__memcached_password before it execs memcached, so an unreadable
#     secret is not a degraded cache: it is a container that exits 1 with
#     "the password secret ... is not readable by uid 11211", which the health
#     gate then reports as `container workcenter-memcached-1 is unhealthy`.
#   * Workcenter's broker is `USER node` (uid 1000) and mounts zuliprc as its
#     bot credentials (compose.yaml, IN-5.17).
#
# Hand each file to the uid that reads it and keep the mode at 0600: the owner
# is the consumer, not the world, which is the point of 0600 in the first place.
# Only root can hand a file to another uid; a harness that is not root leaves it
# readable and says so — the same trade-off mount_points() makes for the
# directories the containers write into.
#
# setup.sh (Phase 8) has the same obligation for a real deployment; the reason
# is written up in production.md §5.2.
# ---------------------------------------------------------------------------
# The image `remove_generated_tree` runs its cleanup in. It is the PostgreSQL image
# `Authentik/compose.yaml` deploys, so it is present after any run and a cleanup
# never downloads anything. It only has to be an image with a shell and `rm`.
readonly RUNTIME_STATE_IMAGE="docker.io/library/postgres:16-alpine"

# Remove a directory that a *container* owns.
#
# Bind mounts make a container's writes the container's uid on the host, so the
# person running this cannot delete them — Authentik's PostgreSQL data directory is
# uid 65534 mode 0700. Needing root for that would make `--down` a privileged
# operation, which this harness refuses to be, and would leave every user who is
# not root with a checkout they cannot reset.
#
# Docker can do it with no host privilege at all: a throwaway container runs as
# root **in its own namespace**, and the bind mount hands it the same inodes. The
# direct attempt comes first because it is instant when the user does own the tree,
# which is the common case for everything the harness itself wrote.
remove_generated_tree() {
  local path="$1" rel
  rel="${path#"${ROOT_DIR}/"}"
  rm -rf "${path}" 2>/dev/null || true
  [[ -e "${path}" ]] || return 0
  command -v docker >/dev/null 2>&1 || return 1
  docker image inspect "${RUNTIME_STATE_IMAGE}" >/dev/null 2>&1 || return 1
  docker run --rm --entrypoint sh -v "${ROOT_DIR}:/workcenter" \
    "${RUNTIME_STATE_IMAGE}" -c "rm -rf '/workcenter/${rel}'" >/dev/null 2>&1 || true
  [[ ! -e "${path}" ]]
}

own_for_container() {
  local path="$1" uid="$2" why="$3"
  [[ -f "${path}" ]] || return 0
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would make %s readable by uid %s (read by %s)\n' "${path#"${ROOT_DIR}/"}" "${uid}" "${why}"
    return 0
  fi
  # A Docker secret is a bind mount, so the container reads the *host* file as its
  # own uid. Handing the file to that uid is a `chown`, which needs root and would
  # also leave the file owned by a uid the person running this cannot rewrite — so
  # the harness widens the mode instead and keeps ownership where it belongs.
  #
  # These are secrets generated per run for a stack bound to the loopback
  # interface, and the alternative is a privileged operation inside a test run.
  # `scripts/setup-testing.sh --ownership` is there for anyone who would rather
  # have the narrower mode and the host-side uid.
  if [[ "$(stat -c %u "${path}")" -eq "${uid}" ]]; then
    chmod 600 "${path}"
  else
    chmod 644 "${path}"
  fi
}

# ---------------------------------------------------------------------------
# Zulip's secrets
#
# docker-zulip takes its six secrets as files, and Zulip/compose.yaml mounts each
# one as a Docker secret. Only the *.example templates are committed, so a fresh
# checkout has no `zulip__postgres_password` — and Docker refuses the whole stack
# with "bind source path does not exist", after every image has been built and
# every other container created.
#
# A test run therefore generates them, exactly as it generates .env and the local
# certificate: random, mode 600, recorded in the manifest so --down removes what
# the run created and nothing else. setup.sh (Phase 8) generates the same files
# from the same templates for a real deployment.
# ---------------------------------------------------------------------------
ensure_zulip_secrets() {
  step 'Zulip secrets'
  local dir="${ROOT_DIR}/Zulip/secrets"
  if [[ ! -d "${dir}" ]]; then
    info 'Zulip/secrets is absent: nothing to generate'
    return 0
  fi
  local example target created=0
  for example in "${dir}"/*.example; do
    [[ -e "${example}" ]] || continue
    target="${example%.example}"
    if [[ -f "${target}" ]]; then
      # An earlier run of this script (or a hand-written file) may carry the
      # trailing newline upstream rejects. Strip it rather than regenerate: the
      # value may already be in use by a running database.
      if [[ "$(basename "${target}")" != "zuliprc" && "$(tail -c 1 "${target}" | wc -l)" -eq 1 ]]; then
        if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
          printf '   would strip the trailing newline from: %s\n' "${target#"${ROOT_DIR}/"}"
        else
          printf '%s' "$(cat "${target}")" >"${target}"
          chmod 600 "${target}"
          SECRETS_CHANGED=1
          warn "$(basename "${target}") ended in a newline, which Zulip rejects: stripped it"
        fi
      else
        info "$(basename "${target}") exists: leaving it alone"
      fi
      continue
    fi
    if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
      printf '   would generate: %s\n' "${target#"${ROOT_DIR}/"}"
      continue
    fi
    case "$(basename "${target}")" in
      zuliprc)
        # Not a secret this script can invent: it is the broker's bot credentials,
        # issued by Zulip itself (IN-5.17, Phase 5). The template is copied so the
        # broker's read-only mount is a file rather than the directory Docker
        # would otherwise create, and so the placeholders are obvious.
        cp "${example}" "${target}"
        ;;
      *)
        # Hex, not base64: these values travel into postgres, redis, rabbitmq and
        # memcached configuration, and a stray +, / or = is one quoting bug away
        # from a service that starts and cannot authenticate.
        # No trailing newline, on purpose: the docker-zulip entrypoint rejects a
        # secret whose file contains one (Zulip/compose.yaml, "The files must
        # contain a single line with **no trailing newline**"). `printf` writes
        # exactly the value and nothing else.
        if command -v openssl >/dev/null 2>&1; then
          printf '%s' "$(openssl rand -hex 32)" >"${target}"
        else
          head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' >"${target}"
        fi
        ;;
    esac
    chmod 600 "${target}"
    record_created "${target}"
    SECRETS_CHANGED=1
    created=$((created + 1))
  done
  ok "generated ${created} Zulip secret file(s)"

  # Two of these files are read by a container that is not root, and Compose
  # mounts them with the host's ownership (see own_for_container above). Both
  # calls also run when the file already existed, so a secrets directory left
  # behind by an earlier run is repaired rather than trusted.
  own_for_container "${dir}/zulip__memcached_password" 11211 'the memcached image (uid 11211)'
  own_for_container "${dir}/zuliprc" 1000 'the Workcenter image (uid 1000)'
}

# Every file the composed stack mounts as a secret must exist before `up` runs.
# Docker's own failure for a missing one arrives after the images are built, names
# a single file, and reads like a daemon fault; this check names all of them and
# says where they come from.
# State that was initialised with the previous credentials cannot be fixed by
# recreating containers: postgres writes the role password at initdb, and
# rabbitmq stores its user in the message store. When a secret has just
# changed and that state exists, the only honest options are to start clean or
# to stop — a stack that boots into an authentication loop teaches nothing.
verify_credential_state() {
  [[ "${SECRETS_CHANGED}" -eq 1 ]] || return 0
  local stale=0 dir
  for dir in "${ROOT_DIR}/Zulip/database" "${ROOT_DIR}/Zulip/rabbitmq" "${ROOT_DIR}/Zulip/redis"; do
    [[ -e "${dir}" ]] || continue
    grep -qxF "${dir}" "${MANIFEST}" 2>/dev/null && continue   # created by this run
    # Existence is not the same as holding credentials: this script creates these
    # directories as mount points before anything runs in them, so one left empty by
    # a previous run — cleared by hand, or after a start that never got as far as
    # initialising — has no password to disagree with. Only a directory with content
    # can be in the state this guard is about.
    [[ -n "$(ls -A "${dir}" 2>/dev/null)" ]] || continue
    warn "credential-bearing state from an earlier run: ${dir#"${ROOT_DIR}/"}"
    stale=$((stale + 1))
  done
  if [[ "${stale}" -gt 0 ]]; then
    fail 'a Zulip secret changed, and that state still holds the previous credentials'
    fail "  postgres would reject Zulip's connection and rabbitmq would reject its user,"
    fail '  so the stack would come up in a restart loop rather than in a working state'
    fail ''
    fail '  Start clean, then re-run:'
    fail '      ./scripts/e2e.sh --down      # removes the generated secrets and this state'
    fail '      ./scripts/e2e.sh             # regenerates both, consistently'
    exit 1
  fi
  ok 'the credentials and the existing state agree'
}

verify_secret_files() {
  local model missing=0 path
  model="$(compose_model)"
  if [[ -z "${model}" ]]; then
    warn 'could not read the composed model; skipping the secret file check'
    return 0
  fi
  while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    if [[ ! -e "${path}" ]]; then
      fail "a secret file the stack mounts does not exist: ${path}"
      missing=$((missing + 1))
    fi
  done < <(printf '%s\n' "${model}" | awk '
    /^[a-z]/ { in_secrets = ($0 == "secrets:") ; next }
    in_secrets && /file:/ { line = $0; sub(/^[[:space:]]*file:[[:space:]]*/, "", line); print line }
  ')
  if [[ "${missing}" -gt 0 ]]; then
    fail "${missing} secret file(s) missing: generate them from the *.example templates in the application folder"
    exit 1
  fi
  ok 'every secret file the stack mounts exists'
}

# ---------------------------------------------------------------------------
# Images
#
# `docker image inspect` first: a pull is only correct when the tag is absent, and
# a repeat run on a host that has them must work without a network.
# ---------------------------------------------------------------------------
compose_config() {
  run docker compose \
    -f "${ROOT_DIR}/compose.yaml" \
    -f "${COMPOSE_TEST_FILE}" \
    --project-name "${COMPOSE_PROJECT}" \
    config "$@"
}

# The composed model, as rendered YAML, for the questions only it can answer.
compose_model() {
  docker compose \
    -f "${ROOT_DIR}/compose.yaml" \
    -f "${COMPOSE_TEST_FILE}" \
    --project-name "${COMPOSE_PROJECT}" \
    config 2>/dev/null || true
}

# Images the composition builds locally, one per line.
#
# A name heuristic cannot answer this — a local tag looks exactly like a registry
# tag, and asking Docker to pull one that nothing publishes fails with "pull access
# denied ... repository does not exist", which is where a run once stopped. The
# rendered configuration says which services carry a `build:` key, so that is what
# decides. Zulip is not among them: it runs the pinned upstream image unmodified.
built_images() {
  compose_model | awk '
    function emit() { if (image != "" && built) print image }
    /^  [A-Za-z0-9_.-]+:$/ { emit(); service = $1; sub(/:$/, "", service); image = ""; built = 0; next }
    /^    image:/ { image = $0; sub(/^    image:[[:space:]]*/, "", image) }
    /^    build:/ { built = 1 }
    END { emit() }
  '
}

# Images that come from a registry, one per line. Locally built images are
# removed here rather than recognised later.
pullable_images() {
  compose_model | awk '
    function emit() { if (image != "" && !built) print image }
    /^  [A-Za-z0-9_.-]+:$/ { emit(); service = $1; sub(/:$/, "", service); image = ""; built = 0; next }
    /^    image:/ { image = $0; sub(/^    image:[[:space:]]*/, "", image) }
    /^    build:/ { built = 1 }
    END { emit() }
  ' | sort -u
}

ensure_images() {
  step 'Application images'
  local image built
  # Say what is built here before anything is pulled: a locally built tag has no
  # registry behind it, and a "pull access denied" is the failure this prevents.
  built="$(built_images)"
  if [[ -n "${built}" ]]; then
    while IFS= read -r image; do
      [[ -n "${image}" ]] || continue
      info "built locally, not pulled: ${image}"
    done <<<"${built}"
  fi

  local images
  images="$(pullable_images)"
  if [[ -z "${images}" ]]; then
    warn 'could not read the image list from the compose files; skipping the pull step'
    return 0
  fi
  while IFS= read -r image; do
    [[ -n "${image}" ]] || continue
    if docker image inspect "${image}" >/dev/null 2>&1; then
      info "present: ${image}"
      continue
    fi
    if [[ "${DO_PULL}" -eq 0 ]]; then
      fail "image missing and --no-pull was given: ${image}"
      exit 1
    fi
    info "pulling ${image} (not present)"
    if ! run docker pull "${image}" >>"${LOG_DIR}/pull.log" 2>&1; then
      if network_failure_in "${LOG_DIR}/pull.log"; then
        warn "the pull failed while resolving or connecting; retrying ${image} once"
        if ! run docker pull "${image}" >>"${LOG_DIR}/pull.log" 2>&1; then
          fail "could not pull ${image}"
          network_failure_hint
          tail -n 20 "${LOG_DIR}/pull.log" >&2 || true
          exit 1
        fi
      else
        fail "could not pull ${image}"
        tail -n 20 "${LOG_DIR}/pull.log" >&2 || true
        exit 1
      fi
    fi
    ok "pulled ${image}"
  done <<<"${images}"
}

# A build or a pull can fail for reasons that have nothing to do with the code:
# a resolver that dropped a lookup, a mirror that refused a connection, a TLS
# handshake that timed out. The log says which, and the difference matters — one
# is worth retrying, the other is not.
network_failure_in() {
  grep -qiE 'DNS: transient error|temporary failure in name resolution|no such host|i/o timeout|TLS handshake timeout|connection reset by peer|unable to select packages|failed to resolve|dial tcp.*connect' "$1" 2>/dev/null
}

network_failure_hint() {
  warn 'this is a network or DNS failure while fetching packages or layers, not a build error:'
  warn '  the image installs Alpine packages from dl-cdn.alpinelinux.org, so an unreachable'
  warn '  resolver or mirror fails the build before any Workcenter code is compiled'
  warn '  check that this host resolves and reaches the mirror, then re-run'
}

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
build_image() {
  if [[ "${DO_BUILD}" -eq 0 ]]; then
    info 'skipping the build (--no-build)'
    docker image inspect "${WORKCENTER_IMAGE:-workcenter:dev}" >/dev/null 2>&1 \
      || warn 'the image is not present and --no-build was given: the stack will fail to start'
    return 0
  fi
  step 'Workcenter image'
  local image="${WORKCENTER_IMAGE:-workcenter:dev}"
  local revision created start size
  revision="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  created="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  info "building ${image} (revision ${revision})"
  info "build log: ${LOG_DIR}/build.log"

  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would run: docker build -t %s --build-arg REVISION=%s --file Dockerfile .\n' "${image}" "${revision}"
    return 0
  fi

  start="$(date +%s)"
  local attempt=1
  while true; do
    if docker build \
        --tag "${image}" \
        --build-arg "VERSION=${WORKCENTER_VERSION:-dev}" \
        --build-arg "REVISION=${revision}" \
        --build-arg "CREATED=${created}" \
        --file "${ROOT_DIR}/Dockerfile" \
        "${ROOT_DIR}" >"${LOG_DIR}/build.log" 2>&1; then
      break
    fi
    if [[ "${attempt}" -lt 2 ]] && network_failure_in "${LOG_DIR}/build.log"; then
      warn "the build failed while fetching packages; retrying once (attempt ${attempt})"
      attempt=$((attempt + 1))
      sleep 5
      continue
    fi
    fail 'the image build failed'
    network_failure_in "${LOG_DIR}/build.log" && network_failure_hint
    fail "  full log: ${LOG_DIR}/build.log"
    printf '\n  last 25 lines:\n' >&2
    tail -n 25 "${LOG_DIR}/build.log" >&2 || true
    exit 1
  done
  # A zero exit is not proof: assert the tag exists.
  if ! docker image inspect "${image}" >/dev/null 2>&1; then
    fail "the build reported success but ${image} is not present"
    exit 1
  fi
  size="$(docker image inspect "${image}" --format '{{.Size}}' | awk '{printf "%.0f MiB", $1/1048576}')"
  ok "built ${image} in $(( $(date +%s) - start ))s (${size})"
}

# ---------------------------------------------------------------------------
# The pinned Zulip release, across the committed documents
#
# The pin appears in two shapes, and each has to be rewritten deliberately:
#
#   1. image tags            ghcr.io/zulip/zulip-server:12.3-0
#   2. the docker-zulip tag  the upstream compose.yaml URL blob/12.3-0/
#
# A blunt search-and-replace on "12.2" would be wrong: `T-12.2` in Testing.md and
# `### 12.2 Rules` in contributions.md are section numbers, not versions. Every
# pattern below is therefore anchored to a version context, and each file that
# changes is reported.
#
# Nothing here re-verifies the *claims* those documents make about the release —
# it cannot. It rewrites the pin and says so, because a version claim is only as
# good as the release it was read at (integration.md IN-3.25 is the precedent).
# ---------------------------------------------------------------------------
zulip_pin_files() {
  # Only the files that deploy Zulip. The Markdown specification set is
  # deliberately absent: it is the historical record, and it names the release the
  # application was built against when those documents were written. Rewriting a
  # version claim in prose would also falsify the "verified at release X" notes
  # that sit beside it, which is a review decision, not a script's.
  #
  # These three are the pin: the tag the deployment pulls, the value it is declared
  # in, and the composition's own comment that names it for an operator reading
  # Zulip/compose.yaml. There is no derived tag and no Dockerfile to keep in step.
  printf '%s\n' \
    "${ROOT_DIR}/Zulip/.env.example" \
    "${ROOT_DIR}/Zulip/compose.yaml" \
    "${ROOT_DIR}/.env.example"
}

update_zulip_pin() {
  local version="$1" commit="${2:-}"
  local tag="${version}-0" file changed=0
  step "Zulip pin -> ${tag}"
  for file in $(zulip_pin_files); do
    [[ -f "${file}" ]] || continue
    [[ -w "${file}" ]] || { warn "cannot write ${file}"; continue; }
    local before after
    before="$(cat "${file}")"
    # 1. The image tag, upstream and in the Workcenter documentation that quotes
    #    it, plus the recorded upstream commit and the bold prose that names the
    #    release ("**Zulip 12.3**"). Un-bolded version claims — "on Zulip 12.3
    #    `zulip_groups` is not synchronised", "12.2 added a check" — are
    #    release-specific statements, not pins, and are deliberately left: like the
    #    Markdown, they need a review rather than a rewrite.
    sed -i \
      -e "s|zulip-server:[0-9][0-9.]*-0|zulip-server:${tag}|g" \
      -e "s|docker-zulip/blob/[0-9][0-9.]*-0/|docker-zulip/blob/${tag}/|g" \
      -e "s|^\(#* *ZULIP_UPSTREAM_COMMIT=\).*|\1${commit}|" \
      -e "s|pins at [0-9][0-9.]*-0|pins at ${tag}|g" \
      -e "s|pinned at [0-9][0-9.]*-0|pinned at ${tag}|g" \
      -e "s|\*\*Zulip [0-9][0-9.]*\*\*|**Zulip ${version}**|g" \
      "${file}"
    after="$(cat "${file}")"
    if [[ "${before}" != "${after}" ]]; then
      changed=$((changed + 1))
      local differ
      differ="$(diff <(printf '%s' "${before}") <(printf '%s' "${after}") | grep -c '^[<>]' || true)"
      ok "${file#"${ROOT_DIR}/"}: ${differ} line(s)"
    fi
  done
  if [[ "${changed}" -eq 0 ]]; then
    info "nothing to change: the deployment files already carry the ${tag} pin"
  else
    ok "${changed} deployment file(s) now pin ${tag}"
  fi
  if [[ -z "${commit}" ]]; then
    warn 'no release commit was given: the tracked commit is left as it was'
    warn '  pass --zulip-commit <sha> so the fork can follow the exact revision'
  fi
  info 'the Markdown specification set was not touched: it records the release the'
  info 'application was built against, and a version claim in prose needs a review,'
  info 'not a rewrite (see the note in Readme.md)'
}

# ---------------------------------------------------------------------------
# The pinned Zulip release
#
# Zulip runs the upstream image **unmodified**: there is no derived tag, no build
# and no overlay file. What makes the Chat pane embeddable is applied by Traefik on
# the `zulip` router (integration.md §8.4, IN-5.8), so the only thing this script
# has to know about Zulip is which tag is pinned — and whether a newer release
# exists, because the pin is the one file a later release moves.
# ---------------------------------------------------------------------------
zulip_pinned_tag() {
  local pin="" file
  for file in "${ROOT_DIR}/Zulip/.env" "${ROOT_DIR}/Zulip/.env.example"; do
    [[ -f "${file}" ]] || continue
    pin="$(sed -n 's/^ZULIP_IMAGE=//p' "${file}" | head -1)"
    [[ -n "${pin}" ]] && break
  done
  printf '%s' "${pin}"
}

# The organization Workcenter deploys in Zulip (IN-5.30). Empty is a valid choice:
# it means "deploy no organization", and the Chat pane then says so. The generated
# `Zulip/.env` wins even when it is the one that is empty.
zulip_organization_name() {
  local name="" file
  for file in "${ROOT_DIR}/Zulip/.env" "${ROOT_DIR}/Zulip/.env.example"; do
    [[ -f "${file}" ]] || continue
    name="$(sed -n 's/^ZULIP_ORGANIZATION_NAME=//p' "${file}" | head -1)"
    break
  done
  printf '%s' "${name}"
}

latest_zulip_release() {
  # The latest server release, from GitHub. One unauthenticated request is
  # enough; GITHUB_TOKEN is used when the operator has one, because the hourly
  # rate limit is per address and a shared host can exhaust it.
  #
  # Every failure mode here is expected, not exceptional: no network, a rate
  # limit, a captive portal returning HTML. The function therefore returns the
  # empty string rather than a non-zero status — with `pipefail` a failing curl
  # would otherwise abort the whole run through the ERR trap, when the caller's
  # documented behaviour is to fall back to the pin and say so.
  local url="https://api.github.com/repos/zulip/zulip/releases/latest"
  local out=""
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    out="$(curl -sS --max-time 20 -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H 'Accept: application/vnd.github+json' "${url}" 2>/dev/null \
      | tr ',' '\n' | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | sed 's/^v//' || true)"
  else
    out="$(curl -sS --max-time 20 -H 'Accept: application/vnd.github+json' "${url}" 2>/dev/null \
      | tr ',' '\n' | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | sed 's/^v//' || true)"
  fi
  printf '%s' "${out}"
  return 0
}

# The pinned release, and whether a newer one exists. Zulip is not built, so this
# is the whole of the Zulip stage: report the tag Workcenter is built against, and
# move it — in the generated files only — when the operator has not asked to keep
# it. `ensure_images` then pulls whatever tag the run ends up using.
report_zulip_release() {
  step 'The Zulip release'
  local pinned version file
  pinned="$(zulip_pinned_tag)"
  if [[ -z "${pinned}" ]]; then
    fail 'ZULIP_IMAGE is not set in Zulip/.env or Zulip/.env.example'
    exit 1
  fi
  info "pinned upstream: ${pinned}"
  if [[ "${DO_PULL}" -eq 0 ]]; then
    info 'skipping the release check (--no-pull)'
    return 0
  fi
  version="$(latest_zulip_release)"
  if [[ -z "${version}" ]]; then
    warn 'could not read the latest Zulip release from GitHub; keeping the pinned one'
    return 0
  fi
  if [[ "${pinned}" == *":${version}-0" || "${pinned}" == *":${version}" ]]; then
    ok "the pin is the latest Zulip release (${version})"
    return 0
  fi
  warn "a newer Zulip release exists: ${version} (pinned: ${pinned##*:})"
  if [[ "${DO_PIN}" -eq 1 ]]; then
    info 'keeping the pin (--pin)'
    return 0
  fi
  # Move the pin in the generated files only: the committed example and the
  # documents keep the reviewed pin, and setup.sh (Phase 8) is what changes those.
  for file in "${ROOT_DIR}/Zulip/.env" "${ROOT_DIR}/.env"; do
    [[ -f "${file}" ]] || continue
    sed -i "s|^ZULIP_IMAGE=.*|ZULIP_IMAGE=ghcr.io/zulip/zulip-server:${version}-0|" "${file}"
  done
  export ZULIP_IMAGE="ghcr.io/zulip/zulip-server:${version}-0"
  ok "adopting ${version}; the pin moved in the generated .env files"
  warn 'the committed documents still carry the old pin: run ./scripts/e2e.sh --bump-zulip-pin to move them'
}

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------
compose() {
  run docker compose \
    -f "${ROOT_DIR}/compose.yaml" \
    -f "${COMPOSE_TEST_FILE}" \
    --project-name "${COMPOSE_PROJECT}" \
    "$@"
}

# The address Traefik presents to the `proxy` network. That is the address
# Zulip's nginx sees for every request that arrives through the ingress, and
# therefore the value LOADBALANCER_IPS has to contain (Zulip/.env.example). It is
# read from Docker rather than configured because Docker assigns it when the
# network is created; both the network and the container name are fixed by the
# composition (`proxy` in Traefik/compose.yaml, `container_name: traefik`).
traefik_proxy_address() {
  docker network inspect proxy \
    --format '{{range .Containers}}{{if eq .Name "traefik"}}{{.IPv4Address}}{{end}}{{end}}' \
    2>/dev/null | cut -d/ -f1
}

# `curl` and not `docker inspect`: the container's healthcheck says the *process* is
# well, and what the provisioning needs is that the API answers on the hostname the
# applications and browsers will use — which also proves Traefik's route to it
# exists, the thing FileBrowser's startup discovery depends on (IN-3.6).
wait_for_authentik() {
  step 'Identity provider readiness'
  local deadline=$(( $(date +%s) + AUTHENTIK_READY_TIMEOUT ))
  local code
  while (( $(date +%s) < deadline )); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --insecure \
      --resolve "${AUTHENTIK_HOST}:443:127.0.0.1" \
      "${AUTHENTIK_URL}/-/health/ready/" 2>/dev/null || true)"
    if [[ "${code}" == '200' || "${code}" == '204' ]]; then
      ok "Authentik answers on ${AUTHENTIK_URL}"
      return 0
    fi
    sleep 5
  done
  fail "Authentik did not answer ${AUTHENTIK_URL}/-/health/ready/ within ${AUTHENTIK_READY_TIMEOUT}s (last: ${code:-no response})"
  return 1
}

stack_up() {
  step 'Deploying the stack'
  info 'Traefik is the only ingress; every published port is bound to 127.0.0.1'
  # `up -d`, not `up --wait`: Compose aborts on the first unhealthy report, which
  # for a cold deployment is Zulip still running its first-boot migrations. The
  # health budget is the operator's (--wait), and wait_healthy below applies it
  # while reporting progress.
  DEPLOY_ACTIVE=1

  # Zulip trusts a reverse proxy **by address** (Zulip/.env.example,
  # integration.md IN-5.14): its nginx uses LOADBALANCER_IPS as the
  # `set_real_ip_from` list, and Django answers HTTP 500 "Reverse proxy
  # misconfiguration" to any request from an address that is not in it. The
  # address Traefik presents on `proxy` is assigned by Docker when the network is
  # created, so it cannot be written into an .env file in advance: bring the proxy
  # up on its own, read the address, and only then let Zulip start.
  compose up -d traefik 2>&1 | tee -a "${LOG_DIR}/up.log"
  local proxy_address
  proxy_address="$(traefik_proxy_address)"
  if [[ -n "${proxy_address}" ]]; then
    export LOADBALANCER_IPS="127.0.0.1,${proxy_address}"
    info "Zulip will trust the reverse proxy at ${proxy_address}"
  else
    warn 'could not read the address Traefik presents on `proxy`: Zulip will trust 127.0.0.1 only'
  fi

  # The identity provider comes up next, and on its own, because everything else
  # authenticates against it. IN-3.6 is explicit that FileBrowser's provider
  # discovery runs **at startup** and that a failure there stops the container —
  # and on a fresh instance the provider does not exist until it has been
  # provisioned, which happens just below. Bringing the whole stack up at once
  # therefore deadlocks: FileBrowser crash-loops on a 404 for an application nobody
  # has created yet, the health wait never passes, and the provisioning that would
  # fix it never runs.
  #
  # Authentik's own healthcheck is the gate: `ak healthcheck` answers only once the
  # migrations have finished and the worker is up, which on a cold database is
  # minutes.
  info 'bringing up the identity provider first: everything else authenticates against it'
  compose up -d authentik-postgresql authentik-server authentik-worker \
    2>&1 | tee -a "${LOG_DIR}/up.log"
  DEPLOY_ACTIVE=0
  if ! wait_for_authentik; then
    fail 'the identity provider did not become ready'
    DEPLOY_ACTIVE=1
    collect_unhealthy_evidence
    return 1
  fi
  if ! ensure_authentik_identity; then
    fail 'the identity provider could not be configured'
    DEPLOY_ACTIVE=1
    return 1
  fi
  DEPLOY_ACTIVE=1

  # ---------------------------------------------------------------------------
  # The application stack.
  #
  # A section of its own, because it *is* one: the identity provider is up and
  # configured by this point, and everything below is the applications coming up
  # behind it.
  # ---------------------------------------------------------------------------
  step 'Bringing up the application stack'
  info 'Traefik and Authentik are up and configured: starting Workcenter, Files, Chat and Office'

  compose up -d 2>&1 | tee -a "${LOG_DIR}/up.log"

  # `--force-recreate` is for exactly one situation, and it is worth being precise
  # about which: `up -d` **already** recreates any service whose *configuration*
  # changed — image, environment, labels, mounts. What it cannot know about is a
  # mounted file whose **contents** changed underneath an identical configuration.
  # That is the secret case, and it is the only one this flag is for.
  #
  # So it is scoped to the services that read a per-run secret, and deliberately not
  # applied to the project. Applying it to everything used to recreate Traefik and
  # all three Authentik services as well — four containers that read no per-run
  # secret at all, whose own values are persistent and were written before they first
  # started. That cost a measured ten seconds, and worse: recreating Traefik changes
  # its address on `proxy`, which fired the re-point below and left Zulip started
  # **three times** in one run (created, force-recreated, re-pointed).
  #
  # The list is "services that read a per-run secret", not "Zulip's services",
  # because that is the property the flag is about. `workcenter` is on it for
  # `Zulip/secrets/zuliprc`: a bind-mounted *file* is resolved when the container is
  # created, so a regenerated secret is a new inode the running shell cannot see.
  if [[ "${SECRETS_CHANGED}" -eq 1 ]]; then
    info 'a secret changed this run: recreating only the services that read one'
    compose up -d --force-recreate zulip database memcached rabbitmq redis workcenter \
      2>&1 | tee -a "${LOG_DIR}/up.log"
  fi

  # Read the proxy address again, because a service recreated above may have moved
  # it. (It no longer can: Traefik is not in that list. The check stays because it
  # is cheap and because the invariant it guards — Zulip trusting the address
  # Traefik actually presents — is not one to leave to a comment.)
  local address_after
  address_after="$(traefik_proxy_address)"
  if [[ -n "${address_after}" && "${address_after}" != "${proxy_address}" ]]; then
    export LOADBALANCER_IPS="127.0.0.1,${address_after}"
    info "the proxy came back at ${address_after}: recreating Zulip so it trusts that address"
    compose up -d --force-recreate zulip 2>&1 | tee -a "${LOG_DIR}/up.log"
  fi
  ok 'the stack was created and started'
  if [[ "${WITH_MAILCOW}" -eq 1 ]]; then
    bring_up_mailcow
  else
    info 'skipping Mailcow (--no-mailcow): the Mail pane is not testable this run'
  fi
}

# A free loopback port, from `start` upwards.
#
# Mailcow publishes its own web ports and an override **cannot** unpublish them
# (IN-6.4: Docker concatenates `ports:` rather than replacing it), so a port that is
# already taken on this host fails the whole service — nginx, and with it the Mail
# pane — for a reason that has nothing to do with Mailcow. They are chosen here
# instead of assumed.
pick_free_port() {
  local port="$1" limit=$(( $1 + 400 ))
  while (( port < limit )); do
    if mailcow_port_usable "${port}"; then
      printf '%s' "${port}"
      return 0
    fi
    port=$(( port + 1 ))
  done
  return 1
}

# Is this port one Mailcow may publish?
#
# Three tests, and the first is the one that matters. **A port below 1024 is never
# acceptable**, whatever the socket says: the configurator's own defaults are 80 and
# 443, and this runs *before* Traefik exists, so at the moment of asking they are
# genuinely free — and taken a minute later. Only checking "is anything listening"
# therefore picks exactly the two ports the stack itself is about to bind, and the
# collision surfaces at `up` as `failed to bind host port`.
mailcow_port_usable() {
  local port="$1"
  [[ -n "${port}" ]] || return 1
  (( port >= 1024 && port <= 65535 )) || return 1
  (( port != TRAEFIK_HTTP_PORT && port != TRAEFIK_HTTPS_PORT )) || return 1
  ! (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null
}

# ---------------------------------------------------------------------------
# Mailcow's own configuration
#
# Mailcow is not configured by writing a file: it is configured by running **its
# own configurator**, which is what an operator does and what `setup.sh` will do for
# production. `generate_config.sh` writes `mailcow.conf` from an inline heredoc — it
# never reads `mailcow.conf.example`, which is documentation — prompts for four
# things, and refuses to run when a config already exists unless it may move it
# aside.
#
# So the harness does what an operator does, with the prompts answered from the
# environment: `MAILCOW_HOSTNAME`, `MAILCOW_TZ`, `SKIP_CLAMD` and `SKIP_BRANCH` are
# all read before the prompt is reached, and `--dev` stops it switching branches
# under a pinned checkout.
#
# Three things are then added that the configurator cannot know:
#
#   * **Workcenter's keys** — the ones `docker-compose.override.yml` interpolates.
#     A missing one is not a warning: `${MAIL_HOST}` inside a Traefik label
#     interpolates to the empty string, the rule becomes `Host()`, and Mailcow runs
#     perfectly with no route to it at all. `compose.yaml` warns about the same thing
#     from the other side.
#   * **Free loopback ports**, because Mailcow cannot be stopped from publishing its
#     own (IN-6.4) and a taken port fails the service for no functional reason.
#   * **`TRUSTED_PROXIES` / `API_ALLOW_FROM`**, so Mailcow believes the client
#     address Traefik forwards and lets the provisioning reach its API.
#
# The configurator is run when there is no configuration to keep. A `mailcow.conf`
# that already has a database behind it is **reused**: regenerating one would mint a
# new `DBPASS`, `DBROOT` and `REDISPASS` against a MySQL initialized with the old
# ones, which does not fail loudly — it fails as "Mailcow is up and every service is
# unhealthy". Everything a run overwrites is backed up, and `--down` puts it back.
ensure_mailcow_config() {
  step 'Mail configuration'
  if [[ "${WITH_MAILCOW}" -eq 0 ]]; then
    info 'skipping Mailcow (--no-mailcow)'
    return 0
  fi
  local dir="${ROOT_DIR}/Mailcow"
  if [[ ! -f "${dir}/docker-compose.yml" ]]; then
    warn 'Mailcow is not present in this checkout (Phase 8 runs its own setup)'
    warn 'the Mail pane will not be testable this run'
    return 0
  fi
  if [[ ! -f "${dir}/generate_config.sh" ]]; then
    warn 'Mailcow/generate_config.sh is missing: cannot configure it'
    return 0
  fi
  # `generate_config.sh` refuses to start without it, and upstream ships it as a
  # symlink. Restoring it is cheaper than explaining the error.
  [[ -L "${dir}/.env" || -f "${dir}/.env" ]] || ln -s mailcow.conf "${dir}/.env" 2>/dev/null || true

  local conf="${dir}/mailcow.conf"
  local generated=0
  if [[ ! -f "${conf}" ]]; then
    generated=1
  else
    # Reused, but this run is about to rewrite its ports and add Workcenter's keys,
    # so the previous contents are kept for `--down`. A test run has to leave the
    # checkout exactly as it found it; that is the whole promise of `--down`.
    record_backup "${conf}"
  fi

  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    if [[ "${generated}" -eq 1 ]]; then
      printf '   would run: Mailcow/generate_config.sh --dev (answered from the environment)\n'
    else
      printf '   would keep the existing Mailcow/mailcow.conf (only its ports and Workcenter keys are checked)\n'
    fi
    return 0
  fi

  if [[ "${generated}" -eq 1 ]]; then
    # `Mailcow/data/` is **not** recorded for removal. It looks like runtime state
    # and is not: the clone ships the configuration templates, the web tree and the
    # `ssl-example` assets under it, and `generate_config.sh` writes into all three.
    # A run that deleted it would leave a Mailcow that cannot be configured again.
    local existed=0
    [[ -f "${conf}" ]] && existed=1
    ( cd "${dir}" && MAILCOW_HOSTNAME="${MAIL_HOST}" MAILCOW_TZ="${MAILCOW_TZ:-UTC}" \
        SKIP_CLAMD=y SKIP_BRANCH=y MAILCOW_BRANCH=master SKIP_LETS_ENCRYPT=y \
        ./generate_config.sh --dev ) >"${LOG_DIR}/mailcow-config.log" 2>&1 </dev/null || {
      warn "Mailcow's configurator failed; see ${LOG_DIR#"${ROOT_DIR}/"}/mailcow-config.log"
      return 1
    }
    ok 'ran Mailcow’s own configurator (generate_config.sh) for this test profile'
    [[ "${existed}" -eq 1 ]] || record_created "${conf}"
  fi
  [[ -f "${conf}" ]] || { warn 'Mailcow/mailcow.conf was not produced'; return 1; }

  # --- Workcenter's keys ----------------------------------------------------
  # The free ports are chosen once and reused, so a re-run does not move a
  # published port for no reason.
  local http_port https_port
  http_port="$(sed -n 's/^HTTP_PORT=//p' "${conf}" | head -1)"
  https_port="$(sed -n 's/^HTTPS_PORT=//p' "${conf}" | head -1)"
  if ! mailcow_port_usable "${http_port}"; then
    http_port="$(pick_free_port 18080)" || { warn 'no free port for Mailcow HTTP'; return 1; }
  fi
  if ! mailcow_port_usable "${https_port}" || [[ "${https_port}" == "${http_port}" ]]; then
    https_port="$(pick_free_port $(( http_port + 1 )))" || { warn 'no free port for Mailcow HTTPS'; return 1; }
  fi

  local key value
  while IFS='=' read -r key value; do
    [[ -n "${key}" ]] || continue
    if grep -qE "^${key}=" "${conf}"; then
      sed -i "s|^${key}=.*|${key}=${value}|" "${conf}"
    else
      printf '%s=%s\n' "${key}" "${value}" >>"${conf}"
    fi
  done <<EOF
MAILCOW_HOSTNAME=${MAIL_HOST}
MAIL_HOST=${MAIL_HOST}
BASE_DOMAIN=${BASE_DOMAIN}
WORKCENTER_HOST=${WORKCENTER_HOST}
FILEBROWSER_HOST=${FILEBROWSER_HOST}
CHAT_HOST=${CHAT_HOST}
OFFICE_HOST=${OFFICE_HOST}
HTTP_PORT=${http_port}
HTTPS_PORT=${https_port}
HTTP_BIND=127.0.0.1
HTTPS_BIND=127.0.0.1
HTTP_REDIRECT=n
AUTODISCOVER_SAN=n
SKIP_LETS_ENCRYPT=y
TRUSTED_PROXIES=${MAILCOW_TRUSTED_PROXIES:-172.16.0.0/12}
API_ALLOW_FROM=${MAILCOW_API_ALLOW_FROM:-172.16.0.0/12}
EOF

  # The API key the provisioning authenticates with. Mailcow seeds whatever is in
  # this key into its own `api` table, so generating one here is what makes the
  # identity configuration possible at all (production.md §5.7, access path 1).
  if ! grep -qE '^API_KEY=[a-f0-9]{32}$' "${conf}"; then
    if command -v openssl >/dev/null 2>&1; then
      if grep -qE '^API_KEY=' "${conf}"; then
        sed -i "s|^API_KEY=.*|API_KEY=$(openssl rand -hex 16)|" "${conf}"
      else
        printf 'API_KEY=%s\n' "$(openssl rand -hex 16)" >>"${conf}"
      fi
    fi
  fi
  chmod 600 "${conf}" 2>/dev/null || true

  ok "Mailcow configured on 127.0.0.1:${http_port} (HTTP) and :${https_port} (HTTPS)"
  if [[ "${generated}" -eq 0 ]]; then
    info 'an existing Mailcow configuration was reused; its ports and Workcenter keys were checked'
  fi
  # Every variable the override interpolates has to be resolvable, and one that is
  # missing does not error: it becomes the empty string inside a Traefik rule.
  local missing='' v
  for v in MAILCOW_HOSTNAME MAIL_HOST BASE_DOMAIN WORKCENTER_HOST FILEBROWSER_HOST \
           CHAT_HOST OFFICE_HOST HTTP_PORT HTTP_BIND TRUSTED_PROXIES API_ALLOW_FROM; do
    grep -qE "^${v}=." "${conf}" || missing="${missing} ${v}"
  done
  if [[ -n "${missing}" ]]; then
    warn "Mailcow/mailcow.conf is missing:${missing} — the override cannot interpolate them"
    return 1
  fi

  # The test-only override. Mailcow's OIDC exchange happens in **php-fpm**, so that
  # is the container that has to trust the local authority — and the authority only
  # exists in a test run, which is why this is generated here rather than committed
  # beside the other overrides.
  #
  # **PHP does not read `CURL_CA_BUNDLE`.** That variable is honoured by libcurl's
  # own tooling and by the Go and Python clients elsewhere in this stack, so setting
  # it here looked right and did nothing: the exchange failed with
  #
  #   cURL error 60: SSL certificate problem: unable to get local issuer certificate
  #   for https://auth.example.com/application/o/token/
  #
  # — logged in Mailcow's own `logs` table rather than on stdout, which is why the
  # UI could only say "login failed". PHP's curl extension takes its trust anchor
  # from the `curl.cainfo` **ini** setting, so the mount that matters is an ini file
  # in the directory this image scans. `openssl.cafile` is set alongside it for the
  # PHP paths that use OpenSSL directly rather than curl.
  local ca_ini="${ROOT_DIR}/user-data/mailcow-ca.ini"
  local test_override="${dir}/docker-compose.test.yml"
  if [[ "${DO_DRY_RUN}" -eq 0 ]]; then
    cat >"${ca_ini}" <<INI
; Generated by scripts/e2e.sh for a test run. Not committed.
; PHP's curl extension ignores CURL_CA_BUNDLE; these two settings are what it reads.
curl.cainfo=/certs/local-ca.crt
openssl.cafile=/certs/local-ca.crt
INI
    record_created "${ca_ini}"
    cat >"${test_override}" <<YAML
# Generated by scripts/e2e.sh for a test run. Not committed, and rewritten on
# every run — see the Mailcow section of scripts/e2e.sh for why.
services:
  php-fpm-mailcow:
    environment:
      # Kept because it costs nothing and libcurl-based paths outside PHP's curl
      # extension do read it. It is *not* what makes the exchange work.
      CURL_CA_BUNDLE: /certs/local-ca.crt
    volumes:
      - ${ROOT_DIR}/Traefik/certs/local-ca.crt:/certs/local-ca.crt:ro
      - ${ca_ini}:/usr/local/etc/php/conf.d/zz-workcenter-ca.ini:ro
YAML
    record_created "${test_override}"
  fi
}

# Mailcow is driven from its own directory with no `-f`, so Docker merges
# Workcenter's override (integration.md IN-6.3).
bring_up_mailcow() {
  step 'Mailcow'
  # The generated test override is added only when it is present: `--down` removes
  # it as part of reverting Mailcow, and a `--file` naming a path that no longer
  # exists makes Compose refuse the whole project.
  local -a mc_extra=()
  [[ -f "${ROOT_DIR}/Mailcow/docker-compose.test.yml" ]] \
    && mc_extra=(--file "${ROOT_DIR}/Mailcow/docker-compose.test.yml")
  if [[ ! -f "${ROOT_DIR}/Mailcow/docker-compose.yml" || ! -f "${ROOT_DIR}/Mailcow/mailcow.conf" ]]; then
    warn 'Mailcow is not initialised in this checkout (Phase 8 runs its own setup)'
    warn 'the Mail pane will not be testable this run'
    return 0
  fi
  # Mailcow's own web ports are published on the loopback interface and cannot be
  # unpublished (IN-6.4: an override cannot remove a `ports:` entry). They are not
  # how Traefik reaches Mailcow — that is the `proxy` network — so a port that is
  # already taken on this host fails the whole service for no functional reason, and
  # Docker's own message ("failed to bind host port ... address already in use")
  # does not say which key to change. Read them and say so first.
  local mc_http mc_https port busy=0
  mc_http="$(sed -n 's/^HTTP_PORT=//p' "${ROOT_DIR}/Mailcow/mailcow.conf" | head -1)"
  mc_https="$(sed -n 's/^HTTPS_PORT=//p' "${ROOT_DIR}/Mailcow/mailcow.conf" | head -1)"
  for port in "${mc_http:-80}" "${mc_https:-443}"; do
    # A subshell so the descriptor closes with it; `/dev/tcp` is a bash built-in
    # and needs no tool that may be absent.
    if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then
      warn "127.0.0.1:${port} is already in use; Mailcow publishes it and cannot unpublish it (IN-6.4)"
      busy=1
    fi
  done
  if [[ "${busy}" -eq 1 ]]; then
    warn 'set HTTP_PORT and HTTPS_PORT in Mailcow/mailcow.conf to free ports and re-run'
    warn 'Traefik reads those keys too, so nothing else needs changing'
  fi
  # No `-f`: Compose only merges `docker-compose.override.yml` when it discovers
  # the file itself, and passing `-f docker-compose.yml` silently drops the
  # override — which is Workcenter's entire Mailcow integration (the `proxy`
  # network, the Traefik labels, the healthchecks). The container comes up looking
  # healthy and reachable by nothing. `compose.yaml` says the same thing from the
  # other side, so the two cannot be read independently.
  if ! run docker compose --project-name mailcow --project-directory "${ROOT_DIR}/Mailcow" \
      --file "${ROOT_DIR}/Mailcow/docker-compose.yml" \
      --file "${ROOT_DIR}/Mailcow/docker-compose.override.yml" \
      "${mc_extra[@]}" \
      up -d >>"${LOG_DIR}/mailcow.log" 2>&1; then
    fail 'Mailcow failed to start'
    tail -n 20 "${LOG_DIR}/mailcow.log" >&2 || true
    exit 1
  fi
  ok 'Mailcow started'
}

# A crash loop is not a slow start. Docker restarts a failing container forever,
# so waiting for the health deadline only delays the report — and buries the
# reason under hundreds of restarts. Two restarts is the limit: a service is
# allowed one for a dependency that was not up yet, and no more.
# The log of a container that keeps exiting, captured while it still exists.
# The teardown destroys the container and its log with it, so this runs during
# the health wait. `collect_unhealthy_evidence` cannot do this job: it selects
# containers with --filter health=unhealthy, and a container in a restart loop
# has no unhealthy health state to filter on — Docker reports it as restarting,
# which is why an earlier run pointed the operator at an empty evidence file.
capture_restart_logs() {
  local id service count previous seen
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    count="$(docker inspect "${id}" --format '{{.RestartCount}}' 2>/dev/null || echo 0)"
    [[ "${count}" =~ ^[0-9]+$ ]] || continue
    [[ "${count}" -gt 0 ]] || continue
    service="$(docker inspect "${id}" --format '{{index .Config.Labels "com.docker.compose.service"}}' 2>/dev/null || echo container)"
    seen="${LOG_DIR}/${service:-container}-restarts"
    previous="$(cat "${seen}" 2>/dev/null || echo 0)"
    [[ "${count}" -le "${previous}" ]] && continue
    printf '%s\n' "${count}" >"${seen}"
    {
      printf '=== %s restart %s (at %s) ===\n' "${service:-container}" "${count}" "$(date -u +%H:%M:%SZ)"
      docker logs --tail 60 "${id}" 2>&1
      printf '\n'
    } >>"${LOG_DIR}/${service:-container}-crash.log" 2>&1
  done < <(docker ps -aq --filter "label=com.docker.compose.project=${COMPOSE_PROJECT}" 2>/dev/null || true)
}

# Restart counts are cumulative for the life of a container, and a container is
# only recreated when its own configuration changes. A crash loop from an earlier
# run would therefore fail every run after it — even once the cause is fixed and
# the container is healthy again — which is the opposite of useful. The baseline
# is taken when the health wait begins, and only restarts *during this run* count.
declare -A RESTART_BASELINE=()

record_restart_baseline() {
  RESTART_BASELINE=()
  local id count
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    count="$(docker inspect "${id}" --format '{{.RestartCount}}' 2>/dev/null || echo 0)"
    [[ "${count}" =~ ^[0-9]+$ ]] || count=0
    RESTART_BASELINE["${id}"]="${count}"
  done < <(docker ps -aq --filter "label=com.docker.compose.project=${COMPOSE_PROJECT}" 2>/dev/null || true)
}

check_restart_loops() {
  local id name count base restarted looping=0
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    name="$(docker inspect "${id}" --format '{{.Name}}' 2>/dev/null | tr -d '/')"
    count="$(docker inspect "${id}" --format '{{.RestartCount}}' 2>/dev/null || echo 0)"
    [[ "${count}" =~ ^[0-9]+$ ]] || count=0
    base="${RESTART_BASELINE[${id}]:-0}"
    [[ "${base}" =~ ^[0-9]+$ ]] || base=0
    restarted=$((count - base))
    if [[ "${restarted}" -gt "${MAX_RESTARTS}" ]]; then
      fail "${name} has restarted ${restarted} times since this run started (limit ${MAX_RESTARTS}): it is crash-looping"
      looping=1
    fi
  done < <(docker ps -aq --filter "label=com.docker.compose.project=${COMPOSE_PROJECT}" 2>/dev/null || true)
  [[ "${looping}" -eq 0 ]] && return 0
  warn 'the service restarts because it cannot complete its start; the log below says why'
  return 1
}

# When the deadline passes, the useful question is "what does the unhealthy
# container itself report?", not "what did Compose print". For each unhealthy
# service this writes its health-probe output and its last 40 log lines to one
# file, so the answer is in the run directory rather than in a re-run.
collect_unhealthy_evidence() {
  local out="${LOG_DIR}/unhealthy.log" id name state
  : >"${out}"
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    name="$(docker inspect "${id}" --format '{{.Name}}' 2>/dev/null | tr -d '/')"
    state="$(docker inspect "${id}" --format '{{.State.Status}}' 2>/dev/null)"
    {
      printf '=== %s (%s) ===\n' "${name}" "${state}"
      docker inspect "${id}" --format '{{json .State.Health}}' 2>/dev/null \
        | tr ',' '\n' | grep -iE '"Status"|"ExitCode"|"Output"' | tail -20
      printf '%s\n' '--- last 40 log lines ---'
      docker logs --tail 40 "${id}" 2>&1
      printf '\n'
    } >>"${out}" 2>&1
    # A Zulip that cannot finish its first boot is the common case here, and the
    # reason is usually in the log rather than in the probe.
    if [[ "${name}" == *zulip* ]]; then
      warn "Zulip is not healthy: its first start runs migrations behind a 300s start period."
      warn "  If the log shows a rejected secret, the secret files must contain a single line"
      warn "  with no trailing newline (Zulip/compose.yaml); --down then a re-run regenerates them."
    fi
  done < <(docker ps -aq --filter "label=com.docker.compose.project=${COMPOSE_PROJECT}" \
             --filter "health=unhealthy" 2>/dev/null || true)
  fail "  evidence: ${out}"
}

wait_healthy() {
  step 'Service health'
  local deadline=$(( $(date +%s) + WAIT_TIMEOUT )) rows unhealthy
  # Only restarts observed from here on are this run's (see RESTART_BASELINE).
  record_restart_baseline
  while :; do
    rows="$(docker compose -f "${ROOT_DIR}/compose.yaml" -f "${COMPOSE_TEST_FILE}" \
      --project-name "${COMPOSE_PROJECT}" ps --format '{{.Service}} {{.State}} {{.Health}}' 2>/dev/null || true)"
    printf '%s\n' "${rows}" | sed 's/^/  /'
    unhealthy="$(printf '%s\n' "${rows}" | awk 'NF && ($2 != "running" || ($3 != "" && $3 != "healthy"))' | wc -l)"
    # Before anything can be torn down, take the log of whichever container is
    # exiting: after `down`, the reason is gone with the container.
    capture_restart_logs
    if ! check_restart_loops; then
      collect_unhealthy_evidence
      return 1
    fi
    [[ "${unhealthy}" -eq 0 && -n "${rows}" ]] && break
    if [[ "$(date +%s)" -ge "${deadline}" ]]; then
      fail "${unhealthy} service(s) are not healthy after ${WAIT_TIMEOUT}s"
      collect_unhealthy_evidence
      exit 1
    fi
    sleep 5
  done
  ok 'every service is running and healthy'
}

# ---------------------------------------------------------------------------
# Checks
#
# Everything here is unauthenticated and local: the applications are reached
# through Traefik by hostname, resolved to 127.0.0.1 with --resolve, over the
# self-signed certificate the test profile installs.
# ---------------------------------------------------------------------------
CURL_BASE=(curl -sS --insecure --max-time 20)
CHECK_FAILURES=0

request() {
  local host="$1" path="$2"
  "${CURL_BASE[@]}" --resolve "${host}:443:127.0.0.1" -o /dev/null -w '%{http_code}' \
    "https://${host}${path}" 2>/dev/null || echo '000'
}

fetch() {
  local host="$1" path="$2"
  "${CURL_BASE[@]}" --resolve "${host}:443:127.0.0.1" "https://${host}${path}" 2>/dev/null || true
}

headers() {
  local host="$1" path="${2:-/}"
  "${CURL_BASE[@]}" -D - -o /dev/null --resolve "${host}:443:127.0.0.1" \
    "https://${host}${path}" 2>/dev/null | tr -d '\r' || true
}

# ---------------------------------------------------------------------------
# Signing in for real
#
# `oidc_login CLIENT_ID REDIRECT_URI USERNAME PASSWORD [extra…]` runs
# `scripts/lib/oidc-login.mjs`, which drives Authentik's own authentication flow,
# exchanges the authorization code and verifies the id_token against the
# provider's JWKS. On success it prints the claims as JSON; on failure it returns
# non-zero and the reason lands in the run's log.
#
# Two properties make this worth the trouble over a "does the endpoint answer"
# check. It exercises the **registered redirect URI**, which is the failure
# OIDC.md §13 calls `invalid redirect URI` and the one a copy-pasted issuer
# produces. And it verifies the **signature**, so a provider with no signing key —
# Trap 2, which otherwise shows up as every client failing at once — fails here
# instead of in a browser three steps later.
#
# The redirect URI has to be one the provider already knows, so each caller passes
# the application's own.
# ---------------------------------------------------------------------------
oidc_login() {
  local client_id="$1" redirect_uri="$2" username="$3" password="$4"
  shift 4
  # Client type decides whether a secret is needed, and it is the application that
  # decides the client type. The shell is `public` — it exchanges the code in the
  # browser and has nowhere to keep a secret, so PKCE protects the exchange. The
  # three applications exchange it server-side, are registered `confidential`, and
  # the token endpoint answers `invalid_client` without the secret (verified
  # against the pinned instance). The secret is read from the same root `.env`
  # line the application itself reads, so this cannot drift from the deployment.
  local secret_var secret
  secret_var="$(printf '%s' "${client_id}" | tr '[:lower:]' '[:upper:]')_OIDC_CLIENT_SECRET"
  secret="$(sed -n "s/^${secret_var}=//p" "${ROOT_DIR}/.env" | head -1)"

  node "${SCRIPT_DIR}/lib/oidc-login.mjs" \
    --base-url "${AUTHENTIK_URL}" \
    --ca "${ROOT_DIR}/Traefik/certs/local-ca.crt" \
    --resolve "${AUTHENTIK_HOST}:127.0.0.1" \
    --client-id "${client_id}" \
    --client-secret "${secret}" \
    --redirect-uri "${redirect_uri}" \
    --username "${username}" \
    --password "${password}" \
    --json "$@" 2>>"${LOG_DIR}/oidc-login.log"
}

# Asserts that a login succeeded and that the token's `groups` claim is exactly
# what the identity model promises. `expect` is a space-separated list; a name
# prefixed with `!` must be ABSENT, which is how "a member is not an
# administrator" is expressed (O-3.2 keeps the two groups separate).
check_oidc_groups() {
  local label="$1" claims="$2"; shift 2
  local want ok_groups=1
  # The claim has to be **unique**. Two scope mappings that both write `groups`
  # are concatenated rather than merged, so a provider carrying both the built-in
  # `profile` (which emits groups on the 2026.8 train) and the custom `groups`
  # mapping answers `["workspaceusers","workspaceadmin","workspaceusers",…]`.
  # Membership tests still pass, which is why this needs saying explicitly: it
  # looks right in every application and is wrong in the token.
  local grouped
  grouped="$(jq -r '.groups | length as $n | unique | length as $u | if $n == $u then "ok" else "\($n) entries, \($u) distinct" end' <<<"${claims}" 2>/dev/null)"
  if [[ "${grouped}" != "ok" ]]; then
    fail "${label}: the groups claim has duplicates (${grouped}) — two mappings are writing it"
    ok_groups=0
  fi
  for want in "$@"; do
    if [[ "${want}" == '!'* ]]; then
      if jq -e --arg g "${want#!}" '.groups | index($g)' <<<"${claims}" >/dev/null 2>&1; then
        fail "${label}: token carries ${want#!}, which it must not"
        ok_groups=0
      fi
    elif ! jq -e --arg g "${want}" '.groups | index($g)' <<<"${claims}" >/dev/null 2>&1; then
      fail "${label}: token does not carry ${want} (groups: $(jq -c '.groups' <<<"${claims}" 2>/dev/null))"
      ok_groups=0
    fi
  done
  # The scope the userinfo endpoint demands, and the one Authentik drops in silence
  # when the provider has no `openid` mapping. A token without it authenticates the
  # id_token perfectly and is refused by `/userinfo/` with `403`, which a browser
  # reports as a CORS failure — see `oidc-login.mjs`.
  if ! jq -e '.scopes | index("openid")' <<<"${claims}" >/dev/null 2>&1; then
    fail "${label}: the token has no 'openid' scope (scopes: $(jq -c '.scopes' <<<"${claims}" 2>/dev/null)) — /userinfo/ will refuse it"
    ok_groups=0
  fi
  if [[ "${ok_groups}" -eq 1 ]]; then
    ok "${label}: groups $(jq -c '.groups' <<<"${claims}")"
  else
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi
}

# ---------------------------------------------------------------------------
# The Zulip organization
#
# A Zulip server has no organization until one is created, and without one every
# page on the Chat host answers **404 "There is no Zulip organization at
# <host>"** — so the Chat pane cannot render anything, whatever else is healthy
# (IN-5.30). The pinned upstream image creates none of its own, and Workcenter no
# longer patches it, so the deployment creates it.
#
# The check is the pane's own contract rather than a database query: if `/` on the
# Chat host already answers like a served organization (302 to the login page, or
# 200 for a signed-in visitor), there is nothing to do. That is also what makes the
# step idempotent across runs — `Zulip/database` survives a `down`, so a repeat run
# finds the organization it created last time.
#
# The command runs *inside* the container a second time, as the `zulip` user, which
# is how Zulip's own management commands are meant to run. The name is passed as an
# argument rather than through the container environment: docker-zulip warns about
# any environment variable that is not one of the ones it knows, and an organization
# name is not one of them.
# ---------------------------------------------------------------------------
ensure_zulip_organization() {
  step 'Zulip organization'
  local name
  name="$(zulip_organization_name)"
  if [[ -z "${name}" ]]; then
    warn 'ZULIP_ORGANIZATION_NAME is empty: no organization is created for this run'
    warn 'the Chat pane will report that Zulip has no organization'
    return 0
  fi
  local code
  code="$(request "${CHAT_HOST}" '/')"
  if [[ "${code}" == "200" || "${code}" == "302" ]]; then
    info "Zulip already serves an organization on ${CHAT_HOST}: leaving it alone"
    return 0
  fi
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would create the Zulip organization: %s\n' "${name}"
    return 0
  fi
  info "creating the Zulip organization: ${name}"
  if compose exec -T zulip \
      bash -lc 'sudo -u zulip /home/zulip/deployments/current/manage.py create_realm \
        "$1" "$SETTING_ZULIP_ADMINISTRATOR" "$1 Administrator" --automated' \
      -- "${name}" >>"${LOG_DIR}/zulip-organization.log" 2>&1; then
    ok "created the Zulip organization ${name}"
  elif grep -q 'Subdomain is already in use' "${LOG_DIR}/zulip-organization.log"; then
    # The pre-check's GET can land while the ingress is still loading the Chat
    # router, and then this command is what discovers that the organization is
    # already there. That is the idempotent case, not a failure.
    info "the Zulip organization ${name} already exists: leaving it alone"
  else
    fail 'could not create the Zulip organization'
    fail "  full log: ${LOG_DIR}/zulip-organization.log"
    tail -n 20 "${LOG_DIR}/zulip-organization.log" >&2 || true
    exit 1
  fi
}

# The numeric id of the organization this run serves.
#
# `-r` on a management command accepts the numeric id or the string id, and a
# realm created without `--string-id` has an empty string id — so the numeric one
# is the only handle a command can use here. `list_realms` prints it. The internal
# `zulipinternal` realm is skipped by matching the **whole** domain, scheme and
# all: its domain is `zulipinternal.<chat host>` while the customer realm's is
# exactly the chat host, and matching only the host would find the internal realm
# first.
zulip_realm_id() {
  compose exec -T zulip bash -lc \
    'sudo -u zulip /home/zulip/deployments/current/manage.py list_realms' 2>/dev/null \
    | awk -v host="https://${CHAT_HOST}" '$0 ~ host { print $1; exit }'
}

# The Zulip testing administrator (IN-5.31).
#
# Docker-zulip exposes no environment variable that creates an account — only
# `SETTING_*` (settings.py), `CONFIG_*` (zulip.conf), `SECRET_*` and a short list
# of its own, and `SETTING_ZULIP_ADMINISTRATOR` only names the realm owner's
# address — so the account is created with Zulip's own management commands inside
# the container, which is the methodology the application accepts.
#
# Two Zulip facts shape the credentials. It authenticates by **email**, so the
# login is `admin@<shell host>` and not `admin`. And it enforces a password policy
# of its own: `PASSWORD_MIN_LENGTH` is 8 and `PASSWORD_MIN_GUESSES` is 10000
# (`zproject/default_settings.py`, applied by `UserProfile.set_password` ->
# `zproject.backends.check_password_strength`), so `admin` is refused with
# `PasswordTooWeakError` however it is set. `admin1234` is the shortest obvious
# extension of `admin` that passes.
#
# The password travels through `--password-file` on stdin, never the command line,
# so it does not appear in `ps` or in this script's log. Both commands are
# idempotent in effect: an existing account and an existing role are successes.
ensure_zulip_admin() {
  step 'Zulip admin account'
  if [[ -z "$(zulip_organization_name)" ]]; then
    info 'no Zulip organization is deployed: no admin account is created'
    return 0
  fi
  local realm
  realm="$(zulip_realm_id)"
  if [[ -z "${realm}" ]]; then
    warn "could not find the Zulip realm for ${CHAT_HOST}: no admin account was created"
    warn 'the Chat pane may serve an organization, but there is no password login to print'
    return 0
  fi
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would ensure the Zulip admin %s exists with the owner role\n' "${ZULIP_ADMIN_EMAIL}"
    return 0
  fi
  local admin_log="${LOG_DIR}/zulip-admin.log"
  # Create the account unless it is already there. `create_user` exits non-zero
  # with "User already exists." in that case, which is a success for this step.
  if printf '%s' "${ZULIP_ADMIN_PASSWORD}" | compose exec -T zulip bash -lc '
        set -e
        pw="$(mktemp)"
        cat >"${pw}"
        chmod 600 "${pw}"
        chown zulip "${pw}"
        rc=0
        sudo -u zulip /home/zulip/deployments/current/manage.py create_user \
          "$1" "$2" -r "$3" --password-file "${pw}" --automated || rc=$?
        rm -f "${pw}"
        exit "${rc}"
      ' -- "${ZULIP_ADMIN_EMAIL}" 'Workcenter Admin' "${realm}" >>"${admin_log}" 2>&1; then
    ok "created the Zulip admin ${ZULIP_ADMIN_EMAIL}"
  elif grep -q 'User already exists' "${admin_log}"; then
    info "the Zulip admin ${ZULIP_ADMIN_EMAIL} already exists"
  else
    fail "could not create the Zulip admin ${ZULIP_ADMIN_EMAIL}"
    fail "  full log: ${admin_log}"
    tail -n 20 "${admin_log}" >&2 || true
    exit 1
  fi
  # Give it Zulip's top administrator role. Re-applying a role it already has
  # exits non-zero with "User already has this role.", which is the idempotent
  # case rather than a failure.
  if compose exec -T zulip bash -lc \
      'sudo -u zulip /home/zulip/deployments/current/manage.py change_user_role \
        "$1" owner -r "$2" --automated' \
      -- "${ZULIP_ADMIN_EMAIL}" "${realm}" >>"${admin_log}" 2>&1; then
    ok "the Zulip admin ${ZULIP_ADMIN_EMAIL} is a realm owner"
  elif grep -q 'already has this role' "${admin_log}"; then
    info "the Zulip admin ${ZULIP_ADMIN_EMAIL} is already a realm owner"
  else
    fail "could not give ${ZULIP_ADMIN_EMAIL} the Zulip owner role"
    fail "  full log: ${admin_log}"
    tail -n 20 "${admin_log}" >&2 || true
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# The OIDC identities, as members of the Zulip organization
#
# Two things have to be true before the Chat pane is usable at all, and neither is
# about the provider — which is why both were found by a person clicking, not by a
# check:
#
#   * **The realm has to allow the sign-up.** Zulip's `invite_required` defaults to
#     true, so an OIDC user who authenticates perfectly is stopped at *"You need an
#     invitation to join this organization."* The gate that decides who may sign in
#     is Authentik's **application binding** — only `workspaceusers` reaches the
#     provider at all — so Zulip's own gate asks a question that has already been
#     answered, one layer too late and with no way for the user to answer it.
#     Turning it off hands the decision to the layer that owns it.
#
#     Zulip has **no group-claim gate**: `invite_required` and the email-domain
#     restriction are the only two, and neither reads a claim. So there is nothing
#     to configure that would restrict membership by `groups`, and the honest
#     arrangement is the one this makes — Authentik decides, Zulip admits.
#   * **The accounts have to exist with the right role.** Zulip identifies users by
#     email, and the fixture identities are `admin@wc.test` and `user@wc.test`
#     (`Testing.md` §7.1) — *not* the deployment's own address, which is what the
#     local administrator uses. A realm owner has to be one of the identities that
#     can actually sign in, or the pane has no owner in it at all.
ensure_zulip_members() {
  step 'Zulip organization membership'
  if [[ -z "$(zulip_organization_name)" ]]; then
    info 'no Zulip organization is deployed: nothing to join'
    return 0
  fi
  local realm
  realm="$(zulip_realm_id)"
  if [[ -z "${realm}" ]]; then
    warn "could not find the Zulip realm for ${CHAT_HOST}"
    return 0
  fi
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would allow OIDC sign-up and make %s a realm owner\n' "${AUTHENTIK_TEST_ADMIN_EMAIL}"
    return 0
  fi
  local log="${LOG_DIR}/zulip-members.log"

  # 1. Stop asking for an invitation. `do_set_realm_property` is the supported path
  #    rather than assigning the column, because it emits the realm event that
  #    connected clients listen for.
  if compose exec -T zulip bash -lc '
        sudo -u zulip /home/zulip/deployments/current/manage.py shell -c "
from zerver.actions.realm_settings import do_set_realm_property
from zerver.models import Realm
realm = Realm.objects.get(string_id=\"\")
if realm.invite_required:
    do_set_realm_property(realm, \"invite_required\", False, acting_user=None)
    print(\"invite_required -> False\")
else:
    print(\"invite_required already False\")
"' >>"${log}" 2>&1; then
    ok 'Zulip no longer requires an invitation: the provider decides who may sign in'
  else
    warn "could not relax Zulip's invitation requirement; see ${log#"${ROOT_DIR}/"}"
  fi

  # 2. The two identities, created if absent. The password is generated and never
  #    printed: these accounts sign in through Authentik, and a password nobody
  #    knows is the correct state for that.
  local who email role display pw
  while IFS='|' read -r email role display; do
    [[ -n "${email}" ]] || continue
    pw="$(openssl rand -base64 24 2>/dev/null || printf 'unused-%s' "${RANDOM}")"
    # `</dev/null` on every call that could read stdin, and it is not decoration:
    # this loop is fed by a heredoc, and `compose exec` **inherits the loop's
    # stdin** and consumes it. Without the redirect the first member is created and
    # the loop then ends — one account, no error, and a second identity that simply
    # never appears. It is silent, which is why the accounts had to be counted
    # rather than trusted.
    if printf '%s' "${pw}" | compose exec -T zulip bash -lc '
          set -e
          f="$(mktemp)"; cat >"${f}"; chmod 600 "${f}"; chown zulip "${f}"
          rc=0
          sudo -u zulip /home/zulip/deployments/current/manage.py create_user \
            "$1" "$2" -r "$3" --password-file "${f}" --automated || rc=$?
          rm -f "${f}"; exit "${rc}"
        ' -- "${email}" "${display}" "${realm}" >>"${log}" 2>&1; then
      ok "created the Zulip account ${email}"
    elif grep -q 'User already exists' "${log}"; then
      info "the Zulip account ${email} already exists"
    fi
    if compose exec -T zulip bash -lc \
        'sudo -u zulip /home/zulip/deployments/current/manage.py change_user_role \
          "$1" "$2" -r "$3" --automated' -- "${email}" "${role}" "${realm}" \
        </dev/null >>"${log}" 2>&1; then
      ok "the Zulip account ${email} has the ${role} role"
    elif grep -q 'already has this role' "${log}"; then
      info "the Zulip account ${email} already has the ${role} role"
    else
      warn "could not give ${email} the ${role} role; see ${log#"${ROOT_DIR}/"}"
    fi
  done <<MEMBERS
${AUTHENTIK_TEST_ADMIN_EMAIL}|owner|Workcenter Admin
${AUTHENTIK_TEST_USER_EMAIL}|member|Workcenter User
MEMBERS
}

check_http() {
  local label="$1" host="$2" path="$3" want="$4" code
  code="$(request "${host}" "${path}")"
  if [[ "${code}" == "${want}" ]]; then
    ok "${label}: ${host}${path} -> ${code}"
  else
    fail "${label}: ${host}${path} -> ${code} (expected ${want})"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi
}

run_checks() {
  step 'Automated checks'
  local host="${WORKCENTER_HOST}"

  check_http 'shell health' "${host}" '/healthz' '200'
  check_http 'shell page' "${host}" '/' '200'
  check_http 'broker health' "${host}" '/api/broker/health' '200'

  if fetch "${host}" '/' | grep -qi 'workcenter'; then
    ok 'the shell HTML names Workcenter'
  else
    fail 'the shell HTML does not name Workcenter'
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # The broker's health payload must describe the three applications; a pane with
  # no address would be a configuration mistake (broker.md §3.4).
  local health
  health="$(fetch "${host}" '/api/broker/health')"
  if printf '%s' "${health}" | grep -q '"files"' \
      && printf '%s' "${health}" | grep -q '"chat"' \
      && printf '%s' "${health}" | grep -q '"mail"'; then
    ok 'the broker reports health for Files, Chat and Mail'
  else
    fail "the broker health payload is missing an application: ${health:0:160}"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  check_http 'Files pane' "${FILEBROWSER_HOST}" '/' '200'
  # Password login is **off** from Phase 4 on, and that is the contract this check
  # now asserts (A-1, I-FB-5, and the `auth.methods.password.enabled: false` in
  # Filebrowser/config.yaml). It inverted deliberately: before identity existed the
  # harness proved the pane was reachable by signing in with a known password;
  # now the password must be refused and the OIDC checks below are what prove
  # access. Leaving the old assertion would have made "Phase 4 is done" and "the
  # harness passes" mutually exclusive.
  local fb_login
  fb_login="$("${CURL_BASE[@]}" -o /dev/null -w '%{http_code}' -X POST \
    -H "X-Password: ${FILEBROWSER_ADMIN_PASSWORD}" \
    --resolve "${FILEBROWSER_HOST}:443:127.0.0.1" \
    "https://${FILEBROWSER_HOST}/api/auth/login?username=admin" 2>/dev/null || echo '000')"
  if [[ "${fb_login}" == "200" ]]; then
    fail "Files password login still works: ${FILEBROWSER_HOST}/api/auth/login -> 200"
    fail '  password authentication must be off once Authentik is the only way in (A-1)'
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  else
    ok "Files password login is refused (${fb_login}); OIDC is the only way in"
  fi
  # The Chat host serves the organization this run created (IN-5.30): with one, `/`
  # answers 302 to the login page for an anonymous visitor and 200 for a signed-in
  # one; with none it answers 404 "There is no Zulip organization at <host>" and the
  # pane has nothing to render. `/login/` is asserted separately below because it
  # answers 200 in both states — it proves the host is routed, not that it is
  # provisioned.
  local chat_root
  chat_root="$(request "${CHAT_HOST}" '/')"
  if [[ "${chat_root}" == "302" || "${chat_root}" == "200" ]]; then
    ok "Chat has an organization: ${CHAT_HOST}/ -> ${chat_root}"
    # The Chat testing account (IN-5.31): Zulip's own email+password exchange,
    # which answers 200 with an API key on success. The password is never printed.
    local zl_login
    zl_login="$("${CURL_BASE[@]}" -o /dev/null -w '%{http_code}' -X POST \
      --data-urlencode "username=${ZULIP_ADMIN_EMAIL}" \
      --data-urlencode "password=${ZULIP_ADMIN_PASSWORD}" \
      --resolve "${CHAT_HOST}:443:127.0.0.1" \
      "https://${CHAT_HOST}/api/v1/fetch_api_key" 2>/dev/null || echo '000')"
    if [[ "${zl_login}" == "200" ]]; then
      ok "Chat admin login works (${ZULIP_ADMIN_EMAIL})"
    else
      fail "Chat admin login: ${CHAT_HOST}/api/v1/fetch_api_key -> ${zl_login} (expected 200)"
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
  else
    fail "Chat has no organization: ${CHAT_HOST}/ -> ${chat_root} (expected 302 or 200)"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi
  check_http 'Chat pane' "${CHAT_HOST}" '/login/' '200'
  check_http 'Office health' "${OFFICE_HOST}" '/healthcheck' '200'

  # Framing: the panes must be embeddable by the shell's origin (broker.md §8,
  # IN-8.5). `frame-ancestors` is checked **first**, because a browser that sees it
  # ignores `X-Frame-Options` (CSP Level 2+): that is how Zulip — whose pinned
  # upstream image still sends `X-Frame-Options: DENY` — is framed by the ingress
  # (integration.md §5.4, IN-5.27). Testing XFO first would call the specified
  # deployment blocked.
  local spec name app_host app_headers
  for spec in "Files:${FILEBROWSER_HOST}" "Chat:${CHAT_HOST}" "Mail:${MAIL_HOST}"; do
    name="${spec%%:*}"; app_host="${spec#*:}"
    app_headers="$(headers "${app_host}")"
    if printf '%s' "${app_headers}" | grep -qiE 'frame-ancestors'; then
      ok "${name} declares a framing policy"
    elif printf '%s' "${app_headers}" | grep -qiE 'x-frame-options: *deny'; then
      warn "${name} sends X-Frame-Options: DENY with no frame-ancestors policy -- its pane cannot be embedded"
    elif printf '%s' "${app_headers}" | grep -qiE 'x-frame-options'; then
      ok "${name} declares a framing policy"
    else
      warn "${name} declares no framing policy"
    fi
  done

  # The shared-disk contract (integration.md IN-9.6, broker.md §5.3).
  local inode_broker inode_files
  inode_broker="$(compose exec -T workcenter stat -c '%d:%i' /srv/files 2>/dev/null || echo '?')"
  inode_files="$(docker compose -f "${ROOT_DIR}/Filebrowser/compose.yaml" \
      --project-name "${COMPOSE_PROJECT}" exec -T filebrowser stat -c '%d:%i' /srv/files 2>/dev/null || echo '?')"
  if [[ "${inode_broker}" == "?" || "${inode_files}" == "?" ]]; then
    warn 'could not compare the source mount inside both containers'
  elif [[ "${inode_broker}" == "${inode_files}" ]]; then
    ok "the broker and FileBrowser share one source directory (${inode_broker})"
  else
    fail "the source directories differ: broker ${inode_broker}, FileBrowser ${inode_files}"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  local image="${WORKCENTER_IMAGE:-workcenter:dev}"
  if docker image inspect "${image}" --format '{{index .Config.Labels "org.opencontainers.image.title"}}' 2>/dev/null | grep -qi workcenter; then
    ok 'the image carries its OCI title label'
  else
    warn 'the image is missing its OCI title label'
  fi

  # The certificate a browser is asked to accept must be an **end entity**. A
  # certificate with `CA:TRUE` used as a server certificate is refused by Firefox's
  # verifier — `MOZILLA_PKIX_ERROR_CA_CERT_USED_AS_END_ENTITY` — while curl, Chrome
  # and `certutil -V` all accept it, which is how a run can pass every other check
  # here and still be unusable in a browser: the shell shows "untrusted
  # certificate" and both panes stay blank however the trust stores are set up.
  # Asserted on what Traefik *serves*, not on the file on disk, and on the chain a
  # client is asked to build.
  local served_cert
  served_cert="$(echo | timeout 15 openssl s_client -connect 127.0.0.1:443 \
    -servername "${WORKCENTER_HOST}" 2>/dev/null | openssl x509 -noout -text 2>/dev/null)"
  if grep -q 'CA:FALSE' <<<"${served_cert}" \
      && grep -q 'TLS Web Server Authentication' <<<"${served_cert}"; then
    ok 'the served certificate is an end-entity server certificate'
  else
    fail 'the served certificate is not an end-entity server certificate'
    fail '  Firefox refuses a CA certificate used as a server certificate even when it is trusted'
    fail '  (MOZILLA_PKIX_ERROR_CA_CERT_USED_AS_END_ENTITY)'
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi
  if echo | timeout 15 openssl s_client -connect 127.0.0.1:443 \
      -servername "${WORKCENTER_HOST}" -CAfile "${ROOT_DIR}/Traefik/certs/local-ca.crt" 2>/dev/null \
      | grep -q 'Verify return code: 0'; then
    ok 'the served certificate chains to the local certificate authority'
  else
    fail 'the served certificate does not chain to Traefik/certs/local-ca.crt'
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # -------------------------------------------------------------------------
  # Identity (roadmap Phase 4, milestone M4 "One identity")
  #
  # The exit criteria at the protocol level: one login, the right groups in the
  # token, every application accepting that token, and the surfaces that are meant
  # to refuse doing so.
  # -------------------------------------------------------------------------
  step 'Automated checks: identity'

  check_http 'Identity: Authentik answers' "${AUTHENTIK_HOST}" '/-/health/live/' 200

  # ---------------------------------------------------------------------------
  # Every application's own sign-in entry has to reach the provider.
  #
  # This is separate from the token checks below and it was missing, which is how
  # a full green run shipped a stack where all three panes failed to sign anyone
  # in. Those checks prove the **provider** issues a good token; they say nothing
  # about whether an application can start its own flow. Each failure below was a
  # different one, and each was invisible from the provider's side:
  #
  #   * **FileBrowser** exchanged the code and then answered
  #     `500 no valid username found for identifier 'preferred_username'` — a claim
  #     the token had stopped carrying.
  #   * **Zulip** answered `500` before it even redirected, because its own go-camo
  #     proxy refused the discovery request (`407`) and it could not verify the
  #     certificate.
  #   * **Mailcow** answered `Login failed` because its php-fpm container was not on
  #     the network the identity host resolves on.
  #
  # Three applications, three causes, one blind spot: nothing drove a *browser's*
  # entry point. So this drives it — a request to each application's SSO entry must
  # come back a redirect to the provider's authorize endpoint, with that
  # application's own client_id in it.
  # ---------------------------------------------------------------------------
  local app_entry entry_label entry_path expected_client location
  while IFS='|' read -r app_entry entry_label entry_path expected_client; do
    [[ -n "${app_entry}" ]] || continue
    location="$(curl -sS -o /dev/null -D- "${CURL_BASE[@]}" \
      --resolve "${app_entry}:443:127.0.0.1" \
      "https://${app_entry}${entry_path}" 2>/dev/null \
      | tr -d '\r' | awk 'tolower($1) == "location:" { print $2 }' | tail -1)"
    if [[ "${location}" == *"/application/o/authorize/"* && "${location}" == *"client_id=${expected_client}"* ]]; then
      ok "${entry_label}: the SSO entry redirects to the provider as ${expected_client}"
    else
      fail "${entry_label}: ${entry_path} did not start an OIDC flow (got '${location:0:90}')"
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
  done < <(printf '%s\n' \
    "${FILEBROWSER_HOST}|Files sign-in|/api/auth/oidc/login?redirect=%2Ffiles%2F|filebrowser" \
    "${MAIL_HOST}|Mail sign-in|/?iam_sso=1|mailcow" \
    "${CHAT_HOST}|Chat sign-in|/login/oidc/?idp=oidc|zulip")

  # ---------------------------------------------------------------------------
  # The two things Zulip decides for itself, after the provider has said yes.
  #
  # Both are invisible from the provider's side and both stop a fully authenticated
  # user dead: a realm that requires an invitation refuses everyone the provider
  # just admitted, and an organization whose owner is not one of the identities that
  # can sign in has no owner in the pane at all. Neither is a claim, so no token
  # check can see them.
  # ---------------------------------------------------------------------------
  if [[ -n "$(zulip_organization_name)" ]] && [[ -n "$(zulip_realm_id)" ]]; then
    local zfacts
    zfacts="$(compose exec -T zulip bash -lc \
      'sudo -u zulip /home/zulip/deployments/current/manage.py shell -c "
from zerver.models import Realm, UserProfile
r = Realm.objects.get(string_id=\"\")
print(\"invite_required\", r.invite_required)
for e in (\"'"${AUTHENTIK_TEST_ADMIN_EMAIL}"'\", \"'"${AUTHENTIK_TEST_USER_EMAIL}"'\"):
    u = UserProfile.objects.filter(realm=r, delivery_email=e, is_active=True).first()
    print(\"member\", e, u.role if u else \"absent\")
"' </dev/null 2>/dev/null | grep -E "^(invite_required|member) ")" || true

    if grep -q '^invite_required False' <<<"${zfacts}"; then
      ok 'Chat sign-up: the organization does not require an invitation'
    else
      fail 'Chat sign-up: the organization still requires an invitation, so OIDC users are refused'
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
    # Zulip's role numbers: 100 realm owner, 200 administrator, 400 member.
    if grep -q "^member ${AUTHENTIK_TEST_ADMIN_EMAIL} 100$" <<<"${zfacts}"; then
      ok "Chat membership: ${AUTHENTIK_TEST_ADMIN_EMAIL} is a realm owner"
    else
      fail "Chat membership: ${AUTHENTIK_TEST_ADMIN_EMAIL} is not a realm owner ($(grep "^member ${AUTHENTIK_TEST_ADMIN_EMAIL}" <<<"${zfacts}" || echo absent))"
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
    if grep -qE "^member ${AUTHENTIK_TEST_USER_EMAIL} (100|200|400)$" <<<"${zfacts}"; then
      ok "Chat membership: ${AUTHENTIK_TEST_USER_EMAIL} is a member of the organization"
    else
      fail "Chat membership: ${AUTHENTIK_TEST_USER_EMAIL} is not in the organization"
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
  fi

  # The issuer has to be the **public** URL, not the container's `http://`
  # address. IN-7.4 is exactly this: behind a proxy that fails to forward the
  # original scheme, Authentik advertises an `http://` issuer and every client
  # fails with `unexpected "iss" claim value` — a failure that otherwise only
  # appears once a browser is involved.
  local discovery
  discovery="$(fetch "${AUTHENTIK_HOST}" '/application/o/workcenter/.well-known/openid-configuration')"
  if jq -e --arg want "${AUTHENTIK_URL}/application/o/workcenter/" '.issuer == $want' \
      <<<"${discovery}" >/dev/null 2>&1; then
    ok "identity: the provider advertises its public issuer"
  else
    fail "identity: the provider advertises '$(jq -r '.issuer // "nothing"' <<<"${discovery}" 2>/dev/null)'"
    fail "          expected ${AUTHENTIK_URL}/application/o/workcenter/ (IN-7.4 mints an http:// issuer)"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # JWKS must be populated. OIDC.md §4.5 Trap 2: a provider with no signing key
  # signs with HS256 and publishes no key, which breaks every client that verifies
  # a token — Zulip, FileBrowser and the shell's own server-side check alike.
  if jq -e '.keys | length > 0' <<<"$(fetch "${AUTHENTIK_HOST}" '/application/o/workcenter/jwks/')" >/dev/null 2>&1; then
    ok 'identity: the provider publishes a JWKS signing key'
  else
    fail 'identity: the provider publishes no JWKS key — every client will reject its tokens (Trap 2)'
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # --- the administrator ----------------------------------------------------
  # Every application this run deploys, each with its **own** registered redirect
  # URI: that is what makes this a configuration check and not only a login check.
  # Mailcow is listed only when it is part of the run — its provider is still
  # provisioned either way, because the identity model describes the deployment and
  # not this invocation.
  local identity_apps
  identity_apps="$(printf '%s\n' \
    "workcenter|workcenter|https://${WORKCENTER_HOST}/" \
    "filebrowser|filebrowser|https://${FILEBROWSER_HOST}/api/auth/oidc/callback" \
    "zulip|zulip|https://${CHAT_HOST}/complete/oidc/")"
  if [[ "${WITH_MAILCOW}" -eq 1 ]]; then
    identity_apps+=$'\n'"mailcow|mailcow|https://${MAIL_HOST}/"
  fi

  local app client redirect
  while IFS='|' read -r app client redirect; do
    [[ -z "${app}" ]] && continue
    if claims="$(oidc_login "${client}" "${redirect}" \
        "${AUTHENTIK_TEST_ADMIN_EMAIL}" "${AUTHENTIK_TEST_ADMIN_PASSWORD}")"; then
      check_oidc_groups "admin → ${app}" "${claims}" "${WORKCENTER_USER_GROUP}" "${WORKCENTER_ADMIN_GROUP}"
    else
      fail "admin → ${app}: sign-in failed (see ${LOG_DIR#"${ROOT_DIR}/"}/oidc-login.log)"
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
  done <<<"${identity_apps}"

  # --- the ordinary member --------------------------------------------------
  # In `workspaceusers` and **not** in `workspaceadmin`: the separation the whole
  # group model rests on (O-3.2, O-3.3).
  while IFS='|' read -r app client redirect; do
    [[ -z "${app}" ]] && continue
    if claims="$(oidc_login "${client}" "${redirect}" \
        "${AUTHENTIK_TEST_USER_EMAIL}" "${AUTHENTIK_TEST_USER_PASSWORD}")"; then
      check_oidc_groups "member → ${app}" "${claims}" "${WORKCENTER_USER_GROUP}" "!${WORKCENTER_ADMIN_GROUP}"
    else
      fail "member → ${app}: sign-in failed"
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
  done <<<"${identity_apps}"

  # --- the outsider ---------------------------------------------------------
  # In no group at all, so the application binding refuses the authorization
  # request. This is the fixture that makes "workspaceusers decides who may sign
  # in" a tested statement rather than an assumption (O-3.3, IN-3.8).
  if oidc_login workcenter "https://${WORKCENTER_HOST}/" \
      "${AUTHENTIK_TEST_OUTSIDER_EMAIL}" "${AUTHENTIK_TEST_OUTSIDER_PASSWORD}" --expect-denied >/dev/null; then
    ok "identity: ${AUTHENTIK_TEST_OUTSIDER_EMAIL} is refused (no group)"
  else
    fail "identity: ${AUTHENTIK_TEST_OUTSIDER_EMAIL} was NOT refused — the application binding is not limiting access"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # --- single logout --------------------------------------------------------
  # A-7: signing out of Workcenter ends the Authentik session, and that is what
  # signs out every application following it. The value of checking it here rather
  # than trusting the redirect is that a provider which accepts `end-session` and
  # keeps the session anyway looks identical from a browser.
  local logout_result
  if logout_result="$(oidc_login workcenter "https://${WORKCENTER_HOST}/" \
      "${AUTHENTIK_TEST_ADMIN_EMAIL}" "${AUTHENTIK_TEST_ADMIN_PASSWORD}" --then-logout)"; then
    if jq -e '.session_ended == true' <<<"${logout_result}" >/dev/null 2>&1; then
      ok 'identity: signing out ends the provider session (A-7)'
    else
      fail 'identity: the provider session survived a sign-out'
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
  else
    fail "identity: the single-logout check failed (see ${LOG_DIR#"${ROOT_DIR}/"}/oidc-login.log)"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # --- the Authentik admin console ------------------------------------------
  # `akadmin` is the built-in superuser (I-AK-2). The console's HTML answers 200
  # to anyone — it is a single-page app and the redirect happens in JavaScript —
  # so the check authenticates and then asks an admin-only API endpoint who it is.
  # That is the difference between "the page loaded" and "an administrator can
  # administer the provider".
  local console_result
  if console_result="$(node "${SCRIPT_DIR}/lib/oidc-login.mjs" \
      --base-url "${AUTHENTIK_URL}" \
      --ca "${ROOT_DIR}/Traefik/certs/local-ca.crt" \
      --resolve "${AUTHENTIK_HOST}:127.0.0.1" \
      --username akadmin \
      --password "${AUTHENTIK_BOOTSTRAP_PASSWORD}" \
      --admin-console --json 2>>"${LOG_DIR}/oidc-login.log")"; then
    if jq -e '.console == true and .is_superuser == true' <<<"${console_result}" >/dev/null 2>&1; then
      ok 'identity: the Authentik admin console is reachable as akadmin (superuser)'
    else
      fail "identity: akadmin reached the API but is not a superuser: ${console_result}"
      CHECK_FAILURES=$((CHECK_FAILURES + 1))
    fi
  else
    fail "identity: akadmin could not reach the Authentik admin console"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # --- the dashboard --------------------------------------------------------
  # Three checks, because two of them are easy to pass for the wrong reason.
  #
  # One: unauthenticated must never reach it. Two and three: the **group boundary**
  # must hold through the outpost — an administrator gets in, a member of
  # `workspaceusers` does not. A 200 from the outpost's own pages is not access,
  # which is why the verifier only counts a 200 that came from the protected path
  # itself; without that, both of these passed while every account was being let
  # through.
  local dash_code
  dash_code="$(request "${TRAEFIK_HOST}" '/dashboard/')"
  if [[ "${dash_code}" == '200' ]]; then
    fail "identity: the Traefik dashboard answers 200 unauthenticated (${TRAEFIK_HOST}/dashboard/)"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  else
    ok "identity: the Traefik dashboard refuses an unauthenticated request (${dash_code})"
  fi

  local dash_result
  if dash_result="$(node "${SCRIPT_DIR}/lib/oidc-login.mjs" \
      --base-url "${AUTHENTIK_URL}" \
      --ca "${ROOT_DIR}/Traefik/certs/local-ca.crt" \
      --resolve "${AUTHENTIK_HOST}:127.0.0.1,${TRAEFIK_HOST}:127.0.0.1" \
      --username "${AUTHENTIK_TEST_ADMIN_EMAIL}" \
      --password "${AUTHENTIK_TEST_ADMIN_PASSWORD}" \
      --forward-auth "https://${TRAEFIK_HOST}/dashboard/" --json 2>>"${LOG_DIR}/oidc-login.log")" \
      && jq -e '.forward_auth == true and .status == 200' <<<"${dash_result}" >/dev/null 2>&1; then
    ok "identity: ${AUTHENTIK_TEST_ADMIN_EMAIL} reaches the Traefik dashboard (forward auth)"
  else
    fail "identity: ${AUTHENTIK_TEST_ADMIN_EMAIL} could not reach the Traefik dashboard"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # ---------------------------------------------------------------------------
  # Mailcow's own sign-in, walked the way a browser walks it.
  #
  # This is the check that was missing, and its absence is why every provider-side
  # check passed while Mailcow answered every real sign-in with a blank page: the
  # provider issued a perfect token, and the application threw a TypeError before
  # it ever looked at one. Only starting at the application's own entry point can
  # see that, which is what `--sso-entry` does.
  #
  # The landing URL is the assertion that matters. Mailcow sends a signed-in user
  # into SOGo at `/SOGo/so/<address>/Mail/view`, so the address appearing there is
  # proof that the session belongs to *this* account — not merely that a page was
  # served.
  # ---------------------------------------------------------------------------
  local mail_result mail_landed
  if mail_result="$(node "${SCRIPT_DIR}/lib/oidc-login.mjs" \
      --base-url "${AUTHENTIK_URL}" \
      --ca "${ROOT_DIR}/Traefik/certs/local-ca.crt" \
      --resolve "${AUTHENTIK_HOST}:127.0.0.1,${MAIL_HOST}:127.0.0.1" \
      --username "${AUTHENTIK_TEST_ADMIN_EMAIL}" \
      --password "${AUTHENTIK_TEST_ADMIN_PASSWORD}" \
      --sso-entry "https://${MAIL_HOST}/?iam_sso=1" \
      --expect 'SOGo' --json 2>>"${LOG_DIR}/oidc-login.log")" \
      && jq -e '.ok == true and .status == 200 and .refused == false' <<<"${mail_result}" >/dev/null 2>&1; then
    mail_landed="$(jq -r '.landed' <<<"${mail_result}")"
    ok "Mail SSO: ${AUTHENTIK_TEST_ADMIN_EMAIL} landed inside SOGo (${mail_landed#"https://${MAIL_HOST}"})"
  else
    fail "Mail SSO: ${AUTHENTIK_TEST_ADMIN_EMAIL} did not complete the sign-in at ${MAIL_HOST}"
    fail "  the application served: $(jq -r '.landed // "nothing"' <<<"${mail_result}" 2>/dev/null || echo 'no result')"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # The same walk for a member, because the two accounts reach different mailboxes.
  if mail_result="$(node "${SCRIPT_DIR}/lib/oidc-login.mjs" \
      --base-url "${AUTHENTIK_URL}" \
      --ca "${ROOT_DIR}/Traefik/certs/local-ca.crt" \
      --resolve "${AUTHENTIK_HOST}:127.0.0.1,${MAIL_HOST}:127.0.0.1" \
      --username "${AUTHENTIK_TEST_USER_EMAIL}" \
      --password "${AUTHENTIK_TEST_USER_PASSWORD}" \
      --sso-entry "https://${MAIL_HOST}/?iam_sso=1" \
      --expect 'SOGo' --json 2>>"${LOG_DIR}/oidc-login.log")" \
      && jq -e --arg e "${AUTHENTIK_TEST_USER_EMAIL}" \
        '.ok == true and (.landed | contains($e))' <<<"${mail_result}" >/dev/null 2>&1; then
    ok "Mail SSO: ${AUTHENTIK_TEST_USER_EMAIL} landed in their own mailbox"
  else
    fail "Mail SSO: ${AUTHENTIK_TEST_USER_EMAIL} did not reach their mailbox"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi

  # The refusal is the exit criterion a person would otherwise have to test by
  # hand: a `workspaceusers` member is not an administrator anywhere, and the
  # dashboard is the one surface where that is visible.
  if node "${SCRIPT_DIR}/lib/oidc-login.mjs" \
      --base-url "${AUTHENTIK_URL}" \
      --ca "${ROOT_DIR}/Traefik/certs/local-ca.crt" \
      --resolve "${AUTHENTIK_HOST}:127.0.0.1,${TRAEFIK_HOST}:127.0.0.1" \
      --username "${AUTHENTIK_TEST_USER_EMAIL}" \
      --password "${AUTHENTIK_TEST_USER_PASSWORD}" \
      --forward-auth "https://${TRAEFIK_HOST}/dashboard/" --json \
      >>"${LOG_DIR}/oidc-login.log" 2>&1; then
    fail "identity: ${AUTHENTIK_TEST_USER_EMAIL} reached the Traefik dashboard — the admin-only binding is not enforced"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  else
    ok "identity: ${AUTHENTIK_TEST_USER_EMAIL} is refused the Traefik dashboard (${WORKCENTER_ADMIN_GROUP} only)"
  fi

  step 'Automated checks: result'
  if [[ "${CHECK_FAILURES}" -eq 0 ]]; then
    ok 'every automated check passed'
  else
    fail "${CHECK_FAILURES} automated check(s) failed"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# The test accounts
#
# The manual walk needs to know what to type. FileBrowser Quantum's built-in admin
# username is always `admin`, and its password is FILEBROWSER_ADMIN_PASSWORD,
# which this run sets (IN-3.26). The value is spelled out only when it is the
# non-secret test default, so an operator who exported their own is not handed
# their own password back on stdout.
#
# Zulip has no equivalent, and the line says so rather than leaving a person
# guessing. docker-zulip 12.3 exposes no environment variable that creates a login
# account: `SETTING_ZULIP_ADMINISTRATOR` only names the address of the realm owner,
# and `manage.py create_realm --automated` creates that account with a disabled
# password (IN-5.30), so there is nothing for this run to set or print.
# ---------------------------------------------------------------------------
print_test_accounts() {
  step 'Test accounts'
  # One identity, every surface (A-1, milestone M4). There are no per-application
  # passwords to print any more: FileBrowser's password login is off, Zulip's is
  # secondary to its OIDC backend, and both are reached with the accounts below.
  printf '  Authentik — https://%s (admin console: sign in as akadmin)\n' "${AUTHENTIK_HOST}"
  printf '    %s / %s   -> %s + %s (admin in every application, and the Traefik dashboard)\n' \
    "${AUTHENTIK_TEST_ADMIN_EMAIL}" "${AUTHENTIK_TEST_ADMIN_PASSWORD}" \
    "${WORKCENTER_USER_GROUP}" "${WORKCENTER_ADMIN_GROUP}"
  printf '    %s / %s    -> %s only (no administrative rights anywhere)\n' \
    "${AUTHENTIK_TEST_USER_EMAIL}" "${AUTHENTIK_TEST_USER_PASSWORD}" "${WORKCENTER_USER_GROUP}"
  printf '    %s / %s -> no group at all: the denial fixture\n' \
    "${AUTHENTIK_TEST_OUTSIDER_EMAIL}" "${AUTHENTIK_TEST_OUTSIDER_PASSWORD}"
  printf '  Each application: sign in through Workcenter, or start at the application and it redirects.\n'
  printf '    Files  https://%s\n' "${FILEBROWSER_HOST}"
  printf '    Chat   https://%s/login/oidc/?idp=oidc   (Zulip is SP-initiated only, O-4.4)\n' "${CHAT_HOST}"
  printf '    Mail   https://%s\n' "${MAIL_HOST}"
  printf '    Shell  https://%s\n' "${WORKCENTER_HOST}"
  printf '  Signing out of Workcenter ends the Authentik session and every application with it (A-7).\n'
  # Mailcow's admin page is the one surface that is **not** OIDC, and saying so here
  # is the difference between "the password is wrong" and "this page does not use
  # the identity provider at all".
  printf '\n  Mailcow admin page — https://%s/admin  (local credential, NOT the SSO identity)\n' "${MAIL_HOST}"
  printf '    %s / %s\n' "${MAILCOW_ADMIN_USER}" "${MAILCOW_ADMIN_PASSWORD}"
  printf '  The Mail pane and its SOGo page sign in through Authentik as %s.\n' "${AUTHENTIK_TEST_ADMIN_EMAIL}"
}

# ---------------------------------------------------------------------------
# The manual checklist
# ---------------------------------------------------------------------------
print_manual_checks() {
  step 'Manual checks — Phase 4 (identity: Authentik everywhere)'
  cat <<EOF
  The automated checks above cover the protocol: the right groups in the token,
  every application accepting it, the refusals, and sign-out ending the session.
  What a person still has to judge:

  [ ] Sign in at https://${WORKCENTER_HOST}/ as ${AUTHENTIK_TEST_ADMIN_EMAIL}.
      You are asked **once**, and land in the workspace.
  [ ] The three panes are reachable without a second prompt: Files, Chat and Mail
      each render inside the shell rather than showing their own sign-in page.
  [ ] The user menu reads "Workcenter - Admin" and offers the admin links
      (Traefik, Mailcow, Authentik).
  [ ] https://${TRAEFIK_HOST}/dashboard/ opens without asking again — forward auth
      sees the Authentik session — while https://${AUTHENTIK_HOST}/ shows the
      admin console.
  [ ] Sign out from the user menu. Authentik asks you to confirm the sign-out,
      then returns you to https://${WORKCENTER_HOST}/. Reloading it asks you to
      sign in again.
  [ ] Sign in again as ${AUTHENTIK_TEST_USER_EMAIL}. The user menu now reads
      "Workcenter - User", the admin links are gone, and https://${TRAEFIK_HOST}/dashboard/
      is **refused** — that is the group boundary the exit criteria name.
  [ ] In Authentik, remove ${AUTHENTIK_TEST_USER_EMAIL} from
      ${WORKCENTER_USER_GROUP} (Directory -> Groups), sign out and try again:
      the sign-in is refused everywhere, not just in one pane. This is the exit
      criterion a person can only test by hand; the next run of this script puts
      the membership back.
  [ ] Add the account back, and confirm it works again.

  Then the deployment checks that still hold from Phase 3:

  [ ] \`docker compose ps\` shows every service healthy, and none of them had to
      restart to get there.
  [ ] Each hostname serves its application over HTTPS once the hostnames resolve
      to this machine (\`--hosts\` does that).
  [ ] No application publishes a port to the host: Traefik's ports only.
  [ ] Mailcow answers on its own hostname with Workcenter's override applied: no
      published ports, \`TRUSTED_PROXIES\` set, and its four added healthchecks
      reporting healthy.
  [ ] All five Zulip services are up: trimming them is not permitted.

  The shell checks from Phase 2 still hold:

  [ ] The brand header reads "Workcenter - Admin" for an administrator and
      "Workcenter - User" for everyone else.
  [ ] Dark is the default; the sun switches to light and the moon switches back.
  [ ] The language button shows a rounded flag and the two-letter code.
EOF
  step 'What comes next'
  cat <<'EOF'
  - The six transfer flows are Phase 5; the automated checks cover the plumbing
    they will use, not the flows themselves.
  - Playwright takes over these checks in Phase 6; see Testing.md.
EOF
  printf '\n  Open:  https://%s/   (a browser needs the host entries and the CA — see below)\n' "${WORKCENTER_HOST}"
  printf '  Stop:  ./scripts/e2e.sh --down\n\n'
}

# ---------------------------------------------------------------------------
# Browser prerequisites — checked, never changed
#
# Reaching the stack from a **browser** needs two things this script cannot
# provide: the hostnames in `/etc/hosts`, and the local certificate authority in
# the system and per-user trust stores. Both are system state, so both belong to
# `scripts/setup-testing.sh`.
#
# Nothing else depends on them. The harness reaches the stack through
# `curl --resolve` and the CA file in the checkout, which needs no privilege — which
# is why `--no-browser` can drop the requirement entirely on a machine that will
# never open the result.
# ---------------------------------------------------------------------------

# Do the two halves hold? Prints what is wrong; returns 1 if anything is.
browser_prerequisites_ok() {
  local missing=0

  # Every name the deployment serves, not merely the marker. A block left behind by
  # an older run resolves five of the seven, and the two it is missing are the
  # identity provider and the dashboard.
  local want_names="${WORKCENTER_HOST} ${FILEBROWSER_HOST} ${CHAT_HOST} ${MAIL_HOST} ${OFFICE_HOST} ${AUTHENTIK_HOST} ${TRAEFIK_HOST}"
  local have_names=''
  if grep -qF '# >>> workcenter e2e >>>' /etc/hosts 2>/dev/null; then
    have_names="$(sed -n '/# >>> workcenter e2e >>>/,/# <<< workcenter e2e <<</p' /etc/hosts 2>/dev/null \
      | sed '1d;$d' | sed 's/^127\.0\.0\.1[[:space:]]*//')"
  fi
  if [[ "${have_names}" == "${want_names}" ]]; then
    ok "/etc/hosts resolves all seven hostnames"
  elif [[ -n "${have_names}" ]]; then
    warn '/etc/hosts has a stale Workcenter block: a browser cannot resolve every hostname'
    info "   present: ${have_names}"
    info "   wanted:  ${want_names}"
    missing=1
  else
    warn '/etc/hosts has no Workcenter entries: a browser cannot resolve the hostnames'
    missing=1
  fi

  # The anchor file the setup script installs, in whichever directory this
  # distribution uses. Readable by anyone, so this needs no privilege to check.
  if localca_installed; then
    ok 'the local certificate authority is installed in the system trust store'
  elif [[ -z "$(localca_anchor_dir)" ]]; then
    warn 'no recognisable system trust store on this machine'
    missing=1
  else
    warn 'the local certificate authority is not trusted by this machine'
    missing=1
  fi

  [[ "${missing}" -eq 0 ]]
}

# The report. Named for what it does: it checks nothing the gate above does not, and
# unlike the gate it never refuses to go on — which is what you want when you are
# working out *why* a page will not load.
check_browser_prerequisites() {
  step 'Browser prerequisites'
  printf '   the stack is reached by name, not by port:  https://%s/\n' "${WORKCENTER_HOST}"
  if browser_prerequisites_ok; then
    info "open https://${WORKCENTER_HOST}/ in a browser"
  else
    info 'both are one-time system changes, and this script does not make them:'
    printf '      sudo ./scripts/setup-testing.sh\n'
    printf '  Until then the automated checks still run, and a browser will warn.\n'
  fi
}

# The gate. Fails the run **before anything is built** when the machine has not been
# prepared, because the alternative is a ten-minute deploy followed by a browser that
# cannot open it — which is precisely the outcome the preflight exists to prevent.
#
# It insists on exactly what `scripts/setup-testing.sh` provides, and it is checked
# here rather than assumed because both halves are system state the harness has no
# business changing. `--no-browser` is the way out for a machine that will never
# open the result.
require_browser_preflight() {
  step 'Preflight: will a browser be able to open this?'
  printf '   the stack is reached by name, not by port:  https://%s/\n' "${WORKCENTER_HOST}"
  if browser_prerequisites_ok; then
    info 'the machine is prepared: the run should be openable when it finishes'
    return 0
  fi
  fail 'this machine is not ready for a browser, and the run would not be viewable'
  printf '\n  These are one-time system changes and only this command makes them:\n\n' >&2
  printf '      sudo ./scripts/setup-testing.sh\n\n' >&2
  printf '  It creates the local certificate authority, installs it in the trust\n' >&2
  printf '  stores, and writes the seven hostnames into /etc/hosts.\n' >&2
  printf '  To run the checks anyway on a machine with no browser:  --no-browser\n\n' >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Shell-only mode (the Phase 2 path)
# ---------------------------------------------------------------------------
shell_only_build() {
  if [[ "${DO_BUILD}" -eq 0 ]]; then
    info 'skipping the build (--no-build)'
    [[ -f "${ROOT_DIR}/dist/index.html" ]] || { fail 'dist/index.html is missing'; exit 1; }
    return 0
  fi
  step 'Building the shell'
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would run: yarn build\n'
    return 0
  fi
  if ! (cd "${ROOT_DIR}" && yarn build >"${LOG_DIR}/shell-build.log" 2>&1); then
    fail "the build failed; see ${LOG_DIR}/shell-build.log"
    tail -n 20 "${LOG_DIR}/shell-build.log" >&2 || true
    exit 1
  fi
  ok 'build complete'
}

# Every Workcenter server of this checkout, from the process table. A pid file is
# a convenience; a server started by hand is still a server --down must stop.
our_server_pids() {
  local pid argv0 argv1 cwd state
  for pid in $(ls /proc 2>/dev/null | grep -E '^[0-9]+$' || true); do
    [[ -r "/proc/${pid}/cmdline" ]] || continue
    argv0="$(tr '\0' '\n' <"/proc/${pid}/cmdline" 2>/dev/null | sed -n 1p)"
    argv1="$(tr '\0' '\n' <"/proc/${pid}/cmdline" 2>/dev/null | sed -n 2p)"
    state="$(sed 's/.*) //' "/proc/${pid}/stat" 2>/dev/null | cut -d' ' -f1)"
    [[ "${state}" == "Z" ]] && continue
    # `--` before each value: a Node process launched with a flag as its first
    # argument (`node --import …`) would otherwise have that flag read as an
    # option, printing `basename: unrecognized option '--import'` on every run.
    [[ "$(basename -- "${argv0:-}")" == "node" ]] || continue
    [[ "$(basename -- "${argv1:-}")" == "server.js" ]] || continue
    cwd="$(readlink "/proc/${pid}/cwd" 2>/dev/null || true)"
    if [[ "${cwd}" == "${ROOT_DIR}" || "${argv1}" == "${ROOT_DIR}/server.js" ]]; then
      printf '%s\n' "${pid}"
    fi
  done
  # The loop's status is the status of its last test, which is 1 whenever the last
  # process examined is not ours. Returning that would make this function fail its
  # caller under `set -e` and abort a teardown for no reason.
  return 0
}

stop_shell_servers() {
  local stopped=0 pid state
  for pid in $(our_server_pids); do
    info "stopping the shell server (pid ${pid})"
    kill "${pid}" 2>/dev/null || true
    for _ in $(seq 1 20); do
      state="$(sed 's/.*) //' "/proc/${pid}/stat" 2>/dev/null | cut -d' ' -f1)"
      [[ -z "${state}" || "${state}" == "Z" ]] && break
      sleep 0.25
    done
    kill -9 "${pid}" 2>/dev/null || true
    stopped=1
  done
  rm -f "${SHELL_PID_FILE}"
  if [[ "${stopped}" -eq 1 ]]; then ok 'shell server stopped'; else info 'no shell server was running'; fi
}

shell_only_up() {
  step 'Serving the shell on this host'
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would run: HOST=%s PORT=%s node server.js\n' "${HOST}" "${PORT}"
    return 0
  fi
  mkdir -p "${RUN_DIR}"
  stop_shell_servers
  (
    cd "${ROOT_DIR}"
    HOST="${HOST}" PORT="${PORT}" nohup node server.js >"${SHELL_LOG_FILE}" 2>&1 &
    echo $! >"${SHELL_PID_FILE}"
  )
  local url="http://127.0.0.1:${PORT}/healthz" i
  for i in $(seq 1 40); do
    if node -e 'fetch(process.argv[1]).then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))' "${url}" >/dev/null 2>&1; then
      ok "the shell answers at ${url}"
      return 0
    fi
    sleep 0.5
  done
  fail "the shell did not become healthy; see ${SHELL_LOG_FILE}"
  tail -n 20 "${SHELL_LOG_FILE}" >&2 || true
  exit 1
}

# ---------------------------------------------------------------------------
# Teardown
#
# The contract: after --down the only thing left is the images. Everything Docker
# created is removed by project name; everything the run created is listed in the
# manifest and removed by path.
# ---------------------------------------------------------------------------
stack_down() {
  step 'Stopping the stack'
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if docker ps -aq --filter "label=com.docker.compose.project=${COMPOSE_PROJECT}" | grep -q .; then
      if compose down -v --remove-orphans --timeout 30 >>"${LOG_DIR}/down.log" 2>&1; then
        ok 'compose services, networks and volumes removed'
      else
        warn 'compose down reported a problem; see the log'
      fi
    else
      info 'no compose services were running'
    fi
    if docker ps -aq --filter 'label=com.docker.compose.project=mailcow' | grep -q .; then
      info 'stopping Mailcow (its own project)'
      local -a mc_extra_dn=()
      [[ -f "${ROOT_DIR}/Mailcow/docker-compose.test.yml" ]] \
        && mc_extra_dn=(--file "${ROOT_DIR}/Mailcow/docker-compose.test.yml")
      run docker compose --project-name mailcow --project-directory "${ROOT_DIR}/Mailcow" \
        --file "${ROOT_DIR}/Mailcow/docker-compose.yml" \
        --file "${ROOT_DIR}/Mailcow/docker-compose.override.yml" \
        "${mc_extra_dn[@]}" \
        down -v --remove-orphans --timeout 30 >>"${LOG_DIR}/down.log" 2>&1 \
        || warn 'Mailcow did not stop cleanly; see the log'

      # Compose cannot even parse the override without a readable `mailcow.conf`:
      # it interpolates `${BASE_DOMAIN:?…}` and refuses the project. That is one of
      # the states a run legitimately leaves behind — `--down` is what reverts the
      # configuration — so a teardown that depends on the configuration it is about
      # to remove cannot be the only way out. Whatever Compose could not reach is
      # removed by the project label it set on every container.
      if docker ps -aq --filter 'label=com.docker.compose.project=mailcow' | grep -q .; then
        info 'removing the Mailcow containers Compose could not reach'
        # shellcheck disable=SC2046
        run docker rm -f $(docker ps -aq --filter 'label=com.docker.compose.project=mailcow') \
          >>"${LOG_DIR}/down.log" 2>&1 || warn 'some Mailcow containers could not be removed'
        # shellcheck disable=SC2046
        docker network rm $(docker network ls -q --filter 'label=com.docker.compose.project=mailcow') \
          >>"${LOG_DIR}/down.log" 2>&1 || true
      fi
    fi
  else
    warn 'docker is unavailable: skipping the stack teardown'
  fi

  stop_shell_servers
  # The /etc/hosts entries and the trusted certificate are **not** removed here.
  # Both are system state that only root can change, and this script never has
  # root (see the check at the top of `main`); they are put in place once by
  # `scripts/setup-testing.sh` and taken away by the same script's `--remove`.
  # Teardown removing them would also mean a run that ends with `--down` silently
  # breaking the browser path for the run after it.

  step 'Removing what this run created'
  local removed=0 path manifest
  # Every manifest, not only this run's. `--down` is usually its own invocation,
  # and that invocation created nothing: the .env files, the certificates and the
  # mount points it has to remove were recorded by the runs that came before it.
  # RUN_DIR is deleted at the end of this function, so those manifests are the
  # only record of what a run created and this is the last chance to read them.
  #
  # Removal goes through `remove_generated_tree`, which falls back to deleting
  # inside a throwaway container when the path belongs to a container's uid. This
  # loop used a bare `rm -rf` and was the one place that did not, so a root-owned
  # directory was reported as an error the host cannot act on:
  #
  #   rm: cannot remove '.../Authentik/data/postgres': Permission denied
  #
  # The documented contract is that nothing about removing generated state needs
  # privilege (Testing.md, "Removing generated state"), and the mechanism for it
  # already existed two functions away.
  local manifest_claimed=''
  for manifest in "${RUN_DIR}"/created-*.manifest; do
    [[ -f "${manifest}" ]] || continue
    while IFS= read -r path; do
      [[ -n "${path}" ]] || continue
      manifest_claimed+="${path}"$'\n'
      if [[ -e "${path}" ]]; then remove_generated_tree "${path}" && removed=$((removed + 1)); fi
    done <"${manifest}"
  done

  # Put back every file a run overwrote. Mailcow is the reason this exists: it is
  # configured by its own configurator, which rewrites `mailcow.conf` in place, and
  # a half-restored Mailcow is worse than either state — the file has to match the
  # database it was generated for.
  #
  # Every backup manifest, not only this run's: `--down` is usually its own
  # invocation and created nothing itself.
  local backups original store restored=0
  for backups in "${RUN_DIR}"/backups-*.manifest; do
    [[ -f "${backups}" ]] || continue
    while IFS="$(printf '\t')" read -r original store; do
      [[ -n "${original}" && -f "${store}" ]] || continue
      mkdir -p "$(dirname "${original}")" 2>/dev/null || true
      if cp -a "${store}" "${original}" 2>/dev/null; then
        restored=$((restored + 1))
      else
        warn "could not restore ${original#"${ROOT_DIR}/"} from its backup"
      fi
    done <"${backups}"
  done
  [[ "${restored}" -gt 0 ]] && info "restored ${restored} file(s) a run had overwritten"
  # Runtime directories the applications create on first start: gitignored, and
  # the product of a test run rather than operator data.
  # Zulip's secrets are generated per run: remove the real files, never the
  # committed *.example templates.
  local secret
  for secret in "${ROOT_DIR}"/Zulip/secrets/*; do
    [[ -e "${secret}" ]] || continue
    [[ "${secret}" == *.example ]] && continue
    rm -f "${secret}" && removed=$((removed + 1))
  done
  local runtime_dirs=(
    "${ROOT_DIR}/Authentik/data"
    "${ROOT_DIR}/Filebrowser/data"
    "${ROOT_DIR}/Filebrowser/cache"
    "${ROOT_DIR}/OnlyOffice/data"
    "${ROOT_DIR}/OnlyOffice/logs"
    "${ROOT_DIR}/OnlyOffice/lib"
    "${ROOT_DIR}/OnlyOffice/db"
    "${ROOT_DIR}/Zulip/data"
    "${ROOT_DIR}/Zulip/database"
    "${ROOT_DIR}/Zulip/rabbitmq"
    "${ROOT_DIR}/Zulip/redis"
    "${ROOT_DIR}/Traefik/acme.json"
  )
  local path stubborn=0
  for path in "${runtime_dirs[@]}"; do
    [[ -e "${path}" ]] || continue
    if remove_generated_tree "${path}"; then
      removed=$((removed + 1))
    else
      stubborn=$((stubborn + 1))
    fi
  done
  if [[ "${stubborn}" -gt 0 ]]; then
    warn "${stubborn} runtime path(s) could not be removed"
    info 'they belong to the containers that wrote them; this needs no root, but it'
    info 'does need Docker:  ./scripts/e2e.sh --down   (with the daemon running)'
    info 'or, if the daemon is gone:  sudo ./scripts/setup-testing.sh --ownership'
  fi
  [[ "${DO_KEEP}" -eq 1 ]] || rm -rf "${RUN_DIR}"
  ok "removed ${removed} path(s) created or populated by the run"

  step 'Verifying nothing is left behind'
  local leftovers=0
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    local containers networks volumes
    containers="$(docker ps -a --filter "label=com.docker.compose.project=${COMPOSE_PROJECT}" --format '{{.Names}}' 2>/dev/null || true)"
    networks="$(docker network ls --filter "name=${COMPOSE_PROJECT}" --format '{{.Name}}' 2>/dev/null || true)"
    volumes="$(docker volume ls --filter "name=${COMPOSE_PROJECT}" --format '{{.Name}}' 2>/dev/null || true)"
    for group in "${containers}" "${networks}" "${volumes}"; do
      if [[ -n "${group}" ]]; then
        warn "leftover: $(printf '%s' "${group}" | tr '\n' ' ')"
        leftovers=$((leftovers + 1))
      fi
    done
  fi
  # `.env` is the one generated file an operator is invited to edit, so it is only
  # a leftover when a manifest says a run created it. The check used to be bare
  # existence, which reported the operator's own configuration as a failure on
  # every teardown of a checkout the harness had ever bootstrapped — the manifest
  # that recorded it belongs to a run whose run directory is long gone.
  for path in "${ROOT_DIR}/.env"; do
    [[ -e "${path}" ]] || continue
    if grep -qxF "${path}" <<<"${manifest_claimed}"; then
      warn "leftover file: ${path} (a run created it and it survived removal)"
      leftovers=$((leftovers + 1))
    else
      info "${path#"${ROOT_DIR}/"} was not created by a run: kept"
    fi
  done
  if [[ "${leftovers}" -eq 0 ]]; then
    ok 'no containers, networks, volumes or generated files remain'
  else
    warn "${leftovers} leftover(s) listed above"
  fi
  info 'images were kept, as the contract requires:'
  docker image ls --format '    {{.Repository}}:{{.Tag}} {{.Size}}' 2>/dev/null \
    | grep -E 'workcenter|traefik|filebrowser|onlyoffice|zulip|mailcow' || true
}

clean_everything() {
  stack_down
  step 'Cleaning build output'
  rm -rf "${ROOT_DIR}/dist" "${RUN_DIR}"
  ok 'removed dist/ and the run directory'
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    local images
    images="$(docker image ls --format '{{.Repository}}:{{.Tag}}' | grep -E '^workcenter' || true)"
    if [[ -n "${images}" ]]; then
      while IFS= read -r image; do
        [[ -n "${image}" ]] || continue
        run docker image rmi "${image}" >/dev/null 2>&1 && ok "removed image ${image}" || true
      done <<<"${images}"
    fi
  fi
}

# ---------------------------------------------------------------------------
main() {
  # Refuse to run as root, before anything is created.
  #
  # This is a safety property, not a style preference. Everything the harness
  # writes — the generated `.env` files, the certificates, the runtime state the
  # containers then fill — would belong to root, so the *next* run as the ordinary
  # user could neither read nor replace it, and the fix would be another root
  # command. The one thing that genuinely needs root is one-time setup and lives in
  # `scripts/setup-testing.sh`; a test run needs none of it.
  if [[ "$(id -u)" -eq 0 ]]; then
    printf '\033[31m✖\033[0m %s\n' 'refusing to run as root' >&2
    printf '  Everything this run creates would belong to root, and the next run would\n' >&2
    printf '  then need root to replace it. Run it as yourself:\n' >&2
    printf '      ./scripts/e2e.sh%s\n' "$*" >&2
    printf '  The privileged, one-time setup is a separate script:\n' >&2
    printf '      sudo ./scripts/setup-testing.sh\n' >&2
    exit 1
  fi
  if [[ -n "${SUDO_USER:-}" ]]; then
    printf '\033[31m✖\033[0m %s\n' "refusing to run under sudo (SUDO_USER=${SUDO_USER})" >&2
    printf '  Run ./scripts/e2e.sh as %s, not through sudo.\n' "${SUDO_USER}" >&2
    exit 1
  fi

  parse_args "$@"
  prepare_run_dir
  set_compose_env

  # Teardown first, and without the full dependency check: a broken or stopped
  # Docker daemon is one of the reasons a run has to be cleaned up.
  # A pin bump touches committed files only: no daemon, no stack, no network
  # unless nothing was specified.
  if [[ "${DO_BUMP}" -eq 1 ]]; then
    local target="${ZULIP_VERSION_ARG}"
    if [[ -z "${target}" ]]; then
      target="$(latest_zulip_release)"
      if [[ -z "${target}" ]]; then
        fail "could not read the latest Zulip release from GitHub; pass --zulip-version"
        exit 1
      fi
    fi
    update_zulip_pin "${target}" "${ZULIP_COMMIT_ARG}"
    exit 0
  fi

  if [[ "${DO_CLEAN}" -eq 1 ]]; then
    check_dependencies
    clean_everything
    ok 'clean'
    exit 0
  fi
  if [[ "${DO_HOSTS}" -eq 1 ]]; then
    check_dependencies
    # Report and exit. `--hosts` predates the preflight and is kept as the
    # diagnostic: it says what is missing without refusing to go on, which is what
    # you want when you are working out *why* a page will not load.
    ensure_env_file
    check_browser_prerequisites
    exit 0
  fi
  if [[ "${DO_TRUST_CERT}" -eq 1 ]]; then
    check_dependencies
    # `.env` carries the hostnames the certificate has to name, so it is generated
    # first — and the certificate itself is created here if it does not exist yet,
    # by the same `localca_ensure` the setup script calls. What this cannot do is
    # *trust* it: that writes to system stores only root may change, which is the
    # whole reason `scripts/setup-testing.sh` exists.
    ensure_env_file
    step 'Certificate prerequisites'
    if [[ -f "${ROOT_DIR}/Traefik/certs/local-ca.crt" ]]; then
      ok 'Traefik/certs/local-ca.crt exists'
      info 'trust it with:  sudo ./scripts/setup-testing.sh --trust-cert'
    else
      fail 'Traefik/certs/local-ca.crt was not generated'
      exit 1
    fi
    exit 0
  fi
  if [[ "${DO_DOWN}" -eq 1 ]]; then
    check_dependencies
    stack_down
    ok 'everything stopped'
    exit 0
  fi

  check_dependencies

  if [[ "${MODE}" == "shell-only" ]]; then
    shell_only_build
    shell_only_up
    print_manual_checks
    exit 0
  fi

  # **Before anything is built.** The harness exists so that a person can open the
  # result; a deploy that cannot be opened has not been verified, and discovering
  # that after ten minutes of building is the failure this gate prevents. It checks
  # only what `scripts/setup-testing.sh` provides — the seven hostnames and the
  # authority in a trust store — and says exactly how to supply them.
  [[ "${DO_BROWSER}" -eq 1 ]] && require_browser_preflight

  [[ -f "${COMPOSE_TEST_FILE}" ]] || { fail "the local test profile is missing: ${COMPOSE_TEST_FILE}"; exit 1; }
  ensure_env_file
  ensure_app_env_files
  ensure_identity_secrets
  ensure_shell_config
  ensure_identity_config
  ensure_zulip_secrets
  ensure_zulip_identity
  ensure_mount_points
  # Mailcow's own configurator, before anything is deployed. `stack_up` brings
  # Mailcow up at its end, so this has to have run by then — and a Mailcow without a
  # configuration does not fail politely: it fails as a service whose nginx cannot
  # bind and whose Traefik rule interpolates to `Host()`.
  ensure_mailcow_config
  # Before the images: this is what decides which Zulip tag the run uses, and
  # ensure_images pulls whatever the pin ends up being.
  report_zulip_release
  ensure_images
  build_image
  verify_secret_files
  verify_credential_state
  stack_up
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    step 'Dry run'
    info 'stopping here: nothing was built, deployed or started'
    printf '  Run it for real with: ./scripts/e2e.sh%s\n' "$([[ "${WITH_MAILCOW}" -eq 0 ]] && echo ' --no-mailcow')"
    exit 0
  fi
  wait_healthy
  DEPLOY_ACTIVE=0
  # Authentik was configured inside `stack_up`, before the rest of the stack: it has
  # to exist before FileBrowser starts, because FileBrowser's discovery at startup
  # is fatal (IN-3.6). What is left here is Mailcow, which is an OIDC client like
  # the others but runs its own project and its own database.
  ensure_mailcow_identity
  # Before the checks, because several of them read the Chat host: an organization
  # is what makes that host serve anything at all (IN-5.30), and the test admin
  # belongs to it (IN-5.31).
  ensure_zulip_organization
  ensure_zulip_admin
  # The identities that actually sign in through the provider, as opposed to the
  # local administrator above — see `ensure_zulip_members` for why both are needed.
  ensure_zulip_members
  [[ "${DO_HOSTS}" -eq 1 ]] && check_browser_prerequisites
  run_checks
  print_test_accounts
  print_manual_checks

  if [[ "${DO_KEEP}" -eq 1 ]]; then
    info 'the stack is left running (--keep)'
  else
    info 'the stack is left running so the manual checks can be walked'
    printf '  Stop it when finished: ./scripts/e2e.sh --down\n'
  fi
}

main "$@"
