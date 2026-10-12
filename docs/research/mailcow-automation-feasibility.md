# Feasibility — automating the Mailcow deployment and its post-boot configuration

> **Status:** analysis for the `setup.sh` design (roadmap Phase 8). This file is not part of the
> specification set; `production.md`, `integration.md`, `OIDC.md` and `roadmap.md` remain authoritative.
>
> **Scope.** Two independent questions:
>
> * **Part 1 — deployment.** Can the Workcenter `setup.sh` pull Mailcow's repository and drive Mailcow's
>   own installer so that a Mailcow instance is generated, ready to be brought up with the rest of the
>   stack?
> * **Part 2 — configuration after boot.** Can Mailcow's API, once the stack is up, configure the
>   domain, the default mailbox, the admin account and the Authentik Generic-OIDC identity provider
>   without the Mailcow Web UI?
>
> **Method.** Both parts were verified against Mailcow's actual source (`master` @
> `ca07d8d3331849ae294179aedce95c8126d3050f`, 2026-09-21; API reports version `2026-09`) **and
> empirically**: `generate_config.sh` was run non-interactively, the merged Compose file was validated,
> a live Mailcow stack (11 services) was brought up, and the API calls in Part 2 were executed and their
> results confirmed in the database and through a real Web UI login. Everything below marked
> **verified** was executed in this environment; everything marked *source-verified* was read from
> Mailcow's code but not executed (noted where the environment could not reproduce a condition).

---

## 1. Verdicts

| | Verdict | One-line reason |
| --- | --- | --- |
| **Part 1 — generate a Mailcow instance** | ✅ **Feasible, with two required guards** | The installer runs fully non-interactively with the documented variables and the merged Compose validates — but `generate_config.sh` **exits 1 on a re-run** (an unguarded overwrite prompt), and `FORCE=y` authorises edits to the host Docker daemon on IPv6-capable hosts. |
| **Part 2 — configure Mailcow via the API** | ✅ **Feasible and verified end-to-end** | Domain, mailbox (`authsource: generic-oidc`), admin password and the Generic-OIDC identity provider were all configured through the API with no Web UI, and the admin logged in afterwards. |

One specification conflict must be resolved either way: **Mailcow holds a single identity provider at a
time**, so the plan's Generic-OIDC (I-MC-5) and LDAP (I-MC-6) providers cannot both be active for the
same deployment (§5.4).

---

## 2. Naming and prerequisites

* Mailcow has **no `setup.sh`**. Its installer is **`generate_config.sh`**; it also ships `update.sh`
  and `helper-scripts/`. Where the request says "mailcow's setup.sh", read `generate_config.sh`.
* The installer requires `openssl curl docker git awk sha1sum grep cut` **and `jq`**, with Docker ≥ 24.
  `jq` is a recent addition (`get_installed_tools` in `_modules/scripts/core.sh`) and is **not**
  mentioned in the Workcenter specs; a host without it fails immediately.
* The checkout must be a **real git clone** (not a source tarball): the generator runs `git fetch --all`
  and `git checkout -f "$MAILCOW_BRANCH"` when `MAILCOW_BRANCH` is set.

---

## 3. Part 1 — automating the deployment

### 3.1 The generation recipe, verified

The exact command from `production.md` §5.2 / `roadmap.md` I-MC-1 was executed against a fresh clone
with stdin closed:

```bash
cd Mailcow
export MAILCOW_HOSTNAME="mail.${BASE_DOMAIN}"
export MAILCOW_TZ="${TZ:-Etc/UTC}"
export MAILCOW_BRANCH="master"
export MAILCOW_DBPASS="$(openssl rand -hex 24)"
export MAILCOW_DBROOT="$(openssl rand -hex 24)"
export MAILCOW_REDISPASS="$(openssl rand -hex 24)"
export SKIP_CLAMD="${SKIP_CLAMD:-n}"
export FORCE="y"
./generate_config.sh </dev/null
```

