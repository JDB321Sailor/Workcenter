#!/usr/bin/env bash
# Workcenter — Authentik provisioning library.
#
# Creates or reconciles everything `docs/authentication/OIDC.md` §4.1 lists as
# required, through Authentik's own API:
#
#   * the groups `workspaceusers` and `workspaceadmin`                    (O-3.1)
#   * the scope mappings `groups`, `email-verified`, `mailcow_template`   (§4.2, §4.5)
#   * the OIDC providers and applications `workcenter`, `filebrowser`,
#     `zulip`, `mailcow`                                                  (§5.4–§5.7)
#   * the proxy provider `traefik-dashboard` + application `traefik`, and the
#     embedded outpost membership that makes forward auth work            (§5.8)
#   * the application icons (`meta_icon`)                                 (§5.5.4)
#   * the operator identities the caller asks for                         (Testing.md §7.1)
#
# It is the implementation of `production.md` §5.5.1 and P-40: **create-or-update,
# never duplicate.** The API has no upsert, so every object is looked up by its
# unique key first — `name` for groups and mappings, `client_id` for providers,
# `slug` for applications, the `managed` id for built-in mappings and the embedded
# outpost — and the create is only attempted when the lookup returns nothing.
#
# Two properties are deliberate:
#
#   1. **It is a library, not a script.** `scripts/e2e.sh` sources it, and
#      `setup.sh` will source the same file, so the harness and the installer
#      cannot drift apart: fixing a provider field fixes it for both.
#   2. **It talks to the instance over the network, not over `docker exec`.** The
#      same code path therefore works against an adopted Authentik that Workcenter
#      did not deploy (production.md §5.5.2, access path 2).
#
# Every function is idempotent and safe to re-run. `authentik_provision` is the
# entry point; the rest are individually callable so a caller can create only the
# test identities, or only the OIDC objects.

# Sourced, never executed. `return` is the correct exit inside a sourced file.
[[ -n "${AUTHENTIK_LIB_LOADED:-}" ]] && return 0
AUTHENTIK_LIB_LOADED=1

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# The caller exports these before calling anything. They are read once here so a
# later change to the environment cannot half-configure a run.
AUTHENTIK_HOST="${AUTHENTIK_HOST:?authentik.sh needs AUTHENTIK_HOST}"
AUTHENTIK_BASE_URL="${AUTHENTIK_BASE_URL:-https://${AUTHENTIK_HOST}}"

# The group model (OIDC.md §3). Configurable, but identical everywhere.
AUTHENTIK_USER_GROUP="${WORKCENTER_USER_GROUP:-workspaceusers}"
AUTHENTIK_ADMIN_GROUP="${WORKCENTER_ADMIN_GROUP:-workspaceadmin}"

# OIDC.md §4.4 names the flows every provider carries. They are looked up by slug
# because the API wants a PK, and the slugs are stable across releases while the
# PKs are random UUIDs.
AUTHENTIK_AUTHZ_FLOW_SLUG="${AUTHENTIK_AUTHZ_FLOW_SLUG:-default-provider-authorization-implicit-consent}"
AUTHENTIK_INVALIDATION_FLOW_SLUG="${AUTHENTIK_INVALIDATION_FLOW_SLUG:-default-provider-invalidation-flow}"
AUTHENTIK_AUTHENTICATION_FLOW_SLUG="${AUTHENTIK_AUTHENTICATION_FLOW_SLUG:-default-authentication-flow}"

# OIDC.md §4.5 Trap 2: a provider with no signing key signs with HS256 and
# publishes no JWKS, so every client that verifies against `jwks_uri` fails. The
# built-in pair is what §5.4 names.
AUTHENTIK_SIGNING_KEY_NAME="${AUTHENTIK_SIGNING_KEY_NAME:-authentik Self-signed Certificate}"

# Every built-in the provider is built from, in one place, because the readiness
# gate and the provisioning that follows it have to agree on the list.
#
# They did not, and the run failed in the gap: the gate named only the two flows,
# which were the objects that had failed *so far*. A blueprint does not create
# them all at once — the one carrying the scope mappings lands after the one
# carrying the flows — so the gate opened in between and provisioning died on its
# next call with `no built-in scope mapping '.../scope-openid'`. A gate listing the
# failures it happens to have seen is a gate that fails again on the next one.
#
# These are exactly the objects `authentik_ensure_oauth2_provider` looks up before
# it can build a provider, and the gate checks each with the same lookup.
AUTHENTIK_READY_FLOWS=(
  "${AUTHENTIK_AUTHZ_FLOW_SLUG}"
  "${AUTHENTIK_INVALIDATION_FLOW_SLUG}"
)
AUTHENTIK_READY_SCOPE_MAPPINGS=(
  'goauthentik.io/providers/oauth2/scope-openid'
)

# `docker ps` and the file lookup both want a name; the Compose service is
# `authentik-server` (Authentik/compose.yaml).
AUTHENTIK_SERVER_CONTAINER="${AUTHENTIK_SERVER_CONTAINER:-authentik-server}"

# How long to wait for the server to finish its migrations and answer
# `/-/health/ready/`. First boot of a new database is the slow case.
AUTHENTIK_READY_TIMEOUT="${AUTHENTIK_READY_TIMEOUT:-600}"

# The HTTP transport. By default `--resolve` sends the public hostname to the
# loopback Traefik the harness binds (Testing.md §6.3), and `--insecure` accepts
# the deployment's own CA — the same posture `scripts/e2e.sh` takes for its checks.
# A caller that already has a routable base URL sets AUTHENTIK_CURL_EXTRA before
# sourcing this file (an empty array is valid) to drop both.
if [[ -z "${AUTHENTIK_CURL_EXTRA+x}" ]]; then
  AUTHENTIK_CURL_EXTRA=("--insecure" "--resolve" "${AUTHENTIK_HOST}:443:127.0.0.1")
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# The harness defines info/ok/warn/fail before sourcing this file. These fallbacks
# keep the library usable from a caller that does not, and keep the output format
# identical when it does.
command -v info >/dev/null 2>&1 || info() { printf '\033[36mℹ\033[0m %s\n' "$*"; }
command -v ok >/dev/null 2>&1 || ok() { printf '\033[32m✔\033[0m %s\n' "$*"; }
command -v warn >/dev/null 2>&1 || warn() { printf '\033[33m⚠\033[0m %s\n' "$*" >&2; }
command -v fail >/dev/null 2>&1 || fail() { printf '\033[31m✖\033[0m %s\n' "$*" >&2; }

