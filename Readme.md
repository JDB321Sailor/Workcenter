# Workcenter

**Files, chat and mail in one page — with files that move between them.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Derived from Dashy](https://img.shields.io/badge/derived%20from-Dashy-8616ee.svg)](https://github.com/lissy93/dashy)
[![FileBrowser Quantum](https://img.shields.io/badge/FileBrowser%20Quantum-2.0.6--beta-4cb6e0.svg)](https://github.com/gtsteffaniak/filebrowser)
[![Zulip](https://img.shields.io/badge/Zulip-docker--zulip-52c2e2.svg)](https://github.com/zulip/docker-zulip)
[![Mailcow](https://img.shields.io/badge/Mailcow%20%2B%20SOGo-dockerized-e8462c.svg)](https://github.com/mailcow/mailcow-dockerized)
[![ONLYOFFICE](https://img.shields.io/badge/ONLYOFFICE-Docs-ff6f3d.svg)](https://github.com/ONLYOFFICE/DocumentServer)
[![Authentik](https://img.shields.io/badge/Auth-Authentik%20OIDC-fd4b2d.svg)](https://goauthentik.io/)
[![Traefik](https://img.shields.io/badge/Proxy-Traefik%20v3-24a1c1.svg)](https://traefik.io/)

Workcenter is a **self-hosted workspace** that puts three applications side by side in a single
browser tab, behind a single sign-in:

| | Application | What it gives you |
| --- | --- | --- |
| 🗂 | **[FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser)** | Your files, with search and **[ONLYOFFICE](https://github.com/ONLYOFFICE/DocumentServer)** document editing built in |
| 💬 | **[Zulip](https://github.com/zulip/docker-zulip)** | Organised team chat, running as the full docker-zulip stack |
| ✉ | **SOGo on [Mailcow](https://github.com/mailcow/mailcow-dockerized)** | Mail, calendars and contacts, deployed alongside the whole Mailcow stack |

and then adds the thing none of them can do alone: **you can move a file from one to another without
leaving the page.**

* Save a **mail attachment** straight into your files.
* Attach a **file from your files** to a mail you are writing.
* Save a **Zulip attachment** into your files.
* Send a **file from your files** into a Zulip message.

Authentication is **[Authentik](https://goauthentik.io/)** for every application — one login, one
group model. Ingress is **[Traefik](https://traefik.io/)** — one TLS certificate story, one place to
route. Deployment is **one script**: `./setup.sh`.

> **Build status:** Phase 1 complete. The Workcenter derivation is finished: Workcenter renders a
> single view — the sidebar plus the embedded content surface — with deep-linkable pane routes.
> The application switcher, the status indicators, the OIDC sign-in flow and the
> cross-application file broker are in the roadmap's later phases. The table below marks what
> is shipped and what is planned.
>
> **Workcenter is a derivative of [Dashy](https://github.com/https://github.com/lissy93/dashy).** Dashy's *Workspace*
> view — a persistent left sidebar with applications launched inside the page — is the seed from which
> Workcenter grew. Dashy's *Default* and *Minimal* views are intentionally not part of Workcenter.
> See [`roadmap.md`](./roadmap.md) for exactly what was kept and what was discarded by Workcenter.

---

## Table of contents

- [Why Workcenter exists](#why-workcenter-exists)
- [Features](#features)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [The integrated applications](#the-integrated-applications)
- [Documentation](#documentation)
- [Development](#development)
- [Testing](#testing)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [Licence and credits](#licence-and-credits)

---

## Why Workcenter exists

Running a self-hosted stack usually means five browser tabs, five logins, and a desktop round-trip
every time a file needs to get from one service to another. Downloading an invoice from webmail and
then uploading it to your file server is three context switches for one file.

Workcenter's answer is to treat those three applications as **one workspace**:

1. **One tab.** A single page with an application switcher above the sidebar and the active
   application below it.
2. **One login.** Authentik issues the session; every application accepts it; two groups
   (`workspaceusers`, `workspaceadmin`) define who gets in and who administers.
3. **One filesystem.** All three applications are bind-mounted under the Workcenter root, so moving a
   file between them is a local operation — not a download and re-upload.
4. **One deployment.** `setup.sh` and `docker compose up -d` build the whole thing, including the
   reverse proxy, the identity provider, the office suite and the mail server.

---

## Features

### The workspace shell

**Shipped**

| Feature | Detail |
| --- | --- |
| **Single view** | One page. No Default dashboard, no Minimal start page, no config-download page. |
| **Deep-linkable panes** | `/` for the workspace, and `/files`, `/chat` and `/mail` for the three applications. |
| **Persistent content surface** | Applications are embedded once and kept mounted, so switching preserves scroll position and session state. |
| **Sidebar navigation** | Sections and items come from `user-data/conf.yml`; sections that set `hideFromWorkspace` are omitted. |
| **Theming** | The full theme set inherited from Dashy, plus custom colours and an external stylesheet. |
| **Multi-language** | 33 locales; English is the master. `yarn validate-locales` enforces key parity. |
| **OIDC client** | The Workcenter-derived Authentik-compatible OIDC client, with silent renewal and group-based admin. |
| **Healthcheck** | `/healthz` reports status, uptime and version for the container healthcheck. |

**Planned**

| Feature | Detail |
| --- | --- |
| **Application switcher** | Three buttons — Files, Chat, Mail — above the sidebar, each with its own accent colour. Keyboard shortcuts `Alt+1/2/3`. |
| **Swapping sidebar** | The sidebar body follows the active application: FileBrowser sources, folders and links; Zulip channels, topics and DMs; SOGo mail folders, calendars and address books. |
| **Pane state preservation** | Switching applications keeps each pane mounted, so drafts, scroll position and sessions survive. |
| **Status indicators** | Per-application health from the Docker healthchecks, shown beneath each application button in the switcher, under a `STATUS` label. |
| **Diagnostic panes** | An application that will not load shows what failed and offers Retry — never a blank frame. |
| **Theme bridge** | The shell's light/dark choice is pushed into each embedded application where it supports one. |

### Cross-application file movement

| Flow | From → To | Where the action lives |
| --- | --- | --- |
| **F1** | SOGo mail → Files | **Save to files** next to the attachment |
| **F2** | Files → SOGo mail | **Attach from files** in the compose window |
| **F3** | Zulip → Files | **Save to files** on the message attachment |
| **F4** | Files → Zulip | **Send from files** in the Zulip compose box |

Every transfer streams, shows progress, can be cancelled, de-duplicates by content hash, writes
atomically (no partial files ever appear) and is recorded in an audit log.

### Deployment

| Feature | Detail |
| --- | --- |
| **One bootstrap script** | `./setup.sh` creates the application folders, downloads and prepares each application, detects or deploys Traefik, asks for your base URL, derives six hostnames, collects the OIDC values and brings the stack up. |
| **One compose entry point** | A root `compose.yaml` that references each application's own compose file. |
| **Mailcow stays Mailcow** | Mailcow runs from its own unmodified `docker-compose.yml` with a Workcenter `docker-compose.override.yml`, so `update.sh` keeps working. |
| **Traefik everywhere** | Every service carries Traefik v3 labels; TLS is issued and renewed automatically; the dashboard is admin-only behind Authentik. |
| **Health-gated startup** | Workcenter depends on Zulip, FileBrowser and Mailcow reporting healthy. |
| **Optional internal TLS** | TLS between backend services can be enabled, with a Workcenter-generated internal CA. |
| **Bind-mounted state** | Every volume lives inside its application's folder in the repository root. |

### Authentication

| Feature | Detail |
| --- | --- |
| **Authentik for everything** | Workcenter, FileBrowser Quantum, Zulip and Mailcow each get their own Authentik OIDC provider and application. |
| **SOGo via the Mailcow UI** | SOGo has no native OIDC, so Mailcow's built-in **Generic-OIDC** identity provider is the authenticated front door; Mailcow's LDAP provider covers IMAP/SMTP credentials. |
| **Two groups, everywhere** | `workspaceusers` for access, `workspaceadmin` for administration — identical semantics across all four surfaces. |
| **Single logout** | Signing out of Workcenter ends the Authentik session and propagates to the applications that support it. |

---

## How it works

```
                            ┌────────────────────────────┐
   Browser ──── HTTPS ─────▶│          Traefik           │
   (one tab)                │  TLS · routing · ACME      │
                            └──────────────┬─────────────┘
                                           │
        ┌──────────────┬───────────────────┼───────────────────┬──────────────┐
        ▼              ▼                   ▼                   ▼              ▼
  ┌───────────┐  ┌───────────┐      ┌─────────────┐     ┌───────────┐  ┌───────────┐
  │Workcenter │  │FileBrowser│      │   Zulip     │     │ Mailcow   │  │ Authentik │
  │  shell    │  │  Quantum  │      │ (5 services)│     │  + SOGo   │  │   OIDC    │
  │  + broker │  │+OnlyOffice│      └─────────────┘     └───────────┘  └───────────┘
  └─────┬─────┘  └───────────┘
        │
        │  the broker moves bytes by path, and by API where the store is remote
        └───────────────▶ shared host filesystem under the Workcenter root
```

The shell renders three persistent iframes. Because third-party applications cannot script each
other, a same-origin **broker** inside the Workcenter container performs the transfers: it holds the
per-user credentials, resolves the FileBrowser source path, talks IMAP to Dovecot and the REST API to
Zulip, and writes files atomically into the shared tree.

Full detail: [`architecture.md`](./architecture.md) and [`integration.md`](./integration.md).

---

## Requirements

### Host

| Resource | Minimum | Recommended |
| --- | --- | --- |
| CPU | 4 vCPU | 8 vCPU |
| RAM | 8 GB | 16 GB |
| Disk | 100 GB | 250 GB SSD |
| OS | Any Linux with Docker Engine 24+ and Compose v2.20+ | Debian/Ubuntu LTS |
| Network | A public domain with six DNS records, ports 80 and 443 reachable | — |

> **Note:** Zulip alone wants ~2 GB of RAM, OnlyOffice ~2 GB, and Mailcow runs a dozen containers.
> This is a real stack, not a single container.

### Software

| Tool | Version |
| --- | --- |
| Docker Engine | 24+ |
| Docker Compose | v2.20+ (needs `include:`) |
| Git | any recent |
| OpenSSL | any recent |
| Node.js + Yarn | 24.x and Yarn 1.22 — **only if you are developing Workcenter itself** |

### DNS

Point these at your host before running `setup.sh`:

| Record | Purpose |
| --- | --- |
| `example.com` | Workcenter |
| `filebrowser.example.com` | FileBrowser Quantum |
| `auth.example.com` | Authentik |
| `mail.example.com` | Mailcow login and SOGo |
| `chat.example.com` | Zulip |
| `traefik.example.com` | Traefik dashboard (admin only) |

Mail additionally needs correct `MX`, `SPF`, `DKIM` and `DMARC` records; see the
[Mailcow DNS guide](https://docs.mailcow.email/getstarted/prerequisite-dns/).

---

## Quick start

```bash
# 1. Clone
git clone https://github.com/<your-org>/workcenter.git
cd workcenter

# 2. Bootstrap: folders, application files, Traefik, hostnames, OIDC, then bring the stack up
chmod +x setup.sh
./setup.sh

# 3. Watch the stack come up
docker compose ps
```

`setup.sh` will:

1. Create `Filebrowser/`, `Zulip/`, `Mailcow/` (and `OnlyOffice/`, `Authentik/`, `Traefik/` as needed).
2. Download and prepare each application — Mailcow through its own `generate_config.sh`, the others
   by fetching their files and generating configuration and secrets.
3. Detect whether Traefik is already running; if not, add it to the stack.
4. Ask for your base URL and derive the six hostnames above.
5. Configure everything it can, then walk you through the **one** step that needs you: creating the
   OIDC applications and providers in Authentik.
6. Bring the stack up with `docker compose up -d` and report each service's health.

If Authentik is not configured yet, the script stops with:

```
Create required OIDC application and provider per OIDC.md in authentik.
Once complete rerun setup.sh to input the .env variables as necessary for Workcenter.
```

Follow [`OIDC.md`](./OIDC.md), then rerun `./setup.sh`.

### Then

* Open `https://example.com` — you will be redirected to Authentik, and land in the workspace.
* Add yourself to `workspaceadmin` in Authentik if you need administrative access.
* Create your first mailbox in the Mailcow UI before expecting mail to flow.

---

## Configuration

Workcenter is configured by **`.env`** (deployment) and **`user-data/conf.yml`** (application).

```yaml
# user-data/conf.yml — the shape, not a complete example
pageInfo:
  title: Workcenter
  description: Files, chat and mail in one place

appConfig:
  baseDomain: example.com
  defaultTheme: dark
  enableMultiTasking: true          # panes stay mounted — the Workcenter default
  auth:
    enableOidc: true
    oidc:
      clientId: workcenter
      endpoint: https://auth.example.com/application/o/workcenter/
      adminGroup: workspaceadmin
      scope: openid profile email groups
  applications:
    files: { url: https://filebrowser.example.com, accent: blue }
    chat:  { url: https://chat.example.com,       accent: violet }
    mail:  { url: https://mail.example.com/SOGo,  accent: teal }

broker:
  enabled: true
  transfer:
    maxSizeMiB: 512
    timeoutSeconds: 300
    deduplicate: true
```

Every setting, with types and defaults, is documented in
[`architecture.md` §6](./architecture.md#6-configuration-model) and `docs/configuring.md`.

### Environment variables

Deployment settings live in `.env` at the repository root, with every key documented in
the deployment guide in [`production.md`](./production.md). Per-application settings live in that application's own
`.env`/`.env.example`. **Nothing is hard-coded**, and no secret is ever committed.

---

## The integrated applications

| Application | Version policy | Deployed by | Folder |
| --- | --- | --- | --- |
| **[FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser)** | Pinned to **`2.0.6-beta`** | Workcenter `compose.yaml` | `Filebrowser/` |
| **[ONLYOFFICE Docs](https://github.com/ONLYOFFICE/DocumentServer)** | Pinned tag | Workcenter `compose.yaml` | `OnlyOffice/` |
| **[Zulip](https://github.com/zulip/docker-zulip)** | `ghcr.io/zulip/zulip-server:<version>-0` | `Zulip/compose.yaml` | `Zulip/` |
| **[Mailcow Dockerized](https://github.com/mailcow/mailcow-dockerized)** | Upstream `master`, updated by `update.sh` | Mailcow's own compose + Workcenter override | `Mailcow/` |
| **SOGo** | Ships inside Mailcow | Mailcow | `Mailcow/` |
| **[Authentik](https://github.com/goauthentik/authentik)** | Pinned tag | `Authentik/compose.yaml` | `Authentik/` |
| **[Traefik](https://github.com/traefik/traefik)** | v3 | `Traefik/compose.yaml` | `Traefik/` |

**Original FileBrowser is deprecated** — Workcenter uses **FileBrowser Quantum** only, and its
configuration follows the Quantum **v2** schema.

Full wiring for each: [`integration.md`](./integration.md).

---

## Documentation

### The specification set

| Document | Contents |
| --- | --- |
| [`roadmap.md`](./roadmap.md) | Goals, integration requirements, UI requirements, the phased build plan |
| [`architecture.md`](./architecture.md) | Folder structure, file breakdown, layout, configuration model |
| [`design.md`](./design.md) | Every UI element, state, token and interaction |
| [`integration.md`](./integration.md) | What each integrated application is, and exactly how it is wired in |
| [`OIDC.md`](./OIDC.md) | How OIDC works here, the Authentik setup walkthrough, and the `setup.sh` prompt contract |
| [`Testing.md`](./Testing.md) | Test strategy, the Playwright harness, and the gates every merge passes |
| [`production.md`](./production.md) | Production deployment, the `setup.sh` contract, volumes, upgrades, backups |
| [`standards.md`](./standards.md) | Coding, naming, documentation and security standards |
| [`contributions.md`](./contributions.md) | Branching, the PR guide, review process, promotion to `Stable` |
| [`Agents.md`](./Agents.md) | Requirements for AI coding agents working in this repository |
| [`CHANGELOG.md`](./CHANGELOG.md) | The running log of changes |

### Long-form guides

Start at [`docs/readme.md`](./docs/readme.md) for the full index, including
[deployment](./docs/deployment.md), [configuration](./docs/configuring.md),
[management](./docs/management.md), [security](./docs/security.md),
[theming](./docs/theming.md) and [troubleshooting](./docs/troubleshooting.md).

---

## Development

```bash
# Work on the shell only — no stack required
git checkout Dev
yarn install --frozen-lockfile
yarn dev                       # http://localhost:8080

# Checks
yarn check-all                 # lint + typecheck + unit tests + locales + config
yarn test:coverage
yarn test:e2e                  # needs the test stack
```

| Command | What it does |
| --- | --- |
| `yarn dev` | Vite dev server with hot reloading |
| `yarn build` | Production bundle into `dist/` |
| `yarn start` | Run the Express server (requires a prior build) |
| `yarn lint` / `yarn lint:fix` | ESLint over `src/`, `services/`, `tests/`, `e2e/` |
| `yarn typecheck` | `vue-tsc --noEmit` |
| `yarn test` / `yarn test:coverage` | Vitest |
| `yarn validate-locales` | Fails if an i18n key is missing from `en.json` |
| `yarn validate-config` | Validates `user-data/conf.yml` against the schema |
| `yarn health-check` | Probes the server's `/healthz` |

**Branches:** every pull request targets `Dev`, which is where the application lives.
`Dev` is promoted into `Beta` when production testing is ready, and `Beta` is promoted into
`Stable` when beta testing completes. `Stable` is the GitHub default branch and holds the
documentation — switch to `Dev` before you start work.

See [`contributions.md`](./contributions.md) for the full workflow and
[`standards.md`](./standards.md) for the conventions.

---

## Testing

Workcenter is verified at three levels:

| Level | Tool | Scope |
| --- | --- | --- |
| **Unit and component** | Vitest (`happy-dom`) | Store, config, broker adapters, components |
| **Server and broker** | Vitest + `supertest` | Express routes, OIDC verification, authorisation |
| **End-to-end** | **Playwright** | The whole stack brought up with deterministic defaults: sign-in, application switching, sidebar swap, deep links, and all **four** file-movement flows |

The E2E suite runs on every pull request into `Dev`, so a breaking integration is caught before it
reaches `Beta`. Full detail, including how to run the stack locally and how failures are reported, is
in [`Testing.md`](./Testing.md).

---

## Deployment

| Task | Command / document |
| --- | --- |
| First deployment | `./setup.sh` |
| Start / stop | `docker compose up -d` / `docker compose down` |
| Health | `docker compose ps` |
| Logs | `docker compose logs -f <service>` |
| Update Workcenter | `git pull` then `docker compose up -d --build` |
| Update Mailcow | `cd Mailcow && ./update.sh` — **never** by hand |
| Update an image pin | Edit the tag in `.env`, then `docker compose up -d` |
| Back up | [`production.md`](./production.md) |
| Restore | [`production.md`](./production.md) |
| Enable internal TLS | Set `ENABLE_INTERNAL_TLS=true`, rerun `./setup.sh` |

Everything operational is in [`production.md`](./production.md).

---

## Troubleshooting

| Symptom | First thing to check |
| --- | --- |
| Redirect loop at sign-in | The Authentik issuer URL must exactly match the public HTTPS URL; check `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` and `X-Forwarded-Proto` |
| `invalid redirect URI` | The exact URL is not registered on the provider — register both the bare URL and the trailing-slash variant |
| A pane shows "refused to connect" | The application is sending `X-Frame-Options: DENY` or a restrictive `frame-ancestors`; see [`docs/troubleshooting.md`](./docs/troubleshooting.md) |
| A pane shows a login page inside the shell | The application's session expired; use **Sign in again**, or **Open in new tab** |
| Mail attachments will not save | Check the broker's file-source mount resolves to the same host directory as FileBrowser's source |
| Zulip will not load or stops updating | Check Traefik's long-poll route: response buffering must be **off** and the read/idle timeout must exceed 60 s (Zulip's own nginx uses `proxy_read_timeout 1200;`). Zulip has no websockets, so `Upgrade` handling is not the issue. Also check `CSRF_TRUSTED_ORIGINS` |
| A service is unhealthy after an update | `docker compose logs <service>`; Mailcow must only ever be updated with `./update.sh` |

Full runbook: [`docs/troubleshooting.md`](./docs/troubleshooting.md) and
[`OIDC.md`](./OIDC.md#troubleshooting).

---

## Security

* No secret is ever committed; every secret is generated and gitignored.
* TLS terminates at Traefik for every public hostname; no service is published directly.
* OIDC uses the authorization code flow with PKCE, and only **signed** tokens are accepted.
* Containers run as non-root where the image permits.
* The Mailcow UI, Authentik admin UI and Traefik dashboard are administrative surfaces and are
  restricted to `workspaceadmin`.

To report a vulnerability, please do **not** open a public issue — see
[`SECURITY.md`](./.github/SECURITY.md).

---

## Roadmap

The build plan, milestones and definition of done live in [`roadmap.md`](./roadmap.md). In short:
the shell, the deployment, unified OIDC and the four file-movement flows are 1.0; everything else is
deliberately out of scope.

---

## Contributing

Contributions are welcome — bug fixes, regression tests, documentation and new integration
capabilities.

1. Read [`contributions.md`](./contributions.md) and [`standards.md`](./standards.md).
2. Branch from `Dev`, and open your pull request **against `Dev`**.
3. Add a [`CHANGELOG.md`](./CHANGELOG.md) entry in the same PR.
4. Make sure `yarn check-all` passes.

If you are an AI coding agent, read [`Agents.md`](./Agents.md) first — it contains binding rules.

---

## Licence and credits

Workcenter is released under the **MIT Licence**, matching [Workcenter](https://github.com/JDB321Sailor/Workcenter),
from which it is derived.

Workcenter is possible because of these projects:

| Project | Licence | Role |
| --- | --- | --- |
| [**Workcenter**](https://github.com/JDB321Sailor/Workcenter) by Alicia Sykes | MIT | The Workspace view, theming, authentication and documentation conventions this project is built on |
| [**FileBrowser Quantum**](https://github.com/gtsteffaniak/filebrowser) | Apache-2.0 | The file manager, and the standard for version control and contribution process |
| [**Zulip**](https://github.com/zulip/zulip) | Apache-2.0 | Team chat |
| [**Mailcow Dockerized**](https://github.com/mailcow/mailcow-dockerized) | GPL-3.0 | Mail server stack |
| [**SOGo**](https://github.com/Alinto/sogo) | LGPL-2.1 | Webmail, calendar and contacts |
| [**ONLYOFFICE Docs**](https://github.com/ONLYOFFICE/DocumentServer) | AGPL-3.0 | Document editing |
| [**Authentik**](https://github.com/goauthentik/authentik) | MIT / GPL-3.0 | Identity provider |
| [**Traefik**](https://github.com/traefik/traefik) | MIT | Reverse proxy |

Workcenter integrates these projects; it does not vendor or modify them. Their licences apply to
their own code, and upstream documentation remains the authority for upstream behaviour.

---

<p align="center"><sub>Workcenter — files, chat and mail, in one page · built on <a href="https://github.com/JDB321Sailor/Workcenter">Workcenter</a></sub></p>
