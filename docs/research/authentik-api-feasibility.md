# Feasibility — automating Authentik providers and applications

> **Status:** analysis for the `setup.sh` design (roadmap Phase 4). This file is not part of the
> specification set; `OIDC.md`, `production.md` and `integration.md` remain authoritative.
>
> **Question.** `production.md` §5.5 and `OIDC.md` §5/§8 record "exactly one manual step": after
> Authentik is deployed, a human creates the groups, the scope mappings, five providers/applications
> and the embedded-outpost membership in the Authentik Web UI, then re-runs `setup.sh` to paste the
> values. Can the Authentik REST API (or its declarative blueprint mechanism) create all of that for
> the four integrated applications, so the manual step can be removed?

---

## 1. Answer

**Yes.** Every object the Workcenter specification requires can be created programmatically, for all
four applications plus the Traefik-dashboard consumer, using either:

* the **v3 REST API** (`/api/v3/…`, OpenAPI 3), authenticated with the token that
  `AUTHENTIK_BOOTSTRAP_TOKEN` already creates for `akadmin` on first startup; or
* **blueprints** — Authentik's own declarative, reconciled, transactional YAML provisioning mechanism,
  which is a better fit for a script that already renders configuration files.

Three things are outside that statement and must be planned for:

1. **Mailcow's own Identity-Provider settings** (System → Configuration → Access → Identity Provider,
   and each mailbox's `Generic-OIDC` flag) live in Mailcow, not Authentik. The Authentik side for
   Mailcow is automatable; the Mailcow side is a separate system (`OIDC.md` §7.3, O-7.2).
2. **Version shape changes.** The repository pins `AUTHENTIK_TAG=2024.12` (`architecture.md` §6.1)
   while the published documentation describes 2026.8 and the published OpenAPI schema is a
   2026.11 pre-release. Endpoint *paths* are stable, but **field shapes and defaults are not**
   (§7). The automation must be validated against the tag that is actually pinned.
3. **`production.md`'s "exactly one manual step"** becomes "**no manual Authentik step; one remaining
   Mailcow-side step**", so that sentence needs to change.

---

## 2. What the specification requires today

`OIDC.md` §4.1 enumerates fifteen objects, and §4.4 the settings that apply to all five providers:

| # | Object | Type | Name |
| --- | --- | --- | --- |
| 1–2 | Group | Directory → Groups | `workspaceusers`, `workspaceadmin` |
| 3 | Property (scope) mapping | Customization → Property Mappings | `groups` (plus `email-verified`, `mailcow_template`; optional `zulip_groups`/`zulip_role`) |
| 4–11 | Provider + Application | OAuth2/OpenID + Application | `workcenter`, `filebrowser`, `zulip`, `mailcow` |
| 12–13 | Provider + Application | Proxy + Application | `traefik-dashboard`, application `traefik` |
| 14 | Outpost | Applications → Outposts | `authentik Embedded Outpost` (must include the proxy provider) |
| 15 | Outpost (optional) | Applications → Outposts | `ldap` (only for the LDAP mail-protocol mode) |

Provider settings common to all of them: authorization flow
`default-provider-authorization-implicit-consent`, invalidation flow
`default-provider-invalidation-flow`, client type **Confidential**, signing key
`authentik Self-signed Certificate`, encryption key **empty**, scopes
`openid profile email-verified groups` (+ `offline_access` where silent renewal is on), *Include claims
in id_token* **on**, access/refresh token validity, and an application access binding to
`workspaceusers` (`workspaceadmin` for the dashboard).

---

## 3. The automation surfaces Authentik provides

### 3.1 Solving the bootstrap (authentication)