# Counts of what the last `authentik_provision` did, for the closing report.
AUTHENTIK_CREATED=0
AUTHENTIK_UPDATED=0
AUTHENTIK_UNCHANGED=0

# ---------------------------------------------------------------------------
# Transport
# ---------------------------------------------------------------------------
# `authentik_api METHOD PATH [JSON]` writes the response body to stdout. The HTTP
# status cannot travel back through a global, because nearly every caller captures
# the body with `$(...)` and that runs in a subshell — an assignment made in there
# is discarded. The status therefore goes to a file, which survives the subshell,
# and `authentik_last_code` reads it back.
AUTHENTIK_CODE_FILE="${TMPDIR:-/tmp}/workcenter-authentik-code.$$"
: >"${AUTHENTIK_CODE_FILE}"

authentik_last_code() {
  local code
  code="$(cat "${AUTHENTIK_CODE_FILE}" 2>/dev/null || true)"
  printf '%s' "${code:-000}"
}

authentik_api() {
  local method="$1" path="$2" body="${3:-}"
  local body_file="${TMPDIR:-/tmp}/workcenter-authentik-body.$$"
  local -a args=(-sS -o "${body_file}" -w '%{http_code}' -X "${method}")
  args+=(-H "Authorization: Bearer ${AUTHENTIK_TOKEN}")
  args+=(-H 'Accept: application/json')
  if [[ -n "${body}" ]]; then
    args+=(-H 'Content-Type: application/json' --data-binary "${body}")
  fi
  args+=("${AUTHENTIK_CURL_EXTRA[@]}" "${AUTHENTIK_BASE_URL}${path}")
  curl "${args[@]}" >"${AUTHENTIK_CODE_FILE}" 2>/dev/null || printf '000' >"${AUTHENTIK_CODE_FILE}"
  [[ -f "${body_file}" ]] && cat "${body_file}"
  rm -f "${body_file}"
}

