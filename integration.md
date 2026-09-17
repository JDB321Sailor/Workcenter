# Workcenter — Integration Specification

> **Scope:** what each integrated application *is*, why Workcenter integrates it, exactly how it is
> wired in, and how the cross-application file movement works.
> **Audience:** implementers and operators.
> **Companions:** [`roadmap.md`](./roadmap.md) · [`architecture.md`](./architecture.md) ·
> [`OIDC.md`](./OIDC.md) · [`production.md`](./production.md) · [`Testing.md`](./Testing.md)

---

## Table of contents

1. [Integration model](#1-integration-model)
2. [The integration matrix](#2-the-integration-matrix)
3. [FileBrowser Quantum (Files)](#3-filebrowser-quantum-files)
4. [ONLYOFFICE Docs (editing, inside Files)](#4-onlyoffice-docs-editing-inside-files)
5. [Zulip (Chat)](#5-zulip-chat)
6. [Mailcow Dockerized and SOGo (Mail)](#6-mailcow-dockerized-and-sogo-mail)
7. [Authentik (identity)](#7-authentik-identity)
8. [Traefik (ingress)](#8-traefik-ingress)
9. [The cross-application file broker](#9-the-cross-application-file-broker)
10. [Health model](#10-health-model)
11. [Network and volume map](#11-network-and-volume-map)
12. [Integration verification matrix](#12-integration-verification-matrix)

---

## 1. Integration model

Workcenter integrates by **configuration and orchestration, never by patching**. Each application is
pinned to a version, deployed from its own image, configured through bind-mounted files and
environment variables, and reached either over its own HTTP API or through its own UI embedded in a
pane.

There are exactly four integration mechanisms:

| # | Mechanism | Used for |
| --- | --- | --- |
| **M1** | **Embedding** — the application's own web UI in a pane | Files, Chat, Mail *presentation* |
| **M2** | **OIDC / SSO** — one identity, one session | All four user-facing surfaces |
| **M3** | **REST API calls from the broker** | Zulip upload/download; FileBrowser file operations |
| **M4** | **Protocol access from the broker** | IMAP/SMTP to Dovecot/Postfix for mail attachments |

And exactly one deliberate deviation:

| Deviation | Scope | Why |
| --- | --- | --- |
| **D-1: a derived Zulip image** | One nginx header include file in `custom_zulip_files/` | Zulip ships `X-Frame-Options: DENY` with no supported way to change it (see [§5.4](#54-the-framing-problem)). The derived image pins the same upstream version and changes one static header. No application code is patched |

> **Rule IN-1:** if an integration appears to require patching an upstream application's source, stop
> and escalate. The only sanctioned exception is D-1, and any second exception requires a roadmap change.

---

## 2. The integration matrix

| Application | Version pin | Subdomain | Presentation | Identity | Data path | Health |
| --- | --- | --- | --- | --- | --- | --- |
| **Workcenter shell + broker** | built from this repo | `example.com` | — | OIDC client | — | `/healthz` |
| **FileBrowser Quantum** | `2.0.6-beta` | `filebrowser.example.com` | pane (iframe) | OIDC client | REST `/api/` + shared bind mount | image `HEALTHCHECK` → `/health` |
| **ONLYOFFICE Docs** | pinned tag | `office.example.com` (or internal) | inside the Files pane | none (JWT) | JWT-signed callbacks | `/healthcheck` |
| **Zulip** (5 services) | `ghcr.io/zulip/zulip-server:<ver>-0` | `chat.example.com` | pane (iframe, **derived image**) | OIDC client | REST `/api/v1/` | `/health` (IP-restricted) |
| **Mailcow** (18 services) | upstream `master` | `mail.example.com` | pane (iframe, SOGo) | **Generic-OIDC IdP** | IMAP/SMTP from the broker | override healthchecks + Mailcow API |
| **Authentik** | pinned tag | `auth.example.com` | — | the IdP | JWKS / discovery | `/-/health/live/`, `/-/health/ready/` |
| **Traefik** | `v3` | `traefik.example.com` | — | forward-auth (proxy provider) | — | `/ping` |

---

## 3. FileBrowser Quantum (Files)

### 3.1 What it is

[FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser) is the actively maintained fork of
the original FileBrowser — which is **deprecated** and is *not* used by Workcenter. Quantum adds
real-time indexing, search, previews, shares, WebDAV, an office-integration stack and a per-user
sidebar. **Workcenter targets the v2 line (2.0.6-beta) exclusively**, because v2 changed the
configuration schema, the database engine (SQLite rather than BoltDB) and the sidebar model.

### 3.2 Why Workcenter uses it

It is the file-management surface and the **substrate for cross-application file movement**: every
transfer in Workcenter ultimately writes into, or reads from, a FileBrowser source.

### 3.3 Wiring

**Image and ports**

```yaml
services:
  filebrowser:
    image: ${FILEBROWSER_IMAGE}          # gtstef/filebrowser:2.0.6-beta
    # ghcr.io/gtsteffaniak/filebrowser is an equivalent registry
    expose: ["80"]
    volumes:
      - ./Filebrowser/data:/home/filebrowser/data
      - ./Filebrowser/config.yaml:/home/filebrowser/data/config.yaml:ro
      - ${FILEBROWSER_SOURCE_PATH}:/srv/files
    environment:
      FILEBROWSER_CONFIG: /home/filebrowser/data/config.yaml
      FILEBROWSER_DATABASE_PATH: /home/filebrowser/data/database.sqlite
      FILEBROWSER_OIDC_CLIENT_ID: ${FILEBROWSER_OIDC_CLIENT_ID}
      FILEBROWSER_OIDC_CLIENT_SECRET: ${FILEBROWSER_OIDC_CLIENT_SECRET}
      FILEBROWSER_JWT_TOKEN_SECRET: ${FILEBROWSER_JWT_TOKEN_SECRET}
      FILEBROWSER_ONLYOFFICE_SECRET: ${FILEBROWSER_ONLYOFFICE_SECRET}
```

| Ref | Note |
| --- | --- |
| IN-3.1 | Image tags strip the leading `v`: git tag `v2.0.6-beta` → `2.0.6-beta`. There is **no `latest`** on the beta line, so the pin is mandatory. |
| IN-3.2 | `FILEBROWSER_DATABASE_PATH` does **not** override `server.database.path` — if the YAML sets the path, the YAML wins. Set it in exactly one place. |
| IN-3.3 | The image runs as uid/gid `1000:1000`; the bind-mounted source must be writable by that user. |

**Configuration (`Filebrowser/config.yaml`)** — v2 has exactly six top-level keys, and decoding is
**strict**: an unknown key is a fatal startup error.

```yaml
server:
  database:
    path: "/home/filebrowser/data/database.sqlite"
  sources:
    - path: "/srv/files"
      name: "Files"
      config:
        defaultEnabled: true        # REQUIRED: without this, OIDC users see an empty tree
        defaultPermissions:
          view: true
          download: true
          modify: true
          create: true
          delete: true
  cacheDir: "/home/filebrowser/data/cache"

http:
  port: 80
  baseURL: "/"
  externalUrl: "https://filebrowser.example.com"
  internalUrl: "http://filebrowser:80"   # OnlyOffice and the broker call back here
  trustProxyHeaders: true                # REQUIRED behind Traefik
  disableWebDAV: false

auth:
  methods:
    oidc:
      enabled: true
      issuerUrl: "https://auth.example.com/application/o/filebrowser/"
      clientId: ""            # from FILEBROWSER_OIDC_CLIENT_ID
      clientSecret: ""        # from FILEBROWSER_OIDC_CLIENT_SECRET
      scopes: "openid email profile groups"
      groupsClaim: "groups"
      userIdentifier: "preferred_username"
      adminGroup: "workspaceadmin"
      userGroups: ["workspaceusers"]
      logoutRedirectUrl: "https://auth.example.com/application/o/filebrowser/end-session/"
    password:
      enabled: false

frontend:
  name: "Files"
  disableDefaultLinks: false

integrations:
  office:
    url: "https://office.example.com"
    internalUrl: "http://onlyoffice:80"
    secret: ""                # from FILEBROWSER_ONLYOFFICE_SECRET
```

| Ref | Note |
| --- | --- |
| IN-3.4 | **`config.defaultEnabled: true` on the source is mandatory.** The default is `false`, and a user created via OIDC sees no files until a source is enabled for them. It is only implied automatically when there is exactly one source — do not rely on that. |
| IN-3.5 | **`http.trustProxyHeaders: true` is mandatory.** FileBrowser builds its OIDC redirect URI from the **incoming request** (`https://<host><baseURL>api/auth/oidc/callback`), never from `externalUrl`. Traefik must send `X-Forwarded-Proto` and `X-Forwarded-Host` with `passHostHeader`. Register exactly the derived URI in Authentik. |
| IN-3.6 | Provider discovery runs **at startup**, and failure is fatal. If Authentik is unreachable when FileBrowser starts, FileBrowser will not start. Order the stack accordingly. |
| IN-3.7 | Valid v2 keys are `http.disableWebDAV` (not `server.disableWebDAV` — the latter fails startup), and `integrations.office` (not a root `office:`). There is **no** `disableVerifyTLS` for OnlyOffice; it exists only for auth methods. |
| IN-3.8 | `userGroups` blocks sign-in for anyone outside `workspaceusers` (HTTP 403). Remove it to allow any Authentik user. |

**Traefik labels**

```yaml
labels:
  traefik.enable: "true"
  traefik.docker.network: "proxy"
  traefik.http.routers.filebrowser.rule: "Host(`filebrowser.example.com`)"
  traefik.http.routers.filebrowser.entrypoints: "websecure"
  traefik.http.routers.filebrowser.tls: "true"
  traefik.http.routers.filebrowser.tls.certresolver: "le"
  traefik.http.routers.filebrowser.middlewares: "security-headers@file"
  traefik.http.services.filebrowser.loadbalancer.server.port: "80"
```

### 3.4 The sidebar: how Workcenter integrates with it

FileBrowser Quantum's sidebar is a fixed `<nav id="sidebar">` positioned at `top: 4em`, containing
either a links list or a file-tree navigation mode. It has **no slot, no plugin hook, no custom-JS
hook and no public JavaScript API**.

| Ref | Consequence |
| --- | --- |
| IN-3.9 | Workcenter **cannot inject the switcher into FileBrowser's sidebar DOM.** Instead: (a) Workcenter renders its own switcher as a body-level fixed element positioned over FileBrowser's chrome, and (b) `frontend.styling.customCSS` is used to shift `#sidebar` down by the switcher's height. `style-src` is not restricted, so injected CSS applies. |
| IN-3.10 | In addition, `setup.sh` **mirrors** the switcher inside FileBrowser as per-user `custom` sidebar links, so a user who opens FileBrowser directly (outside the shell) still sees the other two applications. |
| IN-3.11 | Per-user sidebar links persist **server-side in the user object** as `{name, category, target, icon, sourceName?}`. Read: `GET /api/users?username=self`. Write: `PATCH /api/users?username=<login>` with `{"which":["sidebarLinks","showToolsInSidebar"],"data":{…}}` → `204`. Non-admins may patch their own `sidebarLinks`. |
| IN-3.12 | Valid categories: `source`, `source-minimal`, `source-alt`, `source-hybrid`, `source-hybrid-2`, `tool`, `custom` (plus frontend-only `share`, `shareInfo`, `download`, `divider`). Source links that do not resolve to a configured source are **silently dropped**; non-source links are unvalidated. |
| IN-3.13 | **Round-trip trap:** `sourceName` is written as the source's **filesystem path** but returned on read as its **display name**. Any code that reads a link and writes it back must translate. |

### 3.5 File operations the broker uses

| Operation | Call |
| --- | --- |
| List a folder | `GET /api/resources/items?path=&source=` |
| Download a file | `GET /api/resources/download?source=&file=` |
| Upload a file | `POST /api/resources?path=&source=[&override=true][&isDir=true]` |
| Move / copy | `PATCH /api/resources` (JSON body) |
| Preview / inline view | `GET /api/resources/preview`, `GET /api/resources/view` |
| Mint a service token | `POST /api/auth/token?name=&days=&minimal=true` (requires the `api` permission) |
| WebDAV | `https://filebrowser.example.com/dav/<source-name>/<path>` — Basic auth where the **username is ignored** and the password is a **minimal API token** |

| Ref | Note |
| --- | --- |
| IN-3.14 | **The API base path is `/api/`. There is no `/api/v1/`.** Public/share routes live under `/public/api/`. Swagger is at `/swagger/`. |
| IN-3.15 | Authentication order is `?auth=<token>` → `Authorization` header (Bearer, or Basic where the password is the token) → the `filebrowser_quantum_jwt` cookie. There is **no `X-Auth` header**. |
| IN-3.16 | The broker uses a **minimal** API token for service-to-service work, and the user's own session for per-user operations. Never a full-admin token for routine transfers. |

---

## 4. ONLYOFFICE Docs (editing, inside Files)

### 4.1 What it is

[ONLYOFFICE Docs](https://github.com/ONLYOFFICE/DocumentServer) (formerly Document Server) is a
self-hosted collaborative office suite — documents, spreadsheets, presentations, forms, PDFs and
diagrams — with real-time co-editing over OOXML formats.

### 4.2 Why Workcenter uses it

It turns the Files pane into an editing surface. Without it, Workcenter can store and preview
documents but not edit them.

### 4.3 Wiring

```yaml
services:
  onlyoffice:
    image: ${ONLYOFFICE_IMAGE}          # onlyoffice/documentserver
    expose: ["80"]
    environment:
      JWT_ENABLED: "true"
      JWT_SECRET: ${FILEBROWSER_ONLYOFFICE_SECRET}   # byte-identical to integrations.office.secret
      JWT_HEADER: "Authorization"
      ONLYOFFICE_HTTPS_HSTS_ENABLED: "false"
      ALLOW_PRIVATE_IP_ADDRESS: "true"
    volumes:
      - ./OnlyOffice/data:/var/www/onlyoffice/Data
      - ./OnlyOffice/logs:/var/log/onlyoffice
      - ./OnlyOffice/lib:/var/lib/onlyoffice
      - ./OnlyOffice/db:/var/lib/postgresql
```

**Three URL roles — get these wrong and editing silently fails:**

| Role | Key | Value in Workcenter |
| --- | --- | --- |
| Browser → OnlyOffice | `integrations.office.url` | `https://office.example.com` (must be reachable from the user's browser) |
| FileBrowser → OnlyOffice | `integrations.office.internalUrl` | `http://onlyoffice:80` (bypasses Traefik) |
| OnlyOffice → FileBrowser | `http.internalUrl` | `http://filebrowser:80` |

**Callbacks OnlyOffice must be able to make, unauthenticated:**

```
GET  <http.internalUrl>/api/resources/view?file=…&viewToken=…&source=…&auth=<JWT>
POST <http.internalUrl>/api/office/callback?source=…&path=…&auth=<JWT>
     (+ /public/api/office/callback and /public/api/resources/view for shares)
```

| Ref | Note |
| --- | --- |
| IN-4.1 | Authorisation on those callbacks is the **`?auth=` JWT**, not a cookie. Any forward-auth middleware must exclude `/health`, `/public/*`, `/api/office/callback`, `/api/resources/view` and `/api/resources/download`. |
| IN-4.2 | The secret is generated with `openssl rand -base64 32` and must be byte-identical on both sides. It is supplied through `FILEBROWSER_ONLYOFFICE_SECRET` and the OnlyOffice `JWT_SECRET`. |
| IN-4.3 | **The OnlyOffice Traefik router must allow framing.** Never apply `frameDeny` to it, and set `accesscontrolalloworiginlist=*`, which the upstream guide calls critical for FileBrowser ↔ OnlyOffice to work. |
| IN-4.4 | The FileBrowser router, by contrast, uses the `security-headers` middleware. The two routers must not share a framing middleware. |
| IN-4.5 | For internal self-signed HTTPS between the containers, use a Traefik `serversTransport` with `insecureSkipVerify` — **not** a FileBrowser `disableVerifyTLS` flag, which does not exist for OnlyOffice. |
| IN-4.6 | Healthcheck: `curl -f http://localhost/healthcheck`. |

---

## 5. Zulip (Chat)

### 5.1 What it is

[Zulip](https://github.com/zulip/zulip) is an open-source team chat application built around
**topic-based threading** — every conversation lives in a channel and a topic, which makes
asynchronous work tractable in a way linear chat is not.

### 5.2 Why Workcenter uses it

It is the Chat pane: durable, threadable team conversation, with file sharing that participates in
Workcenter's cross-application transfers.

### 5.3 Deployment

Workcenter deploys the **full docker-zulip stack** — the five services from
[`zulip/docker-zulip`'s `compose.yaml`](https://github.com/zulip/docker-zulip/blob/main/compose.yaml):

| Service | Image | Role |
| --- | --- | --- |
| `database` | `zulip/zulip-postgresql:14` | PostgreSQL |
| `memcached` | `memcached:alpine` | Cache (SASL-protected) |
| `rabbitmq` | `rabbitmq:4.2` | Queue |
| `redis` | `redis:alpine` | Cache/rate limiting |
| `zulip` | `ghcr.io/zulip/zulip-server:<version>-0` | The application (nginx + Django + Tornado + supervisor) |

| Ref | Note |
| --- | --- |
| IN-5.1 | The legacy `zulip/docker-zulip` Docker Hub image is the **end-of-life lineage** for Zulip 11.x and earlier. Workcenter uses `ghcr.io/zulip/zulip-server`. |
| IN-5.2 | `DISABLE_HTTPS` and `SSL_CERTIFICATE_GENERATION` are legacy and now cause a **hard startup failure**. Do not set them. |
| IN-5.3 | Secrets are file-based (`/run/secrets/zulip__*`). `setup.sh` generates them into `Zulip/secrets/`. |
| IN-5.4 | All persistent state is bind-mounted under `Zulip/`: `/data`, the PostgreSQL data directory, RabbitMQ and Redis. |

**Configuration mechanism**

| Kind | Mechanism |
| --- | --- |
| Scalars | `SETTING_<NAME>` environment variables (docker-zulip translates them into `settings.py`) |
| **Dicts and lists** | **`ZULIP_CUSTOM_SETTINGS`** — raw Python appended to `settings.py`. `SETTING_*` cannot express a dict |
| Auth backends | `ZULIP_AUTH_BACKENDS` — bare class names; docker-zulip prepends `zproject.backends.` |

| Ref | Note |
| --- | --- |
| IN-5.5 | `SOCIAL_AUTH_OIDC_ENABLED_IDPS` **must** go through `ZULIP_CUSTOM_SETTINGS`. Treat that block as reviewed code — a Python syntax error prevents Zulip from starting. |
| IN-5.6 | `SOCIAL_AUTH_OIDC_ENABLED`, `SOCIAL_AUTH_OIDC_CLIENT_ID`, `SOCIAL_AUTH_OIDC_SECRET` and `SOCIAL_AUTH_OIDC_URL` **do not exist** in Zulip. Only `SOCIAL_AUTH_OIDC_ENABLED_IDPS` and `SOCIAL_AUTH_OIDC_FULL_NAME_VALIDATED` do. |

### 5.4 The framing problem

**Zulip cannot be embedded as shipped.**

```
puppet/zulip/files/nginx/zulip-include-common/headers
    → add_header X-Frame-Options DENY always;
```

That include is applied at server scope. Zulip exposes **no Django `X_FRAME_OPTIONS` setting** and has
**no `XFrameOptionsMiddleware`**. Its CSP, where it sets one, never includes `frame-ancestors` — so
there is nothing to relax there either.

**Workcenter's answer (deviation D-1):** build a thin derived image from the pinned
`ghcr.io/zulip/zulip-server` image, using docker-zulip's supported customisation hook. The upstream
Dockerfile performs `cp -rf /root/custom_zulip/* /root/zulip`, so a `custom_zulip_files/` directory in
the build context can override the nginx header include — changing `DENY` to the equivalent of
`frame-ancestors 'self' https://example.com`.

```
Zulip/
├── Dockerfile               # FROM ghcr.io/zulip/zulip-server:<pinned> ; COPY custom_zulip_files/ /root/custom_zulip/
└── custom_zulip_files/
    └── puppet/zulip/files/nginx/zulip-include-common/headers   # DENY → frame-ancestors allow-list
```

| Ref | Note |
| --- | --- |
| IN-5.7 | The derived image is pinned to the **same** upstream version. It exists only to change one static header. No application code is patched. |
| IN-5.8 | The override must restrict framing to the Workcenter origin — never `*`. Zulip is a chat application holding user content; framing it from anywhere would enable clickjacking. |
| IN-5.9 | If the derived image becomes unmaintainable, the fallback is to render the Chat pane as a launch surface (summary plus **Open in new tab**) rather than an embedded frame. That decision is recorded in the roadmap as an open risk. |
| IN-5.10 | The Playwright suite asserts the Chat pane actually renders application content, not an error page, so a regression here fails CI rather than shipping silently. |

### 5.5 Traefik and the long-poll connection

| Ref | Requirement |
| --- | --- |
| IN-5.11 | **Zulip has no websockets.** Real-time events arrive over **HTTP long-polling** to `/json/events` and `/api/v1/events` (Zulip's nginx proxies both to Tornado with `proxy_buffering off; proxy_read_timeout 1200;`). Traefik needs no `Upgrade`/`Connection` handling and no sticky sessions. |
| IN-5.12 | Traefik **must disable response buffering** on the long-poll route and allow read/idle timeouts well beyond 60 seconds. The label is `traefik.http.services.<svc>.loadbalancer.responseforwarding.flushinterval`, and a custom `serversTransport` (`traefik.http.services.<svc>.loadbalancer.serverstransport`) must reference an entry defined in Traefik's **dynamic file** configuration. The entrypoint-level `respondingTimeouts.readTimeout` defaults to 60 s and is what actually kills long-polls. |
| IN-5.13 | **Pass the client `Host` header through unchanged and set `X-Forwarded-Proto: https`.** Zulip's CSRF protection depends on trusting the proxy, so the proxy's address must be in `SETTING_LOADBALANCER_IPS`. **`CSRF_TRUSTED_ORIGINS` is not a Zulip production setting** — it exists only in Zulip's development settings. `SETTING_USE_X_FORWARDED_HOST` is a fallback, not the preferred mechanism. |
| IN-5.13a | Do **not** set `ALLOWED_HOSTS`; Zulip derives it from `SETTING_EXTERNAL_HOST`. |
| IN-5.14 | `/health` is IP-restricted (`allow 127.0.0.1; allow <LOADBALANCER_IPS>; deny all`), so a probe from Traefik needs Traefik's address in `SETTING_LOADBALANCER_IPS` — otherwise it receives **403**, which is easy to mistake for an application failure. |
| IN-5.14a | **Do not publish ports 80/443 from the `zulip` container.** Replace the upstream `ports:` with `ports: !override` (Compose v2.24.4+), publish only what mail needs (25), and let Traefik reach `zulip:80` over the shared network. Note that Compose **appends** sequences, so a plain `volumes:`/`ports:` key in an override file yields *both* the upstream entry and yours — `!override` is required to replace them. |

### 5.6 File operations the broker uses

| Operation | Call |
| --- | --- |
| Upload into a message | `POST /api/v1/user_uploads` (multipart) → `{"uri": …, "url": …}` |
| Upload a large file | `POST /api/v1/tus` (resumable) |
| Download an attachment | `GET /user_uploads/{realm_id}/{filename}` |
| Send a message containing the file | `POST /api/v1/messages` with the returned Markdown link |

| Ref | Note |
| --- | --- |
| IN-5.15 | **There is a hard 25 MiB request-body cap** at Zulip's nginx (`client_max_body_size 25m`), even when `POST /register` advertises a higher `max_file_upload_size_mib`. `POST /api/v1/user_uploads` returns **413** above 25 MiB. Files at or above that size **must** use `/api/v1/tus`, whose location sets `client_max_body_size 0`. |
| IN-5.16 | Zulip's nginx sets permissive CORS on `/api/`, `/user_uploads`, `/avatar` and `/thumbnail` (`Access-Control-Allow-Origin: *`, `Authorization` allowed), and a request to `GET /user_uploads/…` carrying an `Authorization` header bypasses rate limiting. Attachment downloads may therefore be fetched directly; uploads **are** rate limited (200/min/user). |
| IN-5.17 | The broker authenticates with a dedicated **bot** (`email` + API key from `Zulip/secrets/zuliprc`) using HTTP Basic. Create the bot in Zulip, subscribe it to the target channel, and store its credentials as a secret. |

### 5.7 Admin mapping on the pinned version

| Ref | Note |
| --- | --- |
| IN-5.18 | **OIDC group→role sync requires Zulip 13.** Zulip 11 added group sync for **SAML only**. On the pinned 12.2 image, `zulip_groups`/`zulip_role` claims are accepted into the IdP configuration but not synchronised. |
| IN-5.19 | `setup.sh` therefore propagates `workspaceadmin` **out of band** with `PATCH /api/v1/users/{user_id}` (role: owner 100, administrator 200, moderator 300, member 400, guest 600), and re-runs on demand. This is idempotent and safe to repeat. |
| IN-5.20 | When Workcenter moves to Zulip 13, the out-of-band step is replaced by `SOCIAL_AUTH_SYNC_ATTRS_DICT` with `groups` and `role` entries and the `zulip_groups`/`zulip_role` claims listed in the IdP's `extra_attrs`. |

---

## 6. Mailcow Dockerized and SOGo (Mail)

### 6.1 What they are

[Mailcow Dockerized](https://github.com/mailcow/mailcow-dockerized) is a full self-hosted mail
server stack — Postfix, Dovecot, Rspamd, ClamAV, MariaDB, Redis, Unbound, nginx, a management UI and
**[SOGo](https://github.com/Alinto/sogo)** for webmail, calendars and contacts. Mailcow runs roughly
eighteen containers and expects to own its own lifecycle through `generate_config.sh` and `update.sh`.

### 6.2 Why Workcenter uses it

It is the Mail pane, and it is the source and destination for two of the four file-movement flows.
SOGo is not deployed separately — it ships inside Mailcow.

### 6.3 The orchestration rule

> **Mailcow is never forked, never re-composed, and never driven with `-f`.**

| Ref | Rule |
| --- | --- |
| IN-6.1 | Mailcow runs from **its own unmodified `docker-compose.yml`**, prepared by **its own `generate_config.sh`**, updated by **its own `update.sh`**. |
| IN-6.2 | Workcenter's only change is `Mailcow/docker-compose.override.yml`. Mailcow's own `.gitignore` lists that filename, confirming it is the sanctioned, update-safe customisation point. |
| IN-6.3 | Mailcow is always driven with `docker compose` **from inside `Mailcow/` with no `-f` flag**, so the override auto-merges. `Mailcow/.env` is a **symlink to `mailcow.conf`**, and Mailcow's compose reads it — never set `COMPOSE_FILE` in `mailcow.conf`, because that file *is* the env file. |

### 6.4 Non-interactive preparation

`setup.sh` runs Mailcow's own generator without any interactive prompt by pre-setting the variables
its guards test and forcing the one scripted question:

```bash
cd Mailcow
export MAILCOW_HOSTNAME="mail.example.com"
export MAILCOW_TZ="Etc/UTC"
export MAILCOW_BRANCH="master"
export MAILCOW_DBPASS="$(openssl rand -hex 24)"
export MAILCOW_DBROOT="$(openssl rand -hex 24)"
export MAILCOW_REDISPASS="$(openssl rand -hex 24)"
export SKIP_CLAMD="n"
export FORCE="y"            # suppresses the interactive IPv6 daemon.json prompt
./generate_config.sh
```

Every guard in `generate_config.sh` is a `while [ -z "$VAR" ]`-style test, so a pre-set variable is
never prompted for. The script refuses to run unless `.env` is a symlink to `mailcow.conf` in the
current directory — which the clone already provides.

### 6.5 The Traefik integration, and its traps

```yaml
# Mailcow/docker-compose.override.yml — shape, not final content
services:
  nginx-mailcow:
    networks:
      mailcow-network:
        aliases: [nginx]
      proxy: {}
    labels:
      traefik.enable: "true"
      traefik.docker.network: "proxy"
      traefik.http.routers.mailcow.rule: "Host(`mail.example.com`)"
      traefik.http.routers.mailcow.entrypoints: "websecure"
      traefik.http.routers.mailcow.tls: "true"
      traefik.http.routers.mailcow.tls.certresolver: "le"
      traefik.http.services.mailcow.loadbalancer.server.port: "8080"

networks:
  proxy:
    external: true
```

Also required in `mailcow.conf`:

| Setting | Value | Why |
| --- | --- | --- |
| `SKIP_LETS_ENCRYPT` | `y` | Traefik handles certificates |
| `AUTODISCOVER_SAN` | `n` | No Mailcow-managed SANs |
| **`HTTP_REDIRECT`** | **`n`** | **Critical.** `generate_config.sh` writes `y`, and with `y` the only listener on `HTTP_PORT` is a 301 redirect to HTTPS — so Traefik → `http://nginx:8080` returns `301 https://mail.example.com` and **loops forever**. The Mailcow Traefik guide omits this step |
| `HTTP_BIND` / `HTTPS_BIND` | `127.0.0.1` | Keeps Mailcow's own listeners off the public interface |
| `TRUSTED_PROXIES` | The Traefik network CIDR | Correct client IPs in Mailcow's logs and rate limiting |

| Ref | Note |
| --- | --- |
| IN-6.4 | **An override file cannot remove Mailcow's published ports.** Docker *concatenates* `ports` and `expose` lists rather than replacing them, so an override cannot delete `80:80`/`443:443`, and adding `127.0.0.1:80:80` produces two conflicting bindings. Use `HTTP_BIND`/`HTTPS_BIND` — Mailcow's own documented mechanism — plus the override's `expose` and the `proxy` network. |
| IN-6.5 | Mailcow's compose defines **zero** `healthcheck:` blocks. Workcenter's override adds them for `nginx-mailcow`, `sogo-mailcow`, `mysql-mailcow` and `redis-mailcow`, so `depends_on: condition: service_healthy` is meaningful. |
| IN-6.6 | `providers.docker.network` must be set in Traefik's static config, because Mailcow containers join more than one network and Traefik would otherwise guess wrong. |

### 6.6 Authentication

Mailcow has a **first-class Identity Provider feature** at
**System → Configuration → Access → Identity Provider**, with **Generic-OIDC**, **Keycloak** and
**LDAP** options. Workcenter uses Generic-OIDC against Authentik.

| Ref | Note |
| --- | --- |
| IN-6.7 | The Mailcow UI is an **OIDC client**. Do **not** put `mail.example.com` behind an Authentik forward-auth proxy. |
| IN-6.8 | A mailbox's `authsource` column is an enum of `mailcow`, `keycloak`, `generic-oidc`, `ldap`, and the provider settings live in a `(key, value)` table named `identity_provider`. `setup.sh` can therefore switch a mailbox to `generic-oidc` with a single `UPDATE`. |
| IN-6.9 | Switching a mailbox to `generic-oidc` **does not erase** the existing SQL password, so reverting to `mailcow` restores password login. |
| IN-6.10 | **OIDC mailboxes cannot authenticate IMAP, SMTP, POP3 or SIEVE.** Mailcow's login helper has no `generic-oidc` branch for mail protocols. **App passwords are mandatory**, generated per user at *Mailbox Settings → App Passwords*. |
| IN-6.11 | Alternatively, Mailcow's **LDAP** identity provider performs a real bind for mail protocols as well as the UI, making Authentik the source of truth for both. This requires deploying Authentik's LDAP outpost. |
| IN-6.12 | Authentik's LDAP outpost is **bind-and-search only** — it exposes no add/modify handlers, which is sufficient for Mailcow, since Mailcow only binds and reads attributes. Verify a simple bind with an end-user password before relying on this path. |

### 6.7 SOGo, and why it is reached through the Mailcow UI

SOGo **≥ 5.12** has native OIDC, and Mailcow ships SOGo 5.12.10 — so the code is compiled in. But
Mailcow does not configure it, and enabling it would require a Dovecot **OAuth2 passdb** (absent) and
an `OCSOpenIdURL` pointing at a `sogo_openid` table that does not exist in Mailcow's schema. Mailcow's
documentation states the consequence: identity-provider users *"can only log in to SOGo through the
mailcow UI."*

**How the SSO session works** (this is what makes the Mail pane predictable):

```
Browser → Traefik → nginx-mailcow
   ├── /       → Mailcow UI (its own login, or Generic-OIDC)
   └── /SOGo   → internal auth_request → 127.0.0.1:65510/sogo-auth
                     → data/web/sogo-auth.php
                        ├─ HTTP Basic present?      → validate, inject x-webobjects-remote-user
                        ├─ Mailcow session present? → inject Basic <email>:<sogo-sso.pass>
                        └─ neither?                 → EMPTY headers → SOGo's own login form
```

Mailcow sets `SOGoTrustProxyAuthentication = YES`, which is why the injected headers are trusted.
`SOGoUserSources` is generated at container start into `/var/lib/sogo/GNUstep/Defaults/sogod.plist`
by `bootstrap-sogo.sh`, as one `type = sql` source per mail domain against `_sogo_static_view`.

| Ref | Note |
| --- | --- |
| IN-6.13 | The SOGo session is established by the Mailcow UI's **"Login to Webmail"** action, which calls `/sogo-auth.php?login=<address>` and sets a session flag that the auth proxy later turns into injected credentials. |
| IN-6.14 | Opening `/SOGo` **without** that session shows SOGo's own login form. The Workcenter Mail pane must detect this and surface its `auth-error` state with **Sign in again**, which opens `https://mail.example.com` so the session can be established. |
| IN-6.15 | The shared `sogo-sso.pass` is regenerated on **every Dovecot container start** and lives in `Mailcow/data/conf/phpfpm/sogo-sso/`. Dovecot's static passdb accepts it only from SOGo's container IP. Nothing in Workcenter may cache or depend on that value. |
| IN-6.16 | If you ever attempt native SOGo OIDC anyway, set `SOGoOpenIdTokenCheckInterval` to a non-zero value (for example `60`) — its default of `0` performs a token check on every request and causes a large slowdown. Do **not** write configuration against `SOGoAuthenticationMethod` or `SOGoWebAuthentication`; those settings do not exist. |

### 6.8 Mail access the broker uses

| Operation | Mechanism |
| --- | --- |
| List a message's attachments (F1) | **IMAP over TLS** to `dovecot-mailcow`, `BODYSTRUCTURE` then `FETCH` of the MIME part |
| Retrieve an attachment (F1) | IMAP `FETCH BODY.PEEK[<part>]`, streamed |
| Attach a file to a draft (F2) | **SMTP submission** to `postfix-mailcow` with the file as a MIME part |
| Credentials | The user's Mailcow **app password** (default) or their Authentik credentials via Mailcow's LDAP provider |

| Ref | Note |
| --- | --- |
| IN-6.17 | SOGo exposes no stable public REST API for attachment extraction. IMAP is the reliable, standards-based path and does not depend on SOGo internals. |
| IN-6.18 | The broker stores mail credentials **encrypted at rest**, keyed by a secret held only in `.env`. It never stores an administrator password for routine transfers. |
| IN-6.19 | For F1, the broker writes into the FileBrowser source using **temp-file-then-atomic-rename**, so FileBrowser's indexer never sees a partial file. |

---

## 7. Authentik (identity)

### 7.1 What it is

[Authentik](https://goauthentik.io/) is an open-source identity provider speaking OIDC, OAuth 2.0,
SAML 2.0 and LDAP, with a policy engine, MFA and an outpost model for forward authentication.

### 7.2 Wiring

```yaml
services:
  postgresql:
    image: docker.io/library/postgres:16-alpine
    environment: { POSTGRES_PASSWORD: ${PG_PASS}, POSTGRES_USER: authentik, POSTGRES_DB: authentik }
    volumes: [ "./data/postgres:/var/lib/postgresql/data" ]
  server:
    image: ghcr.io/goauthentik/server:${AUTHENTIK_TAG}
    command: server
    environment: &authentik-env
      AUTHENTIK_POSTGRESQL__HOST: postgresql
      AUTHENTIK_POSTGRESQL__PASSWORD: ${PG_PASS}
      AUTHENTIK_SECRET_KEY: ${AUTHENTIK_SECRET_KEY}
      AUTHENTIK_BOOTSTRAP_PASSWORD: ${AUTHENTIK_BOOTSTRAP_PASSWORD}
      AUTHENTIK_BOOTSTRAP_TOKEN: ${AUTHENTIK_BOOTSTRAP_TOKEN}
      AUTHENTIK_BOOTSTRAP_EMAIL: ${AUTHENTIK_BOOTSTRAP_EMAIL}
      AUTHENTIK_ERROR_REPORTING__ENABLED: "false"
      AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS: "172.16.0.0/12"
    volumes: [ "./data/media:/media", "./data/certs:/certs", "./data/templates:/templates" ]
  worker:
    image: ghcr.io/goauthentik/server:${AUTHENTIK_TAG}
    command: worker
    environment: *authentik-env
```

| Ref | Note |
| --- | --- |
| IN-7.1 | Authentik's own repository no longer publishes a compose file on `main`; use the compose from the installation documentation. |
| IN-7.2 | **Redis was removed in Authentik 2025.10.** Recent versions need only PostgreSQL, the server and the worker. |
| IN-7.3 | `AUTHENTIK_COOKIE_SAMESITE` and `AUTHENTIK_WEB__PORT` **do not exist**. Use `AUTHENTIK_COOKIE_DOMAIN` and `AUTHENTIK_LISTEN__HTTP`. |
| IN-7.4 | `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` must include Traefik's network, and Traefik must send `X-Forwarded-Proto: https`. Without it Authentik advertises an `http://` issuer and every client fails with `unexpected "iss" claim value`. |
| IN-7.5 | **`email_verified` defaults to `False`** in recent Authentik versions. FileBrowser and Zulip can reject logins on that basis; if so, map or override the claim. This is a classic silent login failure. |
| IN-7.6 | **The `groups` claim is emitted only by the `profile` scope.** A provider whose Selected Scopes omit `profile` will never deliver groups, and every `adminGroup` check fails. |
| IN-7.7 | Health endpoints: `/-/health/live/` and `/-/health/ready/` on the server; `ak healthcheck` for the worker; `/outpost.goauthentik.io/ping` on port 9300 for the outpost. |
| IN-7.8 | Forward auth through Traefik needs **two routers** — one for `/outpost.goauthentik.io/` at a **higher priority** than the application's router — plus `maxResponseBodySize: 4194304` on the middleware. |

The full provider walkthrough is in [`OIDC.md`](./OIDC.md).

---

## 8. Traefik (ingress)

### 8.1 What it is

[Traefik](https://traefik.io/) v3 is a cloud-native reverse proxy that discovers services from Docker
labels and manages TLS certificates automatically.

### 8.2 Why Workcenter uses it

One ingress point, one TLS story, one place to express routing. Every public hostname in the stack
terminates at Traefik.

### 8.3 Static configuration (`Traefik/traefik.yml`)

```yaml
entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint: { to: websecure, scheme: https }
  websecure:
    address: ":443"
    transport:
      respondingTimeouts:
        readTimeout: 0        # required: Zulip's long-poll must not be cut off
        idleTimeout: 0
  traefik:
    address: ":8080"          # the dashboard/API entrypoint

api:
  dashboard: true

ping:
  entryPoint: traefik         # /ping on :8080

providers:
  docker:
    exposedByDefault: false
    network: proxy            # REQUIRED: Mailcow containers join several networks
  file:
    directory: /etc/traefik/dynamic
    watch: true

certificatesResolvers:
  le:
    acme:
      email: "${ACME_EMAIL}"
      storage: /acme.json
      httpChallenge:
        entryPoint: web
```

| Ref | Note |
| --- | --- |
| IN-8.1 | **Traefik's image has no `HEALTHCHECK`.** Workcenter's compose defines one against `/ping` on the `traefik` entrypoint. |
| IN-8.2 | In v3, `traefik.http.routers.<name>.tls=true` is still required even when using labels; the old `sslRedirect`/`sslForceHost` options were **removed** in v3. |
| IN-8.3 | `providers.docker.network` is mandatory here because Mailcow containers are attached to more than one network. |
| IN-8.4 | Detecting whether Traefik is already running is part of `setup.sh`; see [`production.md`](./production.md). If one exists, Workcenter adopts it rather than deploying a second proxy. |

### 8.4 Middleware contracts

| Middleware | Used by | Notes |
| --- | --- | --- |
| `security-headers@file` | Workcenter, FileBrowser, Mailcow, Zulip | HSTS, `X-Content-Type-Options`, `Referrer-Policy`, and a per-application `frame-ancestors` |
| `no-frame-block@file` | OnlyOffice | Must **not** deny framing |
| `authentik@file` (forwardauth) | Traefik dashboard only | Plus the second, higher-priority router described in IN-7.8 |
| Long-poll tuning | Zulip's event routes | Response buffering off, extended read/idle timeouts |

> **Rule IN-8.5:** framing policy is expressed **per application**, never globally. Workcenter's own
> `frame-ancestors` allow-list is the Workcenter origin; OnlyOffice must be framable; Zulip's framing
> is handled by its derived image.

---

## 9. The cross-application file broker

The broker is specified functionally in [`roadmap.md` §7](./roadmap.md#7-the-headline-capability-cross-application-file-movement),
architecturally in [`architecture.md` §4](./architecture.md#4-the-broker), and tested in
[`Testing.md`](./Testing.md). This section covers only **how it talks to each application**.

### 9.1 Flow F1 — SOGo attachment → Files

```
User clicks "Save to files" in the Mail pane
   │
   ├─1. Shell → broker:  POST /api/broker/mail/attachments/save {messageId, partId, destPath}
   │
   ├─2. Broker → Dovecot:  IMAP over TLS (993) as the user
   │        SELECT INBOX → UID FETCH <uid> BODYSTRUCTURE → locate the part
   │        UID FETCH <uid> BODY.PEEK[<part>]  → stream
   │
   ├─3. Broker → filesystem:  write <destPath>/.<name>.<rand>.part  →  fsync  →  rename to <name>
   │        (de-duplicate by content hash; resolve collisions as "name (2).ext")
   │
   ├─4. FileBrowser Quantum's file watcher indexes the new file
   │
   └─5. Broker → shell:  progress events → success + {"openUrl": "<filebrowser deep link>"}
```

### 9.2 Flow F2 — Files → SOGo attachment

```
User clicks "Attach from files" in the Mail compose window
   ├─1. Shell → broker:  GET /api/broker/files/list?path=       → file picker contents
   ├─2. User selects a file; shell → broker:  POST /api/broker/mail/attachments/attach
   ├─3. Broker → filesystem:  open the file inside the FileBrowser source (streamed)
   ├─4. Broker → Postfix:  SMTP submission with the file as a MIME part
   └─5. Broker → shell:  the attachment appears in the compose window with its real name and size
```

### 9.3 Flow F3 — Zulip file → Files

```
User clicks "Save to files" on a Zulip message attachment
   ├─1. Shell → broker:  POST /api/broker/chat/files/save {uri, destPath}
   ├─2. Broker → Zulip:  GET https://chat.example.com<uri>  with Authorization: Basic <bot email:api key>
   │        (permissive CORS and no rate limit on authorised user_uploads GETs)
   ├─3. Broker → filesystem:  atomic write, content-hash de-duplication
   └─4. Broker → shell:  success + "Open folder"
```

### 9.4 Flow F4 — Files → Zulip message

```
User clicks "Send from files" in the Zulip compose box
   ├─1. Shell → broker:  GET /api/broker/files/list?path=       → file picker contents
   ├─2. User selects a file; shell → broker:  POST /api/broker/chat/files/send
   ├─3. Broker → filesystem:  open the file, read its size
   │      size <  25 MiB → POST /api/v1/user_uploads   (multipart)
   │      size >= 25 MiB → POST /api/v1/tus            (resumable; the only route with no body cap)
   ├─4. Broker returns {"uri": …}; the shell inserts the Markdown link into the message
   └─5. User sends the message normally
```

### 9.5 Broker integration rules

| Ref | Rule |
| --- | --- |
| IN-9.1 | Every broker route is authenticated by the Workcenter OIDC session and authorised per user. |
| IN-9.2 | Transfers stream with backpressure; memory use does not scale with file size. |
| IN-9.3 | Writes into the FileBrowser source are temp-file-then-rename, in the destination directory. |
| IN-9.4 | Every transfer is recorded: actor, direction, source, destination, bytes, result, timestamp. |
| IN-9.5 | Credentials are stored encrypted at rest, keyed by a secret held only in `.env`. |
| IN-9.6 | The broker's file source mount and FileBrowser's source mount resolve to the **same host directory**, asserted at startup. |
| IN-9.7 | Mailcow and Zulip mounts are read-only for the broker; all writes to those systems go through their own APIs. |
| IN-9.8 | Rate limits are respected: Zulip uploads are capped at 200/min/user. |

---

## 10. Health model

Workcenter gates startup on its dependencies and reports their health through the status indicators inside the application switcher.

| Application | Healthcheck | Notes |
| --- | --- | --- |
| Workcenter | `node services/healthcheck.js` → own `/healthz` | Baked into the image |
| FileBrowser Quantum | Image `HEALTHCHECK`: `curl -f http://localhost:80/health` → `{"message":"ok"}` | Works unmodified; override if the port or `baseURL` changes |
| ONLYOFFICE | `curl -f http://localhost/healthcheck` | Added in the compose file |
| Zulip `zulip` | Image `HEALTHCHECK`: `curl -isfL --insecure http://localhost/health` | 10 s interval, 300 s start period |
| Zulip `database`, `memcached`, `rabbitmq`, `redis` | **None upstream** | Workcenter's override adds them |
| Mailcow `nginx-mailcow`, `sogo-mailcow`, `mysql-mailcow`, `redis-mailcow` | **None upstream** | Workcenter's override adds them |
| Mailcow (aggregate) | Mailcow API with `API_KEY` + `API_ALLOW_FROM`, or `docker compose ps` | The exact API status route is not verified against the pinned version; `docker compose ps` is the fallback |
| Authentik | `/-/health/live/`, `/-/health/ready/`; worker `ak healthcheck` | Added in the compose file |
| Traefik | `/ping` on the `traefik` entrypoint | Image has no built-in check |

| Ref | Rule |
| --- | --- |
| IN-10.1 | Every service has an explicit `healthcheck`. "No healthcheck upstream" means "Workcenter adds one", not "skip it". |
| IN-10.2 | Workcenter declares `depends_on` with `condition: service_healthy` for FileBrowser, OnlyOffice, Zulip and Authentik. |
| IN-10.3 | Mailcow is brought up by its own tooling before Workcenter; the broker's health probe, not a compose dependency, is what asserts Mail readiness. |
| IN-10.4 | The application switcher status indicators reflect these checks. A failing check produces a `degraded` or `unhealthy` indicator, never a blank pane. |

---

## 11. Network and volume map

### 11.1 Networks

| Network | Type | Members |
| --- | --- | --- |
| `proxy` | external bridge | Traefik, Workcenter, FileBrowser, OnlyOffice, Zulip, Authentik server, Mailcow nginx |
| `internal` | bridge | Workcenter, FileBrowser, OnlyOffice, Zulip services, Authentik |
| `mailcow-network` | Mailcow's own bridge | All Mailcow services |

### 11.2 Volumes (all bind mounts inside the repository root)

```
Workcenter/
├── Filebrowser/data          → /home/filebrowser/data
├── Filebrowser/office-cache  → OnlyOffice working cache
├── OnlyOffice/{data,logs,lib,db}
├── Zulip/{data,database,rabbitmq,redis}
├── Mailcow/data              → Mailcow's runtime tree (web, conf, assets, hooks)
├── Authentik/data/{postgres,media,certs,templates}
├── Traefik/{acme.json,certs,logs}
└── user-data/                → /app/user-data (config + broker token store)
```

> **Rule IN-11.1:** any new persisted path is a bind mount of the form
> `./<AppFolder>/<subpath>:<container path>`. Anonymous volumes are not used for anything Workcenter
> must back up.

---

## 12. Integration verification matrix

Each row is asserted by the Playwright suite (see [`Testing.md`](./Testing.md)) or by a documented
manual check.

| # | Integration | Assertion | Automated |
| --- | --- | --- | --- |
| 1 | Workcenter ↔ Authentik | Sign-in completes; the id_token contains `groups` | ✅ |
| 2 | FileBrowser ↔ Authentik | Files pane loads without a second login | ✅ |
| 3 | FileBrowser source | A new OIDC user sees a populated file tree (`defaultEnabled`) | ✅ |
| 4 | FileBrowser ↔ OnlyOffice | A `.docx` opens in the editor | ✅ |
| 5 | FileBrowser → broker | The broker can list and read the user's source | ✅ |
| 6 | Zulip ↔ Authentik | Chat pane loads without a second login | ✅ |
| 7 | Zulip framing | The Chat pane renders application content, not an error page | ✅ |
| 8 | Zulip long-poll | Events arrive within the polling window (no buffering) | ✅ |
| 9 | Zulip upload | A small file uploads and returns a `uri` | ✅ |
| 10 | Zulip large upload | A >25 MiB file uploads via `/api/v1/tus` | ✅ |
| 11 | Zulip download | An attachment downloads to the file source (**F3**) | ✅ |
| 12 | Mailcow ↔ Authentik | The Mailcow UI accepts an Authentik login | ✅ |
| 13 | SOGo session | After the Mailcow session exists, the SOGo pane loads | ✅ |
| 14 | Mail IMAP | The broker lists attachments for a seeded message | ✅ |
| 15 | Mail → Files | An attachment lands in the source (**F1**) | ✅ |
| 16 | Files → Mail | A source file attaches to a draft (**F2**) | ✅ |
| 17 | Files → Zulip | A source file is sent into a message (**F4**) | ✅ |
| 18 | Traefik dashboard | Admin reaches it; non-admin is denied | ✅ |
| 19 | Traefik ↔ Mailcow | No redirect loop (`HTTP_REDIRECT=n`) | ✅ |
| 20 | Status indicators | All three indicators beneath the switcher buttons report healthy | ✅ |
| 21 | Mailcow LDAP (optional) | An LDAP bind succeeds for an end-user password | ⚠️ manual |
| 22 | Internal TLS (optional) | Services communicate over TLS with the internal CA | ⚠️ manual |

---

<p align="center"><sub>Workcenter integration specification · FileBrowser Quantum · ONLYOFFICE · Zulip · Mailcow/SOGo · Authentik · Traefik</sub></p>