| Variable | Effect |
| --- | --- |
| `AUTHENTIK_BOOTSTRAP_TOKEN` | Creates an API token for `akadmin`. The value *is* the token key: "the string you specify for this variable is the token key you can use to authenticate yourself to the API." Read on the **first** startup only. |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` / `_HASH` | Sets the `akadmin` password (plain or pre-hashed). Setting both is an error. |
| `AUTHENTIK_BOOTSTRAP_EMAIL` | Sets `akadmin`'s email. |

The specification already generates and passes these (`OIDC.md` §5.1, `integration.md` §7.2), so
`setup.sh` can authenticate as soon as Authentik is healthy with
`Authorization: Bearer $AUTHENTIK_BOOTSTRAP_TOKEN`. The API base is `/api/v3/` (schema at
`/api/v3/schema/`, browser at `/api/v3/`), and requests are plain JSON. Session-cookie auth is also
possible but then needs a CSRF header; API tokens are the right choice here.

> On an *existing* instance the bootstrap token is not re-read. `setup.sh` must then create its own
> token (`POST /api/v3/core/tokens/`, `intent: api`) — and note that a token's key is **not** settable
> through create; it is read with `…/{identifier}/view_key/` or set with `…/set_key/` (blueprints may
> set `key` directly).

### 3.2 The REST API — verified create operations

Extracted from the published OpenAPI 3 schema (`https://api.goauthentik.io/schema.yml`); `required`
and property lists are copied from `components.schemas`. **The published schema is a 2026.11
pre-release; confirm field shapes against the pinned instance's own `/api/v3/schema/`.**

| Object | Operation | Required | Key optional fields |
| --- | --- | --- | --- |
| Group | `POST /api/v3/core/groups/` | `name` | `is_superuser`, `parents`, `roles`, `attributes`, `users` |
| Scope mapping | `POST /api/v3/propertymappings/provider/scope/` | `expression`, `name`, `scope_name` | `description`, `managed` |
| OAuth2/OIDC provider | `POST /api/v3/providers/oauth2/` | `authorization_flow`, `invalidation_flow`, `name`, `redirect_uris` | `client_type`, `grant_types`, `client_id`, `client_secret`, `property_mappings`, `signing_key`, `encryption_key`, `include_claims_in_id_token`, `sub_mode`, `issuer_mode`, token validity, `logout_uri`, `logout_method` |
| Application | `POST /api/v3/core/applications/` | `name`, `slug` | `provider` (FK), `meta_launch_url`, `meta_description`, `policy_engine_mode`, `open_in_new_tab`, `backchannel_providers` — **`group` is a free-text dashboard grouping label, not an access binding** |
| Policy binding (access) | `POST /api/v3/policies/bindings/` | `order`, `target` | **`group` (UUID)**, `user`, `policy`, `negate`, `enabled`, `timeout`, `failure_result` |
| Proxy provider | `POST /api/v3/providers/proxy/` | `authorization_flow`, `external_host`, `invalidation_flow`, `name` | `mode` (`forward_single`/`forward_domain`), `internal_host`, `internal_host_ssl_validation`, `certificate`, `skip_path_regex`, `cookie_domain` |
| Outpost | `POST /api/v3/outposts/instances/` | `config`, `name`, `providers`, `type` | `managed`, `service_connection` |
| API token | `POST /api/v3/core/tokens/` | `identifier` | `intent`, `user`, `expiring`, `expires` |

Resolving the objects the spec references by name/slug:

| Lookup | Endpoint |
| --- | --- |
| Default flows | `GET /api/v3/flows/instances/?slug=<slug>` (flow UUIDs are `uuid4`, never deterministic) |
| Built-in signing certificate | `GET /api/v3/crypto/certificatekeypairs/?name=authentik Self-signed Certificate` |
| Existing application (idempotency) | `GET /api/v3/core/applications/?slug=<slug>` |
| Existing OAuth2 provider | `GET /api/v3/providers/oauth2/?client_id=<id>` — **provider `name` is not unique**, `client_id` is |
| Scope mapping | `GET /api/v3/propertymappings/provider/scope/?managed=<managed-id>` (see §3.5) |
| Embedded outpost | `GET /api/v3/outposts/instances/?managed__iexact=goauthentik.io/outposts/embedded` |

Field semantics worth recording:

* **`redirect_uris` is version-dependent.** In the current schema each item is an *object*
  (`{url, matching_mode}`); Authentik 2026.5 made this a breaking change and it was an array of
  **strings** before that — including at the pinned 2024.12. The automation must emit the shape the
  pinned tag accepts. Matching is strict (or `regex` on the newer shape).
* **`grant_types`** was added in 2026.5. The model/serializer default is an **empty list**, and the
  authorize view rejects any grant not in it, so a provider created by API on a 2026.5+ instance must
  send `grant_types: [authorization_code, refresh_token]` explicitly even though the WebUI's "all
  selected" wording suggests otherwise. *(Source-derived; confirm on the pinned version.)*