# A failed call is a hard error: every caller below depends on the object it asked
# for, and silently continuing would leave a half-configured identity provider.
_authentik_require() {
  local want="$1" what="$2" code
  code="$(authentik_last_code)"
  if [[ "${code}" != "${want}" ]]; then
    fail "Authentik API: ${what} returned HTTP ${code} (expected ${want})"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Ready check
# ---------------------------------------------------------------------------
# IN-7.7: the server answers `/-/health/live/` as soon as the process is up and
# `/-/health/ready/` only once migrations have finished and the worker is
# reachable. Provisioning against `live` would race the schema.
authentik_wait_ready() {
  local deadline=$((SECONDS + AUTHENTIK_READY_TIMEOUT))
  info 'Waiting for Authentik to finish starting…'
  # `/health/ready/` is **not** the condition this needs, and trusting it is how a
  # fresh deployment failed: the endpoint is served by the server process, and it
  # answers before the API will accept the bootstrap token. Provisioning then ran
  # straight into `403` on its first call and stopped, with every object after it
  # uncreated. What matters is the thing the next line depends on — an
  # authenticated request that comes back `200` — so that is what is polled.
  #
  # An API that answers is still not an instance that can be *provisioned*. The
  # built-in flows, scope mappings and signing key are created by the **worker**
  # applying blueprints, which happens after the server starts serving; until then
  # the API is healthy and the objects the next call names do not exist. On the
  # 2026.8 pin that is exactly how provisioning stopped, with
  # `no flow 'default-provider-authorization-implicit-consent'`.
  #
  # So the gate is the token **and every built-in the provider is built from** —
  # and the list has to be the whole list. It used to name the two flows alone,
  # which was the objects that had failed *so far*: a blueprint does not create
  # them all at once, and the one carrying the scope mappings lands after the one
  # carrying the flows. The gate therefore opened in the window between them, and
  # provisioning died on the very next thing it asked for:
  #
  #   ✖ Authentik has no built-in scope mapping '.../scope-openid'
  #
  # A gate that lists the dependencies it happens to have seen fail is a gate that
  # fails again on the next one. These are the objects `authentik_ensure_oauth2_provider`
  # names before it can do anything, and each is checked by the same lookup that
  # will run a moment later.
  local code missing
  while ((SECONDS < deadline)); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' "${AUTHENTIK_CURL_EXTRA[@]}" \
      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" -H 'Accept: application/json' \
      "${AUTHENTIK_BASE_URL}/api/v3/core/users/me/" 2>/dev/null || true)"
    missing=''
    if [[ "${code}" == '200' ]]; then
      local slug mapping
      for slug in "${AUTHENTIK_READY_FLOWS[@]}"; do
        [[ -n "$(authentik_find_flow "${slug}")" ]] || missing="flow ${slug}"
      done
      for mapping in "${AUTHENTIK_READY_SCOPE_MAPPINGS[@]}"; do
        [[ -n "$(authentik_find_builtin_scope_mapping "${mapping}")" ]] || missing="scope ${mapping}"
      done
      [[ -n "$(authentik_find_signing_key "${AUTHENTIK_SIGNING_KEY_NAME}")" ]] \
        || missing="signing key ${AUTHENTIK_SIGNING_KEY_NAME}"
    fi
    if [[ "${code}" == '200' && -z "${missing}" ]]; then
      ok 'Authentik is ready, accepts the API token, and its blueprints are applied'
      return 0
    fi
    [[ -n "${missing}" ]] && info "  still waiting for: ${missing}"
    sleep 5
  done
  fail "Authentik was not ready to be provisioned within ${AUTHENTIK_READY_TIMEOUT}s (last API status: ${code:-none}, waiting for: ${missing:-none})"
  return 1
}

# Confirms the token is accepted and identifies who it belongs to. This is the
# check `production.md` §5.5.3 names for an operator-supplied token, and it is
# just as useful for a bootstrap one: it fails loudly here rather than halfway
# through creating objects.
authentik_verify_token() {
  local body code
  body="$(authentik_api GET /api/v3/core/users/me/)"
  code="$(authentik_last_code)"
  if [[ "${code}" != '200' ]]; then
    fail "Authentik rejected the API token (HTTP ${code})"
    return 1
  fi
  AUTHENTIK_TOKEN_USER="$(jq -r '.user.username // .user.email // "unknown"' <<<"${body}" 2>/dev/null)"
  ok "Authentik API token accepted as ${AUTHENTIK_TOKEN_USER}"
}

# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------
# Every `_find_*` returns the object's `pk` on stdout, or nothing when the object
# does not exist. They are the whole of P-40: the caller creates only when the
# lookup is empty.
#
# Query values are escaped with jq's `@uri`. Two of them carry characters that
# must not travel raw: the built-in signing key's name has spaces, and the
# embedded outpost's `managed` id contains slashes.
_authentik_esc() { jq -rn --arg v "$1" '$v|@uri'; }

_authentik_lookup() {
  # path, jq filter
  local path="$1" filter="$2" body
  body="$(authentik_api GET "${path}")"
  [[ "$(authentik_last_code)" == '200' ]] || return 1
  jq -r "${filter}" <<<"${body}" 2>/dev/null | head -n1
}

authentik_find_group() {
  local name="$1"
  _authentik_lookup "/api/v3/core/groups/?name=${name}" \
    '.results[] | select(.name == "'"${name}"'") | .pk'
}

authentik_find_scope_mapping() {
  local name="$1"
  # The OAuth2/OIDC scope mappings are a *provider* property mapping. On the
  # pinned 2024.12 train the route is `/propertymappings/provider/scope/`; the
  # shorter `/propertymappings/scope/` some newer documentation shows does not
  # exist here, and answers 404 rather than redirecting.
  _authentik_lookup "/api/v3/propertymappings/provider/scope/?name=${name}" \
    '.results[] | select(.name == "'"${name}"'") | .pk'
}

# A **built-in** scope mapping, found by the `managed` id Authentik gives it.
#
# They cannot be found by name: a built-in is called
# `authentik default OAuth Mapping: OpenID 'openid'`, and the short word is its
# `scope_name`. Looking one up by `openid` therefore matches nothing, silently — the
# loop below would skip it and the provider would be created without it.
authentik_find_builtin_scope_mapping() {
  local managed="$1"
  _authentik_lookup "/api/v3/propertymappings/provider/scope/?managed__iexact=$(_authentik_esc "${managed}")" \
    '.results[] | select(.managed == "'"${managed}"'") | .pk'
}

authentik_find_oauth2_provider() {
  local client_id="$1"
  _authentik_lookup "/api/v3/providers/oauth2/?client_id=${client_id}" \
    '.results[] | select(.client_id == "'"${client_id}"'") | .pk'
}

authentik_find_proxy_provider() {
  local name="$1"
  _authentik_lookup "/api/v3/providers/proxy/?search=${name}" \
    '.results[] | select(.name == "'"${name}"'") | .pk'
}

authentik_find_application() {
  local slug="$1"
  # `superuser_full_list` is required, not cosmetic: without it this endpoint
  # returns only the applications the *calling user* may see, and the `traefik`
  # application is deliberately bound to `workspaceadmin` alone. An automation
  # that forgot the flag would decide the dashboard application does not exist and
  # try to create it a second time.
  _authentik_lookup "/api/v3/core/applications/?slug=${slug}&superuser_full_list=true" \
    '.results[] | select(.slug == "'"${slug}"'") | .pk'
}

authentik_find_flow() {
  local slug="$1"
  _authentik_lookup "/api/v3/flows/instances/?slug=${slug}" \
    '.results[] | select(.slug == "'"${slug}"'") | .pk'
}

authentik_find_signing_key() {
  local name="$1"
  _authentik_lookup "/api/v3/crypto/certificatekeypairs/?search=$(_authentik_esc "${name}")" \
    '.results[] | select(.name == "'"${name}"'") | .pk'
}

authentik_find_user() {
  local username="$1"
  _authentik_lookup "/api/v3/core/users/?username=${username}" \
    '.results[] | select(.username == "'"${username}"'") | .pk'
}

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------
authentik_ensure_group() {
  local name="$1" pk body
  pk="$(authentik_find_group "${name}")"
  body="$(jq -nc --arg n "${name}" '{name: $n, is_superuser: false, attributes: {}}')"
  if [[ -z "${pk}" ]]; then
    authentik_api POST /api/v3/core/groups/ "${body}" >/dev/null
    _authentik_require 201 "create group ${name}" || return 1
    AUTHENTIK_CREATED=$((AUTHENTIK_CREATED + 1))
    return 0
  fi
  authentik_api PATCH "/api/v3/core/groups/${pk}/" "${body}" >/dev/null
  _authentik_require 200 "update group ${name}" || return 1
}

# ---------------------------------------------------------------------------
# Scope mappings
# ---------------------------------------------------------------------------
# `name` is what the API and the Web UI show; `scope_name` is the **claim** the
# scope contributes. They are deliberately allowed to differ: OIDC.md §4.5 Trap 1
# replaces the built-in `email` scope with a mapping named `email-verified` whose
# scope name is still `email`.
authentik_ensure_scope_mapping() {
  local name="$1" scope_name="$2" description="$3" expression="$4" pk body
  pk="$(authentik_find_scope_mapping "${name}")"
  body="$(jq -nc \
    --arg n "${name}" --arg s "${scope_name}" \
    --arg d "${description}" --arg e "${expression}" \
    '{name: $n, scope_name: $s, description: $d, expression: $e}')"
  if [[ -z "${pk}" ]]; then
    authentik_api POST /api/v3/propertymappings/provider/scope/ "${body}" >/dev/null
    _authentik_require 201 "create scope mapping ${name}" || return 1
    AUTHENTIK_CREATED=$((AUTHENTIK_CREATED + 1))
    return 0
  fi
  authentik_api PATCH "/api/v3/propertymappings/provider/scope/${pk}/" "${body}" >/dev/null
  _authentik_require 200 "update scope mapping ${name}" || return 1
}

# The four mappings in one place, so a caller cannot create three of them and
# forget the fourth. Expressions are from OIDC.md §4.2 and §4.5.
authentik_ensure_scope_mappings() {
  local created_before="${AUTHENTIK_CREATED}"
  authentik_ensure_scope_mapping 'groups' 'groups' \
    'Workcenter: exposes the user'"'"'s Authentik groups as a claim' \
    'return {"groups": [g.name for g in request.user.ak_groups.all()]}' || return 1
  authentik_ensure_scope_mapping 'email-verified' 'email' \
    'Workcenter: replaces the built-in email scope so email_verified is true' \
    'return {
    "email": request.user.email,
    "email_verified": request.user.attributes.get("email_verified", False),
}' || return 1
  # A **replacement for the built-in `profile`**, and it exists only because the
  # built-in cannot be used. On the 2026.8 train the built-in's expression emits
  # `groups` as well as the standard claims, and a claim two mappings write is
  # *concatenated*: attaching it beside the custom `groups` mapping below produced
  # `["workspaceusers","workspaceadmin","workspaceusers","workspaceadmin"]`.
  #
  # Dropping `profile` instead is not an option either, and that is the part that
  # cost a second round: `preferred_username` is not decoration. FileBrowser
  # identifies users by it and answers
  # `500 {"message":"no valid username found for identifier 'preferred_username'"}`
  # without it. The shell falls back to the email address; FileBrowser does not.
  #
  # So this is the built-in's claim set **minus groups** — the standard claims a
  # client expects from `profile`, with the group claim owned by exactly one
  # mapping. It is deliberately not the built-in: this expression is ours, so it
  # cannot change under a version bump the way the built-in's did.
  authentik_ensure_scope_mapping 'profile' 'profile' \
    'Workcenter: the standard profile claims, without groups (the groups mapping owns that claim)' \
    'avatar = request.user.avatar
return delete_none_values({
    "name": request.user.name,
    "given_name": ak_obj_attr(request.user, "given_name", "name"),
    "family_name": ak_obj_attr(request.user, "family_name"),
    "preferred_username": request.user.username,
    "nickname": request.user.username,
    "picture": avatar if avatar and not avatar.startswith("data:") else None,
})' || return 1
  authentik_ensure_scope_mapping 'mailcow_template' 'mailcow_template' \
    'Workcenter: the Mailcow mailbox template its users receive' \
    'return {
    "mailcow_template": request.user.attributes.get("mailcow_template", "default"),
}' || return 1
  ok "scope mappings: groups, email-verified, profile, mailcow_template ($((AUTHENTIK_CREATED - created_before)) created)"
}

