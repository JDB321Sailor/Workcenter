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
#   ./scripts/e2e.sh --hosts         # map the six hostnames to 127.0.0.1 for a browser
#   ./scripts/e2e.sh --dry-run       # print what it would do, in order
#   ./scripts/e2e.sh --help
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
readonly RUN_DIR="${ROOT_DIR}/user-data/e2e"
readonly RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
readonly LOG_DIR="${RUN_DIR}/logs/${RUN_ID}"
readonly MANIFEST="${RUN_DIR}/created-${RUN_ID}.manifest"
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
  --hosts           Make the stack usable from a browser on this machine: add the
                    six hostnames to /etc/hosts pointing at 127.0.0.1, and trust
                    the local test certificate — a frame whose certificate does
                    not validate is not rendered at all, so the panes stay blank
                    without it. Both are removed again on --down. Needs root.
  --trust-cert      Install the local test certificate into this machine's system
                    trust store and into the certificate store of every browser
                    profile that belongs to the invoking user, then exit. No stack
                    is touched: use it to fix a browser that still reports the
                    certificate as untrusted. Needs root for the system store; the
                    browser stores are written as their owner.
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

prepare_run_dir() {
  mkdir -p "${LOG_DIR}"
  : >"${LOG_DIR}/harness.log"
  : >"${MANIFEST}"
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

  # The local profile needs a certificate: Traefik serves it as the default when
  # no ACME resolver answers, and there is no DNS name to validate here. It has to
  # name every hostname this run serves — not only the shell's — because the shell
  # reaches the applications through Traefik by those names and *verifies* what it
  # is given (NODE_EXTRA_CA_CERTS, broker.md §10.2). A certificate that names one
  # of them leaves the broker reporting the others unreachable, and gives a browser
  # a hostname mismatch where the honest warning is only an untrusted issuer.
  #
  # It is a **CA plus a leaf**, not the single self-signed certificate this used to
  # generate, and the difference is not cosmetic:
  #
  #   * `openssl req -x509` writes `Basic Constraints: critical CA:TRUE` into the
  #     certificate it produces, and that certificate was then used as the *server*
  #     certificate. OpenSSL, curl, Chrome and NSS's own `certutil -V` all accept
  #     that. **Firefox does not**: it verifies with mozillapkix, which refuses a
  #     CA certificate used as an end entity —
  #     `MOZILLA_PKIX_ERROR_CA_CERT_USED_AS_END_ENTITY`. Firefox then refuses the
  #     connection outright, so the shell shows its "untrusted certificate" page
  #     and every pane is blank, no matter what is installed into any trust store:
  #     the profile's `cert9.db` can hold the certificate with trust `C,,`, the
  #     system store can hold it, and `curl` can verify every hostname, and Firefox
  #     still refuses to load the page.
  #   * A leaf with `CA:FALSE`, `keyUsage` and `extendedKeyUsage=serverAuth`, signed
  #     by a long-lived local CA, is a shape every client accepts.
  #
  # The CA is the only thing a trust store ever receives, so re-signing a leaf does
  # not invalidate a trust decision an operator already made.
  local san="DNS:localhost,DNS:${WORKCENTER_HOST},DNS:${FILEBROWSER_HOST},DNS:${CHAT_HOST},DNS:${MAIL_HOST},DNS:${OFFICE_HOST},IP:127.0.0.1"
  local ca_crt="${ROOT_DIR}/Traefik/certs/local-ca.crt"
  local ca_key="${ROOT_DIR}/Traefik/certs/local-ca.key"
  local leaf_crt="${ROOT_DIR}/Traefik/certs/local.crt"
  local leaf_key="${ROOT_DIR}/Traefik/certs/local.key"
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would generate: Traefik/certs/local-ca.{crt,key} and Traefik/certs/local.{crt,key} (%s)\n' "${san}"
  elif [[ ! -f "${leaf_crt}" || ! -f "${ca_crt}" ]] \
      || [[ "$(openssl x509 -in "${leaf_crt}" -noout -issuer 2>/dev/null | sed 's/^issuer=//')" \
            == "$(openssl x509 -in "${leaf_crt}" -noout -subject 2>/dev/null | sed 's/^subject=//')" ]]; then
    # Missing, or the self-signed shape this script used to generate — which is
    # itself the issuer, which is why Firefox refuses it. A certificate the
    # *operator* put here is signed by their own authority and is left alone by the
    # check below.
    require_tool openssl 'needed to generate the local certificate'
    local csr="${ROOT_DIR}/Traefik/certs/local.csr"
    {
      openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "${ca_key}" -out "${ca_crt}" \
        -subj '/CN=Workcenter local test CA' \
        -addext 'basicConstraints=critical,CA:TRUE' \
        -addext 'keyUsage=critical,keyCertSign,cRLSign'
      openssl req -newkey rsa:2048 -nodes -keyout "${leaf_key}" -out "${csr}" \
        -subj '/CN=Workcenter local test' \
        -addext "subjectAltName=${san}"
      openssl x509 -req -in "${csr}" -CA "${ca_crt}" -CAkey "${ca_key}" -CAcreateserial \
        -days 30 -out "${leaf_crt}" \
        -extfile <(printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=%s\n' "${san}")
    } >"${LOG_DIR}/certificate.log" 2>&1
    rm -f "${csr}" "${ROOT_DIR}/Traefik/certs/local-ca.srl"
    record_created "${ca_crt}" "${ca_key}" "${leaf_crt}" "${leaf_key}"
    ok 'generated the local certificate authority and a leaf certificate it signs'
    info 'the authority is what a trust store receives: Traefik/certs/local-ca.crt'
  elif ! openssl x509 -in "${leaf_crt}" -noout -ext subjectAltName 2>/dev/null \
      | grep -qiF "DNS:${FILEBROWSER_HOST}"; then
    # An operator may have put a certificate they trust here on purpose, so this is
    # a warning with the remedy rather than a regeneration.
    warn "Traefik/certs/local.crt does not name ${FILEBROWSER_HOST}"
    warn 'the shell will report the applications unreachable: remove Traefik/certs/local.crt and'
    warn 'Traefik/certs/local.key, then re-run, to generate one covering every test hostname'
  else
    info 'local certificate already present'
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
  for folder in Traefik Filebrowser OnlyOffice Zulip; do
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
    "${ROOT_DIR}/Mailcow/data"
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
  # write into these directories. A root-owned bind-mount source is the classic
  # "container starts, first write fails" report, so fix the ownership here when
  # the harness is root; on a host where it is not, say so and carry on.
  if [[ "${DO_DRY_RUN}" -eq 0 ]]; then
    local owned=0
    for dir in "${ROOT_DIR}/Filebrowser/data" "${ROOT_DIR}/Filebrowser/office-cache" \
               "${FILEBROWSER_SOURCE_PATH:-}"; do
      [[ -n "${dir}" && -d "${dir}" ]] || continue
      if chown -R 1000:1000 "${dir}" 2>/dev/null; then
        owned=$((owned + 1))
      fi
    done
    [[ "${owned}" -gt 0 ]] && info "set uid 1000 ownership on ${owned} directory(ies)"
  fi
  ok "created ${created} missing mount point(s)"
}

set_compose_env() {
  # Local testing: no ACME (no DNS), loopback publishing, no OIDC yet (Phase 5).
  export TRAEFIK_CERT_RESOLVER="${TRAEFIK_CERT_RESOLVER:-}"
  export WORKCENTER_HOST="${WORKCENTER_HOST:-workcenter.local}"
  export FILEBROWSER_HOST="${FILEBROWSER_HOST:-filebrowser.workcenter.local}"
  export CHAT_HOST="${CHAT_HOST:-chat.workcenter.local}"
  export MAIL_HOST="${MAIL_HOST:-mail.workcenter.local}"
  export OFFICE_HOST="${OFFICE_HOST:-office.workcenter.local}"
  export BASE_URL="${BASE_URL:-https://${WORKCENTER_HOST}}"
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
# setup.sh (Phase 4) has the same obligation for a real deployment; the reason
# is written up in production.md §5.2.
# ---------------------------------------------------------------------------
own_for_container() {
  local path="$1" uid="$2" why="$3"
  [[ -f "${path}" ]] || return 0
  if [[ "${DO_DRY_RUN}" -eq 1 ]]; then
    printf '   would give %s to uid %s (read by %s)\n' "${path#"${ROOT_DIR}/"}" "${uid}" "${why}"
    return 0
  fi
  if [[ "$(stat -c %u "${path}")" -eq "${uid}" ]] || chown "${uid}:${uid}" "${path}" 2>/dev/null; then
    chmod 600 "${path}"
  else
    chmod 644 "${path}"
    warn "$(basename "${path}") cannot be owned by uid ${uid} here (not root): left readable so ${why} can start"
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
# the run created and nothing else. setup.sh (Phase 4) generates the same files
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
        # issued by Zulip itself (IN-5.17, Phase 6). The template is copied so the
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
  # documents keep the reviewed pin, and setup.sh (Phase 4) is what changes those.
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

stack_up() {
  step 'Deploying the stack'
  info 'Traefik is the only ingress; every published port is bound to 127.0.0.1'
  # `up -d`, not `up --wait`: Compose aborts on the first unhealthy report, which
  # for a cold deployment is Zulip still running its first-boot migrations. The
  # health budget is the operator's (--wait), and wait_healthy below applies it
  # while reporting progress.
  local recreate=()
  if [[ "${SECRETS_CHANGED}" -eq 1 ]]; then
    # Every service that reads a secret file at start must be recreated, not
    # reused: `up -d` would otherwise leave the previous credentials in place.
    recreate=(--force-recreate)
    info 'a secret changed this run: recreating the containers so none keeps the old one'
  fi
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

  compose up -d "${recreate[@]}" 2>&1 | tee -a "${LOG_DIR}/up.log"
  # `--force-recreate` (a secret changed) recreates Traefik as well, and a recreated
  # container is not promised the address it held a moment ago. Re-read it, and if
  # it moved, hand Zulip the address it has now: Zulip's nginx is the only reader,
  # so recreating Zulip alone is enough.
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

# Mailcow is driven from its own directory with no `-f`, so Docker merges
# Workcenter's override (integration.md IN-6.3).
bring_up_mailcow() {
  step 'Mailcow'
  if [[ ! -f "${ROOT_DIR}/Mailcow/docker-compose.yml" || ! -f "${ROOT_DIR}/Mailcow/mailcow.conf" ]]; then
    warn 'Mailcow is not initialised in this checkout (Phase 4 runs its own setup)'
    warn 'the Mail pane will not be testable this run'
    return 0
  fi
  if ! run docker compose -f "${ROOT_DIR}/Mailcow/docker-compose.yml" \
      --project-name mailcow --project-directory "${ROOT_DIR}/Mailcow" \
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

check_restart_loops() {
  local id name count looping=0
  while IFS= read -r id; do
    [[ -n "${id}" ]] || continue
    name="$(docker inspect "${id}" --format '{{.Name}}' 2>/dev/null | tr -d '/')"
    count="$(docker inspect "${id}" --format '{{.RestartCount}}' 2>/dev/null || echo 0)"
    [[ "${count}" =~ ^[0-9]+$ ]] || count=0
    if [[ "${count}" -gt "${MAX_RESTARTS}" ]]; then
      fail "${name} has restarted ${count} times (limit ${MAX_RESTARTS}): it is crash-looping"
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
  # The Files testing account: the login a person types into the pane. `admin` is
  # FileBrowser's built-in admin username, and FILEBROWSER_ADMIN_PASSWORD is what
  # this run set as its password (IN-3.26), so a wiring regression fails here
  # rather than during the manual walk. The password is never printed.
  local fb_login
  fb_login="$("${CURL_BASE[@]}" -o /dev/null -w '%{http_code}' -X POST \
    -H "X-Password: ${FILEBROWSER_ADMIN_PASSWORD}" \
    --resolve "${FILEBROWSER_HOST}:443:127.0.0.1" \
    "https://${FILEBROWSER_HOST}/api/auth/login?username=admin" 2>/dev/null || echo '000')"
  if [[ "${fb_login}" == "200" ]]; then
    ok 'Files admin login works (admin)'
  else
    fail "Files admin login: ${FILEBROWSER_HOST}/api/auth/login -> ${fb_login} (expected 200)"
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
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
  local fb_password='admin'
  [[ "${FILEBROWSER_ADMIN_PASSWORD}" == "admin" ]] || fb_password='<FILEBROWSER_ADMIN_PASSWORD>'
  local zl_password='admin1234'
  [[ "${ZULIP_ADMIN_PASSWORD}" == "admin1234" ]] || zl_password='<ZULIP_ADMIN_PASSWORD>'
  printf '  Files (FileBrowser Quantum)\n'
  printf '    admin / %s   at https://%s\n' "${fb_password}" "${FILEBROWSER_HOST}"
  printf '  Chat (Zulip)\n'
  printf '    %s / %s   at https://%s\n' "${ZULIP_ADMIN_EMAIL}" "${zl_password}" "${CHAT_HOST}"
  printf '    Zulip signs in with the email address, not a username; the account is a realm owner.\n'
}

# ---------------------------------------------------------------------------
# The manual checklist
# ---------------------------------------------------------------------------
print_manual_checks() {
  step 'Manual checks — Phase 3 (deployment skeleton)'
  cat <<'EOF'
  [ ] `docker compose ps` shows every service healthy, and none of them had to
      restart to get there.
  [ ] Each hostname serves its application over HTTPS once the hostnames resolve
      to this machine (`--hosts` does that): the shell, Filebrowser, Zulip,
      ONLYOFFICE and Mailcow/SOGo.
  [ ] The certificate is the expected one: the local self-signed certificate in
      the test profile, and a real Let's Encrypt certificate on a host with DNS.
  [ ] No application publishes a port to the host: `docker compose ps` shows
      Traefik's ports only, and the applications show `expose`.
  [ ] Traefik's dashboard is not reachable unauthenticated (Phase 5 adds
      forward-auth) and `api.insecure` is false.
  [ ] Mailcow answers on its own hostname with Workcenter's override applied: no
      published ports, `TRUSTED_PROXIES` set, and its four added healthchecks
      reporting healthy.
  [ ] The Chat pane embeds: `curl -sI https://chat.<domain>/` carries the
      `Content-Security-Policy: frame-ancestors <shell origin>` Traefik's
      `security-headers@file` middleware sets on the `zulip` router. That header is
      what makes Zulip framable — the image is upstream and still sends
      `X-Frame-Options: DENY`, which a browser ignores once `frame-ancestors` is
      present (integration.md §8.4).
  [ ] All five Zulip services are up: trimming them is not permitted.
  [ ] The Mail pane embeds from the shell's origin, or the pane reports `blocked`
      honestly if the deployment has not applied the nginx override.

  The Phase 2 checks still hold (the shell):

  [ ] The brand header reads "Workcenter - Admin" for an administrator and
      "Workcenter - User" for everyone else, and the word disappears when the
      rail is collapsed.
  [ ] The user row shows initials, the stacked name, the sun/moon button and the
      language button; the menu holds identity, the admin links and Sign out.
  [ ] Dark is the default; the sun switches to light and the moon switches back.
  [ ] The language button shows a rounded flag and the two-letter code; opening
      it lists every language in its own characters and spelling.
  [ ] Collapsing the rail leaves the initials button alone, and its menu stays
      full size with the preference controls reachable.
EOF
  step 'What comes next'
  cat <<'EOF'
  - Sign-in and OIDC are Phase 5: until then the panes are reached
    unauthenticated, which is why this harness binds Traefik to 127.0.0.1.
  - The six transfer flows are Phase 6; the automated checks cover the plumbing
    they will use, not the flows themselves.
  - Playwright takes over these checks in Phase 7; see Testing.md.
EOF
  printf '\n  Open:  https://%s/   (add --hosts to reach it from a browser)\n' "${WORKCENTER_HOST}"
  printf '  Stop:  ./scripts/e2e.sh --down\n\n'
}

# ---------------------------------------------------------------------------
# Host entries (opt-in)
# ---------------------------------------------------------------------------
HOSTS_MARKER_BEGIN="# >>> workcenter e2e >>>"
HOSTS_MARKER_END="# <<< workcenter e2e <<<"

add_hosts_entries() {
  step 'Host entries'
  if grep -q "${HOSTS_MARKER_BEGIN}" /etc/hosts 2>/dev/null; then
    info 'host entries already present'
  elif printf '%s\n127.0.0.1 %s %s %s %s %s\n%s\n' \
      "${HOSTS_MARKER_BEGIN}" "${WORKCENTER_HOST}" "${FILEBROWSER_HOST}" \
      "${CHAT_HOST}" "${MAIL_HOST}" "${OFFICE_HOST}" "${HOSTS_MARKER_END}" \
      >>/etc/hosts 2>/dev/null; then
    ok 'added the six hostnames to /etc/hosts'
  else
    warn 'could not write /etc/hosts (needs root); use curl --resolve instead'
  fi
  # A browser needs both halves: a name that resolves, and a certificate it will
  # accept. Without the second, every pane is a blank frame — see the function.
  trust_local_certificate
}

# ---------------------------------------------------------------------------
# Making the test certificate trusted by a browser
#
# The test profile serves a self-signed certificate (there is no DNS name for ACME
# to validate). `curl --insecure` does not care, but a browser does: a frame whose
# certificate does not validate is **not rendered at all**, so the Files and Chat
# panes stay blank while both applications are healthy, correctly routed and
# correctly framed. That is the "the iframes are not loading" report.
#
# The certificate is its own CA (`Basic Constraints: CA:TRUE`) and names all six
# hostnames, so trusting it once is enough for every pane. It is installed into the
# system store, which curl and Chrome read on Linux; Firefox keeps its own store,
# so that step is printed rather than guessed at. Removing it again is part of
# `--down`, like the /etc/hosts block.
# ---------------------------------------------------------------------------
readonly TRUST_STORE_NAME="workcenter-local-test"

# ---------------------------------------------------------------------------
# Where *this* distribution keeps a locally-trusted certificate
#
# There is no single answer, and assuming one installs a certificate that nothing
# ever reads while reporting success. The stores are:
#
#   Debian, Ubuntu, Mint   /usr/local/share/ca-certificates          update-ca-certificates
#   Arch, CachyOS, Manjaro /etc/ca-certificates/trust-source/anchors update-ca-trust
#   Fedora, RHEL, CentOS   /etc/pki/ca-trust/source/anchors          update-ca-trust
#   openSUSE               /etc/pki/trust/anchors                    update-ca-certificates
#
# (ArchWiki, "Adding a trusted CA certificate": the p11-kit instructions are for
# Arch and Fedora, and the Debian-style ones "do not apply to Arch Linux". The
# machine states it too — /etc/ca-certificates/trust-source/README on Arch says to
# copy into `anchors/` and run `update-ca-trust`.)
#
# The store belongs to the distribution's ca-certificates package, so this never
# creates one: a directory that is not there is not read by anything, and writing
# into it would look like success. When none of the four is present, p11-kit's own
# `trust anchor --store` is used instead, because that tool knows the layout of the
# machine it is running on.
#
# Echoes "<directory>|<refresh command>", or "p11-kit|trust anchor", or nothing.
# ---------------------------------------------------------------------------
ca_trust_anchor() {
  local dir refresh
  while IFS='|' read -r dir refresh; do
    [[ -n "${dir}" ]] || continue
    if [[ -d "${dir}" ]] && command -v "${refresh}" >/dev/null 2>&1; then
      printf '%s|%s' "${dir}" "${refresh}"
      return 0
    fi
  done <<'STORES'
/usr/local/share/ca-certificates|update-ca-certificates
/etc/ca-certificates/trust-source/anchors|update-ca-trust
/etc/pki/ca-trust/source/anchors|update-ca-trust
/etc/pki/trust/anchors|update-ca-certificates
STORES
  if command -v trust >/dev/null 2>&1; then
    printf 'p11-kit|trust anchor'
  fi
  return 0
}

# Re-read the stores after a change. The detected store's own tool when there is
# one, otherwise whichever of the two exists.
refresh_trust_store() {  local anchor refresh
  anchor="$(ca_trust_anchor)"
  refresh="${anchor##*|}"
  case "${refresh}" in
    update-ca-certificates|update-ca-trust)
      "${refresh}" >/dev/null 2>&1 || true
      return 0
      ;;
  esac
  if command -v update-ca-trust >/dev/null 2>&1; then
    update-ca-trust >/dev/null 2>&1 || true
  elif command -v update-ca-certificates >/dev/null 2>&1; then
    update-ca-certificates >/dev/null 2>&1 || true
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Whose browsers to trust the certificate for
#
# Under `sudo`, `$HOME` is root's, so the per-user stores have to be found through
# `SUDO_USER`: looking under `/root` would write a database no browser on the
# desktop reads, and report success while doing it — the same class of mistake as
# assuming one distribution's system store.
# ---------------------------------------------------------------------------
browser_user() {
  local user="${SUDO_USER:-}"
  if [[ -z "${user}" || "${user}" == "root" ]] || ! id -u "${user}" >/dev/null 2>&1; then
    user="$(id -un)"
  fi
  printf '%s' "${user}"
}

browser_home() {
  local home
  home="$(getent passwd "$(browser_user)" 2>/dev/null | cut -d: -f6)"
  [[ -n "${home}" ]] || home="${HOME}"
  printf '%s' "${home}"
}

# Every NSS database a browser on this machine may read. Firefox keeps one per
# profile and the location depends on the version: `~/.mozilla/firefox` before
# Firefox 129 and `~/.config/mozilla/firefox` after it (Firefox 157 on CachyOS,
# verified against a running browser's open files). Snap and Flatpak keep their own
# trees. Chromium, Chrome, Brave and Vivaldi share `~/.pki/nssdb`.
browser_nss_databases() {
  local home dir
  home="$(browser_home)"
  for dir in "${home}"/.config/mozilla/firefox/*/ \
             "${home}"/.mozilla/firefox/*/ \
             "${home}"/snap/firefox/common/.mozilla/firefox/*/ \
             "${home}"/.var/app/org.mozilla.firefox/.mozilla/firefox/*/ \
             "${home}"/.var/app/org.mozilla.firefox/.config/mozilla/firefox/*/; do
    [[ -f "${dir}cert9.db" ]] && printf '%s\n' "${dir%/}"
  done
  [[ -f "${home}/.pki/nssdb/cert9.db" ]] && printf '%s\n' "${home}/.pki/nssdb"
  return 0
}

# Run a command as the browser's user: a root-owned `cert9.db` inside someone's
# profile is a browser that can no longer write its own store.
as_browser_user() {
  local user
  user="$(browser_user)"
  if [[ "$(id -u)" -ne 0 || "${user}" == "$(id -un)" ]]; then
    "$@"
  elif command -v runuser >/dev/null 2>&1; then
    runuser -u "${user}" -- "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -u "${user}" -- "$@"
  else
    return 127
  fi
}

# The name of a running browser, or nothing. A store written while the browser is
# up may not be re-read until it restarts, which is worth saying rather than
# leaving as a mystery.
browser_is_running() {
  local user name
  user="$(browser_user)"
  for name in firefox firefox-bin firefox-esr chromium chrome brave vivaldi; do
    if pgrep -u "${user}" -x "${name}" >/dev/null 2>&1; then
      printf '%s' "${name}"
      return 0
    fi
  done
  return 0
}

trust_local_certificate() {
  # The **authority**, not the leaf: the leaf is the certificate the stack serves,
  # and a trust store must never receive it (it is also CA:FALSE, so no store would
  # accept it as an anchor). `local-ca.crt` is stable while leaves are re-signed.
  local cert="${ROOT_DIR}/Traefik/certs/local-ca.crt"
  local anchor dir refresh target="" installed=0
  if [[ ! -f "${cert}" ]]; then
    warn "Traefik/certs/local-ca.crt is missing: run once without --down to generate it"
    return 0
  fi
  anchor="$(ca_trust_anchor)"
  dir="${anchor%%|*}"
  refresh="${anchor##*|}"
  if [[ "${dir}" == "p11-kit" ]]; then
    # No known store on this machine: let p11-kit write its own layout.
    if trust anchor --store "${cert}" >/dev/null 2>&1; then
      ok 'trusted the local certificate through p11-kit (system-wide)'
      installed=1
    fi
  elif [[ -n "${dir}" ]]; then
    target="${dir}/${TRUST_STORE_NAME}.crt"
    if [[ -f "${target}" ]] && cmp -s "${cert}" "${target}"; then
      info "the local certificate authority is already trusted in ${dir}"
      installed=1
    elif install -m 644 "${cert}" "${target}" 2>/dev/null && refresh_trust_store; then
      ok "trusted the local certificate authority in ${dir} (${refresh})"
      installed=1
    fi
  fi
  # ---------------------------------------------------------------------------
  # The browsers' own stores
  #
  # Firefox keeps a certificate database per profile and does **not** read the
  # system store by default: on a machine where the anchor above is installed and
  # the consolidated bundle verifies every hostname, `certutil -d sql:<profile> -h
  # all -L` still lists no such anchor and Firefox shows "untrusted certificate" —
  # so the shell is reached with an exception and the panes, whose origins each need
  # their own, are never rendered at all (a frame whose TLS fails is blank, with no
  # interstitial to accept). `security.enterprise_roots.enabled` makes Firefox read
  # the system anchors, but it is not set by default and it is Firefox's choice, not
  # the deployment's, so the certificate is written where Firefox looks.
  # ---------------------------------------------------------------------------
  if command -v certutil >/dev/null 2>&1; then
    local db databases=0
    while IFS= read -r db; do
      [[ -n "${db}" ]] || continue
      databases=$((databases + 1))
      # Compare what is stored with the authority **by fingerprint**: the nickname
      # survives a change of certificate shape, so "the nickname exists" is not the
      # same as "this certificate is trusted" — that mistake would leave the old,
      # unusable self-signed certificate in place for ever, reporting success. PEM
      # bytes would not do either: `certutil` re-encodes what it exports, so a
      # byte comparison never matches and every run rewrites the entry.
      local stored_fp file_fp
      # `|| true`: a profile that does not hold the nickname yet — the normal first
      # run, and every fresh browser profile — makes `certutil -L -n` exit non-zero
      # with no output, and `openssl` then fails on empty input. Under `pipefail`
      # that aborted the whole run before the certificate could be installed at all.
      # An empty fingerprint is simply "not stored", which the comparison below
      # already handles.
      stored_fp="$(as_browser_user certutil -d "sql:${db}" -L -n "${TRUST_STORE_NAME}" -a 2>/dev/null \
        | openssl x509 -noout -fingerprint -sha256 2>/dev/null || true)"
      file_fp="$(openssl x509 -in "${cert}" -noout -fingerprint -sha256 2>/dev/null)"
      if [[ -n "${stored_fp}" && "${stored_fp}" == "${file_fp}" ]]; then
        info "the local certificate authority is already in ${db}"
        installed=1
        continue
      fi
      # `|| true`: `-D` exits non-zero when the nickname is not there, which is the
      # normal first run and every profile this script has not written yet. The `-A`
      # below is the command whose result matters.
      as_browser_user certutil -d "sql:${db}" -D -n "${TRUST_STORE_NAME}" >/dev/null 2>&1 || true
      if as_browser_user certutil -d "sql:${db}" -A -t 'C,,' \
          -n "${TRUST_STORE_NAME}" -i "${cert}" 2>/dev/null; then
        ok "trusted the local certificate authority in ${db}"
        installed=1
      else
        warn "could not write the certificate into ${db}"
      fi
    done < <(browser_nss_databases)
    if [[ "${databases}" -eq 0 ]]; then
      info "no browser certificate store was found for $(browser_user)"
    else
      # In a variable, not in the condition: a command substitution in `elif` would
      # print the browser's name before the warning it belongs to.
      local running
      running="$(browser_is_running)"
      if [[ -n "${running}" ]]; then
        warn "${running} is running: restart it for the new trust to take effect"
      fi
    fi
  fi
  if [[ "${installed}" -eq 0 ]]; then
    warn 'a browser will not render the panes until this certificate is trusted:'
    if [[ -n "${target}" ]]; then
      warn "  sudo install -m 644 Traefik/certs/local-ca.crt ${target} && sudo ${refresh}"
    elif [[ "${dir}" == "p11-kit" ]]; then
      warn '  sudo trust anchor --store Traefik/certs/local-ca.crt'
    else
      warn 'no certificate store was recognised on this machine; trust it by hand:'
      warn '  Arch/Fedora:   sudo trust anchor --store Traefik/certs/local-ca.crt'
      warn '  Fedora/RHEL:   sudo install -m 644 Traefik/certs/local-ca.crt /etc/pki/ca-trust/source/anchors/ && sudo update-ca-trust'
      warn '  Debian/Ubuntu: sudo install -m 644 Traefik/certs/local-ca.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates'
      warn '  openSUSE:      sudo install -m 644 Traefik/certs/local-ca.crt /etc/pki/trust/anchors/ && sudo update-ca-certificates'
    fi
  fi
  if [[ "${databases:-0}" -eq 0 ]]; then
    info 'Firefox does not read the system store on its own: either import'
    info 'Traefik/certs/local-ca.crt under Settings → Privacy & Security → Certificates →'
    info 'View Certificates → Authorities, or set security.enterprise_roots.enabled to true'
  fi
}

remove_trusted_certificate() {
  local removed=0 dir
  # Every store, not only the one this distribution uses: a certificate installed by
  # an earlier run of an older script (which assumed Debian) still has to come out.
  for dir in /usr/local/share/ca-certificates /etc/ca-certificates/trust-source/anchors \
             /etc/pki/ca-trust/source/anchors /etc/pki/trust/anchors; do
    [[ -f "${dir}/${TRUST_STORE_NAME}.crt" ]] || continue
    if rm -f "${dir}/${TRUST_STORE_NAME}.crt"; then
      removed=1
    else
      warn "could not remove ${dir}/${TRUST_STORE_NAME}.crt"
    fi
  done
  # p11-kit may have stored it under a name of its own (`trust anchor --store`).
  # Best-effort, and never counted as a removal: `trust anchor --remove` exits 0
  # even when nothing matched, so the `rm` above and `certutil -D` below are the
  # only proof that something actually came out.
  if command -v trust >/dev/null 2>&1; then
    # Needs root for the system store, and fails for a certificate that is not
    # there: `|| true` because a failure here is not a failure of the teardown.
    trust anchor --remove "${ROOT_DIR}/Traefik/certs/local-ca.crt" >/dev/null 2>&1 || true
  fi
  [[ "${removed}" -eq 1 ]] && refresh_trust_store
  # The browsers' own stores, which is where the panes were made to load.
  if command -v certutil >/dev/null 2>&1; then
    local db
    while IFS= read -r db; do
      [[ -n "${db}" ]] || continue
      # `|| true`: certutil exits non-zero when the nickname is not there, which is
      # the common case, and `set -e` would otherwise abort the teardown.
      as_browser_user certutil -d "sql:${db}" -D -n "${TRUST_STORE_NAME}" 2>/dev/null \
        && removed=1 || true
    done < <(browser_nss_databases)
  fi
  if [[ "${removed}" -eq 1 ]]; then
    ok 'removed the local certificate from the trust store'
  else
    info 'the local certificate was not in a trust store'
  fi
  return 0
}

remove_hosts_entries() {
  grep -q "${HOSTS_MARKER_BEGIN}" /etc/hosts 2>/dev/null || return 0
  if sed -i "/${HOSTS_MARKER_BEGIN}/,/${HOSTS_MARKER_END}/d" /etc/hosts 2>/dev/null; then
    ok 'removed the host entries'
  else
    warn 'could not clean /etc/hosts'
  fi
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
      run docker compose -f "${ROOT_DIR}/Mailcow/docker-compose.yml" \
        --project-name mailcow --project-directory "${ROOT_DIR}/Mailcow" \
        down -v --remove-orphans --timeout 30 >>"${LOG_DIR}/down.log" 2>&1 \
        || warn 'Mailcow did not stop cleanly; see the log'
    fi
  else
    warn 'docker is unavailable: skipping the stack teardown'
  fi

  stop_shell_servers
  [[ "${DO_HOSTS}" -eq 1 ]] && remove_hosts_entries
  # Unconditional: a certificate trusted by an earlier --hosts run is part of what
  # this run created, and leaving a trust anchor behind is worse than a stale
  # /etc/hosts line. It is a no-op when nothing was installed.
  remove_trusted_certificate

  step 'Removing what this run created'
  local removed=0 path manifest
  # Every manifest, not only this run's. `--down` is usually its own invocation,
  # and that invocation created nothing: the .env files, the certificates and the
  # mount points it has to remove were recorded by the runs that came before it.
  # RUN_DIR is deleted at the end of this function, so those manifests are the
  # only record of what a run created and this is the last chance to read them.
  for manifest in "${RUN_DIR}"/created-*.manifest; do
    [[ -f "${manifest}" ]] || continue
    while IFS= read -r path; do
      [[ -n "${path}" ]] || continue
      if [[ -e "${path}" ]]; then rm -rf "${path}" && removed=$((removed + 1)); fi
    done <"${manifest}"
  done
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
  for path in "${runtime_dirs[@]}"; do
    if [[ -e "${path}" ]]; then rm -rf "${path}" && removed=$((removed + 1)); fi
  done
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
  for path in "${ROOT_DIR}/.env"; do
    [[ -e "${path}" ]] && { warn "leftover file: ${path}"; leftovers=$((leftovers + 1)); }
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
  if [[ "${DO_TRUST_CERT}" -eq 1 ]]; then
    check_dependencies
    # `.env` carries the hostnames the certificate has to name, and generating it
    # here is what makes this usable on its own — a browser fix should not need a
    # deployment.
    ensure_env_file
    step 'Trusting the local certificate'
    trust_local_certificate
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

  [[ -f "${COMPOSE_TEST_FILE}" ]] || { fail "the local test profile is missing: ${COMPOSE_TEST_FILE}"; exit 1; }
  ensure_env_file
  ensure_app_env_files
  ensure_shell_config
  ensure_zulip_secrets
  ensure_mount_points
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
  # Before the checks, because several of them read the Chat host: an organization
  # is what makes that host serve anything at all (IN-5.30), and the test admin
  # belongs to it (IN-5.31).
  ensure_zulip_organization
  ensure_zulip_admin
  [[ "${DO_HOSTS}" -eq 1 ]] && add_hosts_entries
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