**Result: exit 0, no blocking prompt, `mailcow.conf` written.** The variables the script honours are
confirmed in source: `MAILCOW_HOSTNAME`, `MAILCOW_TZ`, `MAILCOW_BRANCH`, `MAILCOW_DBPASS`,
`MAILCOW_DBROOT`, `MAILCOW_REDISPASS`, `SKIP_CLAMD`, `FORCE`. The values written matched the
environment (`MAILCOW_HOSTNAME`, `TZ`, and the three passwords taken verbatim rather than randomised).
The generator also wrote `data/web/inc/app_info.inc.php`, generated a snake-oil certificate, and made an
external "bad ASN" lookup — all harmless, all automatic.

The post-generation `sed` recipe was applied and verified to land:

| Key | Generated | After `sed` |
| --- | --- | --- |
| `HTTP_REDIRECT` | `y` | `n` |
| `SKIP_LETS_ENCRYPT` | `n` | `y` |
| `AUTODISCOVER_SAN` | `y` | `n` |
| `HTTP_BIND` | *(empty)* | `127.0.0.1` |
| `HTTPS_BIND` | *(empty)* | `127.0.0.1` |

`TRUSTED_PROXIES`, the six Workcenter host variables, `API_KEY`, `API_KEY_READ_ONLY` and
`API_ALLOW_FROM` are **not** emitted by the generator (confirmed: `TRUSTED_PROXIES` does not appear in
its output at all), so `setup.sh` must append them, exactly as `Mailcow/mailcow.conf.example`
documents.

### 3.2 Guard 1 — the re-run exits 1 (verified)

`generate_config.sh` contains an **unguarded** overwrite prompt:

```bash
if [ -f mailcow.conf ]; then
  read -r -p "A config file exists and will be overwritten, are you sure you want to continue? [y/N] " response
  ...
  *) exit 1 ;;
fi
```

`FORCE=y` does **not** bypass it (the only `FORCE` uses are the Docker-IPv6 prompt and image cleanup).

* Re-running with stdin closed → **exit 1**, no prompt visible in a script.
* Re-running with `y` piped → **exit 0**, moving the old file to `mailcow.conf_backup` (mode 600) and
  regenerating from scratch.

**Consequence.** *"so no prompt is reached"* (I-MC-1) is true **only on a first install**. `setup.sh`
must either (a) run the generator only when `mailcow.conf` is absent, (b) treat reconfiguration as an
explicit `--reconfigure` action that pipes `y`, or (c) detect the existing file and skip. Blindly
re-running it on every invocation wedges the installer, and option (b) discards every operator edit and
re-applies the `sed` recipe (which is fine only because the recipe is idempotent).

### 3.3 Guard 2 — `FORCE=y` can edit the host Docker daemon and restart Docker (*source-verified*)

`generate_config.sh` calls `configure_ipv6` unconditionally. On a host where IPv6 is detected, that
calls `docker_daemon_edit`, and with `FORCE` set it answers the confirmation itself:

```
Your daemon.json is missing: ipv6: true
  ans=Y                      # because FORCE is set
  cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
  jq '.ipv6 = true' ... → mv
  systemctl restart docker   # or: service docker restart
```

This environment has no usable IPv6 (only link-local, no connectivity), so the branch was skipped and
no daemon edit occurred — the source path is shown for hosts that do have IPv6. Two consequences for the
spec's framing of `FORCE=y` as merely "suppresses the interactive IPv6 daemon.json prompt" (P-10):

* it **approves** the edit and **restarts the Docker daemon**, which bounces every Workcenter container
  if the stack is already running;
* it requires `jq`, and it aborts the installer if `jq` is missing.

If a Workcenter `setup.sh` step must not restart Docker, the Mailcow generator should be invoked with
`configure_ipv6`'s manual override settled first (`ENABLE_IPV6` in `mailcow.conf`), or the operator
should be told that Mailcow may restart Docker.

### 3.4 The merged stack, verified

`Mailcow/docker-compose.override.yml` was dropped next to Mailcow's own `docker-compose.yml` and the
result validated **from inside `Mailcow/` with no `-f` flag** (IN-6.3/P-13):

```
docker compose config   → exit 0
```

The merged `nginx-mailcow` service, as resolved:

| Property | Merged value |
| --- | --- |
| networks | `mailcow-network` (alias `nginx`) + external `proxy` |
| published ports | `127.0.0.1:80→80`, `127.0.0.1:443→443` (from `HTTP_BIND`/`HTTPS_BIND`) |
| `expose` | `80` (from `${HTTP_PORT:-80}`) |
| Traefik labels | 10 |
| healthchecks | present on `nginx-mailcow`, `sogo-mailcow`, `mysql-mailcow`, `redis-mailcow` |

A live run then brought up **11 services** (`nginx`, `php-fpm`, `mysql`, `redis`, `dockerapi`,
`dovecot`, `sogo`, `rspamd`, `clamd`, `netfilter`, `unbound`) with no errors, so "ready to be brought
up" is demonstrated, not merely inferred. (The minimal `docker compose up -d mysql-mailcow …` command
also pulled and started the services those depend on.)

### 3.5 Repo hygiene gap

Cloning Mailcow into `Mailcow/` leaves most of its tree untracked in the Workcenter repository.
Workcenter's `.gitignore` ignores only `/Mailcow/.git/`, `/Mailcow/docker-compose.yml`,
`/Mailcow/mailcow.conf` (and `data/` via `**/data/`). Verified with `git check-ignore`:

| Path | Ignored? |
| --- | --- |
| `Mailcow/docker-compose.yml` | yes |
| `Mailcow/mailcow.conf` | yes |
| `Mailcow/data/…` | yes |
| `Mailcow/generate_config.sh` | **no** |
| `Mailcow/update.sh` | **no** |
| `Mailcow/helper-scripts/…` | **no** |
| `Mailcow/_modules/…` | **no** |
| `Mailcow/README.md` | **no** |

`setup.sh` should ignore the whole checkout except Workcenter's own files
(e.g. ignore `/Mailcow/*` and re-include `docker-compose.override.yml`, `mailcow.conf.example`,
`sogo-custom/`), or `git status` becomes unusable on every deployment.

### 3.6 Part 1 verdict

**Feasible.** Mailcow's installer is scriptable exactly as the spec assumes, and the resulting
configuration merges and runs. The two required guards are the re-run overwrite prompt (§3.2) and the
`FORCE` daemon-edit/restart on IPv6 hosts (§3.3); the `jq` prerequisite (§2) and the `.gitignore` gap
(§3.5) should also be fixed.

---

## 4. Part 2 — configuring Mailcow through its API

### 4.1 Enabling the API without the Web UI — verified

Mailcow's API key is checked against the **database `api` table**
(`data/web/inc/sessions.inc.php`: `SELECT … FROM api WHERE api_key = :api_key AND active = '1'`), with
per-row `access` (`rw`/`ro`) and `allow_from` ACL. The key is seeded by the php-fpm entrypoint from
environment variables that Compose takes from `mailcow.conf`
(`docker-compose.yml`: `API_KEY`, `API_KEY_READ_ONLY`, `API_ALLOW_FROM`):

```
DELETE FROM api WHERE access = 'rw';
INSERT INTO api (api_key, active, allow_from, access) VALUES ("${API_KEY}", "1", "${VALIDATED_IPS}", "rw");
```

So the whole bootstrap is declarative — **no Web UI, no manual key generation**. Verified live: after
setting `API_KEY`, `API_KEY_READ_ONLY` and `API_ALLOW_FROM=172.22.1.0/24,127.0.0.1` in `mailcow.conf`
and starting the stack, the `api` table held both active keys with the right ACLs, and:

| Call | Result |
| --- | --- |
| `GET /api/v1/get/status/version` with the **rw** key | `{"version":"2026-09"}` |
| `GET /api/v1/get/status/containers` with the **ro** key | 11 services, each `{type, container, state, started_at, image}` |
| any call with a wrong key | HTTP **401** |
| `POST /api/v1/edit/domain` with the **ro** key | `{"type":"error","msg":"API read/write access denied"}` |

(Confirmed against `production.md` §13.1: the read-only key is enough for the status probe.)

### 4.2 The API surface relevant to Workcenter