* **`client_secret`** is writable on create and returned by the response to a caller with change
  permission — so a caller may either preset it or read back the generated value.
* **`include_claims_in_id_token`** is `true` by default in current source, but the spec requires it on,
  so set it explicitly.
* **`signing_key`** may be omitted, in which case Authentik signs with HS256 using the provider's
  `client_secret` and publishes **no JWKS key**. The spec wants the `authentik Self-signed Certificate`
  for asymmetric signing (RS256 + `kid`), so set it explicitly.
* `client_type` enum: `confidential`, `public`. `sub_mode` enum: `hashed_user_id`, `user_id`,
  `user_uuid`, `user_username`, `user_email`, `user_upn`. `issuer_mode`: `global`, `per_provider`
  (default per-provider, which yields `https://auth.<base>/application/o/<slug>/`).
* List endpoints are paginated (`page`, `page_size`, `ordering`, `search`) plus field filters. **There
  is no upsert**: look up by a unique key, then `PATCH`, else `POST`.

### 3.3 Blueprints — the stronger fit

A blueprint is a YAML file (`version: 1`, `metadata`, `context`, `entries`) that Authentik reconciles
into objects. Verified properties:

* **Entry shape:** `model` (e.g. `authentik_providers_oauth2.oauth2provider`), `id`, `identifiers`
  (model fields, used as the lookup key), `attrs`, `state` (`present` default, `created`,
  `must_created`, `absent`), `conditions`.