# ---------------------------------------------------------------------------
# Providers
# ---------------------------------------------------------------------------
# OIDC.md §4.4, applied to every provider Workcenter creates:
#
#   * the implicit-consent authorization flow and the invalidation flow, both by
#     slug, because §4.4 requires the invalidation flow on 2024.10 and newer;
#   * `confidential` — Zulip in particular refuses a public client;
#   * a real signing key, so JWKS is populated (Trap 2);
#   * **no encryption key**, so the token is a signed JWT and not a JWE;
#   * `include_claims_in_id_token`, or the shell and the broker never see the
#     `groups` claim;
#   * strict redirect matching.
_authentik_provider_common() {
  local provider_pk="$1" flow_authz="$2" flow_inval="$3" signing_key="$4" client_type="$5"
  shift 5
  local -a mapping_pks=("$@")
  jq -nc \
    --arg authz "${flow_authz}" --arg inval "${flow_inval}" \
    --arg key "${signing_key}" --arg ctype "${client_type}" \
    --argjson maps "$(printf '%s\n' "${mapping_pks[@]}" | jq -R . | jq -sc .)" \
    '{
       authorization_flow: $authz,
       invalidation_flow: $inval,
       client_type: $ctype,
       signing_key: $key,
       encryption_key: null,
       include_claims_in_id_token: true,
       sub_mode: "hashed_user_id",
       issuer_mode: "per_provider",
       property_mappings: $maps,
       access_token_validity: "hours=1",
       refresh_token_validity: "days=30",
       grant_types: ["authorization_code", "refresh_token"]
     }'
}

# `redirect_uris` arrives as a newline-separated list and is sent as an array of
# `{url, matching_mode}` objects, which is what this instance's schema requires
# (`RedirectURIRequest`: both fields required, `matching_mode` one of `strict` or
# `regex`). OIDC.md §4.4 asks for **Strict** matching.
#
# `authentik-api-feasibility.md` §7 predicted the opposite for this train — that
# 2024.12 still took an array of plain strings and that objects arrived in 2026.5.
# The pinned instance rejects a string with `Expected a dictionary, but got str`,
# so the objects are what is sent; the correction is recorded in the document.
authentik_ensure_oauth2_provider() {
  local name="$1" client_id="$2" client_secret="$3" redirect_uris="$4" client_type="${5:-confidential}"
  local pk body
  pk="$(authentik_find_oauth2_provider "${client_id}")"

  local flow_authz flow_inval signing_key
  flow_authz="$(authentik_find_flow "${AUTHENTIK_AUTHZ_FLOW_SLUG}")"
  flow_inval="$(authentik_find_flow "${AUTHENTIK_INVALIDATION_FLOW_SLUG}")"
  signing_key="$(authentik_find_signing_key "${AUTHENTIK_SIGNING_KEY_NAME}")"
  [[ -n "${flow_authz}" ]] || { fail "Authentik has no flow '${AUTHENTIK_AUTHZ_FLOW_SLUG}'"; return 1; }
  [[ -n "${flow_inval}" ]] || { fail "Authentik has no flow '${AUTHENTIK_INVALIDATION_FLOW_SLUG}'"; return 1; }
  [[ -n "${signing_key}" ]] || { fail "Authentik has no signing key '${AUTHENTIK_SIGNING_KEY_NAME}'"; return 1; }

  # The claim-producing scopes.
  #
  # **`openid` is not optional and is not implied.** Authentik intersects the scopes
  # a client asks for with the ones the provider is *configured* for, and silently
  # drops the rest — the log line is "Application requested scopes not configured,
  # setting to overlap". Without `openid` the issued token carries no `openid` scope,
  # and the userinfo endpoint then refuses it outright with `403 Scope mismatch`:
  #
  #     "required": "{'openid'}", "token_has": "{'groups', 'email'}"
  #
  # That is fatal for a browser and **invisible to a server-side check**: the code
  # exchange still succeeds and the id_token still verifies, so every automated
  # check passed while the shell showed "Authentication failed (OIDC)" — its
  # `loadUserInfo` call is the first thing to touch `/userinfo/`, and it sees a
  # CORS-blocked 403.
  #
  # The other four are **custom** mappings, including `profile`. Read
  # `authentik_ensure_scope_mappings` for why the built-in `profile` cannot be used:
  # it duplicates `groups`, and leaving it out costs `preferred_username`, which
  # FileBrowser refuses to sign a user in without.
  local -a mapping_pks=()
  local mapping
  # The same list the readiness gate waits for (`AUTHENTIK_READY_SCOPE_MAPPINGS`),
  # so the two cannot disagree about what has to exist before this can run. When
  # they were written separately the gate checked less than this loop needed, and
  # the gap is where the run failed.
  for mapping in "${AUTHENTIK_READY_SCOPE_MAPPINGS[@]}"; do
    local builtin
    builtin="$(authentik_find_builtin_scope_mapping "${mapping}")"
    if [[ -z "${builtin}" ]]; then
      fail "Authentik has no built-in scope mapping '${mapping}'"
      return 1
    fi
    mapping_pks+=("${builtin}")
  done
  for mapping in groups email-verified profile mailcow_template; do
    local m
    m="$(authentik_find_scope_mapping "${mapping}")"
    [[ -n "${m}" ]] && mapping_pks+=("${m}")
  done

  body="$(_authentik_provider_common "${pk}" "${flow_authz}" "${flow_inval}" "${signing_key}" "${client_type}" "${mapping_pks[@]}")"
  body="$(jq -c \
    --arg n "${name}" --arg cid "${client_id}" --arg sec "${client_secret}" \
    --argjson uris "$(printf '%s\n' "${redirect_uris}" | jq -R . | jq -sc '[.[] | select(length > 0) | {url: ., matching_mode: "strict"}]')" \
    '. + {name: $n, client_id: $cid, client_secret: $sec, redirect_uris: $uris}' <<<"${body}")"

  if [[ -z "${pk}" ]]; then
    authentik_api POST /api/v3/providers/oauth2/ "${body}" >/dev/null
    _authentik_require 201 "create provider ${name}" || return 1
    AUTHENTIK_CREATED=$((AUTHENTIK_CREATED + 1))
    return 0
  fi
  authentik_api PATCH "/api/v3/providers/oauth2/${pk}/" "${body}" >/dev/null
  _authentik_require 200 "update provider ${name}" || return 1
}