| Operation | Path | In the shipped OpenAPI? |
| --- | --- | --- |
| Add domain | `POST /api/v1/add/domain` | yes |
| Add mailbox (with `authsource`) | `POST /api/v1/add/mailbox` | yes |
| Edit mailbox / switch `authsource` | `POST /api/v1/edit/mailbox` | yes |
| Configure IdP (Generic-OIDC or LDAP) | `POST /api/v1/edit/identity-provider` | yes |
| Read IdP config | `GET /api/v1/get/identity-provider` | **no** |
| Test IdP config | `POST /api/v1/edit/identity-provider-test` | **no** |
| Add / edit / delete mailbox template | `/api/v1/{add,edit,delete}/mailbox/template` | **no** |
| Get mailbox templates | `GET /api/v1/get/mailbox/template[/all]` | **no** |
| Edit the global admin (password) | `POST /api/v1/edit/admin` | **no** |
| Container status | `GET /api/v1/get/status/containers` | yes |

Request envelope (`json_api.php`): **`add`** takes the attributes as the raw JSON body; **`edit`** takes
`{"items": [...], "attr": {...}}`; **`delete`** takes the items array. A request with a
`Sec-Fetch-Dest` header other than `empty` is rejected with 403, so browser-origin calls are blocked but
`curl`/scripts are not.

### 4.3 Generic-OIDC against Authentik — verified end-to-end

`identity_provider('edit', …)` requires, for `authsource: generic-oidc`, all of:
`authorize_url`, `token_url`, `userinfo_url`, `client_id`, `client_secret`, `redirect_url`,
`client_scopes` (it sets `ignore_ssl_error` and `login_provisioning` to `false` by default). These map
one-to-one onto `OIDC.md` §7.3 and the Authentik provider:

```bash
curl -X POST -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  https://mail.example.com/api/v1/edit/identity-provider -d '{
  "items": ["identity-provider"],
  "attr": {
    "authsource":     "generic-oidc",
    "authorize_url":  "https://auth.example.com/application/o/authorize/",
    "token_url":      "https://auth.example.com/application/o/token/",
    "userinfo_url":   "https://auth.example.com/application/o/userinfo/",
    "client_id":      "mailcow",
    "client_secret":  "<from Authentik>",
    "redirect_url":   "https://mail.example.com",
    "client_scopes":  "openid profile email mailcow_template",
    "default_template": "Default"
  }}'
```

Verified live: the call returned `object_modified`, `GET /api/v1/get/identity-provider` returned the
stored configuration, and the `identity_provider` table held exactly those key/value rows. The
`default_template` value resolves because Mailcow **seeds "Default" domain and mailbox templates** at
database initialisation; templates are additionally manageable through the (undocumented) template
routes, so the attribute mapping target does not require the UI either.

### 4.4 Domain, mailbox and admin — verified

| Step | Call | Verified result |
| --- | --- | --- |
| Domain | `POST /add/domain {"domain":"example.com",…}` | `domain_added` (DKIM generated automatically) |
| Mailbox, IdP-native | `POST /add/mailbox {…,"authsource":"generic-oidc"}` | `mailbox_added`; DB shows `authsource=generic-oidc` |
| Mailbox, switched later | `POST /edit/mailbox {"items":["user@example.com"],"attr":{"authsource":"generic-oidc"}}` | `mailbox_modified`; DB confirms |
| Admin password | `POST /edit/admin {"items":["admin"],"attr":{"password":…,"password2":…}}` | `admin_modified`; the stored hash changed to bcrypt |
| Admin actually logs in | `POST /admin/` with `login_user`/`pass_user` | **302 → `/admin/dashboard`** |

The successful admin login matters twice: it proves the API-made password change is real, and it proves
that enabling `generic-oidc` does **not** disable the local administrator login (the admin table is
separate from mailbox identities, and `check_login` only diverts to the IdP for `keycloak`/`ldap`).

`edit/admin` and the template routes are **not in Mailcow's shipped OpenAPI document**, though they are
routed and functional. They should be treated as implementation surface, not a public contract: pin the
Mailcow revision and re-test after upgrades, or prefer the documented calls where possible.

### 4.5 Behaviour to design around

* **No upsert.** Repeating `add/domain` returned `{"msg":["domain_exists","example.com"]}`. `setup.sh`
  must check first (`GET /api/v1/get/domain/<domain>`, `get/mailbox/<address>`) or treat the "exists"
  reply as idempotent success.