* **Tags:** `!KeyOf <id>` (resolve another entry's PK), `!Env <VAR>[, default]`,
  `!Find [model, [field, value]]`, `!FindObject`, `!File`, `!Format`, `!If`, `!Context`.
* **Model names** (from the blueprint JSON schema `https://goauthentik.io/blueprints/schema.json`):
  `authentik_core.group`, `authentik_core.application`, `authentik_core.token`, `authentik_core.user`,
  `authentik_crypto.certificatekeypair`, `authentik_flows.flow`, `authentik_outposts.outpost`,
  `authentik_policies.policybinding`, `authentik_providers_oauth2.oauth2provider`,
  `authentik_providers_oauth2.scopemapping`, `authentik_providers_proxy.proxyprovider`.
* **The OAuth2 provider attrs include `client_secret`, `client_id`, `redirect_uris`,
  `property_mappings`, `signing_key`, `client_type`, `sub_mode`, `include_claims_in_id_token`** — a
  blueprint can fully define a provider, including presetting the secret from `!Env`.
* **Discovery and application:** files under the worker's `/blueprints` directory are discovered and
  applied automatically (on startup, on file change, and by a periodic scan — 60 minutes by default);
  alternatively the API exposes `/api/v3/managed/blueprints/` (`import/`, `validate/`,
  `{uuid}/apply/`). **Execution is one atomic transaction** — a failing entry applies nothing.
* **Idempotency is built in:** `state: present` creates or updates the listed attrs; `identifiers`
  locate the object.

A representative rendering of one provider (placeholders, and **string-form `redirect_uris` to match
the pinned 2024.12** — see §7):

```yaml
# yaml-language-server: $schema=https://goauthentik.io/blueprints/schema.json
version: 1
metadata:
  name: workcenter-oidc
entries:
  - model: authentik_core.group
    id: workspaceusers
    identifiers: { name: workspaceusers }
    attrs: { name: workspaceusers }

  - model: authentik_providers_oauth2.scopemapping
    id: groups-mapping
    identifiers: { name: groups }
    attrs:
      name: groups
      scope_name: groups
      expression: |
        return {"groups": [g.name for g in request.user.ak_groups.all()]}

  - model: authentik_providers_oauth2.scopemapping
    id: email-verified-mapping
    identifiers: { name: email-verified }
    attrs:
      name: email-verified
      scope_name: email
      expression: |
        return {"email": request.user.email, "email_verified": True}

  - model: authentik_providers_oauth2.oauth2provider
    id: workcenter-provider
    identifiers: { client_id: workcenter }   # name is not unique; client_id is
    attrs:
      name: workcenter
      authorization_flow: !Find [authentik_flows.flow, [slug, default-provider-authorization-implicit-consent]]
      invalidation_flow: !Find [authentik_flows.flow, [slug, default-provider-invalidation-flow]]
      client_type: confidential
      client_id: workcenter
      client_secret: !Env WORKCENTER_OIDC_CLIENT_SECRET
      redirect_uris:            # string form for the pinned 2024.12; object form from 2026.5
        - https://example.com
        - https://example.com/
      property_mappings:
        - !Find [authentik_providers_oauth2.scopemapping, [managed, goauthentik.io/providers/oauth2/scope-openid]]
        - !Find [authentik_providers_oauth2.scopemapping, [managed, goauthentik.io/providers/oauth2/scope-profile]]
        - !KeyOf email-verified-mapping
        - !KeyOf groups-mapping
      signing_key: !Find [authentik_crypto.certificatekeypair, [name, "authentik Self-signed Certificate"]]
      include_claims_in_id_token: true

  - model: authentik_core.application
    id: workcenter-app
    identifiers: { slug: workcenter }
    attrs:
      name: Workcenter
      slug: workcenter
      provider: !KeyOf workcenter-provider
      meta_launch_url: https://example.com

  # Access is a policy binding, not the application's `group` label.
  - model: authentik_policies.policybinding
    identifiers: { target: !KeyOf workcenter-app, group: !KeyOf workspaceusers }
    attrs:
      order: 0
      enabled: true
```

Defaults confirmed against Authentik's own source rather than assumed:

* Flow slugs: `default-provider-authorization-implicit-consent`,
  `default-provider-invalidation-flow`, `default-authentication-flow`
  (`blueprints/default/flow-*.yaml` in the Authentik repository).
* The embedded outpost is created automatically with
  `managed = goauthentik.io/outposts/embedded` and name `authentik Embedded Outpost`
  (`authentik/outposts/apps.py`); its reconciliation does **not** overwrite `providers`, so an added
  proxy provider persists.
* The built-in scope mappings carry stable managed identifiers
  (`goauthentik.io/providers/oauth2/scope-openid`, `…/scope-email`, `…/scope-profile`,
  `…/scope-offline_access`, …), which are the robust `!Find` keys — `scope_name` alone can be
  ambiguous once a custom mapping shares it.

### 3.4 API or blueprints?

| | REST API | Blueprints |
| --- | --- | --- |
| Idempotency | manual lookup + `PATCH` | built in (`identifiers`, `state`) |
| Atomicity | per-request | per-apply, all-or-nothing |
| Secrets | returned by the create response | injected with `!Env`/`!File` |
| UUID chasing | every FK resolved by hand | `!Find`/`!KeyOf` do it |
| Versionability | code in `setup.sh` | a rendered file, diffable and reviewable |
| Availability | HTTP only | also works at startup |

**Recommendation: blueprints as the provisioning mechanism, the REST API as the control plane** — the
API is still needed to verify what was created, to read back secrets/issuer URLs when they are not
preset, and to `PATCH` the embedded outpost's `providers` list.

---

## 4. Object-by-object mapping

| Spec object | Blueprint model / API path | Notes |
| --- | --- | --- |
| `workspaceusers`, `workspaceadmin` | `authentik_core.group` / `POST /core/groups/` | `workspaceadmin` is the `adminGroup` every app checks |
| `groups` mapping | `authentik_providers_oauth2.scopemapping` / `POST /propertymappings/provider/scope/` | see §6 — the built-in `profile` mapping already emits `groups` on modern versions |
| `email-verified` mapping | same | `scope_name: email`; returns `{"email": …, "email_verified": True}`; must **replace** the built-in `email` scope where that one hardcodes `false` (since 2025.10) |
| `mailcow_template` mapping | same | the claim Mailcow's attribute mapping matches for auto-provisioning |
| `zulip_groups` / `zulip_role` (optional) | same | only if group→role sync is automated out of band (IN-5.18) |
| Signing keys | `!Find` the built-in `authentik Self-signed Certificate`; `POST /crypto/certificatekeypairs/generate/` to create one | set it explicitly; empty means HS256 and no JWKS key |
| Flows | `!Find [authentik_flows.flow, [slug, …]]` / `GET /flows/instances/?slug=` | the two provider flows above |
| `workcenter`, `filebrowser`, `zulip`, `mailcow` providers | `authentik_providers_oauth2.oauth2provider` / `POST /providers/oauth2/` | see §5 for per-app fields |
| Their applications | `authentik_core.application` / `POST /core/applications/` | `provider` = the provider PK |
| Their access binding | `authentik_policies.policybinding` / `POST /policies/bindings/` | `target` = application, `group` = `workspaceusers`; **not** `Application.group` |
| `traefik-dashboard` provider | `authentik_providers_proxy.proxyprovider` / `POST /providers/proxy/` | `mode: forward_single`, `external_host: https://traefik.<base>` |
| `traefik` application + binding | `authentik_core.application` + `authentik_policies.policybinding` | binding group = `workspaceadmin` |
| Embedded outpost membership | `authentik_outposts.outpost` / `PATCH /outposts/instances/{uuid}/` | append the proxy provider's PK to `providers` |
| Optional LDAP outpost | `authentik_outposts.outpost` (`type: ldap`) | only for the `oidc+ldap` mail-protocol mode; Mailcow's LDAP settings remain Mailcow-side |

---

## 5. Per-application requirements (the Authentik side)

Redirect URIs were taken from the applications' own behaviour, not guessed:

| Application | Client ID | Redirect URI(s) to register | Scopes / claims | Source |
| --- | --- | --- | --- | --- |
| **Workcenter** shell | `workcenter` | `https://<base>` and `https://<base>/` | `openid profile email-verified groups` (+`offline_access`); `groups`, `preferred_username` | `src/utils/auth/OidcAuth.js:87` sets `redirect_uri = window.location.origin` |
| **FileBrowser Quantum** | `filebrowser` | `https://filebrowser.<base>/api/auth/oidc/callback` | `openid profile email-verified groups`; `groupsClaim: groups`, `userIdentifier: preferred_username`, `adminGroup: workspaceadmin` | `integration.md` IN-3.5; `Filebrowser/config.yaml:44` |
| **Zulip** | `zulip` | `https://chat.<base>/complete/oidc/` | `openid profile email-verified groups`; `extra_attrs: [groups]` | `OIDC.md` O-6.5, §6.3 |
| **Mailcow / SOGo** | `mailcow` | `https://mail.<base>` | `openid profile email mailcow_template` | `OIDC.md` §7.3 |

> **Spec inconsistency found.** `OIDC.md` §5.5 tells the operator to register
> `https://filebrowser.example.com` and `…/` for FileBrowser, but the application derives its callback
> from the request as `…/api/auth/oidc/callback` (`integration.md` IN-3.5, `Filebrowser/config.yaml`).
> The automation must register the **callback path**, or FileBrowser login fails with a redirect-URI
> mismatch. `OIDC.md` §5.5 should be corrected when the automation lands.

---

## 6. Findings that touch the Workcenter specification

1. **The custom `groups` scope mapping may be unnecessary.** Authentik's built-in `profile` scope
   mapping already returns `groups` (and `preferred_username`, `name`, `picture`) on 2026.x — verified
   in `blueprints/system/providers-oauth2.yaml` at 2025.12, 2026.5 and 2026.8.5. `OIDC.md` §4.2's
   premise ("Authentik does not put group membership in the id_token by default") is therefore **not
   true on current releases**; `integration.md` IN-7.6 already states that the `profile` scope is what
   emits `groups`. At the pinned 2024.12 the built-in behaviour is **unverified**, and the custom
   mapping is harmless, so the safe move is: keep creating it, and drop it only after verifying the
   built-in `profile` output on the pinned tag. The expression is also version-sensitive:
   `request.user.ak_groups.all()` on ≤2026.5, `request.user.groups.all()` on 2026.8.
2. **The access binding is a `PolicyBinding`, not `Application.group`.** The API's
   `ApplicationRequest.group` is a free-text dashboard grouping label. The WebUI's "bind a group to an
   application" creates a policy binding (`target` = application, `group` = group); the automation must
   do the same, or every user will be able to start a login or none will.
3. **FileBrowser's redirect URI** is the callback path, not the host (§5).
4. **The built-in `email` scope's `email_verified`** is `false` from 2025.10 onward, which is why
   `OIDC.md` §4.5 introduces `email-verified`; on the pinned 2024.12 the built-in may still be `true`,
   so this too is a bump-time concern.
5. **`AUTHENTIK_TAG=2024.12` should be revisited.** The docs (2026.8) and the published schema
   (2026.11-rc) are two to three release trains ahead. Nothing requires the newest version, but the
   automation should be written and tested against a tag whose API shape is confirmed, and the pin
   recorded next to it.

---

## 7. Risks and version sensitivity

1. **Version drift is the dominant risk.** Endpoint paths and model names are stable, but:
   * `redirect_uris` changed from an array of **strings** to an array of **objects**
     (`{url, matching_mode}`) in **2026.5** — a documented breaking API change.
   * `grant_types` was added in **2026.5** (default empty in source), so it must be sent explicitly.
   * The built-in `email` mapping changed `email_verified` `true` → **`false`** in **2025.10**.
   * The `profile` scope's group expression changed at **2026.8** (`groups` vs `ak_groups`).
   * `sub_mode` gained `user_upn`; Redis was removed in 2025.10 (compose-only).
   The automation must query the pinned instance's `/api/v3/schema/` (or be pinned to a verified tag)
   rather than assume the published schema.
2. **No upsert in the API.** Create-or-`PATCH` by a unique key (`client_id` for providers — `name` is
   not unique — `slug` for applications, `name` for groups, `managed` for built-in mappings). A naive
   `POST` on a re-run fails with a uniqueness error. Blueprints avoid this.
3. **Signing key.** If omitted, the provider signs with HS256/`client_secret` and has no JWKS key. Set
   the built-in certificate explicitly.
4. **Property mappings are not defaulted.** The API does not preselect `openid`/`email`/`profile`
   (the Admin UI does it in the browser). Omit `property_mappings` and the provider has **no scopes**,
   so no `groups` claim ever arrives.
5. **Secrets in blueprints.** `!Env` reads the worker container's environment, so generated client
   secrets must be passed to the **worker** as well as the `server`, or injected with `!File` from a
   mounted, gitignored, mode-600 file. The rendered blueprint must never be committed.
6. **Blueprint application timing.** Discovery is startup + file change + a periodic scan (60 minutes
   by default); `setup.sh` must wait for and verify the apply through the API, not assume it is
   instant. A malformed blueprint applies nothing (which is good, but must be reported).
7. **Embedded outpost.** Created automatically; the proxy provider must be `PATCH`ed into `providers`.
   `authentik_host` may need setting to `https://auth.<base>/`. Forward auth also needs the two Traefik
   routers (`integration.md` IN-7.8).
8. **Redirect URIs are exact.** Trailing-slash variants matter, and FileBrowser derives its callback
   from the request — so Traefik must pass `X-Forwarded-Proto`/`-Host` (IN-3.5) and
   `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` must include Traefik (IN-7.4), or the issuer is `http://`.
9. **Bootstrap token lifetime.** Read only on first startup; an existing instance needs a token created
   through the API or supplied in `.env`, and a narrow token should be created for `setup.sh`.
10. **Reported API defect.** GitHub issue
    [#16685](https://github.com/goauthentik/authentik/issues/16685) reports `HTTP 405` on
    `POST /api/v3/providers/oauth2/` in some version. **Not verified here** — check it against the
    pinned tag before choosing a REST-only path. (Another reason to prefer blueprints, which do not go
    through that endpoint.)

---

## 8. Recommended shape for `setup.sh` Stage D

1. Generate the client secrets and the Authentik bootstrap values (as `OIDC.md` §5.1 already does) and
   write them to `Authentik/.env`, passing the secret set to **both** `server` and `worker`.
2. Render `Authentik/data/blueprints/workcenter.yaml` (gitignored, mode 600) from the base URL and the
   generated secrets, with one entry per object in §4.
3. Bring Authentik up; wait for `/-/health/ready/`.
4. Apply: rely on the mount watch, or `POST /api/v3/managed/blueprints/import/` +
   `…/{uuid}/apply/`; then read the objects back (`GET …/?slug=…`, `?client_id=…`) to confirm.
5. `PATCH` the embedded outpost to include the `traefik-dashboard` provider.
6. Write the resulting issuer URLs and client IDs/secrets into the root `.env`, `Filebrowser/.env`,
   `Zulip/secrets/` and `Mailcow/workcenter-oidc.env` exactly as Stage D does today.
7. Keep the current manual walkthrough as the fallback when the automation fails or the operator
   declines it — including the exact stop message (`OIDC.md` §8.6).
8. Print the Mailcow-side remainder as the one remaining human step.

## 9. Verification plan

* Fresh deploy of the **pinned** `AUTHENTIK_TAG`; run the automation; assert the fifteen objects exist
  with the correct flows, scopes, redirect URIs and access bindings.
* Sign in through each application: Workcenter shell, FileBrowser, Zulip
  (`/login/oidc/?idp=oidc`), Mailcow UI; inspect the id_token/userinfo for `groups`,
  `preferred_username`, `email_verified` and `mailcow_template`.
* Re-run: idempotent (no changes, secrets stable).
* Rotate one client secret and confirm both sides update.
* Negative: a user outside `workspaceusers` is refused; a user outside `workspaceadmin` is not admin.
* Failure path: a malformed blueprint applies nothing and `setup.sh` reports it.

---

## 10. Sources

Authentik:

* API overview and base path — <https://api.goauthentik.io/>
* API authentication (Bearer token, API token, `goauthentik.io/api` JWT scope) —
  <https://api.goauthentik.io/authentication/>
* OpenAPI 3 schema (source of the `required`/property tables in §3.2) —
  <https://api.goauthentik.io/schema.yml>
* Automated install / bootstrap variables —
  <https://docs.goauthentik.io/install-config/automated-install/>
* OAuth2/OIDC providers — <https://docs.goauthentik.io/add-secure-apps/providers/oauth2/>
* Property mappings and expression context —
  <https://docs.goauthentik.io/add-secure-apps/providers/property-mappings/>,
  <https://docs.goauthentik.io/add-secure-apps/providers/property-mappings/expression/>
* Applications — <https://docs.goauthentik.io/add-secure-apps/applications/>
* Proxy provider — <https://docs.goauthentik.io/add-secure-apps/providers/proxy/>
* Embedded outpost — <https://docs.goauthentik.io/add-secure-apps/outposts/embedded/>
* Blueprints — <https://docs.goauthentik.io/customize/blueprints/>; file structure
  <https://docs.goauthentik.io/customize/blueprints/v1/structure/>; YAML tags
  <https://docs.goauthentik.io/customize/blueprints/v1/tags/>; model overrides
  <https://docs.goauthentik.io/customize/blueprints/v1/models/>; JSON schema / model list
  <https://goauthentik.io/blueprints/schema.json>
* Release notes for the version-sensitive changes — 2025.10, 2026.5, 2026.8
  (<https://docs.goauthentik.io/releases/>)
* Source-derived defaults and identifiers (tag `version/2026.8.3` unless noted):
  `blueprints/default/flow-*.yaml` (flow slugs),
  `blueprints/system/providers-oauth2.yaml` (built-in scope mappings, `profile` claims, `managed` IDs),
  `blueprints/system/bootstrap.yaml` (bootstrap token identifier),
  `authentik/outposts/apps.py` (`MANAGED_OUTPOST = goauthentik.io/outposts/embedded`),
  `authentik/providers/oauth2/models.py` (field defaults, `grant_types=[]`, HS256 fallback)
  (<https://github.com/goauthentik/authentik>)
* Reported `POST /providers/oauth2/` 405 — <https://github.com/goauthentik/authentik/issues/16685>
  *(unverified)*

Workcenter (the requirements side):

* `OIDC.md` §4 (objects, scope mappings, provider settings), §5 (the manual walkthrough), §7 (Mailcow),
  §8 (the `setup.sh` prompt contract), §9 (environment reference)
* `production.md` §5.5 (Stage E / OIDC resolution) and the "exactly one manual step" claim
* `integration.md` §7 (Authentik wiring; IN-3.5 for FileBrowser's derived redirect URI; IN-7.x)
* `architecture.md` §6.1 (`AUTHENTIK_TAG`)
* Application docs: FileBrowser Quantum OIDC
  (<https://filebrowserquantum.com/en/docs/configuration/authentication/oidc/>), Zulip/docker-zulip OIDC
  and Mailcow Generic-OIDC — as summarised in `OIDC.md`
