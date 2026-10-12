#!/usr/bin/env bash
# Workcenter — the privileged half of the test environment, run once.
#
# `scripts/e2e.sh` runs the stack and deliberately never needs root. A test
# harness that asks for root teaches people to run it as root, and then everything
# it creates belongs to root and the *next* run needs root again — which is how a
# checkout ends up needing `sudo` for ordinary work. The handful of things that
# genuinely need privilege live here instead, and they are one-time setup rather
# than part of a test run:
#
#   * **/etc/hosts entries**, so a *browser* on this machine resolves the stack's
#     hostnames. `scripts/e2e.sh` reaches the stack with `curl --resolve` and needs
#     none of them; only a browser does.
#   * **the local certificate authority** in the system and per-user trust stores,
#     so a browser stops warning about a certificate it cannot verify.
#   * **ownership of the runtime state** the containers leave behind. Bind mounts
#     make a container's writes the *container's* uid on the host — PostgreSQL's
#     data directory is uid 65534 mode 0700 — so without this the harness cannot
#     delete or reset it.
#
# Usage, from the checkout, as the user who will run `scripts/e2e.sh`:
#
#   sudo ./scripts/setup-testing.sh              # all three
#   sudo ./scripts/setup-testing.sh --hosts      # only the /etc/hosts entries
#   sudo ./scripts/setup-testing.sh --trust-cert # only the certificate authority
#   sudo ./scripts/setup-testing.sh --ownership  # only the file ownership
#   sudo ./scripts/setup-testing.sh --remove     # undo the entries and the CA
#
# The user is taken from `SUDO_USER`, so everything ends up owned by the person who
# will actually run the harness and never by root — that is the point of the
# script, not a detail of it.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# The markers the /etc/hosts block is delimited by. They have to be defined here and
# nowhere else: this script writes and removes that block, and a marker that is used
# but never set is an `unbound variable` under `set -u`.
HOSTS_MARKER_BEGIN="# >>> workcenter e2e >>>"
HOSTS_MARKER_END="# <<< workcenter e2e <<<"

# The hostnames the stack answers on. These match `scripts/e2e.sh`'s defaults; a
# run with a different domain passes them the same way it does there.
WORKCENTER_HOST="${WORKCENTER_HOST:-workcenter.local}"
FILEBROWSER_HOST="${FILEBROWSER_HOST:-filebrowser.workcenter.local}"
CHAT_HOST="${CHAT_HOST:-chat.workcenter.local}"
MAIL_HOST="${MAIL_HOST:-mail.workcenter.local}"
OFFICE_HOST="${OFFICE_HOST:-office.workcenter.local}"
# The two hostnames Phase 4 added. They belong in /etc/hosts for the same reason
# as the rest, and for a sharper one: without `auth.` a browser cannot reach the
# identity provider at all, so the sign-in redirect lands on a name that does not
# resolve and the only symptom is a page that never comes back.
AUTHENTIK_HOST="${AUTHENTIK_HOST:-auth.workcenter.local}"
TRAEFIK_HOST="${TRAEFIK_HOST:-traefik.workcenter.local}"

# The file this script writes and unwrites. Overridable so the behaviour can be
# exercised without root — `--remove` is the one operation that must be *exactly*
# right, and "it needs sudo" is not a reason for it to be untestable.
HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"

# Every name the block carries, in one place, so the writer and both removal paths
# agree on what belongs to this deployment.
workcenter_hostnames() {
  printf '%s\n' \
    "${WORKCENTER_HOST}" "${FILEBROWSER_HOST}" "${CHAT_HOST}" "${MAIL_HOST}" \
    "${OFFICE_HOST}" "${AUTHENTIK_HOST}" "${TRAEFIK_HOST}"
}