# OIDC.md §5.8: a Proxy provider, because forward auth is not an OIDC flow. It
# carries the authentication flow (the login page the browser is sent to) and the
# external host, and it is the object the embedded outpost serves.
authentik_ensure_proxy_provider() {
  local name="$1" external_host="$2" pk body
  pk="$(authentik_find_proxy_provider "${name}")"

  local flow_authz flow_authn flow_inval
  flow_authz="$(authentik_find_flow "${AUTHENTIK_AUTHZ_FLOW_SLUG}")"
  flow_authn="$(authentik_find_flow "${AUTHENTIK_AUTHENTICATION_FLOW_SLUG}")"
  # The invalidation flow is required by the serializer even though it reads as an
  # OIDC-only concern: it is the flow Authentik runs after a sign-out, so the
  # dashboard's session ends the same way every other surface's does (A-7).
  flow_inval="$(authentik_find_flow "${AUTHENTIK_INVALIDATION_FLOW_SLUG}")"
  [[ -n "${flow_authz}" ]] || { fail "Authentik has no flow '${AUTHENTIK_AUTHZ_FLOW_SLUG}'"; return 1; }
  [[ -n "${flow_authn}" ]] || { fail "Authentik has no flow '${AUTHENTIK_AUTHENTICATION_FLOW_SLUG}'"; return 1; }
  [[ -n "${flow_inval}" ]] || { fail "Authentik has no flow '${AUTHENTIK_INVALIDATION_FLOW_SLUG}'"; return 1; }

  body="$(jq -nc \
    --arg n "${name}" --arg authz "${flow_authz}" --arg authn "${flow_authn}" \
    --arg inval "${flow_inval}" --arg ext "${external_host}" \
    '{name: $n, authorization_flow: $authz, authentication_flow: $authn,
      invalidation_flow: $inval, external_host: $ext, mode: "forward_single",
      intercept_header_auth: true}')"

  if [[ -z "${pk}" ]]; then
    authentik_api POST /api/v3/providers/proxy/ "${body}" >/dev/null
    _authentik_require 201 "create proxy provider ${name}" || return 1
    AUTHENTIK_CREATED=$((AUTHENTIK_CREATED + 1))
    return 0
  fi
  authentik_api PATCH "/api/v3/providers/proxy/${pk}/" "${body}" >/dev/null
  _authentik_require 200 "update proxy provider ${name}" || return 1
}

# ---------------------------------------------------------------------------
# Applications, bindings and the outpost
# ---------------------------------------------------------------------------
authentik_ensure_application() {
  local name="$1" slug="$2" provider_pk="$3" pk body
  pk="$(authentik_find_application "${slug}")"
  body="$(jq -nc \
    --arg n "${name}" --arg s "${slug}" --arg p "${provider_pk}" \
    '{name: $n, slug: $s, provider: $p, policy_engine_mode: "any"}')"
  if [[ -z "${pk}" ]]; then
    authentik_api POST /api/v3/core/applications/ "${body}" >/dev/null
    _authentik_require 201 "create application ${slug}" || return 1
    AUTHENTIK_CREATED=$((AUTHENTIK_CREATED + 1))
    return 0
  fi
  # The detail route is keyed by **slug**, not by the pk the list returns:
  # `/api/v3/core/applications/{slug}/`.
  authentik_api PATCH "/api/v3/core/applications/${slug}/" "${body}" >/dev/null
  _authentik_require 200 "update application ${slug}" || return 1
}

# O-3.3: being in a group decides what you may do, but the **binding** decides who
# may sign in at all. `Application.group` is a free-text dashboard label and is
# emphatically not this — it is a PolicyBinding with the application as the target.
#
# `authentik_ensure_application_binding SLUG GROUP` adds the group; the caller is
# responsible for removing a binding it no longer wants, which is why this
# function only ever adds.
authentik_ensure_application_binding() {
  local slug="$1" group_name="$2" app_pk group_pk body exists
  app_pk="$(authentik_find_application "${slug}")"
  group_pk="$(authentik_find_group "${group_name}")"
  [[ -n "${app_pk}" ]] || { fail "application ${slug} does not exist"; return 1; }
  [[ -n "${group_pk}" ]] || { fail "group ${group_name} does not exist"; return 1; }

  exists="$(_authentik_lookup "/api/v3/policies/bindings/?target=${app_pk}" \
    '.results[] | select(.group == "'"${group_pk}"'") | .pk')"
  if [[ -n "${exists}" ]]; then
    return 0
  fi
  body="$(jq -nc \
    --arg t "${app_pk}" --arg g "${group_pk}" \
    '{target: $t, group: $g, order: 0, enabled: true, negate: false}')"
  authentik_api POST /api/v3/policies/bindings/ "${body}" >/dev/null
  _authentik_require 201 "bind ${group_name} to ${slug}" || return 1
  AUTHENTIK_CREATED=$((AUTHENTIK_CREATED + 1))
}