* **Single identity provider.** Setting the IdP to `ldap` while `generic-oidc` mailboxes exist returned
  `{"msg":["authsource_in_use",null]}`. Mailcow stores one IdP configuration and refuses to change the
  source while mailboxes use another, so **`I-MC-5` (Generic-OIDC) and `I-MC-6` (LDAP) are mutually
  exclusive** for a given deployment. Either pick one for the UI, or configure LDAP out-of-band and keep
  Generic-OIDC as the UI source (or vice versa) — but not both through this endpoint.
* **The client secret comes back.** `GET /api/v1/get/identity-provider` returns `client_secret` (and
  `access_token`) to an authenticated rw caller. A read-only key is intended for status probes only; the
  rw key must be handled as a secret by `setup.sh`.
* **`identity-provider-test`** returned `{"type":"success","msg":"Task completed"}`; it queues a test and
  does not synchronously prove the endpoints are reachable, so it is a smoke check, not a substitute for
  a real login.

### 4.6 What still needs a human / the Web UI

* **Mailcow UI branding** (light/dark logos, UI texts): stored in Redis by a form POST; Mailcow exposes
  no API for it. `production.md` already says so.
* **The SOGo session**: users reach SOGo through the Mailcow UI's *Login to Webmail*
  (`/sogo-auth.php?login=…`), a user action; SOGo's own login form is the fallback (`OIDC.md` O-7.4).
* **Mail-protocol credentials**: app passwords or LDAP (unchanged by this work). Note that
  `OIDC.md` O-7.2's single `UPDATE` for a mailbox's `authsource` is no longer necessary — the API's
  `edit/mailbox` does it.

### 4.7 Part 2 verdict

**Feasible, and verified positively.** Mailcow can be configured for the Workcenter Authentik OIDC
provider **entirely through its API** after the stack is up: API keys are seeded declaratively from
`mailcow.conf`; the domain, the default mailbox (born with `authsource=generic-oidc` or switched later),
the admin password and the full Generic-OIDC provider (endpoints, client, redirect URL, scopes and
attribute-mapping template) were all set and confirmed. The main design constraints are the
single-IdP rule (§4.5) and the absence of upsert.

---

## 5. Recommended shape for `setup.sh`

**Stage B (deployment).**

1. Clone Mailcow if `Mailcow/docker-compose.yml` is absent (`git clone … mailcow-dockerized .` into
   `Mailcow/`); otherwise `git -C Mailcow fetch && git -C Mailcow checkout master` to pick up current
   tooling (or leave updates to `update.sh` per `production.md` §10.2).
2. Verify `jq` and Docker ≥ 24 alongside the other prerequisites.
3. If `mailcow.conf` is **absent**: run `generate_config.sh` with the documented variables and
   `FORCE=y`. If it is **present**: skip it (default), or require an explicit `--reconfigure` that pipes
   `y` and then re-applies every Workcenter key.
4. Apply the five `sed` keys and append `TRUSTED_PROXIES`, the six host variables, `API_KEY`,
   `API_KEY_READ_ONLY`, `API_ALLOW_FROM`.
5. Warn (or refuse, per policy) if the host has usable IPv6, because `FORCE=y` may rewrite
   `/etc/docker/daemon.json` and restart Docker.

**Stage F/G (after `docker compose up -d` in `Mailcow/`).** With the rw key:

1. `GET /api/v1/get/status/version` to confirm the API is live.
2. Ensure the domain (`GET /api/v1/get/domain/<domain>`; `add/domain` if absent).
3. Ensure the IdP (`edit/identity-provider`, `authsource: generic-oidc`, Authentik endpoints,
   `client_scopes: openid profile email mailcow_template`, `default_template: Default`).
4. Ensure the admin password (`edit/admin`) — replacing Mailcow's default `moohoo`.
5. Ensure the default mailbox (`add/mailbox`, `authsource: generic-oidc`).
6. Optionally `edit/identity-provider-test`, then a real UI login smoke test.

**Specification updates to make when this lands**

* `production.md` §5.2 / `roadmap.md` I-MC-1: state the re-run guard, the `jq` prerequisite and the
  `FORCE` daemon-edit caveat.
