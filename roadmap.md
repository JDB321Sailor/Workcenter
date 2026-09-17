# Workcenter — Product Roadmap

> **Document status:** Living document · **Owner:** Workcenter maintainers · **Last major revision:** initial baseline
> **Companion documents:** [`Readme.md`](./Readme.md) · [`architecture.md`](./architecture.md) · [`design.md`](./design.md) ·
> [`integration.md`](./integration.md) · [`OIDC.md`](./OIDC.md) · [`Testing.md`](./Testing.md) ·
> [`production.md`](./production.md) · [`standards.md`](./standards.md) · [`contributions.md`](./contributions.md) ·
> [`Agents.md`](./Agents.md) · [`CHANGELOG.md`](./CHANGELOG.md)

---

## Table of contents

1. [What Workcenter is](#1-what-workcenter-is)
2. [Origin: what we take from Dashy, and what we discard](#2-origin-what-we-take-from-dashy-and-what-we-discard)
3. [Application goals](#3-application-goals)
4. [Scope](#4-scope)
5. [The integrated stack](#5-the-integrated-stack)
6. [Integration requirements](#6-integration-requirements)
7. [The headline capability: cross-application file movement](#7-the-headline-capability-cross-application-file-movement)
8. [UI design requirements](#8-ui-design-requirements)
9. [Deployment requirements](#9-deployment-requirements)
10. [Authentication and authorisation requirements](#10-authentication-and-authorisation-requirements)
11. [Repository, version control and documentation requirements](#11-repository-version-control-and-documentation-requirements)
12. [Step-by-step build plan](#12-step-by-step-build-plan)
13. [Milestones and exit criteria](#13-milestones-and-exit-criteria)
14. [Non-goals](#14-non-goals)
15. [Risks and mitigations](#15-risks-and-mitigations)
16. [Open questions](#16-open-questions)
17. [Definition of done](#17-definition-of-done)

---

## 1. What Workcenter is

Workcenter is a **self-hosted, single-pane workspace application**. It presents three
self-hosted services — **FileBrowser Quantum** (files), **Zulip** (chat) and **SOGo on
Mailcow** (mail and calendar) — inside one page, with one sign-in, one navigation shell
and one set of move-file actions that work *between* those services without the user
ever leaving the page.

Workcenter is a **derivative of [Dashy](https://github.com/lissy93/dashy)**. Dashy's
Workspace view is the seed: a left-hand navigation sidebar plus an iframe surface that
launches web applications without leaving the dashboard. Workcenter takes that seed and
turns it into a purpose-built, three-application product with a real backend, a real
deployment and real cross-application data flows.

### One-sentence mission

> Let a self-hoster sign in once and then read mail, chat with their team and manage
> their files in a single browser tab — moving files freely between all three — with
> the whole stack (reverse proxy, identity provider, office suite and mail server
> included) deployed from one repository by one script.

### The three panes

| Pane | Application | Upstream | What the user does there |
| --- | --- | --- | --- |
| **Files** | FileBrowser Quantum (with OnlyOffice) | [gtsteffaniak/filebrowser](https://github.com/gtsteffaniak/filebrowser) `beta/v2.0.6` | Browse, search, preview, edit, upload and download files |
| **Chat** | Zulip (full docker stack) | [zulip/docker-zulip](https://github.com/zulip/docker-zulip) | Read and send channel/DM messages, share files |
| **Mail** | SOGo, deployed by Mailcow Dockerized | [mailcow/mailcow-dockerized](https://github.com/mailcow/mailcow-dockerized) | Read mail, manage calendars and contacts, open attachments |

---

## 2. Origin: what we take from Dashy, and what we discard

Dashy ships [three views](https://github.com/Lissy93/dashy/blob/master/docs/alternate-views.md):
**Default** (a tile grid dashboard), **Minimal** (a fast tabbed start page) and
**Workspace** (sidebar + in-app iframe launch surface).

### Kept

| Dashy asset | Why Workcenter keeps it |
| --- | --- |
| `src/views/Workspace.vue` and `src/components/Workspace/*` | The entire shell concept: sidebar sections, item launch, embedded web content, multi-tasking iframes |
| Dashy's OIDC client (`src/utils/auth/OidcAuth.js`, `oidc-client-ts`) and route guards | Proven Authentik-compatible PKCE flow, group→admin mapping, silent renewal |
| Dashy's Vuex store + `ConfigAccumalator` config pipeline and `ConfigSchema.json` | The configuration contract; Workcenter keeps a trimmed, renamed schema |
| Dashy's theming system (`src/styles/`, CSS custom properties, `color-themes.scss`) | Zero-cost theming, light/dark, per-user custom CSS |
| Dashy's Dockerfile / `server.js` / `services/healthcheck.js` pattern | Small, hardened Node image with a built-in healthcheck |
| Dashy's docs conventions (`docs/*.md`, kebab-case, task-oriented) | Documentation is a first-class deliverable |
| Dashy's i18n approach (`src/assets/locales/*.json`) | Multi-language support from day one |
| Item `target`/opening-method model (`sametab`, `newtab`, `modal`, `workspace`) | Workcenter narrows this but keeps the semantics for **Open in new tab** escapes |

### Discarded

| Discarded | Reason |
| --- | --- |
| `src/views/Home.vue` (Default view), `src/components/PageStrcture/*`, tile grid, `LinkItems/Item.vue` tile rendering | Workcenter is a three-pane workspace, not a bookmark dashboard |
| `src/views/Minimal.vue`, `src/components/MinimalView/*` | Explicitly out of scope |
| Widgets (`src/components/Widgets/*`, `WidgetView.vue`) and status/ping checks | Not part of the Workcenter product; removes a large dependency and security surface |
| The cloud config sync / config-manager editing UI for arbitrary sections | Workcenter's navigation is derived from its integrations, not hand-authored tiles |
| `docs/alternate-views.md`'s multi-view switching | Only one view exists |

> **Rule:** removing a Dashy subsystem is a **deletion commit** with the reason recorded in
> [`CHANGELOG.md`](./CHANGELOG.md). Nothing is left half-wired.

---

## 3. Application goals

Goals are numbered so that the build plan in [§12](#12-step-by-step-build-plan) and the
exit criteria in [§13](#13-milestones-and-exit-criteria) can reference them.

### G1 — One page, three applications

A user opens `https://workcenter.example.com`, authenticates once against Authentik, and
lands in a shell where **Files**, **Chat** and **Mail** are one click apart. No second
login prompt, no second browser tab, no context switch.

### G2 — Sidebar that swaps with the active application

Above the sidebar sits a **three-button application switcher**. Below it, the sidebar
content is replaced by the active application's own navigator:

* **Files** → the FileBrowser Quantum sidebar (sources/folders, links, tools)
* **Chat** → the Zulip left sidebar (channels, topics, DMs)
* **Mail** → the SOGo sidebar (mail folders, calendars, address books)

### G3 — Move files between applications without leaving the page

The defining capability, and the reason Workcenter exists:

| From → To | Action |
| --- | --- |
| SOGo mail → Files | **Save attachment to my files** |
| Files → SOGo mail | **Attach a file from my files** (on the compose window) |
| Zulip → Files | **Save Zulip attachment to my files** |
| Files → Zulip | **Send a file from my files into a Zulip message** |

All four actions complete **inside the Workcenter page**, with progress feedback and a
final notification, and none of them require the user to download to their desktop and
re-upload.

### G4 — Everything self-hosted and reproducible

`setup.sh` plus `docker compose up -d` takes a bare Linux host with Docker to a **fully
working, TLS-terminated, OIDC-protected Workcenter** with nothing but DNS pointed at it
and one manual visit to the Authentik UI. No SaaS dependency, no manual container
wrangling.

### G5 — One identity

**Authentik** is the only identity provider. Every application in the stack — Workcenter
itself, FileBrowser Quantum, Zulip, Mailcow/SOGo — authenticates against it via OIDC.
Two groups define privilege everywhere: `workspaceusers` (general access) and
`workspaceadmin` (administrative access).

### G6 — Documentation as a deliverable

The repository is only "done" when a competent self-hoster can read the Markdown in the
repository root and reproduce, operate, upgrade and troubleshoot the deployment without
asking a question.

### G7 — Tested by construction

Every merge into `Dev` runs an automated, containerised **Playwright** suite that brings
the whole stack up with deterministic defaults and asserts that the three integrations
and the four file-movement flows actually work.

### Non-functional goals

| Ref | Goal | Target |
| --- | --- | --- |
| G8 | Shell responsiveness | Application switch is perceived as instant; panes stay mounted so switching does not reload state |
| G9 | Resilience | If one upstream app is down, the shell still loads and shows a per-pane health state |
| G10 | Security | No secret in the repository; all traffic TLS; least-privilege containers; OIDC everywhere |
| G11 | Maintainability | Upstream applications are never forked-and-patched in place; they are pinned by version and configured by bind mount |
| G12 | Observability | `docker compose ps` alone tells an operator which service is unhealthy; every service exposes a healthcheck |

---

## 4. Scope

### In scope for 1.0

* The Workcenter shell (Vue 3 + Vite), derived from Dashy's Workspace view.
* The application switcher and the three swappable sidebars.
* The cross-application file broker and its four user-facing actions.
* Authentik OIDC for all four web surfaces, with `workspaceusers` / `workspaceadmin`.
* Traefik v3 reverse proxy, TLS via Let's Encrypt, six subdomains.
* `compose.yaml` orchestration across FileBrowser Quantum, Zulip, Mailcow/SOGo,
  OnlyOffice and Authentik, with per-application folders and bind-mounted volumes.
* `setup.sh` — idempotent bootstrap, configuration, OIDC prompts, stack bring-up.
* Full documentation set and the Playwright integration suite.

### Out of scope for 1.0 (see [§14](#14-non-goals))

* Mobile-native clients, offline mode, PWA install.
* More than three integrated applications.
* Migrating existing FileBrowser v1 / non-Quantum deployments.
* Multi-tenant hosting (one Workcenter instance per organisation/host).

---

## 5. The integrated stack

### 5.1 Components and requested subdomains

| Component | Hostname | Purpose | Deployed by |
| --- | --- | --- | --- |
| Workcenter shell | `example.com` | The product (root URL) | Workcenter repo (built image) |
| FileBrowser Quantum | `filebrowser.example.com` | Files + OnlyOffice editing | Workcenter `compose.yaml`, pinned to `v2.0.6-beta` |
| Authentik | `auth.example.com` | OIDC provider, groups, forward-auth | Workcenter `Authentik/compose.yaml` |
| Mailcow (login + SOGo) | `mail.example.com` | Mail, calendar, contacts; SOGo at `/SOGo` | Mailcow's own `docker-compose.yml` + a Workcenter override |
| Zulip | `chat.example.com` | Team chat | `Zulip/compose.yaml` (docker-zulip) |
| Traefik dashboard | `traefik.example.com` | Proxy dashboard, **admin only** | Workcenter `Traefik/` + Authentik forward-auth |
| OnlyOffice Docs | internal only (`office`, no public hostname required) | Document server for FileBrowser | Workcenter `OnlyOffice/` |

> The base URL is asked for by `setup.sh`; the six hostnames above are **derived** from it
> by prefix substitution. See [`production.md`](./production.md) for the exact algorithm.

### 5.2 Honoured upstream pinning

| Application | Pin | Rationale |
| --- | --- | --- |
| FileBrowser Quantum | **`2.0.6-beta`**, image digest recorded in `.env` | v2 changed the config schema, the database engine (SQLite, not BoltDB) and the sidebar model. Workcenter's integration is written against v2 only. |
| Zulip | `ghcr.io/zulip/zulip-server:<version>-0` | docker-zulip is the officially supported container packaging; the legacy Docker Hub image is not used |
| Mailcow | upstream `master` `docker-compose.yml`, updated by `update.sh` only | Mailcow must be updated by its own tooling; Workcenter only adds an **override** file |
| OnlyOffice Docs | `onlyoffice/documentserver` pinned tag | Must match FileBrowser Quantum's supported OnlyOffice API version |
| Authentik | `ghcr.io/goauthentik/server` pinned tag | Provider/flow names referenced in `OIDC.md` are version-sensitive |

### 5.3 Volume layout (per-application folders)

Everything an application owns lives under that application's folder inside the
Workcenter root. No volumes are mounted from outside the repository tree.

```
Workcenter/
├── Filebrowser/   config.yaml, .env, data/, office-cache/
├── Zulip/         compose.yaml, .env, secrets/, data/, database/, uploads/
├── Mailcow/       mailcow.conf, docker-compose.yml (upstream), docker-compose.override.yml, data/
├── OnlyOffice/    .env, data/, logs/, lib/, db/
├── Authentik/     .env, compose.yaml, data/{postgres,redis,media,certs,templates}
├── Traefik/       compose.yaml, traefik.yml, dynamic/, acme.json, logs/
└── compose.yaml   # root composition, includes the above
```

---

## 6. Integration requirements

Each integration is specified in full in [`integration.md`](./integration.md). The
roadmap-listed requirements below are the acceptance contract.

### 6.1 FileBrowser Quantum (Files)

| Ref | Requirement |
| --- | --- |
| I-FB-1 | Deploy **Quantum 2.0.6-beta**. Images exist at both `gtstef/filebrowser` and `ghcr.io/gtsteffaniak/filebrowser`; tags strip the leading `v` (`2.0.6-beta`, `2.0-beta`, `beta`, plus `-slim` variants), and **there is no `latest` tag for the beta line** — the pin must be explicit in `.env` |
| I-FB-2 | Configuration must use the **v2 `config.yaml` schema**, which has **exactly six top-level keys**: `server`, `auth`, `frontend`, `userDefaults`, `integrations`, `http`. Decoding is **strict** — an unknown key is a fatal startup error, and there is no `office:` key at the root (it is `integrations.office`) |
| I-FB-3 | Persistent state is bind-mounted inside `./Filebrowser/`: `./Filebrowser/data:/home/filebrowser/data`, `./Filebrowser/config.yaml:/home/filebrowser/data/config.yaml`, `./Filebrowser/office-cache:/home/filebrowser/data/cache`. Note the image's default database is `/home/filebrowser/data/database.sqlite` (the docs' `filebrowser.sqlite` is wrong), and `server.database.path` in YAML **overrides** `FILEBROWSER_DATABASE_PATH` |
| I-FB-4 | The user file tree is a **named source** whose path is mounted read-write and is *the same host directory* used by the file broker. The source **must set `config.defaultEnabled: true`**, or OIDC users land in an empty file tree (the default is `false`; it is only implied when there is exactly one source) |
| I-FB-5 | OIDC is configured under `auth.methods.oidc` with `issuerUrl`, `clientId`, `clientSecret`, `scopes: "openid email profile groups"`, `groupsClaim: groups`, `adminGroup: workspaceadmin`, `userGroups: [workspaceusers]`, `userIdentifier: preferred_username`, `logoutRedirectUrl`. Secrets are supplied via `FILEBROWSER_OIDC_CLIENT_ID`, `FILEBROWSER_OIDC_CLIENT_SECRET`, `FILEBROWSER_JWT_TOKEN_SECRET` |
| I-FB-6 | **`http.trustProxyHeaders: true` is mandatory**, plus Traefik sending `X-Forwarded-Proto` and `X-Forwarded-Host` with `passHostHeader`. FileBrowser builds its OIDC **redirect URI from the incoming request** — `https://<host><http.baseURL>api/auth/oidc/callback` — never from `http.externalUrl`, so the URI registered in Authentik must match that derived value exactly. Provider discovery runs **at startup** and a failure there is fatal |
| I-FB-7 | The Office Integration Stack (OnlyOffice) is deployed and configured by `setup.sh` with no manual step: `integrations.office.url` (browser → OnlyOffice), `integrations.office.internalUrl` (FileBrowser → OnlyOffice), and a generated `integrations.office.secret` matching the OnlyOffice `JWT_SECRET`. A third URL role is implied: OnlyOffice calls **back** to FileBrowser via `http.internalUrl` → `http.externalUrl` → the request URL |
| I-FB-8 | OnlyOffice's callback endpoints must be reachable without a session: `GET <internalUrl>/api/resources/view?…&auth=<JWT>` and `POST\|GET <internalUrl>/api/office/callback?…&auth=<JWT>` (plus `/public/api/...` variants for shares). Authorisation is the `?auth=` JWT, **not** a cookie. Any forward-auth middleware must exclude `/health`, `/public/*`, `/api/office/callback`, `/api/resources/view` and `/api/resources/download` |
| I-FB-9 | The image ships a baked-in healthcheck (`curl -f http://localhost:80/health`, and `/health` returns `{"message":"ok"}`), so `depends_on: condition: service_healthy` works with no override. Override it only if the container port or `http.baseURL` changes |
| I-FB-10 | Traefik: the FileBrowser router uses a security-headers middleware. The OnlyOffice router must **allow framing** (never `frameDeny`) and set `accesscontrolalloworiginlist=*`, which the upstream guide calls critical for FileBrowser ↔ OnlyOffice to work |
| I-FB-11 | **The API base path is `/api/` — there is no `/api/v1/`.** Public/share routes are `/public/api/...`. Auth order is `?auth=` → `Authorization` (Bearer, or Basic where the password is the token) → the `filebrowser_quantum_jwt` cookie; there is no `X-Auth` header. Swagger lives at `/swagger/` |
| I-FB-12 | The sidebar is a fixed `<nav id="sidebar">` at `top: 4em` with **no slot, no plugin hook, no custom-JS hook and no public JS API**. `frontend.styling.customCSS` is the only supported injection point (server-injected `<style>`; `style-src` is unrestricted), and `frontend.externalLinks` renders only in the bottom credits. Workcenter therefore places its own switcher as a **body-level fixed element** and shifts FileBrowser's sidebar with `customCSS`; the switcher is *mirrored* inside FileBrowser as per-user `custom` `sidebarLinks` |
| I-FB-13 | Per-user sidebar links persist **server-side in the user object** as `{name, category, target, icon, sourceName?}`. Read via `GET /api/users?username=self`; write via `PATCH /api/users?username=<login>` with `{"which":["sidebarLinks"],"data":{…}}` → 204. Non-admins may patch their own `sidebarLinks`. **Round-trip trap:** `sourceName` is written as a filesystem path but read back as a display name |
| I-FB-14 | **FileBrowser Quantum is Workcenter's appearance standard.** Its light/dark palette is the source the shell's tokens and every other application's branding derive from (`U-21`), and `setup.sh` writes the Workcenter name, icons, backgrounds and accent through `frontend.*` and `userDefaults.ui.themeColor` |
| I-FB-15 | `userDefaults.ui.darkMode` is set **true** so a new user starts dark. At runtime the mode and the locale are carried per user by `PATCH /api/users?username=<login>` with `{"which":["darkMode"]}` / `{"which":["locale"]}` → 204, using the user's own session — both are non-admin-editable |
| I-FB-16 | FileBrowser Quantum has **no inbound message channel and no theme query parameter**, so the Files pane is refreshed after the patch, at the path its outbound `filebrowser:navigation` message last reported, and never while a document editor is open. `locale` values are FileBrowser's own keys (`ptBR`, `zhCN`), not BCP-47 |

### 6.2 Zulip (Chat)

| Ref | Requirement |
| --- | --- |
| I-ZU-1 | Deploy the **full docker-zulip stack**: `database` (`zulip/zulip-postgresql:14`), `memcached`, `rabbitmq`, `redis`, `zulip` (`ghcr.io/zulip/zulip-server:<version>-0`). Trimming services is not permitted |
| I-ZU-2 | All state is bind-mounted under `./Zulip/`: `./Zulip/data:/data`, `./Zulip/database:/var/lib/postgresql/data`, `./Zulip/rabbitmq:/var/lib/rabbitmq`, `./Zulip/redis:/data` |
| I-ZU-3 | All secrets (`zulip__postgres_password`, `zulip__memcached_password`, `zulip__rabbitmq_password`, `zulip__redis_password`, `zulip__secret_key`, `zulip__email_password`) are generated by `setup.sh` into `./Zulip/secrets/` and never committed |
| I-ZU-4 | Configuration is supplied through docker-zulip's env conventions. Scalars use `SETTING_*` (e.g. `SETTING_EXTERNAL_HOST`, `SETTING_ZULIP_ADMINISTRATOR`, `SETTING_EMAIL_HOST`, `SETTING_LOADBALANCER_IPS`). **Dict-valued settings cannot be expressed as `SETTING_*`** — `SOCIAL_AUTH_OIDC_ENABLED_IDPS` and `SOCIAL_AUTH_SYNC_ATTRS_DICT` are supplied through `ZULIP_CUSTOM_SETTINGS` (raw Python appended to `settings.py`) |
| I-ZU-5 | OIDC: the backend list is set with `ZULIP_AUTH_BACKENDS: "EmailAuthBackend,GenericOpenIdConnectBackend"` (bare class names; docker-zulip prepends `zproject.backends.`). The IdP is configured with `SOCIAL_AUTH_OIDC_ENABLED_IDPS` = `{"oidc": {oidc_url, display_name, client_id, secret, auto_signup: True, extra_attrs: [...]}}`, where `oidc_url` is the Authentik issuer. **The redirect URI registered in Authentik is `https://chat.example.com/complete/oidc/`** and login is initiated at `/login/oidc/?idp=oidc`. `SOCIAL_AUTH_OIDC_FULL_NAME_VALIDATED = True` skips the name-confirmation form |
| I-ZU-6 | Admin mapping: **OIDC group→role sync does not exist before Zulip 13.** Zulip 11 added group sync for SAML only; OpenID Connect group sync arrives in Zulip 13 via `SOCIAL_AUTH_SYNC_ATTRS_DICT` with `zulip_groups` / `zulip_role` claims listed in the IdP's `extra_attrs`. On the pinned 12.2 image, `workspaceadmin` membership is propagated **out of band** by `setup.sh` through `PATCH /api/v1/users/{user_id}` (role: owner 100, administrator 200, moderator 300, member 400, guest 600). The roadmap's [open question 4](#16-open-questions) tracks the upgrade |
| I-ZU-7 | Traefik must proxy Zulip's **long-polling event connection**. Zulip has **no websockets** — real-time events go over HTTP long-polling to `/json/events` and `/api/v1/events`. Traefik therefore needs **no** `Upgrade`/`Connection` handling and **no** sticky sessions, but it **must** disable response buffering on that route and allow read/idle timeouts well beyond 60 s (Zulip's own nginx uses `proxy_buffering off; proxy_read_timeout 1200;`). `SETTING_CSRF_TRUSTED_ORIGINS` and `SETTING_USE_X_FORWARDED_HOST` must be set for the public hostname |
| I-ZU-8 | Healthcheck: only the `zulip` service ships one (`curl -isfL --insecure http://localhost/health`, 10 s interval, 300 s start period). `database`, `memcached`, `rabbitmq` and `redis` have **none**, so Workcenter's `Zulip/compose.override.yaml` adds them. Zulip's `/health` is IP-restricted (`allow 127.0.0.1; allow <LOADBALANCER_IPS>; deny all`), so any external probe requires the prober's address in `SETTING_LOADBALANCER_IPS` |
| I-ZU-9 | **Zulip cannot be embedded in an iframe by default.** Its nginx sends `add_header X-Frame-Options DENY always;` at server scope, and Zulip exposes **no** Django setting or middleware to change it. There is no CSP `frame-ancestors` directive to relax. Framing is therefore a **deliberate, documented deviation**: Workcenter builds a thin derived image from the pinned docker-zulip image with a `custom_zulip_files/` override of the nginx header include (docker-zulip's Dockerfile copies `/root/custom_zulip/*` over `/root/zulip`), changing `DENY` to `SAMEORIGIN`→`ALLOW-FROM` semantics via CSP `frame-ancestors 'self' https://example.com`. The derived image keeps the upstream version pin and is rebuilt only when the pin changes. See [risk R1](#15-risks-and-mitigations) |
| I-ZU-10 | The Workcenter file broker needs a Zulip **bot** with an API key (`Zulip/secrets/zuliprc`) and a dedicated channel for the "send file to Zulip" action |
| I-ZU-11 | **Upload size:** Zulip's nginx caps request bodies at **25 MiB** (`client_max_body_size 25m`), even though `POST /register` may advertise `max_file_upload_size_mib` higher. `POST /api/v1/user_uploads` therefore returns 413 above 25 MiB. Files at or above that size must use the resumable **`POST /api/v1/tus`** endpoint, which has `client_max_body_size 0` |
| I-ZU-12 | **Attachment download path:** Zulip's nginx sets permissive CORS on `/api/`, `/user_uploads`, `/avatar` and `/thumbnail` (`Access-Control-Allow-Origin: *`, `Authorization` allowed), and a request to `GET /user_uploads/{realm_id}/{filename}` carrying an `Authorization` header bypasses rate limiting. The broker may therefore fetch attachments directly with `Authorization: Basic base64(email:api_key)`, and the browser can do so cross-origin without CSRF concerns |
| I-ZU-13 | **Appearance is per user and live.** `PATCH /api/v1/settings` with `color_scheme` (1 automatic, 2 dark, 3 light) reaches the open client through Zulip's event queue, so the Chat pane changes without a reload. `PATCH /api/v1/realm/user_settings_defaults` with `color_scheme=2` makes dark the default for new accounts |
| I-ZU-14 | The realm-wide pass uses `target_users` with **`skip_if_already_edited: true`** (feature level 444, present on the pinned 12.2), which is how the advisory contract in `U-20` is enforced for Zulip. `PATCH /api/v1/settings` is `@human_users_only`, so it needs a human administrator account — the file-broker bot key cannot do it |
| I-ZU-15 | Branding is `PATCH /api/v1/realm` (name, description), `POST /api/v1/realm/icon`, and `POST /api/v1/realm/logo` twice, `night=false` and `night=true`. **Zulip ships no custom-CSS mechanism** and its production build contains no editable stylesheet; Workcenter brands it with name, icon, logos and theme only, and never forks its frontend for appearance |
| I-ZU-16 | `default_language` is settable on the same endpoint but **cannot** re-render an open client — Zulip's own source says a reload is fundamentally required — so a language change refreshes the Chat pane |

### 6.3 Mailcow Dockerized with SOGo (Mail)

| Ref | Requirement |
| --- | --- |
| I-MC-1 | Mailcow is cloned by `setup.sh` into `./Mailcow/` using its own repository and prepared with **`generate_config.sh`**, because Mailcow's own tooling owns `mailcow.conf`. The non-interactive recipe (pre-set `MAILCOW_HOSTNAME`, `MAILCOW_TZ`, `MAILCOW_DBPASS`, `MAILCOW_DBROOT`, `MAILCOW_REDISPASS`, `MAILCOW_BRANCH`, `SKIP_CLAMD`, then `FORCE=y ./generate_config.sh`) must be used so no prompt is reached |
| I-MC-2 | Mailcow runs from **its own unmodified `docker-compose.yml`**; Workcenter only supplies `./Mailcow/docker-compose.override.yml`, which Mailcow's documentation explicitly endorses as the supported way to customise without breaking updates. `update.sh` must keep working untouched |
| I-MC-3 | Persistent state stays in `./Mailcow/data/` and Mailcow's named volumes; the override must not relocate Mailcow's internal volumes. Note that Mailcow's `.env` is a tracked symlink to `mailcow.conf`, and `docker compose` is run with no `-f`, so the override auto-merges — Workcenter must not pass `-f` when driving Mailcow |
| I-MC-4 | Traefik fronts `mail.example.com` → `nginx-mailcow`. Per the Mailcow Traefik guide: `AUTODISCOVER_SAN=n`, `SKIP_LETS_ENCRYPT=y` (there is **no** `ENABLE_SSL` variable in current `mailcow.conf`), and `TRUSTED_PROXIES` set to the Traefik network |
| I-MC-4a | **`HTTP_REDIRECT=n` is mandatory.** `generate_config.sh` writes `HTTP_REDIRECT=y`, with which the only listener on `HTTP_PORT` is a 301 redirect to HTTPS — so Traefik → `http://nginx:8080` returns `301 https://mail.example.com` and loops forever. The Mailcow Traefik guide omits this; Workcenter's `setup.sh` sets it |
| I-MC-4b | **An override file cannot remove Mailcow's published ports.** Docker *concatenates* `ports`/`expose` lists rather than replacing them, so `docker-compose.override.yml` cannot delete `80:80`/`443:443`, and adding `127.0.0.1:80:80` produces two conflicting bindings. The supported fix is Mailcow's own `HTTP_BIND`/`HTTPS_BIND` in `mailcow.conf` (set them to `127.0.0.1`), combined with the override exposing the container and attaching it to the `proxy` network. Mailcow's `.gitignore` already lists `docker-compose.override.yml` and `mailcow.conf`, confirming the override is the sanctioned, untracked customisation point |
| I-MC-5 | **OIDC into SOGo via the Mailcow UI**: Mailcow's *Identity Provider* feature (`System → Configuration → Access → Identity Provider`) is configured for **Generic-OIDC** against Authentik — Authorization, Token and User Info endpoints, Client ID/Secret, Redirect URL `https://mail.example.com`, scopes `openid profile email mailcow_template`, attribute→mailbox-template mapping, and per-mailbox *Identity Provider = Generic-OIDC*. This is a **first-class upstream feature**; the Mailcow UI must **not** be placed behind an Authentik forward-auth proxy |
| I-MC-6 | **Mailcow's LDAP identity provider is additionally configured** (Authentik LDAP outpost → Mailcow) so that Authentik becomes the source of truth for *mail protocol* credentials as well as the web UI. This is what gives the broker a non-password path for IMAP/SMTP when the OIDC route only covers the UI. Fields: Host, Port, Use SSL/TLS, Base DN, Username Field, Filter, Attribute Field, Bind DN/Bind Password, Attribute Mapping, Periodic Full Sync, Import Users |
| I-MC-7 | **SOGo's own OIDC is deliberately not wired.** SOGo ≥ 5.12 has native OIDC and Mailcow ships 5.12.10, but Mailcow does not configure it, and enabling it would require a Dovecot **OAuth2 passdb** (absent) plus an `OCSOpenIdURL` pointing at a `sogo_openid` table that does not exist in Mailcow's schema. Mailcow's documented consequence stands: identity-provider users *"can only log in to SOGo through the mailcow UI."* Workcenter therefore authenticates at the Mailcow UI and reaches SOGo through Mailcow's own `sogo-auth` proxy SSO session. [`OIDC.md` §7](./OIDC.md#7-sogo-mailcow-and-the-oidc-reality) documents the mechanism in full |
| I-MC-7a | The SOGo session is established by the Mailcow UI's **"Login to Webmail"** action (`/sogo-auth.php?login=<address>`), which sets a session flag that nginx's `auth_request` then translates into injected credentials. Opening `/SOGo` with no such session shows **SOGo's own login form** — which the Workcenter Mail pane must detect and surface as its `auth-error` state with **Sign in again** |
| I-MC-8 | `SKIP_SOGO=n` and the SOGo container must be present and healthy. Mailcow's compose defines **no** `healthcheck:` blocks of its own (only image-baked `HEALTHCHECK` instructions and one `condition: service_healthy` on unbound), so Workcenter's override supplies explicit healthchecks for `nginx-mailcow`, `sogo-mailcow`, `mysql-mailcow` and `redis-mailcow`, plus a Mailcow API key (`API_KEY`, `API_ALLOW_FROM`) for `/api/v1/get/status/containers` |
| I-MC-9 | External mail clients use Mailcow **app passwords** (documented in `OIDC.md`) unless LDAP is enabled; switching a mailbox's identity provider never destroys the existing SQL password, so fallback to the account password remains possible |
| I-MC-10 | The vmail store must be reachable for the file broker's "save attachment" path; `./Mailcow/data/` and the FileBrowser source are co-located on the same host filesystem |
| I-MC-11 | **SOGo 5.12 has no dark mode**, no theme preference and one stylesheet, so Workcenter *supplies* the palette: a stylesheet bind-mounted into SOGo's web resources through `Mailcow/docker-compose.override.yml`, plus a delimited block appended to `data/conf/sogo/custom-sogo.js` — a file `sogo.conf` already loads through `SOGoUIAdditionalJSFiles`, so no Mailcow configuration key is edited. The block preserves Mailcow's own `mc_logout()` |
| I-MC-12 | That block sets `data-wc-mode` from the `wc_mode` cookie for first paint and updates it on an **origin-checked** `workcenter:mode` message, so the Mail pane changes mode live. It reads only the values `dark` and `light`, never evaluates a received string, and never touches mail content or credentials |
| I-MC-13 | `sogo-mailcow` is **restarted** after any SOGo branding change, because `bootstrap-sogo.sh` rsyncs the web resources into the nginx volume at container start. Everything under `data/conf/sogo/` is tracked by Mailcow and `update.sh` merges `-X theirs`, so `setup.sh --brand` is a documented post-upgrade step |
| I-MC-14 | The Mailcow UI is branded through `data/web/css/build/0081-custom-mailcow.css` and `$UI_THEME` in `data/web/inc/vars.local.inc.php` — both untracked upstream, so both survive `update.sh`. Its own dark mode is keyed on its origin's `localStorage`, which the shell cannot write, so Workcenter leaves the Mailcow UI's mode to the user; it is an admin surface in a new tab, not a pane |

### 6.4 OnlyOffice Documentserver (Editing)

| Ref | Requirement |
| --- | --- |
| I-OO-1 | `onlyoffice/documentserver` deployed under `./OnlyOffice/`, volumes `./OnlyOffice/data`, `./OnlyOffice/logs`, `./OnlyOffice/lib`, `./OnlyOffice/db` |
| I-OO-2 | `JWT_ENABLED=true` with a `setup.sh`-generated secret also written into `Filebrowser/config.yaml` (`integrations.office.secret`) |
| I-OO-3 | Reachable from the browser and from the FileBrowser container; `internalUrl` uses the internal Docker hostname to bypass Traefik |
| I-OO-4 | Healthcheck `curl -f http://localhost/healthcheck` gates FileBrowser's `depends_on` |
| I-OO-5 | If FileBrowser is served over HTTPS, OnlyOffice must be reached over a trusted TLS origin, or the documented self-signed/internal-HTTPS pattern applied |

### 6.5 Authentik (Identity)

| Ref | Requirement |
| --- | --- |
| I-AK-1 | Deployed under `./Authentik/` with PostgreSQL and Redis; state in `./Authentik/data/` |
| I-AK-2 | Bootstrap via `AUTHENTIK_BOOTSTRAP_PASSWORD`, `AUTHENTIK_BOOTSTRAP_TOKEN`, `AUTHENTIK_BOOTSTRAP_EMAIL`, `AUTHENTIK_SECRET_KEY` — all generated or prompted by `setup.sh` |
| I-AK-3 | **One OIDC provider + application per integrated service**: `workcenter`, `filebrowser`, `zulip`, `mailcow`, plus a forward-auth proxy provider for `traefik` |
| I-AK-4 | A **`groups` scope mapping** must exist so group membership is present in the id_token (required by FileBrowser's `adminGroup` and Workcenter's own admin check) |
| I-AK-5 | Groups `workspaceusers` and `workspaceadmin` are created and used consistently by every application |
| I-AK-6 | `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` must include the Traefik/Docker network, and Traefik must send `X-Forwarded-Proto: https`, so the advertised issuer matches the public HTTPS URL |
| I-AK-7 | No application is issued an **encryption** key — signed JWTs only (encrypted JWE tokens are rejected by Dashy-derived clients) |
| I-AK-8 | The Traefik dashboard is protected by an Authentik **forward-auth** middleware, restricted to `workspaceadmin` |
| I-AK-9 | An Authentik **LDAP outpost** is deployed to back Mailcow's LDAP identity provider (I-MC-6), with the same `workspaceusers` / `workspaceadmin` group model |

### 6.6 Cross-application (the broker)

| Ref | Requirement |
| --- | --- |
| I-X-1 | A **file broker** service (see [`architecture.md`](./architecture.md#the-file-broker)) provides the four transfer actions over the same host filesystem, with per-user authorisation |
| I-X-2 | Every transfer is **streamed**, size-capped and time-limited; no partial file is left visible to the user |
| I-X-3 | Every transfer emits a user-visible progress state and a terminal success/failure notification, and is recorded in an audit log |
| I-X-4 | The broker never stores mail or chat credentials in plaintext at rest; per-user tokens are kept in an encrypted store keyed by a secret held only in `.env` |
| I-X-5 | The broker is the **only** component permitted to write into the FileBrowser source tree on behalf of another application |

---

## 7. The headline capability: cross-application file movement

This section is the heart of the roadmap. It is deliberately explicit because it is the
single hardest and most valuable thing Workcenter does.

### 7.1 Design principle

> **The three applications already share a filesystem — Workcenter's job is to expose
> that fact safely, not to re-implement file transfer.**

Because every application is bind-mounted into the Workcenter root
(`./Filebrowser/`, `./Zulip/`, `./Mailcow/`), a file that arrives in one application is
already on the same disk as the others. Workcenter therefore *moves bytes by path*, and
only uses network APIs where a store is genuinely remote (Zulip's upload store, the mail
server's IMAP mailbox).

### 7.2 The four flows

**F1 — SOGo attachment → Files** *(highest priority)*

1. User opens a mail in the Mail pane and selects **Save to files** on an attachment.
2. The Mail pane asks Workcenter for the attachment list for that message.
3. The broker fetches the message body over **IMAP over TLS** to `dovecot-mailcow`, using
   the per-user app password or an SSO-issued token, and streams the MIME part.
4. The broker writes the file into the user's FileBrowser source directory using a
   **temp-file-then-atomic-rename** pattern, de-duplicating the name (`report (2).pdf`).
5. FileBrowser Quantum's file watcher indexes the new file; the Files pane refreshes and
   the user is notified with an **Open** action that deep-links to the folder.

**F2 — Files → SOGo attachment**

1. In the Mail pane's compose window, the user clicks **Attach from files**.
2. A Workcenter file picker (backed by the FileBrowser Quantum API) opens, rooted at the
   user's source.
3. On selection the broker streams the file from the FileBrowser source and attaches it
   through the mail compose flow (SMTP submission via `postfix-mailcow`, or the SOGo
   compose UI's own upload endpoint when available).
4. The attachment appears in the compose window with its real filename and size.

**F3 — Zulip file → Files**

1. On a Zulip message with an attachment, the user selects **Save to files**.
2. The broker resolves the `uri` returned by Zulip's upload API against
   `https://chat.example.com`, streams it with the user's Zulip credentials, and writes
   it into the FileBrowser source exactly as in F1 step 4.
3. Idempotency: a content hash prevents saving the same attachment twice under two names.

**F4 — Files → Zulip message**

1. In the Zulip compose box, the user clicks **Send from files**.
2. The Workcenter file picker opens; on selection the broker uploads the file with
   `POST /api/v1/user_uploads` using a Zulip bot API key, receives `{ "uri": ..., "url": ... }`,
   and inserts the returned Markdown link into the message being composed.
3. Files ≥ 25 MB use the resumable `POST /api/v1/tus` endpoint instead.

### 7.3 Why a broker and not just iframes

Both applications are third-party SPAs inside iframes; they cannot read each other's
storage, and cross-origin scripting is blocked. A same-origin **broker API** owned by
Workcenter is the only place that can hold both credentials and both paths, enforce
authorisation, and present one consistent progress UI to the user.

### 7.4 Engineering requirements for the broker

| Ref | Requirement |
| --- | --- |
| B-1 | Authenticated by the same Authentik OIDC session as the shell; no separate login |
| B-2 | Per-user authorisation: a user may only move files within their own FileBrowser source scope and their own mailbox/chat identity |
| B-3 | Content-addressed de-duplication and collision-safe naming |
| B-4 | Atomic writes; a failed transfer leaves zero residue |
| B-5 | Streaming with backpressure; configurable max size; no full-file buffering in memory |
| B-6 | Audit record per transfer: actor, direction, source, destination, byte count, result, timestamp |
| B-7 | Unit-tested against fixtures; end-to-end tested by Playwright (see [`Testing.md`](./Testing.md)) |
| B-8 | Degrades gracefully: if the broker is down the shell still works, and the four actions report "unavailable" instead of hanging |

---

## 8. UI design requirements

Full element-level specification lives in [`design.md`](./design.md). The roadmap-level
requirements are:

### 8.1 Layout

| Ref | Requirement |
| --- | --- |
| U-1 | A **persistent left rail** on every pane, following the pattern of [FileBrowser Quantum's sidebar](https://filebrowserquantum.com/en/docs/features/sidebar-links/) |
| U-2 | Above the sidebar, a fixed **application switcher** with exactly three buttons: **Files**, **Chat**, **Mail**. The active application is visually unmistakable |
| U-3 | Directly beneath the switcher, the **sidebar body swaps** to the active application's own navigation: FileBrowser sources/folders/links; Zulip channels and DMs; SOGo mail folders, calendars and address books |
| U-4 | To the right of the rail, a single **content surface**. Panes are kept mounted (`enableMultiTasking` semantics inherited from Dashy) so switching preserves scroll position, drafts and sessions |
| U-5 | The switcher never scrolls away; the sidebar body scrolls independently; the content surface scrolls independently |
| U-6 | The **application switcher carries a status indicator beneath each button**, plus a `STATUS` label beneath the indicators, showing per-application health (from the healthchecks in §9) without leaving the page |
| U-7 | A **user menu** in the rail footer: identity, admin badge when in `workspaceadmin`, the appearance control (U-17), the language control (U-18), the admin links, and Logout (which ends the Authentik session) |
| U-17 | The user menu carries the **light/dark mode switcher**, and it is the only appearance control Workcenter offers. Dark is the default, and the menu says so |
| U-18 | The user menu carries a **language element showing the language in use**, written in its own language, with a **flag button** that opens the language menu |
| U-19 | Each switcher button carries the **real brand mark** of its application, committed to `icons/` in the repository and never fetched from a third-party CDN at runtime |

### 8.2 Visual language

| Ref | Requirement |
| --- | --- |
| U-8 | Styling derives from **Dashy's theming model**: CSS custom properties, `color-palette.scss` variables, `--side-bar-*` tokens, light/dark themes and per-user custom CSS |
| U-9 | The three applications are visually distinguished by an accent colour used on the active switcher button, the active sidebar affordance and the pane loading state |
| U-10 | Workcenter chrome must be **quiet**: neutral surfaces, one accent, no gradients or decoration that competes with embedded applications |
| U-11 | Because embedded applications carry their own theming, Workcenter must apply a **theme bridge**: one switch in the shell changes the shell *and* all three applications. FileBrowser Quantum through its per-user `darkMode`, Zulip through `color_scheme`, SOGo through the Workcenter stylesheet supplied at setup — SOGo has no dark mode of its own |
| U-20 | The bridge is **advisory**: a user who has set an appearance inside an application keeps it (`design.md` D-T1) |
| U-21 | **FileBrowser Quantum's palette is the appearance standard.** The shell's tokens and the branding pushed into the other applications are derived from it, from a single source |
| U-22 | `setup.sh` brands the embedded applications — name, logo, palette — so the deployment reads as one product and not as three separate sites behind one proxy |
| U-23 | Where the shell can forward the **language** the same way, it does: FileBrowser's `locale` and Zulip's `default_language`. Where it cannot, the shell says so instead of failing quietly |

### 8.3 Interaction

| Ref | Requirement |
| --- | --- |
| U-12 | A global keyboard shortcut switches applications (`Alt+1/2/3`), and each embedded app is reachable by URL (`/#/files`, `/#/chat`, `/#/mail`) so panes are linkable |
| U-13 | The four file-movement actions are surfaced as **context actions inside each pane's own UI** (attachment row, compose window, message action) — not hidden in a Workcenter menu |
| U-14 | Every long-running action shows progress and can be cancelled without breaking the pane |
| U-15 | If an application fails to load or fails its healthcheck, the pane shows a diagnostic card with the service name, the failing check and a **Retry** button — never a blank iframe |
| U-16 | Accessibility: full keyboard navigation of the rail and switcher, visible focus rings, `aria-current` on the active application, and WCAG AA contrast for shell chrome |

### 8.4 What the UI must NOT do

* Must not show Dashy's Default or Minimal views, view-switcher links, tile grid or widgets.
* Must not expose the Traefik dashboard, Mailcow admin UI or Authentik admin UI to
  non-admin users anywhere in the shell.
* Must not embed any application in a way that requires the user to sign in twice.

---

## 9. Deployment requirements

Full runbook in [`production.md`](./production.md).

| Ref | Requirement |
| --- | --- |
| D-1 | **One root `compose.yaml`** brings up the whole stack and references the per-application compose files (`Zulip/compose.yaml`, `Mailcow/docker-compose.yml` + override, `Authentik/compose.yaml`, `Traefik/compose.yaml`, `OnlyOffice/compose.yaml` as needed) |
| D-2 | **Mailcow keeps its own `docker-compose.yml`** and its own `generate_config.sh` / `update.sh`; Workcenter only adds `docker-compose.override.yml` |
| D-3 | **Traefik** is the single reverse proxy. Every service carries Docker labels using recommended Traefik v3 defaults: `traefik.enable`, `traefik.http.routers.<name>.rule/entrypoints/tls/certresolver`, `traefik.http.services.<name>.loadbalancer.server.port`, `traefik.docker.network` |
| D-4 | **Traefik dashboard** at `traefik.example.com`, protected by Authentik forward-auth, `workspaceadmin` only |
| D-5 | If Traefik is already running on the host, `setup.sh` **adopts** it (detects it, joins the external proxy network, does not deploy a second proxy) |
| D-6 | **Every service has a healthcheck**, and Workcenter declares `depends_on` with `condition: service_healthy` for Zulip, FileBrowser and Mailcow/SOGo. Services whose images lack a healthcheck get one defined in the override |
| D-7 | **TLS between backend services is available on request**: `setup.sh` can generate an internal CA/self-signed pair and switch inter-service URLs to `https://`, with the CA trusted by Workcenter and FileBrowser (`NODE_EXTRA_CA_CERTS`) |
| D-8 | All volumes are **bind mounts inside the owning application's folder** in the Workcenter root |
| D-9 | All generated secrets live in `.env` files inside the application folders, all are `.gitignore`d, and `.env.example` files document every key |
| D-10 | The stack is **idempotent**: re-running `setup.sh` and `docker compose up -d` converges without data loss |
| D-11 | Resource requirements are documented (minimum 4 vCPU / 8 GB RAM / 100 GB disk for the full stack, 2 GB RAM reserved for Zulip alone) |

---

## 10. Authentication and authorisation requirements

Full provider-by-provider walkthrough in [`OIDC.md`](./OIDC.md).

| Ref | Requirement |
| --- | --- |
| A-1 | Authentik is the **only** identity provider; tested end to end |
| A-2 | Workcenter itself is an OIDC client; the shell and the broker API both validate tokens against Authentik |
| A-3 | Every integrated application is an OIDC client (FileBrowser, Zulip, Mailcow) or is protected by Authentik forward-auth (Traefik dashboard) |
| A-4 | Groups are unified: **`workspaceusers`** = general access to every application; **`workspaceadmin`** = administrative access to every application |
| A-5 | Admin grant is *additive and consistent*: `workspaceadmin` maps to FileBrowser `adminGroup`, Zulip organisation owner, Workcenter admin routes |
| A-6 | SOGo is reached through the **Mailcow UI's Generic-OIDC identity provider**, because SOGo has no out-of-the-box OIDC; the Mailcow UI is the authenticated front door to the mailbox |
| A-7 | Logout is single-action: signing out of Workcenter ends the Authentik session and propagates to applications that support RP-initiated logout |
| A-8 | `setup.sh` collects every OIDC value through documented prompts, and those prompts are reproduced verbatim in `OIDC.md` |
| A-9 | No shared/local passwords are used for human accounts; Mailcow app passwords are the only exception and are per-user, per-device, and revocable |

---

## 11. Repository, version control and documentation requirements

### 11.1 Branching model

**FileBrowser Quantum is the standard.** Workcenter uses the promote-through-branches
model:

```
feature branch ──PR──▶ Dev ──promote──▶ Beta ──promote──▶ Stable
```

| Branch | Role |
| --- | --- |
| `Dev` | **Default branch for all PRs.** Integration branch; may be broken between merges |
| `Beta` | Promoted from `Dev` once the Playwright suite is green; candidate releases |
| `Stable` | Promoted from `Beta`; **the GitHub default branch** and the source of production images |

Rules:

* Feature branches are created from `Dev` and PR **into `Dev`**. Never PR a feature directly to `Beta` or `Stable`.
* Promotion is `Dev → Beta → Stable`, in that order, with the E2E gate green at each step.
* Only non-functional changes (docs, workflow config) may target `Beta`/`Stable` directly, and only with maintainer approval.
* Every promotion bumps the version and cuts a `CHANGELOG.md` release section.

### 11.2 Documentation deliverables

These files are the specification of the product and are maintained as part of it:

| File | Contents |
| --- | --- |
| [`roadmap.md`](./roadmap.md) | This document |
| [`Readme.md`](./Readme.md) | Overview, quick start, feature summary |
| [`architecture.md`](./architecture.md) | Folder structure, file breakdown, layout |
| [`design.md`](./design.md) | Every UI element and interaction |
| [`integration.md`](./integration.md) | What each integrated application is and how it is wired in |
| [`OIDC.md`](./OIDC.md) | OIDC concepts, Authentik setup, `setup.sh` prompts |
| [`Testing.md`](./Testing.md) | Test strategy, Playwright harness, gates |
| [`production.md`](./production.md) | Production deployment, `setup.sh` contract, upgrades, backups |
| [`standards.md`](./standards.md) | Coding and documentation standards |
| [`contributions.md`](./contributions.md) | PR guide, process, workflow |
| [`Agents.md`](./Agents.md) | Requirements for AI coding agents |
| [`CHANGELOG.md`](./CHANGELOG.md) | Running log of changes |

### 11.3 Documentation standards

* Markdown only; kebab-case filenames; one `#` H1 per file; sentence-case headings.
* Every configuration key mentioned must be shown in a fenced code block with its real name.
* Every external claim links to the upstream source.
* Documentation changes ship in the same PR as the behaviour they describe.

---

## 12. Step-by-step build plan

Phases are ordered so that each one ends in something runnable. Each phase lists its
**deliverables**, its **exit criteria** and its **dependencies**.

---

### Phase 0 — Repository foundation

**Goal:** an empty-but-correct repository that can build, lint and test.

| Step | Work |
| --- | --- |
| 0.1 | Create the `Dev`, `Beta`, `Stable` branches; set `Stable` as the GitHub default and `Dev` as the PR default target |
| 0.2 | Copy Dashy as the starting point; commit it as `chore: import dashy as upstream baseline` with the exact upstream commit recorded in `CHANGELOG.md` |
| 0.3 | Write the documentation set (this file and its companions) |
| 0.4 | Add `.editorconfig`, `.gitignore` (all `**/.env`, `**/data/`, `**/secrets/`, `acme.json`), and issue/PR templates |
| 0.5 | Stand up the CI skeleton: lint, unit test, build (mirroring FileBrowser Quantum's `regular-tests` workflow shape) |

**Exit criteria:** `yarn install --frozen-lockfile && yarn lint && yarn test` passes on a clean clone; `Dev` is the default PR target.

---

### Phase 1 — Strip Dashy down to the Workspace view

**Goal:** Workcenter is Dashy minus everything that is not the workspace.

| Step | Work |
| --- | --- |
| 1.1 | Delete `src/views/Home.vue`, `src/views/Minimal.vue`, `src/components/MinimalView/`, `src/components/PageStrcture/`, tile-rendering components under `LinkItems/` that only serve the grid |
| 1.2 | Remove widget and status/ping subsystems (`src/components/Widgets/`, `WidgetView.vue`, status-check utilities, related config keys) |
| 1.3 | Collapse `src/router.js` to a single `/` route rendering `Workspace.vue`; remove `ViewSwitcher.vue` and the Home/Minimal links in the sidebar |
| 1.4 | Rename the product in `package.json`, `index.html`, `server.js`, `pageInfo`, locale strings and Docker labels: **Workcenter** |
| 1.5 | Trim `ConfigSchema.json` to the Workcenter surface; add a schema test that fails if a removed key reappears |
| 1.6 | Rebuild `docs/` — keep authentication, deployment, management, security, theming; delete the docs for removed features |
| 1.7 | Delete dead dependencies from `package.json` and confirm the bundle size drops |

**Exit criteria:** the app builds, loads a single workspace view, authenticates via OIDC, and no reference to "Dashy", "Minimal" or "Default view" remains in `src/` (enforced by a lint rule/test).

**Depends on:** Phase 0.

---

### Phase 2 — The Workcenter shell

**Goal:** the three-pane shell with a working application switcher and swapping sidebars.

| Step | Work |
| --- | --- |
| 2.1 | Introduce the application model: a registry of `{ id, name, icon, accent, url, sidebar }` for `files`, `chat`, `mail` |
| 2.2 | Build `AppSwitcher.vue` — three buttons above the rail, `aria-current`, keyboard shortcuts, active accent |
| 2.3 | Build `AppSidebar.vue` — a slot-based host that renders the active application's sidebar surface |
| 2.4 | Implement the **Files** sidebar: FileBrowser sources/folders/links, deep-linked to the FileBrowser Quantum UI |
| 2.5 | Implement the **Chat** sidebar: Zulip channels, topics and DMs |
| 2.6 | Implement the **Mail** sidebar: SOGo mail folders, calendars and address books |
| 2.7 | Make panes **persistent**: all three iframes stay mounted; switching toggles visibility and restores focus/scroll |
| 2.8 | Implement routing: `/files`, `/chat`, `/mail`, deep-linkable, with the pane restored on reload |
| 2.9 | Implement the status indicators inside the application switcher (one beneath each button, plus the `STATUS` label) and the per-pane failure card (`U-15`) |
| 2.10 | Apply the Dashy-derived theming, with the palette derived from FileBrowser Quantum's own values (`U-21`) and dark as the default |
| 2.11 | Build the user menu: identity, admin badge, admin links and Logout (`U-7`) |
| 2.12 | Build the **appearance control** — the light/dark switcher, dark labelled as the default (`U-17`) |
| 2.13 | Build the **language control** — the language in use plus the flag button and its menu (`U-18`) |
| 2.14 | Implement the **theme bridge**: `POST /api/broker/preferences`, the pane message, the mode cookie, and the per-application adapters so one switch changes all three applications (`U-11`, `U-20`) |
| 2.15 | Implement the **language bridge** where the applications allow it (`U-23`) |

**Exit criteria:** all three applications load inside the shell, the sidebar content changes with the active application, switching preserves state, deep links work, and a single mode switch visibly changes the shell and all three panes.

**Depends on:** Phase 1.

---

### Phase 3 — Deployment skeleton: folders, compose and Traefik

**Goal:** a real host running the three applications behind Traefik.

| Step | Work |
| --- | --- |
| 3.1 | Create the per-application folders and commit `.env.example` for each |
| 3.2 | Write the root `compose.yaml` with `include:`/`-f` references and the shared external `proxy` network |
| 3.3 | Write `Traefik/` — static config (`traefik.yml`), dynamic config, ACME, dashboard router, ping healthcheck |
| 3.4 | Write `Filebrowser/` deployment: image pin, `config.yaml` v2 schema, source mount, Traefik labels, healthcheck |
| 3.5 | Write `OnlyOffice/` deployment and wire `integrations.office` |
| 3.6 | Write `Zulip/compose.yaml` from the docker-zulip `compose.yaml`, with bind-mounted state and secrets |
| 3.7 | Write `Mailcow/docker-compose.override.yml` (Traefik labels, port removal in favour of `expose`, `TRUSTED_PROXIES`, explicit healthchecks for `nginx-mailcow`/`sogo-mailcow`/`mysql-mailcow`/`redis-mailcow`) |
| 3.8 | Add `depends_on: condition: service_healthy` from Workcenter to all three applications |

**Exit criteria:** `docker compose up -d` brings the stack up on a test host; every service reports healthy; each subdomain serves its application over valid TLS.

**Depends on:** Phase 0 for folder layout.

---

### Phase 4 — `setup.sh`

**Goal:** one script from bare host to running stack.

Implement exactly the contract in [`production.md`](./production.md):

| Step | Work |
| --- | --- |
| 4.1 | Folder check/create for `Filebrowser`, `Zulip`, `Mailcow` (and `OnlyOffice`, `Authentik`, `Traefik` on demand) |
| 4.2 | Per-application file provisioning: download Mailcow with its own tooling; fetch/compose the best source for FileBrowser and Zulip; generate `.env` files and secrets |
| 4.3 | Traefik detection: if not running, create `Traefik/` and add it to the stack |
| 4.4 | Prompt for the base URL and derive the six hostnames; write them into every `.env` and config |
| 4.5 | Skip the `.env`/OIDC checks for anything the script just created, and go straight to the Authentik deployment question |
| 4.6 | OIDC branch logic exactly as specified in [`OIDC.md`](./OIDC.md): if not configured, ask whether the user has already created the Authentik applications/providers; if yes, create `Authentik/` and prompt for every OIDC variable into the right `.env` files; if no (default), detect a running Authentik, offer to deploy one, and either stop with the exact guidance message or continue |
| 4.7 | Final bring-up: `docker compose up -d`, then poll until every service is healthy, printing a per-service report |
| 4.8 | Branding (`U-22`): write the FileBrowser styling keys, the SOGo stylesheet and script hook, and the Mailcow custom CSS before bring-up; apply the Zulip realm name, icon, both logos and the dark default afterwards; print the one manual Mailcow logo step. Support `--brand` to re-apply it alone |
| 4.9 | Idempotency tests: run `setup.sh` three times and assert convergence, branding included |

**Exit criteria:** from a clean checkout on a bare host, `setup.sh` produces a running stack; the OIDC prompts match `OIDC.md` word for word; a second run makes no destructive change; and all three applications carry the Workcenter name, logo and palette.

**Depends on:** Phase 3.

---

### Phase 5 — Identity: Authentik everywhere

**Goal:** one login, one group model, all four surfaces.

| Step | Work |
| --- | --- |
| 5.1 | `Authentik/compose.yaml` with pinned tag, Postgres, Redis, bootstrap env |
| 5.2 | `OIDC.md` walkthrough: `groups` scope mapping, the four OIDC providers, applications, redirect URIs, signing keys, `workspaceusers`, `workspaceadmin` |
| 5.3 | Wire Workcenter's own OIDC client (from Dashy) to the `workcenter` provider, including `adminGroup: workspaceadmin` |
| 5.4 | Wire FileBrowser `auth.methods.oidc` and prove `adminGroup` works |
| 5.5 | Wire Zulip's `GenericOpenIdConnectBackend` and prove login + admin role |
| 5.6 | Configure Mailcow **Generic-OIDC** and switch mailboxes to the OIDC identity source; deploy the Authentik **LDAP outpost** and wire Mailcow's LDAP identity provider for mail-protocol credentials; document app passwords as the fallback |
| 5.7 | Add the Authentik forward-auth middleware for `traefik.example.com`, restricted to `workspaceadmin` |
| 5.8 | Implement single logout |

**Exit criteria:** a `workspaceusers` member signs in once and reaches all three panes; a `workspaceadmin` member additionally reaches the Traefik dashboard; removing a user from `workspaceusers` locks them out everywhere.

**Depends on:** Phases 3–4.

---

### Phase 6 — The file broker

**Goal:** the four cross-application flows work.

| Step | Work |
| --- | --- |
| 6.1 | Stand up the broker service (Node/TypeScript, same repo, same image as the shell) with OIDC-protected routes |
| 6.2 | Implement the FileBrowser adapter: resolve user source root, list, read, write atomically, hash, de-duplicate |
| 6.3 | Implement the Mail adapter: IMAP(S) fetch of MIME parts; attachment listing; SMTP submission for attach-from-files |
| 6.4 | Implement the Zulip adapter: `POST /api/v1/user_uploads` (+ `/api/v1/tus` for large files), attachment fetch by `uri`, message insertion |
| 6.5 | Implement the transfer engine: streaming, max size, cancellation, atomic rename, audit log |
| 6.6 | Wire the four UI entry points in the shell (attachment row, SOGo compose, Zulip message action, Zulip compose) |
| 6.7 | Progress and notification UI, plus the **Open** deep link into the destination |
| 6.8 | Authorisation tests: user A can never touch user B's files or mailbox |

**Exit criteria:** all four flows (F1–F4) complete inside the page, with progress, notifications, correct filenames, no residue on failure, and a clean audit trail.

**Depends on:** Phases 2, 3, 5.

---

### Phase 7 — The Playwright integration harness

**Goal:** the whole stack is verifiable automatically on every merge into `Dev`.

| Step | Work |
| --- | --- |
| 7.1 | Deterministic test profile: fixed test users, fixed groups, seeded files, a seeded mail message and a seeded Zulip channel |
| 7.2 | `docker compose -f compose.test.yaml up -d` harness that brings the full stack up with test defaults |
| 7.3 | Playwright specs for: OIDC login, application switching, sidebar swap, deep links, theme persistence, each of the four transfers, the switcher status indicators, the pane failure card |
| 7.4 | Seeded-fixture mode that stubs the external mail/chat edges so the suite runs without outbound network |
| 7.5 | CI workflow `e2e.yml` triggered on pull requests into `Dev`; required check |
| 7.6 | Scheduled nightly run and artifact upload (traces, screenshots, videos, service logs) |

**Exit criteria:** a deliberately broken integration fails the suite with an actionable artifact; a clean merge passes; runtime is bounded and documented.

**Depends on:** Phases 2, 5, 6. Detailed in [`Testing.md`](./Testing.md).

---

### Phase 8 — Hardening, observability and operations

| Step | Work |
| --- | --- |
| 8.1 | Internal TLS option between backend services (D-7), including CA distribution |
| 8.2 | Security pass: CSP and frame-ancestors per pane, container hardening, secret handling, dependency audit |
| 8.3 | Backup/restore documentation and scripts for every stateful component |
| 8.4 | Upgrade documentation: Workcenter, FileBrowser Quantum, Zulip, Mailcow (via `update.sh`), OnlyOffice, Authentik |
| 8.5 | Log aggregation guidance and healthcheck-driven alerting |
| 8.6 | Resource sizing and troubleshooting runbooks in `production.md` |

**Exit criteria:** a security review with no unresolved high findings; a restore drill succeeds from documented backup steps only.

**Depends on:** Phase 5.

---

### Phase 9 — 1.0 release

| Step | Work |
| --- | --- |
| 9.1 | Full documentation review against the shipped application |
| 9.2 | Promote `Dev → Beta`, run the full suite, then promote `Beta → Stable` |
| 9.3 | Tag `v1.0.0`; publish images to GHCR with SBOM and provenance |
| 9.4 | Finalise `CHANGELOG.md` for the release |
| 9.5 | Publish the Quick Start path: `git clone` → `./setup.sh` → browse |

**Exit criteria:** a person who has never seen the repository completes the Quick Start on a fresh host in under an hour, unaided.

**Depends on:** all previous phases.

---

## 13. Milestones and exit criteria

| Milestone | Phase | Demonstrable outcome | Goal refs |
| --- | --- | --- | --- |
| **M0 — Scaffold** | 0 | Repository builds, lints and tests on a clean clone | G6, G11 |
| **M1 — Workspace only** | 1 | A Dashy-derived app with one view and no legacy surface | G1 |
| **M2 — Shell** | 2 | Switcher + three swappable sidebars + persistent panes | G1, G2, G8 |
| **M3 — Stack up** | 3 | All services healthy behind Traefik on subdomains | G4, G12 |
| **M4 — One command** | 4 | Bare host → running stack with `setup.sh` | G4 |
| **M5 — One identity** | 5 | Single Authentik login across all four surfaces, group-driven admin | G5, G10 |
| **M6 — File movement** | 6 | All four transfer flows complete in-page | **G3** |
| **M7 — Verified** | 7 | Playwright suite green on every PR into `Dev` | G7 |
| **M8 — Operable** | 8 | Backup, restore, upgrade, internal TLS, security review | G9, G10 |
| **M9 — 1.0** | 9 | Public release, Quick Start reproducible by a stranger | G4, G6 |

---

## 14. Non-goals

Workcenter 1.0 will **not**:

1. Ship a mobile app, a desktop app, or an offline/PWA mode.
2. Integrate a fourth application, or provide a plugin API for arbitrary tiles.
3. Retain Dashy's Default or Minimal views, tile grid, widgets, or status/ping monitoring.
4. Fork and patch a bundled application's source; bundled applications are pinned and configured only.
5. Support FileBrowser **v1** (the deprecated original) or filebrowser v1 data migration.
6. Replace Mailcow's own installer, updater, or compose file.
7. Provide multi-tenant hosting (multiple organisations on one instance).
8. Implement its own mail server, chat server, or file indexer.
9. Store user mail or chat content beyond transient transfer buffers and an audit trail.

---

## 15. Risks and mitigations

| # | Risk | Impact | Mitigation |
| --- | --- | --- | --- |
| R1 | **Iframe blocking** — an upstream application sets `X-Frame-Options: DENY` or a restrictive CSP | A pane cannot be embedded; core value lost | **Confirmed real for Zulip:** its nginx sends `add_header X-Frame-Options DENY always;` at server scope and Zulip exposes **no** setting or middleware to change it (see I-ZU-9). Mitigation: build a thin derived image from the pinned docker-zulip image overriding the nginx header include via `custom_zulip_files/`, changing `DENY` to a CSP `frame-ancestors 'self' https://<workcenter-host>`. This is a **deliberate, documented deviation** from the "never fork a bundled application" rule (R11), scoped to one static header file, version-pinned, and rebuilt only when the pin moves. Contingency if the derived image proves unmaintainable: the Chat pane falls back to a launch surface (Open in new tab) rather than an embedded frame, and the roadmap's milestone M2 is re-scoped. Every pane is additionally verified by a Playwright framing assertion |
| R11 | **The "never fork a bundled application" rule is violated once**, for Zulip's framing header | Precedent creep: every future problem gets solved by forking | The exception is recorded in [`architecture.md` AD-11](./architecture.md#10-architecture-decision-summary) with its exact scope (one nginx include file, no source patches, no behavioural changes), and any further fork request requires a roadmap change |
| R12 | **Zulip admin sync is unavailable on the pinned version** — OIDC group→role sync lands in Zulip 13 | `workspaceadmin` cannot be expressed declaratively in Zulip on 12.2 | `setup.sh` propagates the role out of band via `PATCH /api/v1/users/{user_id}` (I-ZU-6), and re-runs on demand; tracked as open question 4 |
| R13 | **FileBrowser Quantum sidebar cannot be injected into** — no slot, no plugin hook, no custom JS | The Workcenter switcher cannot live inside FileBrowser's own sidebar component tree | Workcenter renders the switcher as a body-level fixed element and shifts FileBrowser's fixed `#sidebar` with `frontend.styling.customCSS`, and mirrors the switcher inside FileBrowser as per-user `custom` `sidebarLinks` (I-FB-12/I-FB-13). Verified visually by Playwright |
| R2 | **SOGo has no native OIDC** | Mail pane authentication story is indirect | Use Mailcow's built-in Generic-OIDC identity provider as the authenticated front door (I-MC-5/I-MC-7) and Mailcow's LDAP identity provider for mail-protocol credentials (I-MC-6); the broker uses LDAP-backed or app-password credentials for IMAP(S)/SMTP; document the limitation honestly |
| R3 | **FileBrowser Quantum v2 churn** (beta) | Config schema or API may shift under us | Pin `2.0.6-beta` exactly, record the digest, isolate all v2-specific assumptions in the adapter layer, and re-verify on every bump |
| R4 | **Mailcow upgrade breakage** | Mail breaks on `update.sh` | Never edit Mailcow's compose file; keep every change in `docker-compose.override.yml`; test upgrades in the harness |
| R5 | **Cross-origin credential handling in the broker** | Security exposure of mail/chat credentials | Encrypted per-user token store; no plaintext at rest; strict per-user authorisation tests; broker is the only writer into the file source |
| R6 | **Resource footprint** (Zulip + Mailcow + OnlyOffice + Authentik together) | Won't run on small VPS | Document minimums (D-11), allow `SKIP_*` flags for optional Mailcow components, and publish a "minimum viable" profile |
| R7 | **Issuer/hostname mismatch behind Traefik** | OIDC redirect loops in every app | One canonical public HTTPS issuer; `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS`; `X-Forwarded-Proto`; a dedicated troubleshooting section in `OIDC.md` |
| R8 | **Scope creep back toward Dashy** | Rebuilt dashboard instead of a workspace | This roadmap's non-goals, plus a lint/schema test that fails if removed Dashy features reappear |
| R9 | **Playwright suite flakiness** | Lost trust in CI | Deterministic seeds, fixed users, stub external edges, retries only for known-timing assertions, artifacts always uploaded |
| R10 | **Two-way file flows hitting size/time limits** | Failed transfers confuse users | Streaming with explicit size caps, cancellation, resumable upload for Zulip (`/api/v1/tus`), and a visible failure reason |

---

## 16. Open questions

These are tracked as decisions to close, not as blockers:

1. **Broker runtime** — Node/TypeScript sharing the shell's image (favoured: one language, one build) versus a separate Go service (favoured by FileBrowser Quantum's stack). Decide in Phase 6.1.
2. **SOGo attach-from-files** — whether to attach via SMTP submission or via SOGo's own compose upload endpoint; depends on what SOGo exposes in the deployed version. Decide in Phase 6.3.
3. **Sidebar rendering depth** — how much of each application's sidebar Workcenter re-implements natively versus surfaces by deep-linking into the embedded app. Decide in Phase 2.4–2.6.
4. **Zulip admin sync** — group sync from the `zulip_groups` claim requires Zulip 13+; if the pinned Zulip is older, `setup.sh` must assert admin via `manage.py`. Confirm against the pinned version.
5. **Mailcow health signal** — Mailcow's compose defines no `healthcheck:` blocks, so Workcenter's override must add them; decide whether the canonical signal is those healthchecks, the Mailcow API (`/api/v1/get/status/containers` with `API_KEY` + `API_ALLOW_FROM`), or both. Decide in Phase 3.7.
6. **Mail credential path for the broker** — Mailcow LDAP (Authentik LDAP outpost) versus per-user app passwords for IMAP/SMTP. LDAP is cleaner for a single identity source; app passwords are simpler and need no outpost. Decide in Phase 6.3.
7. **Internal TLS scope** — which service-to-service links actually need TLS versus which stay on the Docker network. Decide in Phase 8.1.

---

## 17. Definition of done

Workcenter 1.0 is done when **all** of the following are true:

- [ ] A clean host with Docker and DNS pointed at it reaches a working Workcenter using only `./setup.sh`.
- [ ] One Authentik login grants access to Files, Chat and Mail, with no second prompt in any pane.
- [ ] The application switcher is above the sidebar, and the sidebar content swaps per active application.
- [ ] All four file-movement flows complete inside the page with progress and a success notification.
- [ ] `workspaceusers` and `workspaceadmin` behave identically across all four surfaces and the Traefik dashboard.
- [ ] Every service reports healthy in `docker compose ps`, and Workcenter gates on those healthchecks.
- [ ] TLS is terminated at Traefik for every public hostname; internal TLS is available on request.
- [ ] Mailcow still updates through its own `update.sh` without Workcenter-specific breakage.
- [ ] All volumes are bind mounts inside their owning application folder.
- [ ] The Playwright suite runs on every PR into `Dev` and is a required check.
- [ ] Every document in §11.2 exists, matches the shipped application, and is linked from [`Readme.md`](./Readme.md).
- [ ] `CHANGELOG.md` records every change, and `Dev → Beta → Stable` promotion has been exercised at least once.

---

<p align="center"><sub>Workcenter roadmap · derived from <a href="https://github.com/lissy93/dashy">Dashy</a> · built on FileBrowser Quantum, Zulip, Mailcow/SOGo, OnlyOffice, Authentik and Traefik</sub></p>