# OIDC.md §5.8: the `Traefik` application only works if the **embedded outpost**
# serves it. The outpost's `providers` field is a list of **provider** pks —
# integers, as the schema's `array of integer` says — not application pks, so a
# forward-auth application is served by adding its proxy provider here. The
# outpost itself is built in and located by its `managed` id, which is stable
# while its pk is not.
authentik_ensure_outpost_membership() {
  local provider_pk="$1" outpost_json outpost_pk existing body
  [[ -n "${provider_pk}" ]] || { fail 'authentik_ensure_outpost_membership needs a provider pk'; return 1; }

  outpost_json="$(authentik_api GET '/api/v3/outposts/instances/?managed__iexact=goauthentik.io%2Foutposts%2Fembedded')"
  [[ "$(authentik_last_code)" == '200' ]] || { fail 'could not list Authentik outposts'; return 1; }
  outpost_pk="$(jq -r '.results[0].pk // empty' <<<"${outpost_json}")"
  [[ -n "${outpost_pk}" ]] || { fail 'Authentik has no embedded outpost'; return 1; }

  existing="$(jq -r '.results[0].providers // [] | map(tostring) | join(" ")' <<<"${outpost_json}")"
  if [[ " ${existing} " == *" ${provider_pk} "* ]]; then
    return 0
  fi
  # PATCH replaces the whole list, so the existing members are carried over: other
  # providers may already be served by this outpost.
  body="$(jq -nc --argjson new "${provider_pk}" --argjson have "$(jq -c '.results[0].providers // []' <<<"${outpost_json}")" \
    '{providers: ($have + [$new] | unique)}')"
  authentik_api PATCH "/api/v3/outposts/instances/${outpost_pk}/" "${body}" >/dev/null
  _authentik_require 200 "add provider ${provider_pk} to the embedded outpost" || return 1
  AUTHENTIK_CREATED=$((AUTHENTIK_CREATED + 1))
}

# ---------------------------------------------------------------------------
# Application icons
# ---------------------------------------------------------------------------
# The route that carries an icon moved, and on the current pin there is no working
# one by default:
#
#   * **2024.12 line** — `/core/applications/{slug}/set_icon/` takes the bytes as a
#     multipart upload (field `file`). Simple, and it works.
#   * **2026.8 line** — `set_icon/` and `set_icon_url/` were **removed**. An icon is
#     now a file in a storage backend, uploaded through `POST /admin/file/` and
#     referenced by the application's `meta_icon`. That backend is not configured on
#     a default install: the upload answers `500 ImproperlyConfigured: No file
#     management backend configured`, which is a server-side fact and not something
#     a client can work around.
#
# So the upload is attempted on the older route and, when that route is gone, the
# newer one is tried once and the outcome reported. A failure is swallowed either
# way: P-33 and P-43 both say an icon is not worth failing a deployment over, and
# the icons do not affect authentication, authorisation or framing.
authentik_ensure_application_icon() {
  local slug="$1" icon_path="$2" filename code
  [[ -f "${icon_path}" ]] || { warn "icon ${icon_path} not found — skipping"; return 0; }
  filename="$(basename "${icon_path}")"

  code="$(curl -sS "${AUTHENTIK_CURL_EXTRA[@]}" \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
    -F "file=@${icon_path};filename=${filename}" \
    -o /dev/null -w '%{http_code}' \
    "${AUTHENTIK_BASE_URL}/api/v3/core/applications/${slug}/set_icon/" 2>/dev/null || true)"

  if [[ "${code}" == '200' || "${code}" == '204' ]]; then
    AUTHENTIK_UPDATED=$((AUTHENTIK_UPDATED + 1))
    return 0
  fi

  # 404 means the route itself is gone — the newer API. Anything else is a real
  # refusal on a route that exists, and the old message is the useful one.
  if [[ "${code}" == '404' ]]; then
    code="$(curl -sS "${AUTHENTIK_CURL_EXTRA[@]}" \
      -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
      -F "file=@${icon_path};filename=${filename}" -F "name=${filename}" -F 'usage=media' \
      -o /dev/null -w '%{http_code}' \
      "${AUTHENTIK_BASE_URL}/api/v3/admin/file/" 2>/dev/null || true)"
    if [[ "${code}" == '200' || "${code}" == '204' ]]; then
      # Uploaded. Point the application at it; `meta_icon` is writable string on
      # this line, where it used to be a read-only URL.
      authentik_api PATCH "/api/v3/core/applications/${slug}/" \
        "$(jq -nc --arg i "${filename}" '{meta_icon: $i}')" >/dev/null 2>&1 || true
      if [[ "$(authentik_last_code)" == '200' ]]; then
        AUTHENTIK_UPDATED=$((AUTHENTIK_UPDATED + 1))
        return 0
      fi
    fi
    info "application icons need a configured file backend on this Authentik version — ${slug} has none (P-43)"
    return 0
  fi

  warn "could not set the icon on ${slug} (HTTP ${code}) — assign it by hand (P-43)"
  return 0
}

# ---------------------------------------------------------------------------
# Making the documented invalidation flow actually sign the user out
# ---------------------------------------------------------------------------
# Authentik's `default-provider-invalidation-flow` ships with **no stage
# bindings**. A provider that names it — which OIDC.md §4.4 requires on 2024.10
# and newer — therefore reaches the session-end screen without `logout()` ever
# running: the browser is told the session ended, the session is still valid, and
# the next authorization request issues a fresh code without asking for
# credentials. Nothing about the screen distinguishes the two outcomes, so an
# application is simply found still signed in.
#
# Binding the built-in `default-invalidation-logout` stage to that flow is what
# makes the documented choice do what roadmap A-7 says it does. It is done here
# rather than by pointing the providers at a different flow so the flow OIDC.md
# names is the flow that works.
authentik_ensure_invalidation_logout() {
  local flow_pk stage_pk exists body
  flow_pk="$(authentik_find_flow "${AUTHENTIK_INVALIDATION_FLOW_SLUG}")"
  [[ -n "${flow_pk}" ]] || { fail "Authentik has no flow '${AUTHENTIK_INVALIDATION_FLOW_SLUG}'"; return 1; }

  stage_pk="$(_authentik_lookup '/api/v3/stages/user_logout/?page_size=200' \
    '.results[] | select(.name == "default-invalidation-logout") | .pk')"
  [[ -n "${stage_pk}" ]] || { fail 'Authentik has no default-invalidation-logout stage'; return 1; }

  exists="$(_authentik_lookup "/api/v3/flows/bindings/?target=${flow_pk}&page_size=200" \
    '.results[] | select(.stage == "'"${stage_pk}"'") | .pk')"
  if [[ -n "${exists}" ]]; then
    return 0
  fi

  body="$(jq -nc --arg t "${flow_pk}" --arg s "${stage_pk}" \
    '{target: $t, stage: $s, order: 0, evaluate_on_plan: false, re_evaluate_policies: true,
      policy_engine_mode: "any", invalid_response_action: "retry"}')"
  authentik_api POST /api/v3/flows/bindings/ "${body}" >/dev/null
  _authentik_require 201 'bind the logout stage to the invalidation flow' || return 1
  AUTHENTIK_CREATED=$((AUTHENTIK_CREATED + 1))
  ok 'invalidation flow now ends the session (default-invalidation-logout bound)'
}