# Logging, in the same shapes `scripts/e2e.sh` prints.
info() { printf '\033[36mℹ\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '\033[33m⚠\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[31m✖\033[0m %s\n' "$*" >&2; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# The local certificate authority, shared with `scripts/e2e.sh`. The harness reuses
# whatever this script generates, which is what makes the authority a browser trusts
# the same one the stack serves.
# shellcheck source=lib/localca.sh
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/localca.sh"

# The person who will run the harness: `SUDO_USER` when this script was invoked
# through sudo (the normal case), the current user when it was not.
target_user() {
  printf '%s' "${SUDO_USER:-$(id -un)}"
}

# Every action here writes outside the checkout, so root is required — and this is
# the *only* place in the project that is true.
require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    fail 'this script changes system state and must run as root:'
    printf '    sudo %s%s\n' "./scripts/setup-testing.sh" "${1:+ $*}" >&2
    printf '  (%s does not need root and refuses to run with it.)\n' 'scripts/e2e.sh' >&2
    exit 1
  fi
}

add_hosts_entries() {
  step 'Host entries'
  # All seven of the deployment's names, on one line. The list has to grow with the
  # deployment: it held five until Phase 4 added the identity provider and the
  # dashboard, and a browser that cannot resolve `auth.` cannot complete a sign-in.
  local wanted
  wanted="$(printf '127.0.0.1 %s %s %s %s %s %s %s' \
    "${WORKCENTER_HOST}" "${FILEBROWSER_HOST}" "${CHAT_HOST}" "${MAIL_HOST}" \
    "${OFFICE_HOST}" "${AUTHENTIK_HOST}" "${TRAEFIK_HOST}")"

  local current=''
  if grep -qF "${HOSTS_MARKER_BEGIN}" "${HOSTS_FILE}" 2>/dev/null; then
    current="$(sed -n "/${HOSTS_MARKER_BEGIN}/,/${HOSTS_MARKER_END}/p" "${HOSTS_FILE}" 2>/dev/null | sed '1d;$d')"
  fi

  # Stale lines from an older version, which wrote the mapping **without** markers.
  # The marked block only replaces itself, so a machine that ran one keeps its
  # five-name line for ever — resolving a subset of the deployment alongside the
  # current seven, with the two names identity depends on among the missing.
  local tmp
  tmp="$(mktemp)"
  strip_workcenter_hosts "${HOSTS_FILE}" "${tmp}"
  local stale="${HOSTS_DROPPED}"
  # The block itself is three lines and is replaced rather than counted as stale.
  [[ "${current}" != "${wanted}" && -n "${current}" ]] && stale=$((stale - 3))
  [[ "${stale}" -lt 0 ]] && stale=0

  if [[ "${current}" == "${wanted}" && "${stale}" -eq 0 ]]; then
    ok 'host entries already present and current'
    rm -f "${tmp}"
  else
    # **Replace, do not skip.** An append-only block that reports "already present"
    # is how a machine ends up resolving five of the seven names for ever: the
    # check passes, nothing is written, and the two that matter most for identity
    # are the two that are missing.
    printf '%s\n%s\n%s\n' "${HOSTS_MARKER_BEGIN}" "${wanted}" "${HOSTS_MARKER_END}" >>"${tmp}"
    if cat "${tmp}" >"${HOSTS_FILE}" 2>/dev/null; then
      ok 'wrote the deployment’s seven hostnames to /etc/hosts'
      [[ "${stale}" -gt 0 ]] \
        && info "  replaced ${stale} stale entr(y|ies) the older, unmarked format left behind"
    else
      warn "could not write ${HOSTS_FILE} (needs root); use curl --resolve instead"
    fi
    rm -f "${tmp}"
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

# Re-read the stores after a change. The detected store's own tool when there is
# one, otherwise whichever of the two exists.
refresh_trust_store() {
  local anchor refresh
  anchor="$(localca_anchor_dir)"
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
  # **Generate first.** This script is the preflight: it runs *before* the harness,
  # so it cannot wait for the harness to produce the thing it exists to install. It
  # calls the same `localca_ensure` the harness does, which means the authority the
  # trust store receives is the authority the stack will serve — one implementation,
  # so the two cannot drift into two certificates.
  localca_ensure
  # The **authority**, not the leaf: the leaf is the certificate the stack serves,
  # and a trust store must never receive it (it is also CA:FALSE, so no store would
  # accept it as an anchor). `local-ca.crt` is stable while leaves are re-signed.
  local cert="${ROOT_DIR}/Traefik/certs/local-ca.crt"
  local anchor dir refresh target="" installed=0
  if [[ ! -f "${cert}" ]]; then
    fail 'Traefik/certs/local-ca.crt could not be created: a browser cannot be prepared'
    return 1
  fi
  anchor="$(localca_anchor_dir)"
  dir="${anchor%%|*}"
  refresh="${anchor##*|}"
  if [[ "${dir}" == "p11-kit" ]]; then
    # No known store on this machine: let p11-kit write its own layout.
    if trust anchor --store "${cert}" >/dev/null 2>&1; then
      ok 'trusted the local certificate through p11-kit (system-wide)'
      installed=1
    fi
  elif [[ -n "${dir}" ]]; then
    target="${dir}/${LOCALCA_STORE_NAME}.crt"
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
      # that aborted the whole run before the certificate could be installed at all,
      # so `--hosts` died on a machine that had never run it. An empty fingerprint is
      # simply "not stored", which the comparison below already handles.
      #
      # This guard came from `e2e.sh` and had to come with the code when the trust
      # logic moved here; the rebase is what surfaced that it had not.
      stored_fp="$(as_browser_user certutil -d "sql:${db}" -L -n "${LOCALCA_STORE_NAME}" -a 2>/dev/null \
        | openssl x509 -noout -fingerprint -sha256 2>/dev/null || true)"
      file_fp="$(openssl x509 -in "${cert}" -noout -fingerprint -sha256 2>/dev/null)"
      if [[ -n "${stored_fp}" && "${stored_fp}" == "${file_fp}" ]]; then
        info "the local certificate authority is already in ${db}"
        installed=1
        continue
      fi
      # `|| true`: `-D` exits non-zero when the nickname is not there, which is the
      # normal first run. Without the guard the run stops here — before the `-A`
      # that installs the certificate — which is the failure this pair of guards
      # exists to prevent. Carried from `e2e.sh` with the rest of the trust logic.
      as_browser_user certutil -d "sql:${db}" -D -n "${LOCALCA_STORE_NAME}" >/dev/null 2>&1 || true
      if as_browser_user certutil -d "sql:${db}" -A -t 'C,,' \
          -n "${LOCALCA_STORE_NAME}" -i "${cert}" 2>/dev/null; then
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
    [[ -f "${dir}/${LOCALCA_STORE_NAME}.crt" ]] || continue
    if rm -f "${dir}/${LOCALCA_STORE_NAME}.crt"; then
      removed=1
    else
      warn "could not remove ${dir}/${LOCALCA_STORE_NAME}.crt"
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
      as_browser_user certutil -d "sql:${db}" -D -n "${LOCALCA_STORE_NAME}" 2>/dev/null \
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

# Write `$1` to `$2` with every entry this deployment owns taken out, and set
# `HOSTS_DROPPED` to how many lines went.
#
# Two shapes have to come out, and the second is the one that was missed:
#
#   * the **marked block**, which is what the current script writes; and
#   * any **loopback line naming one of the deployment's hostnames**, marked or not.
#     An older version wrote the mapping without markers, and a marked block only
#     ever replaced itself — so `--remove` deleted the block, reported success, and
#     left the older five-name line resolving a subset of the deployment. The
#     machine was not returned to its prior state, which is the whole contract.
#
# Matching on the *first field being a loopback address* is what makes this safe to
# run against a file this script does not own: a comment or an unrelated stanza
# that happens to mention `workcenter.local` is left alone.
strip_workcenter_hosts() {
  local src="$1" dst="$2"
  HOSTS_DROPPED="$(awk \
    -v begin="${HOSTS_MARKER_BEGIN}" -v end="${HOSTS_MARKER_END}" \
    -v hosts="$(workcenter_hostnames | tr '\n' ' ')" '
      BEGIN { n = split(hosts, h, " "); inblock = 0; dropped = 0 }
      $0 == begin { inblock = 1; dropped++; next }
      $0 == end   { inblock = 0; dropped++; next }
      inblock     { dropped++; next }
      ($1 == "127.0.0.1" || $1 == "::1" || $1 == "0.0.0.0") {
        for (i = 2; i <= NF; i++)
          for (j = 1; j <= n; j++)
            if ($i == h[j]) { dropped++; next }
      }
      { print }
      END { print dropped > "/dev/stderr" }
    ' "${src}" 2>&1 >"${dst}")"
}

remove_hosts_entries() {
  step 'Host entries'
  [[ -f "${HOSTS_FILE}" ]] || { info "${HOSTS_FILE} does not exist"; return 0; }
  local tmp
  tmp="$(mktemp)"
  strip_workcenter_hosts "${HOSTS_FILE}" "${tmp}"
  if [[ "${HOSTS_DROPPED}" -eq 0 ]]; then
    info 'no host entries of this deployment were present'
    rm -f "${tmp}"
    return 0
  fi
  if cat "${tmp}" >"${HOSTS_FILE}" 2>/dev/null; then
    ok "removed ${HOSTS_DROPPED} host entr(y|ies) from ${HOSTS_FILE}"
  else
    warn "could not write ${HOSTS_FILE} (needs root)"
  fi
  rm -f "${tmp}"
}

# ---------------------------------------------------------------------------
# Ownership of the runtime state
#
# Bind mounts make a container's writes the *container's* uid on the host:
# Authentik's PostgreSQL data directory is uid 65534 mode 0700, Redis's is the
# same, and Mailcow's tree is a mix. The user who ran the harness can then neither
# read, replace nor delete any of it — `--down` cannot clean up and the next run
# cannot reset stale credentials.
#
# Undoing that is the one thing in this project that genuinely needs root, which
# is why it lives here. It also repairs what a run **as root** leaves behind:
# every file the harness generates belongs to the person who will run it, never to
# root.
# ---------------------------------------------------------------------------
repair_ownership() {
  step 'Runtime state ownership'
  local target
  target="$(target_user)"
  if ! id -u "${target}" >/dev/null 2>&1; then
    warn "cannot resolve the user '${target}'; skipping"
    return 0
  fi
  info "giving ${target} ownership of the generated files and runtime state"

  # The bind-mount targets every application writes into. Anything absent is
  # skipped: a fresh clone has none of them yet.
  local rel changed=0
  local dirs=(
    Authentik/data
    Filebrowser/data
    Filebrowser/office-cache
    OnlyOffice/data OnlyOffice/db OnlyOffice/lib OnlyOffice/logs
    Zulip/data Zulip/database Zulip/rabbitmq Zulip/redis Zulip/secrets
    Mailcow/data
    Traefik/certs Traefik/logs Traefik/acme.json
    user-data
  )
  for rel in "${dirs[@]}"; do
    [[ -e "${ROOT_DIR}/${rel}" ]] || continue
    if chown -R "${target}:${target}" "${ROOT_DIR}/${rel}" 2>/dev/null; then
      changed=$((changed + 1))
    else
      warn "could not change ownership of ${rel}"
    fi
  done

  # Three directories belong to the **Authentik server's** uid rather than to the
  # person running the harness: the image declares `User: 1000` and writes `/media`,
  # `/certs` and `/templates` directly, so on a machine whose first user is not uid
  # 1000 the server cannot create `/media/public` and dies during the tenant
  # migration. PostgreSQL and Redis need nothing here — their entrypoints run as
  # root and take ownership of their own data directories.
  for rel in Authentik/data/media Authentik/data/certs Authentik/data/templates; do
    [[ -e "${ROOT_DIR}/${rel}" ]] || continue
    chown -R 1000:1000 "${ROOT_DIR}/${rel}" 2>/dev/null \
      || warn "could not give ${rel} to uid 1000 (the Authentik server's user)"
  done
  info "Authentik's media, certs and templates belong to uid 1000 (its image's user)"

  # The generated `.env` files. A run as root leaves these owned by root, and the
  # harness then cannot rewrite the OIDC client secrets it is supposed to manage.
  local env_file
  for env_file in .env Authentik/.env Filebrowser/.env OnlyOffice/.env Zulip/.env Traefik/.env Mailcow/mailcow.conf; do
    [[ -e "${ROOT_DIR}/${env_file}" ]] || continue
    chown "${target}:${target}" "${ROOT_DIR}/${env_file}" 2>/dev/null \
      || warn "could not change ownership of ${env_file}"
  done

  ok "${changed} runtime path(s) now belong to ${target}"
  info 'a checkout whose *tracked* files are also root-owned needs a plain chown -R;'
  info "this script only touches what the harness and the containers generate."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Prepare this machine to run the Workcenter test environment.

  sudo ./scripts/setup-testing.sh [--hosts] [--trust-cert] [--ownership] [--remove]

  (no arguments)   all three of the steps below
  --hosts          add the stack's hostnames to /etc/hosts, for a browser
  --trust-cert     install Traefik/certs/local-ca.crt into the trust stores
  --ownership      give the invoking user back the runtime state the containers own
  --remove         undo the two system changes above, returning this machine to the
                   state it was in before this script was first run: every host
                   entry it ever wrote (marked or not) and the certificate from
                   every store it was installed into

`scripts/e2e.sh` never needs root and refuses to run with it. Run this script as
the user who will run that one, through sudo, so the files land on their account.

`--remove` is the end of testing, not part of it. The certificate it installs is
the one the stack serves, so the setup is meant to be done once and kept until you
are finished with the deployment.
EOF
}

main() {
  local do_hosts=0 do_cert=0 do_ownership=0 do_remove=0
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --hosts) do_hosts=1 ;;
      --trust-cert) do_cert=1 ;;
      --ownership) do_ownership=1 ;;
      --remove) do_remove=1 ;;
      -h | --help) usage; exit 0 ;;
      *) fail "unknown argument: ${arg}"; usage >&2; exit 2 ;;
    esac
  done

  # No flags means "prepare this machine", which is the common case.
  if [[ "${do_hosts}" -eq 0 && "${do_cert}" -eq 0 && "${do_ownership}" -eq 0 && "${do_remove}" -eq 0 ]]; then
    do_hosts=1
    do_cert=1
    do_ownership=1
  fi

  require_root "$@"

  if [[ "${do_remove}" -eq 1 ]]; then
    remove_hosts_entries
    remove_trusted_certificate
    return 0
  fi

  # **The certificate comes first, and this script creates it.** It is the preflight:
  # it runs before the harness, so it cannot wait for the harness to produce the
  # thing it exists to install. `localca_ensure` is the same function the harness
  # calls, so the authority installed here is the authority the stack will serve.
  localca_ensure

  [[ "${do_hosts}" -eq 1 ]] && add_hosts_entries
  [[ "${do_cert}" -eq 1 ]] && trust_local_certificate
  [[ "${do_ownership}" -eq 1 ]] && repair_ownership

  step 'Done'
  ok 'the machine is ready for ./scripts/e2e.sh'
  printf '  Run:   ./scripts/e2e.sh\n'
  printf '  Open:  https://%s/\n\n' "${WORKCENTER_HOST}"
}

main "$@"