* `roadmap.md` I-MC-5 / `OIDC.md` §7.3: the IdP is configurable through the API; keep the UI steps as
  the manual fallback.
* Resolve I-MC-5 vs I-MC-6 (single-IdP constraint).
* Broaden `.gitignore` for the Mailcow checkout.
* `OIDC.md` O-7.2 can note that `edit/mailbox` replaces the raw `UPDATE`.

---

## 6. Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| `generate_config.sh` re-run prompt (verified exit 1) | Stalled non-interactive deployment | Run only on first install, or gate behind `--reconfigure` |
| `FORCE=y` + IPv6 host (*source-verified*) | Docker daemon restart; other containers bounce | Detect IPv6 first; warn/refuse, or pre-settle `ENABLE_IPV6` |
| `jq` missing | Installer aborts on install/prereq check | Add `jq` to prerequisites |
| Undocumented endpoints (`edit/admin`, templates) | Breakage across Mailcow upgrades | Pin the Mailcow revision; re-test after `update.sh`; fall back to the UI |
| Single IdP (verified `authsource_in_use`) | OIDC and LDAP cannot coexist | Choose one; document the trade-off |
| No upsert (verified `domain_exists`) | Re-runs error | GET-first or treat "exists" as success |
| rw key exposure | The rw key reads the OIDC client secret | Store with the other secrets; keep the ro key for status probes |
| Version drift | Mailcow changes the API/entrypoint behaviour | `setup.sh` reports the detected Mailcow commit/version and the checks it ran |

---

## 7. Sources

Mailcow (all read at `master` @ `ca07d8d…`, 2026-09-21; cloned locally for inspection):

* `generate_config.sh` — environment variables, the overwrite prompt, the IPv6 call.
* `_modules/scripts/ipv6_controller.sh` — `configure_ipv6`, `docker_daemon_edit`, the `FORCE` path and
  the Docker restart.
* `_modules/scripts/core.sh` — `get_installed_tools` (the `jq` requirement).
* `data/Dockerfiles/phpfpm/docker-entrypoint.sh` — API key seeding (`DELETE`/`INSERT` into `api`).
* `docker-compose.yml` — `API_KEY`, `API_KEY_READ_ONLY`, `API_ALLOW_FROM` env wiring; image tags.
* `data/web/inc/sessions.inc.php` — `X-API-Key` validation against the `api` table.
* `data/web/json_api.php` — request envelope; the `add`/`edit`/`get`/`delete` routes, including
  `admin`, `identity-provider`, `identity-provider-test` and the template sub-routes.
* `data/web/inc/functions.inc.php` — `identity_provider()`: required Generic-OIDC fields, the
  single-IdP `authsource_in_use` check, storage in `identity_provider`.
* `data/web/inc/functions.admin.inc.php` — `admin('edit')` (password).
* `data/web/inc/functions.mailbox.inc.php` — mailbox `authsource` handling (`generic-oidc`).
* `data/web/inc/functions.auth.inc.php` — `check_login`/`admin_login`: the admin path and the
  `generic-oidc` non-diversion.
* `data/web/inc/init_db.inc.php` — the `identity_provider` and `templates` tables, the seeded "Default"
  domain/mailbox templates.
* `data/web/api/openapi.yaml` — the documented endpoint list and `add/domain`, `add/mailbox`,
  `edit/mailbox`, `edit/identity-provider` schemas.
* `data/conf/nginx/templates/sites-default.conf.j2` — the `/api/v1/` route to `json_api.php`.
* Mailcow documentation: <https://docs.mailcow.email/> (installation, API).

Workcenter:

* `production.md` §5.2 (Stage B Mailcow recipe, P-9…P-13), §8, §10.2, §13.1
* `integration.md` §6 (IN-6.1…IN-6.7), `OIDC.md` §7 (O-7.1…O-7.5), `roadmap.md` §6.3 (I-MC-1…I-MC-14)
* `Mailcow/mailcow.conf.example` and `Mailcow/docker-compose.override.yml`
* `docs/research/authentik-api-feasibility.md` — the Authentik side of the OIDC provider