# ---------------------------------------------------------------------------
# Telling the embedded outpost where it is
# ---------------------------------------------------------------------------
# The outpost has to build an authorization URL for the browser, and with both
# `authentik_host` and `authentik_host_browser` empty it falls back to the address
# it was *reached on*. Behind Traefik that is the container's own
# `http://0.0.0.0:9000` — verified against the pinned instance — so the dashboard's
# forward-auth challenge redirects the browser to a host that does not exist and
# the dashboard is unreachable even though every object is configured correctly.
#
# Authentik splits the two addresses for exactly this reason, and both are set to
# the **public** URL. That is deliberate rather than sloppy: on the pinned
# instance the embedded outpost builds the browser's redirect from
# `authentik_host`, not from `authentik_host_browser` — verified by observation,
# the browser was sent to the internal address until `authentik_host` itself was
# changed — and the embedded outpost runs inside the server process, so it never
# needs to dial itself over the network.
authentik_ensure_outpost_host() {
  local external_url="$1"
  local outpost_json outpost_pk body

  outpost_json="$(authentik_api GET '/api/v3/outposts/instances/?managed__iexact=goauthentik.io%2Foutposts%2Fembedded')"
  [[ "$(authentik_last_code)" == '200' ]] || { fail 'could not list Authentik outposts'; return 1; }
  outpost_pk="$(jq -r '.results[0].pk // empty' <<<"${outpost_json}")"
  [[ -n "${outpost_pk}" ]] || { fail 'Authentik has no embedded outpost'; return 1; }

  if jq -e --arg e "${external_url}" \
      '.results[0].config.authentik_host == $e and .results[0].config.authentik_host_browser == $e' \
      <<<"${outpost_json}" >/dev/null 2>&1; then
    return 0
  fi

  body="$(jq -nc \
    --arg url "${external_url}" \
    --argjson config "$(jq -c '.results[0].config // {}' <<<"${outpost_json}")" \
    '{config: ($config + {authentik_host: $url, authentik_host_browser: $url,
                          authentik_host_insecure: false})}')"
  authentik_api PATCH "/api/v3/outposts/instances/${outpost_pk}/" "${body}" >/dev/null
  _authentik_require 200 'point the embedded outpost at the public URL' || return 1
  AUTHENTIK_UPDATED=$((AUTHENTIK_UPDATED + 1))
  ok "embedded outpost told its public URL is ${external_url}"
}

# ---------------------------------------------------------------------------
# Identities
# ---------------------------------------------------------------------------
# `authentik_ensure_user USERNAME EMAIL DISPLAY_NAME PASSWORD GROUP...`
#
# Creates the account when it is absent, sets its password and group membership
# when it is present, and never touches `is_superuser`: the admin in this model is
# an administrator *of the applications*, which is exactly what membership of
# `workspaceadmin` grants (O-3.3). The Authentik superuser stays `akadmin`.
authentik_ensure_user() {
  local username="$1" email="$2" display="$3" password="$4"
  shift 4
  local -a groups=("$@")

  local pk
  pk="$(authentik_find_user "${username}")"
  # `email_verified` and `mailcow_template` are **user attributes**, not constants,
  # because that is what the Mailcow integration reads them from: its scope mappings
  # resolve `request.user.attributes.get(...)`, so the claim is a property of the
  # account rather than of the deployment. Setting them here is what makes the
  # documented expressions return `true` and `default` instead of `false` and the
  # fallback — and Zulip's `email_verified` check is the same trap from the other
  # side (OIDC.md §4.5, Trap 1).
  local body
  body="$(jq -nc --arg u "${username}" --arg e "${email}" --arg n "${display}" \
    '{username: $u, email: $e, name: $n, is_active: true, path: "users", type: "internal",
      attributes: {email_verified: true, mailcow_template: "default"}}')"

  if [[ -z "${pk}" ]]; then
    local created
    created="$(authentik_api POST /api/v3/core/users/ "${body}")"
    _authentik_require 201 "create user ${username}" || return 1
    pk="$(jq -r '.pk // empty' <<<"${created}")"
    AUTHENTIK_CREATED=$((AUTHENTIK_CREATED + 1))
  else
    authentik_api PATCH "/api/v3/core/users/${pk}/" "${body}" >/dev/null
    _authentik_require 200 "update user ${username}" || return 1
  fi

  # The groups are attached by pk, and the list is replaced wholesale so a re-run
  # converges on exactly the requested membership rather than accumulating. An
  # empty list is built explicitly: `printf '%s\n'` with no arguments emits one
  # empty line, which would serialise to `[""]` and be rejected as an unknown pk.
  local -a group_pks=()
  local g p
  for g in "${groups[@]}"; do
    p="$(authentik_find_group "${g}")"
    [[ -n "${p}" ]] || { fail "group ${g} does not exist"; return 1; }
    group_pks+=("${p}")
  done
  local groups_json='[]'
  if (( ${#group_pks[@]} > 0 )); then
    groups_json="$(printf '%s\n' "${group_pks[@]}" | jq -R . | jq -sc .)"
  fi
  authentik_api PATCH "/api/v3/core/users/${pk}/" \
    "$(jq -nc --argjson gs "${groups_json}" '{groups: $gs}')" >/dev/null
  _authentik_require 200 "set groups on ${username}" || return 1

  # `set_password` is its own endpoint; it is not a field on the user object.
  authentik_api POST "/api/v3/core/users/${pk}/set_password/" \
    "$(jq -nc --arg p "${password}" '{password: $p}')" >/dev/null
  _authentik_require 204 "set password on ${username}" || return 1
}

# ---------------------------------------------------------------------------
# The whole flow
# ---------------------------------------------------------------------------
# `_authentik_app SLUG DISPLAY_NAME CLIENT_SECRET REDIRECT_URI...` is one
# application end to end: the provider, the application that carries it, and the
# binding that decides who may sign in. The client id is read from the matching
# `*_OIDC_CLIENT_ID` variable rather than derived from the slug, so the value the
# application is configured with and the value Authentik holds have one source.
_authentik_app() {
  local slug="$1" display="$2" secret="$3"
  shift 3
  local -a uris=("$@")

  local client_id_var client_id
  case "${slug}" in
    workcenter) client_id_var=WORKCENTER_OIDC_CLIENT_ID ;;
    filebrowser) client_id_var=FILEBROWSER_OIDC_CLIENT_ID ;;
    zulip) client_id_var=ZULIP_OIDC_CLIENT_ID ;;
    mailcow) client_id_var=MAILCOW_OIDC_CLIENT_ID ;;
    *) fail "_authentik_app: unknown slug ${slug}"; return 1 ;;
  esac
  client_id="${!client_id_var:-${slug}}"

  # Client type. OIDC.md §4.4 asks for `confidential` on every provider, and that
  # is right for the three applications that exchange the authorization code
  # **server-side** and can keep a secret. It cannot be right for Workcenter
  # itself: the shell runs in the browser and completes the exchange there
  # (`src/utils/auth/OidcAuth.js` via oidc-client-ts, no client secret anywhere in
  # it), so PKCE is what protects the exchange. Registered confidential, the token
  # endpoint answers `invalid_client` — verified against the pinned instance — and
  # the only way to satisfy it would be to ship the secret to every browser.
  local client_type='confidential'
  [[ "${slug}" == 'workcenter' ]] && client_type='public'

  authentik_ensure_oauth2_provider "${slug}" "${client_id}" "${secret}" \
    "$(printf '%s\n' "${uris[@]}")" "${client_type}" || return 1
  local provider_pk
  provider_pk="$(authentik_find_oauth2_provider "${client_id}")"
  authentik_ensure_application "${display}" "${slug}" "${provider_pk}" || return 1
  authentik_ensure_application_binding "${slug}" "${AUTHENTIK_USER_GROUP}" || return 1
  ok "provider + application: ${slug} (${client_id}, ${client_type})"
}

# Creates the groups and mappings first, then the four OIDC providers and their
# applications, then the proxy provider and the dashboard application, then the
# outpost membership, then the icons — the order production.md §5.5.3 prints.
#
# Every OIDC client secret is an input, not an output: the caller generates it,
# this writes it into Authentik, and the same value goes into the application's
# `.env`. That is what removes the read-back step and with it any chance of the
# two ends disagreeing.
#
#   WORKCENTER_OIDC_CLIENT_SECRET, FILEBROWSER_OIDC_CLIENT_SECRET,
#   ZULIP_OIDC_CLIENT_SECRET, MAILCOW_OIDC_CLIENT_SECRET
#
# and the hostnames each provider's redirect URIs are built from.
authentik_provision() {
  local -a required=(
    WORKCENTER_HOST FILEBROWSER_HOST CHAT_HOST MAIL_HOST TRAEFIK_HOST
    WORKCENTER_OIDC_CLIENT_SECRET FILEBROWSER_OIDC_CLIENT_SECRET
    ZULIP_OIDC_CLIENT_SECRET MAILCOW_OIDC_CLIENT_SECRET
  )
  local var
  for var in "${required[@]}"; do
    [[ -n "${!var:-}" ]] || { fail "authentik_provision needs ${var}"; return 1; }
  done

  # Reset the counters so a second call in one run reports its own work.
  AUTHENTIK_CREATED=0
  AUTHENTIK_UPDATED=0
  AUTHENTIK_UNCHANGED=0

  authentik_verify_token || return 1

  # --- groups (O-3.1) ------------------------------------------------------
  authentik_ensure_group "${AUTHENTIK_USER_GROUP}" || return 1
  authentik_ensure_group "${AUTHENTIK_ADMIN_GROUP}" || return 1
  ok "groups: ${AUTHENTIK_USER_GROUP}, ${AUTHENTIK_ADMIN_GROUP}"

  # --- scope mappings (§4.2, §4.5) -----------------------------------------
  authentik_ensure_scope_mappings || return 1

  # --- the four OIDC providers and applications (§5.4–§5.7) ----------------
  # Redirect URIs are the ones OIDC.md registers. FileBrowser is the exception
  # that matters: IN-3.5 says it derives its callback from the incoming request,
  # so the callback path is registered as well as the bare host — registering only
  # the host produces `invalid redirect URI` on the first login.
  _authentik_app 'workcenter' 'Workcenter' "${WORKCENTER_OIDC_CLIENT_SECRET}" \
    "https://${WORKCENTER_HOST}" "https://${WORKCENTER_HOST}/" || return 1
  _authentik_app 'filebrowser' 'FileBrowser' "${FILEBROWSER_OIDC_CLIENT_SECRET}" \
    "https://${FILEBROWSER_HOST}" "https://${FILEBROWSER_HOST}/" \
    "https://${FILEBROWSER_HOST}/api/auth/oidc/callback" || return 1
  # Zulip's redirect URI is the callback path and nothing else — the bare host is
  # not registered, because Zulip never redirects there (O-6.5).
  _authentik_app 'zulip' 'Zulip' "${ZULIP_OIDC_CLIENT_SECRET}" \
    "https://${CHAT_HOST}/complete/oidc/" || return 1
  _authentik_app 'mailcow' 'Mailcow' "${MAILCOW_OIDC_CLIENT_SECRET}" \
    "https://${MAIL_HOST}" "https://${MAIL_HOST}/" || return 1

  # --- the Traefik dashboard (§5.8) ----------------------------------------
  # The application is bound to `workspaceadmin` alone: this is the one surface
  # the admin group exists for, and the exit criteria test it explicitly.
  authentik_ensure_proxy_provider 'traefik-dashboard' "https://${TRAEFIK_HOST}" || return 1
  local proxy_pk
  proxy_pk="$(authentik_find_proxy_provider 'traefik-dashboard')"
  authentik_ensure_application 'Traefik' 'traefik' "${proxy_pk}" || return 1
  authentik_ensure_application_binding 'traefik' "${AUTHENTIK_ADMIN_GROUP}" || return 1
  authentik_ensure_outpost_membership "${proxy_pk}" || return 1
  authentik_ensure_outpost_host "${AUTHENTIK_URL}" || return 1
  ok 'proxy provider + application: traefik-dashboard, traefik (workspaceadmin only)'

  # --- make sign-out actually sign out (A-7) -------------------------------
  authentik_ensure_invalidation_logout || return 1

  # --- icons (P-33: reported, never fatal) ---------------------------------
  local icons_dir="${AUTHENTIK_ICONS_DIR:-${ROOT_DIR:-.}/icons}"
  authentik_ensure_application_icon 'workcenter' "${icons_dir}/workcenter.png"
  authentik_ensure_application_icon 'filebrowser' "${icons_dir}/filebrowser-quantum.svg"
  authentik_ensure_application_icon 'zulip' "${icons_dir}/zulip.svg"
  authentik_ensure_application_icon 'mailcow' "${icons_dir}/mailcow.svg"
  authentik_ensure_application_icon 'traefik' "${icons_dir}/traefik.svg"
  ok 'application icons uploaded and assigned'

  ok "Authentik provisioned (${AUTHENTIK_CREATED} created)"
}
