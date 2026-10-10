# Changelog

All notable changes to **Workcenter** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
the entry taxonomy and release cadence follow the
[FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser) changelog, and
this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
as described in [`contributions.md`](./contributions.md).

> **This file is the running log of changes.**
> Every merged pull request that changes behaviour, configuration, documentation,
> dependencies or deployment **must** add an entry here in the same PR.
> A PR that changes behaviour without a changelog entry is incomplete and will not
> be merged into `Dev`.

## How to write an entry

1. Add your entry to the **`## [Unreleased]`** section at the top of this file while
   your PR is open. Never create a new version heading yourself — release managers
   cut version headings during branch promotion (`Dev` → `Beta` → `Stable`).
2. Put the entry under the correct category, creating the category if it does not
   exist yet. Categories are used in this order:

   | Category | Use it for |
   | --- | --- |
   | `Security` | Vulnerabilities, CVE fixes, hardening, auth/OIDC changes, secret handling |
   | `New Features` | User-visible capability that did not exist before |
   | `Improvements` | Changes to existing behaviour that are not bug fixes |
   | `Notes` | Behaviour changes, deprecations, upgrade warnings, breaking changes |
   | `Bugfixes` | Defect fixes with a reproducible before/after |
   | `Documentation` | Documentation-only changes to `*.md` files |
   | `Deployment` | `compose.yaml`, `setup.sh`, Traefik labels, image pins, volume layout |
   | `Dependencies` | Upstream version bumps (Workcenter, FileBrowser Quantum, Zulip, Mailcow, OnlyOffice, Authentik) |

3. Write one bullet per change, in the imperative or descriptive past tense, and
   reference the issue or PR number at the end of the line: `(#123)`.
4. If the change affects an operator (a new `.env` key, a new volume, a changed
   port, a required Authentik setting), put it under `Notes` **and** add a
   migration note to [`production.md`](./production.md).
5. Never edit a released section. Released history is immutable; corrections are
   made in a new patch release.

### Example entry

```markdown
## [Unreleased]

### New Features
 - The Workcenter shell. The rail now carries an application switcher with one status indicator
   beneath each button and a `STATUS` label, the sidebar body follows the active application, and
   all three panes stay mounted behind it.
 - `src/utils/apps/registry.js` is the single source of truth for the three applications: id,
   name, icon, accent token, configuration key, health key, route and sidebar surface. Adding or
   renaming an application is a one-file change.
 - `src/utils/apps/urls.js` resolves each pane's address from `appConfig.applications`, so an
   operator can move an application without touching code, and builds the deep link for a sidebar
   row.
 - `src/utils/health/HealthService.js` polls `/api/broker/health` and exposes a state per
   application. A failed poll reports `unknown` rather than `unhealthy`, because a check that did
   not run is not a check that failed.
 - The three sidebar surfaces: `FilesSidebar`, `ChatSidebar` and `MailSidebar`, sharing one row
   primitive and one presentation, so they cannot drift apart.
 - `PaneErrorCard` replaces a blank frame: unavailable, blocked, expired session and timeout each
   say what happened and offer Retry, with Open in new tab always available.
 - Configuration: `appConfig.applications` carries one address per application, validated by the
   schema. `appConfig.sections` is accepted but ignored, so an existing configuration still
   validates.

### Improvements
 - The switcher is a proper `tablist`, each pane is its `tabpanel`, and the indicators sit in a
   labelled group that announces changes politely. The active application is signalled by an
   accent underline, an accent icon and label, `aria-selected` and the roving `tabindex`, never by
   colour alone.
 - Panes load when first shown rather than all at once, and a frame that never fires load is
   reported after thirty seconds instead of spinning.

### Removals
 - `src/components/Workspace/` — the sidebar that rendered the `sections` list, and the
   URL-keyed iframe host it fed. The registry replaces both.
 - `src/components/LinkItems/ItemIcon.vue`, the last consumer of which was that sidebar.
 - Workcenter stripped down to the Workspace view. Workcenter now renders a single view: the
   sidebar plus the embedded content surface. The Default view, the Minimal view and the
   config-download view are deleted, along with the widget engine, the status and ping
   monitoring subsystem, the tile grid and the in-app configuration editor.
 - The multi-tasking host is now the only content host, renamed from
   `MultiTaskingWebComtent.vue` to `PaneHost.vue`, and its duplicate component name is
   corrected.
 - The router has one view and four routes: `/`, `/files`, `/chat` and `/mail`, so each
   application pane is deep-linkable. Unknown paths render the view rather than a second page.
 - The product is branded Workcenter throughout: package identity, document title, root
   element, locales, Docker labels and image metadata, and every user-visible string.

### Improvements
 - Branch model made explicit and enforced. Every pull request targets `Dev`; `Dev` is
   promoted into `Beta` when production testing is ready, and `Beta` is promoted into
   `Stable` when beta testing completes. A `Pull-request base branch` job in `ci.yml`
   fails any pull request whose base is not `Dev`, unless its title starts with
   `chore(release): promote`.
 - `PageStrcture/` is renamed to `PageStructure/`, correcting an inherited typo.
 - Prefixing is settled: Workcenter's own CSS classes, element ids and toast containers use
   the `workcenter-` prefix.
 - SPA fallback: a GET for any non-asset path now renders the shell with **200** instead of
   404. A request that looks like a missing static asset still reports 404, and non-GET
   methods still fall through to 404.
 - `user-data/conf.yml` is rewritten as the Workcenter example: one section per integrated
   application, plus the admin surfaces, with an Authentik OIDC block.

### Notes
 - Workcenter has not published a release, a Docker image or a GHCR package. Documentation
   that referred to one, or to the upstream project's image, now says so explicitly.
 - The client environment prefix is `WORKCENTER_`. The inherited `DASHY_` prefix was removed:
   nothing consumed it, and keeping it would document a prefix this project does not read.

### Removals
 - Views: `Home.vue`, `Minimal.vue`, `DownloadConfig.vue`.
 - Component trees: `MinimalView/`, `Widgets/` (96 components), `InteractiveEditor/`,
   `Charts/`, the tile-grid `LinkItems/` components, and the settings tree
   (`ViewSwitcher`, `OptionsPanel`, `SettingsContainer`, `SearchBar`, `LayoutSelector`,
   `ItemSizeSelector`, `NavLinksSwitcher`, `LocalConfigWarning`, `CustomThemeMaker`,
   `ConfigLauncher`, `ThemeSelector`).
 - The dead admin config-editor chain in `Configuration/` and the mixins it used
   (`ConfigSaving`, `ItemMixin`, `ThemingMixin`, `MasonryItem`, `WidgetMixin`,
   `ChartingMixin`, `GlancesMixin`, `NextcloudMixin`).
 - `utils/CloudBackup.js` and the hosted sync endpoint it called, `utils/CheckPageVisibility.js`,
   `utils/CheckItemVisibility.js`, and the dead stylesheets (`schema-editor.scss`,
   `weather-icons.scss`, `styles/widgets/`, the `workcenter-docs` theme).
 - Server: the `/status-check`, `/ping-check` and `/status-ping` endpoints, and the
   update checker that compared against another product's release feed.
 - Configuration schema: `startingView`, `enableMultiTasking`, `widgetsAlwaysUseProxy`,
   `colCount`, `layout`, every `statusCheck*` and `pingCheck*` option,
   `section.widgets`, `section.filteredItems`, `displayData.hideFromHomepage`,
   and the legacy Keycloak-only visibility rules.
 - Hosting artefacts: `CNAME`, `netlify.toml`, `render.yaml`, `Dockerfile-postgresql`.
 - Documentation for removed features, and the provider guides for identity providers
   Workcenter does not use.
 - Locales: the namespaces whose only consumers were removed features, and every key that
   no remaining code references.
 - Dependencies: `pingman` and its Docker `iputils-ping`/`setcap` steps.
 - Download a SOGo attachment straight into the user's FileBrowser Quantum source (#142).
 - Upload a FileBrowser Quantum file into a Zulip message without leaving Workcenter (#151).

### Notes
 - `WORKCENTER_ZULIP_API_KEY` is now required in `.env`; see `OIDC.md` for the
   provisioning steps (#151).
```

---

## [Unreleased]
### New Features
 - **The Zulip organization is provisioned with the deployment.** A Zulip server has no organization
   until one is created, and with none every page on the Chat host answers 404 "There is no Zulip
   organization at <host>" — the Chat pane rendered a Zulip error page and the broker's chat
   integration had no realm to talk to, however healthy everything else was. The pinned image creates
   none of its own, so the deployment does: `setup.sh` asks whether to create one and what to call it
   and records the answer as `ZULIP_ORGANIZATION_NAME` (`Zulip/.env`), then creates it after health
   with `manage.py create_realm` inside the container — owner: the deployment's administrator,
   password disabled (Zulip's production path generates none, and none is written, printed or
   stored), and an existing organization left alone so a re-run is idempotent. `scripts/e2e.sh` runs
   the same step for a test run, so the pane is testable out of the box, and an empty
   `ZULIP_ORGANIZATION_NAME` means "deploy none" deliberately (`integration.md` IN-5.30,
   `production.md` P-36, `Testing.md` §6.5).
 - **Phase 3: the deployment skeleton.** The repository now deploys what it specifies. The root
   `compose.yaml` is the single entry point: it builds the Workcenter image, includes the Traefik,
   Filebrowser, ONLYOFFICE and Zulip compositions, and joins them on the shared `proxy` network, with
   `depends_on: condition: service_healthy` so the shell starts only once the applications it embeds are
   up (roadmap 3.2, 3.8). Mailcow deliberately stays out of it: it ships its own compose file and is
   driven from its own folder with no `-f`, so Docker merges Workcenter's override (integration.md
   IN-6.3). Every application is reachable **only** through Traefik — nothing but the proxy publishes a
   port — and the Workcenter container mounts the shared FileBrowser source read-write plus the Mailcow
   and Zulip trees read-only, which is the contract the broker's by-path flows depend on
   (architecture.md §7.2, AR-35/AR-36).
 - **The Traefik, Filebrowser, ONLYOFFICE, Zulip and Mailcow deployment folders** (roadmap 3.1, 3.3–3.7):
   per-application `.env.example` files, the FileBrowser v2 `config.yaml` with its office integration, the
   Zulip composition with the ingress framing settings the Chat pane needs, and Mailcow's override with Traefik labels,
   `expose` instead of published ports, trusted proxies and the four healthchecks upstream does not ship.
   Every pin and every key is traceable to `integration.md`; nothing was invented.
 - **`compose.test.yaml`**, the local profile: Traefik binds to `127.0.0.1` only and serves the generated
   local certificate instead of using ACME, because a test host has no DNS name for Let's Encrypt to
   validate. That is what makes an unauthenticated stack safe to run before identity exists (Phase 5).
 - The Workcenter shell (roadmap Phase 2). The rail now carries a brand header, the three-button
   application switcher with one status indicator beneath each button and a centred `STATUS` label, a
   filter row, the active application's own navigator and the user menu, in that order
   (`roadmap.md` U-1 … U-3, U-6, `design.md` D-1 … D-4, D-6).
 - The shell renders the real brand mark of each application from `icons/` through the `@icons` alias,
   unrecoloured, with a build-time failure if a mark is missing (`design.md` D-2I, `architecture.md`
   AR-46, `roadmap.md` U-19).
 - `Alt+1/2/3` switches applications from anywhere in the shell, the switcher is a proper tablist
   with `aria-current`, `aria-selected` and roving arrow-key focus, and re-activating the active
   application returns focus to its pane (`design.md` D-2, D-2.2, D-A2, `roadmap.md` U-12, U-16).
 - The three sidebar navigators: FileBrowser Quantum's routes (browse and its five tools), Zulip's
   views (`#inbox`, `#recent`, `#feed`, `#narrow/is/mentioned`, `#narrow/is/starred`, `#drafts`) and
   SOGo's own folder tree (`/SOGo/so/<mailbox>/<Module>/view#!/…`), each read from the pinned
   upstream router; groups collapse and remember their state, and rows are real links
   (`design.md` D-4, D-4.1 … D-4.3, D-4.2).
 - The sidebar filter: type-to-filter over the active application's rows, `Esc` to clear,
   `Ctrl/Cmd+K` to focus, and a stated empty result rather than a blank body (`design.md` D-3).
 - Panes are created when first activated and kept mounted afterwards, so switching preserves
   scroll position, drafts and sessions; each pane has an overflow menu with Reload, Open in new tab,
   Copy link and — for an administrator — health detail (`design.md` D-7, `roadmap.md` U-4).
 - Diagnostics instead of a blank frame: a pane reports `unavailable`, `blocked`, `auth-error` or
   `timeout`, names the failing check, and offers **Retry** and **Open in new tab**
   (`design.md` D-7.1, `roadmap.md` U-15).
 - The user menu: identity from the session, the `Admin` badge for `workspaceadmin`, both preference
   controls, the administrative links and **Sign out** last, which ends the Workcenter session and
   performs RP-initiated logout at Authentik (`design.md` D-6, D-6.3, `roadmap.md` U-7, A-7).
 - The appearance control: a two-option light/dark segmented control with **dark as the default**,
   labelled as such until the user chooses otherwise, applied to the shell instantly
   (`design.md` D-6.1, `roadmap.md` U-17).
 - The language control: the language in use written in its own language, a flag button, a filterable
   listbox, and `document.documentElement.lang` kept in step (`design.md` D-6.2, `roadmap.md` U-18).
 - The theme bridge, shell half: `data-wc-mode`, the `wc_mode` cookie on the shared domain, a
   `workcenter:mode` message posted to each pane at its **exact** origin, and a **Files** pane
   refresh only after the broker confirms a persisted change, at the path FileBrowser last reported
   (`design.md` §4.4, D-T5 … D-T8, `roadmap.md` U-11, U-20).
 - The language bridge: the locale registry now carries each language's endonym, English name, flag
   and the identifier FileBrowser Quantum and Zulip use for it, and forwards the choice in one
   broker call (`design.md` §8.2, D-I6 … D-I11, `roadmap.md` U-23).
 - `GET /api/broker/health`: a same-origin health feed for the switcher's status indicators that
   probes each configured application for reachability and for a framing refusal, and reports
   `unknown` rather than guessing (`design.md` D-2S, `architecture.md` AR-15, AR-37).
 - `POST /api/broker/preferences`: the same-origin route that fans a preference out to the
   applications on behalf of the calling user only, in parallel, with a per-application result so a
   partial failure can be named rather than hidden (`architecture.md` AR-47, AR-48).
 - `scripts/e2e.sh`: builds the shell, serves it, deploys whatever the phase can deploy, and prints
   the manual checklist for the current phase gate (`Testing.md`).

### Improvements
 - **`scripts/e2e.sh` now tests the real deployment.** It validates its dependencies (docker, the compose
   v2 plugin at 2.20+ because the stack uses `include:`, and a reachable daemon, each failure naming what
   to install), generates `.env` and the local certificate when they are absent, **pulls only the images
   that are not already present**, builds the Workcenter image with the build log captured and the last 25
   lines printed on failure, deploys the stack with `up -d --wait`, polls every service to `healthy`, and
   then checks what a machine can check: the shell and broker through Traefik, each application on its own
   hostname, the framing policy of each pane, and the shared source directory compared by device and inode
   inside the Workcenter and Filebrowser containers. `--shell-only` keeps the Phase 2 path for a quick look
   at the UI without Docker, `--dry-run` prints the plan, and `--hosts` maps the six hostnames to
   `127.0.0.1` for a browser (removing the block again on teardown).
 - **Teardown leaves nothing but the images.** `--down` stops the compose project and Mailcow, stops any
   shell server of this checkout, removes the marked `/etc/hosts` block, and deletes exactly what the run
   created — recorded in a manifest as it is created, plus the applications' runtime directories — then
   *verifies* that no container, network, volume or generated file remains. It runs even when the Docker
   daemon is unavailable, because that is one of the reasons a stack needs clearing.
 - **Every run is logged** under `user-data/e2e/logs/<run>/`: the stage narrative, every command issued,
   the build output, and one file per stage, so a failure is read where it happened rather than guessed at.
 - **Two rail-layout corrections.** The user row's right-hand group is now spaced by one property
   used twice — the gap between the mode toggle and the language button, and the inset from the
   language button to the rail edge — with the gap reduced by the sun/moon glyph's centring slack, so
   the two visible distances are identical and the two-letter code has room; the code is also
   `flex: 0 0 auto` with `white-space: nowrap`, so the name column ellipsizes before the code can be
   squeezed or clipped. And the expanded user panel now opens **upward inside the rail column**,
   directly above the initials button, at the rail's width less its inset, instead of appearing to the
   right of the rail; the collapsed panel keeps its previous behaviour, opening beside the 3.5rem rail
   at full width, because that column cannot hold it (`design.md` D-6, D-6.5, D-6.6).
 - **The user menu is now a user row, and the role moved to the brand header.** The rail footer
   shows the signed-in user's initials on a button, their name stacked first-over-last, and two icon
   buttons on its right: a **sun/moon mode toggle** and a **language button** carrying a rounded flag
   and the ISO 639-1 code. The panel behind the initials holds identity, the admin links and Logout,
   and no longer holds the appearance and language controls — those are one click away in the row
   instead of two. The `Admin` badge left the menu entirely: the brand header now reads
   `Workcenter - User` or `Workcenter - Admin` from the same session profile, in a smaller face that
   truncates before it can push the collapse toggle aside, and disappears with the wordmark when the
   rail is collapsed. Collapsing the rail leaves the initials button alone while its panel stays full
   size beside the rail; because that is then the only control left in the row, the collapsed panel
   carries the mode and language buttons, so the language menu is never unreachable. Long names are
   cut at 14 characters a line in the component rather than by CSS, so a name cannot reflow the row
   (`design.md` D-1.1, D-6, D-6.1, D-6.2, D-6.3, D-6.5; `roadmap.md` U-7, U-17, U-18).
 - **The language flags and theme glyphs are committed, not fetched.** 29 square flags from
   [flag-icons](https://github.com/lipis/flag-icons) (MIT) at `icons/flags/<ISO 3166-1>.svg`, cropped
   to a circle in CSS, plus a sun and a moon from Font Awesome Free 6.7.2 (CC BY 4.0) at `icons/ui/`.
   They are reached through the `@icons` alias, so a missing file fails the build and neither the
   language menu nor the mode button depends on a CDN or on the icon font being reachable. Galician
   and the joke locale have no country of their own and keep the registry's glyph rather than wearing
   someone else's flag (`docs/credits.md`, `design.md` D-6.2). Committed icons are now emitted as
   files rather than inlined as data URIs (`vite.config.mjs`), which keeps 28 KB of base64 out of the
   bundle every page load downloads and lets the browser cache each flag once.
 - The layout token contract now matches the design specification: the rail is `16rem` expanded and
   `3.5rem` collapsed, `--header-height` is `0` because the rail's brand header replaces the
   inherited page header, and the switcher, indicator, search, user-menu and transition tokens all
   exist (`design.md` §2.2, D-L1, `architecture.md` AR-13).
 - The shell's colour tokens are now FileBrowser Quantum's own light and dark values, with separate
   "ink" variants for text and icons so the light mode still meets WCAG AA; the accent tokens
   themselves stay FileBrowser's, as the appearance standard requires
   (`design.md` §4.1, §4.3.1, D-T3, D-T4, D-A1).
 - The status indicators reflect real state: the health service is reactive, carries the check, the
   failing endpoint and the time of the last check, backs off exponentially while everything is
   healthy, never polls faster than every 15 s, and reports a failed poll as `unknown`
   (`design.md` D-2S, `standards.md` S-P-5).
 - A healthy indicator focuses its pane and no longer changes which application is active; a
   non-healthy indicator opens that application so its diagnostic card is what the user sees
   (`design.md` D-2S).
 - The rail's collapsed state is read before the first render, so a user who collapsed the rail never
   sees it flash open (`design.md` D-1).
 - **The test run has a known Files admin login, and the harness prints it.** FileBrowser Quantum
   creates its built-in `admin` account on first start, but its password came from nowhere in this
   deployment: `FILEBROWSER_ADMIN_PASSWORD` — the only admin setting the application reads from the
   environment — was not passed through `Filebrowser/compose.yaml`, so every run silently used the
   pinned version's own default. The variable is now wired through, `scripts/e2e.sh` sets it to
   `admin` for a test run (five characters, exactly the application's `minLength`), asserts the login
   it produces, and prints the credentials in a **Test accounts** block. The same block now carries a
   usable Zulip administrator as well: docker-zulip exposes no environment variable that creates an
   account, so `scripts/e2e.sh` creates one with Zulip's own management commands inside the container.
   Zulip authenticates by email and refuses anything shorter than eight characters, so the login is
   `admin@<shell host>` with the password `admin1234` (IN-3.26, IN-5.31, `Testing.md` §6.5).

### Removals
 - **The derived Zulip image.** Zulip now runs the pinned upstream image unmodified. `Zulip/Dockerfile`,
   `Zulip/custom_zulip_files/`, `Zulip/compose.override.yaml` and `Zulip/.dockerignore` are gone, along
   with the `workcenter-zulip:<version>-0` tag, the `ZULIP_UPSTREAM_IMAGE` variable, the
   `WORKCENTER_ORIGIN` build argument and the harness's build, overlay-verification and retagging
   stages. The Chat pane is framed by the ingress instead (see `Notes`), so there is no second image to
   build, pin, retag, cache or rebuild on an upgrade — and no deviation from upstream to track.

### Notes
 - **Framing is an ingress concern, and that is now the documented mechanism.** Zulip ships
   `X-Frame-Options: DENY` at server scope, exposes no Django setting or middleware to change it, and
   its own CSP never carries `frame-ancestors`. A browser that sees a `frame-ancestors` directive
   **ignores `X-Frame-Options`** (CSP Level 2 and later), so the allow-list is written where it can name
   an origin: the `zulip` router's `traefik.http.routers.zulip.middlewares: "security-headers@file"`
   label (`Zulip/compose.yaml`) and that middleware's `frame-ancestors <shell origin>` value
   (`Traefik/dynamic/middlewares.yml`). `integration.md` §5.4 and §8.4 now specify both settings for a
   manual deployment (**IN-5.27**), `production.md` **P-35** makes `setup.sh` responsible for writing the
   origin from the base URL, and **IN-1** no longer sanctions patching an application at all.
   **Upgrading an existing host:** it keeps a now-unused `workcenter-zulip:<version>-0` image (about
   4 GB) — `docker image rm workcenter-zulip:12.3-0` reclaims it, and `./scripts/e2e.sh --clean` removes
   it with the rest.
 - **The release Workcenter is built against is recorded where it is deployed.** **Zulip 12.3**,
   `ghcr.io/zulip/zulip-server:12.3-0`, upstream commit `b3198225…`, stated in `Zulip/.env.example`,
   `.env.example`, `Zulip/compose.yaml`, `Readme.md` and `integration.md`. A later release is adopted
   deliberately — tested against this deployment — by moving the tag:
   `./scripts/e2e.sh --bump-zulip-pin --zulip-version X.Y --zulip-commit <sha>` for the committed files,
   or automatically in the generated `.env` files on the next run unless `--pin` was given.
 - The FileBrowser Quantum pin moves to the newest 2.x beta, **`2.0.9-beta`**
   (`sha256:66969254ed56c62e83d729168fe50e965ada030602d6fc2cec1a0b83a0357040`). The beta line has no
   `latest` tag: `latest` on both registries resolves to the 1.x line, so the pin stays explicit in
   `.env`. The Files sidebar and the preference adapter were re-verified against this tag
   (`integration.md` IN-3.1).
 - **The Mail pane cannot be framed until Mailcow's nginx override lands.** Mailcow's nginx template
   sends `X-Frame-Options: SAMEORIGIN` at server scope
   (`data/conf/nginx/templates/sites-default.conf.j2`), which blocks every other origin — including
   Workcenter's. Roadmap Phase 3 must add a `/SOGo` location in `Mailcow/data/conf/nginx/*.custom`
   that replaces that header with a CSP `frame-ancestors` allow-list naming the Workcenter origin.
   Until then the Mail pane reports its `blocked` state rather than showing a blank frame
   (`integration.md` IN-6.31, `roadmap.md` R14).
 - A pane's appearance is only changed where the application allows it: FileBrowser Quantum and Zulip
   accept the change over their APIs, SOGo is driven by the shell's stylesheet and the
   `workcenter:mode` message, and the Mailcow UI is left to the user. The per-user credentials the
   broker needs for the first two arrive with the file-movement phase, so until then the user menu
   reports that the panes could not be reached (`design.md` §4.4, `architecture.md` AR-47).
 - The appearance mode and the language are remembered per browser (a `localStorage` mirror plus the
   `wc_mode` / `wc_lang` cookies) and are **not** yet stored in a server-side profile; that store
   arrives with the broker's per-user data (roadmap Phase 6, `design.md` D-6.1).
 - `setup.sh` gains `--brand`, which re-applies the branding on its own. Run it after
   `Mailcow/update.sh`: Mailcow tracks everything under `data/conf/sogo/` and merges with
   `-X theirs`, so an upgrade can revert the Mail pane's styling
   ([`production.md` §10.2](./production.md#102-mailcow)).
 - Mailcow's light and dark logos are uploaded by hand in **Configuration → Customize**. They are
   stored in Redis by a form POST and Mailcow exposes no API for it, so `setup.sh` prints the step
   instead of reporting a success it did not achieve.
 - The realm-wide Zulip appearance pass needs a **human** administrator account. Zulip's settings
   endpoint rejects bot API keys, so the file-broker bot cannot perform it.
 - Workcenter is a **derivative of Dashy**: the Default and Minimal views are intentionally
   discarded; only the Workspace view is carried forward.
 - The REST API's section and item routes are removed. `POST`, `GET`, `PATCH` and `DELETE` under
   `/api/config/:filename/sections/…` no longer exist, and neither does the `:sid` / `:iid`
   addressing that selected a section by index or `name` and an item by index or `title`. The API
   now reads and replaces whole files and single top-level keys only: `GET`/`PUT`
   `/api/config/:filename` and `GET`/`PUT` `/api/config/:filename/:key`. A client that used to
   change one section or item must read the file, change it, and `PUT` the whole object back.
   `services/endpoints/api/openapi.yml` describes the reduced surface (#4).
 - `pages` is no longer an addressable config key. Workcenter has no sub-pages, and
   `ConfigSchema.json` rejects the key in `conf.yml` (`additionalProperties: false`), so the API's
   key list and `docs/api.md` now name `pageInfo`, `appConfig` and `sections` only. A sub-page
   *file* is unaffected: it is still read and replaced whole through `/api/config/:filename` (#4).

---

### Bugfixes
 - **`scripts/e2e.sh --down` could leave a Workcenter server running.** The script stopped only the
   pid it had recorded, so a server started by hand, or by a run whose pid file had since been
   removed, stayed live on its port while `--down` reported that everything had stopped — the pid file
   was also deleted even when nothing had been stopped, losing the record of a live process. `--down`
   now stops the recorded processes **and** sweeps the process table for `node server.js` running from
   this checkout, records one pid file per port so two runs cannot overwrite each other, verifies the
   port afterwards, and names whatever still holds it. It never signals a process that is not a
   Workcenter server of this checkout, treats an unreaped (zombie) process as stopped, keeps the pid
   record when a stop fails so the next `--down` can retry, and `--clean` refuses to delete its records
   while a server survives. A start now also stops a leftover server from an earlier run instead of
   silently reusing it, and two defects found while testing — a `pipefail`/SIGPIPE combination in the
   ownership check that made a live server look foreign, and a pid directory deleted by the stop that
   the following start then failed to write into — are fixed with it (`Testing.md` §6.5).
 - **The language code beside the flag was clipped by the rail.** `box-sizing: border-box` is declared
   on `html` in the inherited global stylesheet, and `box-sizing` **does not inherit** — so every box
   inside the rail defaulted to `content-box`. Anything with `width: 100%` and horizontal padding was
   therefore as wide as its container *plus its padding*: the user row measured 280px inside a 256px
   rail, the rail scrolled 24px wide, and its `overflow: hidden` cut that 24px off the right-hand edge,
   which is exactly where the two-letter code sits. The rail subtree now resets to `border-box`
   (`src/styles/workcenter/_rail.scss`), scoped so the panes, toasts and modals at body level keep the
   box model the inherited stylesheets expect. Measured in a real browser: the row is 256px in a 256px
   rail, the rail no longer overflows, and both buttons moved 24px left, leaving the code 18px clear of
   the edge — equal to the gap between the sun/moon and the flag (`design.md` D-6.6).
 - **Every icon in the shell's own chrome was blank.** Sidebar rows, the pane's overflow menu and the
   preference controls render `fas fa-*` glyphs, but the inherited icon check only loaded the library
   when a *tile section* used one — and a workspace-only application has no tile sections, so the kit
   was never requested. The shell now asks for it unless a deployment sets
   `enableFontAwesome: false` (`design.md` D-2I.9), and `tests/unit/icon-library.test.js` covers both
   the request and the opt-out.
 - **The application labels were cut off.** A switcher button was a fixed `2.5rem` tall, but a 24px
   mark, the gap, a label line and the button's padding need about `3rem` — so the label was clipped
   by the button and then by the rail's `overflow: hidden`. The button is now `height: auto` with
   `--switcher-button-height` as a **minimum** (raised to `3rem`, with `--switcher-height` raised to
   `5.5rem` and applied as a minimum too), and the label has an explicit line box so descenders are
   not cut. Design tokens were as much the cause as the CSS, so `design.md` §2.2 records the new
   values.
 - **The rail's collapse control pointed the wrong way and the collapsed rail was unusable.** Three
   separate faults: the glyph was an up/down arrow (an inherited asset) rather than a left/right one;
   the switcher never stacked, so three 24px marks competed for 3.5rem of width and overlapped; and
   the collapse button was hidden (`opacity: 0; pointer-events: none`) until hovered, while the
   sidebar kept its labels in a 3.5rem rail. Because the collapsed state is remembered, a reload came
   back to the same broken rail — it looked unrecoverable. Now: the control is a committed arrow that
   points **left to collapse and right to reopen**, stays visible and clickable in both states, the
   switcher **stacks vertically** with each button taking the application name as its accessible
   name, and `src/styles/workcenter/rail.scss` turns the sidebar into an icon rail (rows keep their
   icon, centred; labels, badges and group headings are dropped; a notice stays readable). The
   collapse action is asserted to round-trip in both the unit tests and the built bundle.
 - **The shell could fail to start at all.** `src/utils/config/ConfigHelpers.js` constructed
   `ConfigAccumulator` at module scope, and the accumulator imported the store, which imports the
   helpers — a cycle whose outcome depended on which module the bundler evaluated first. In the
   failing order the class did not exist yet, the bundle threw `TypeError: … is not a constructor`
   before mounting, and the browser sat on the loading watermark until the "something's gone wrong"
   card appeared. The store now publishes itself through `src/utils/config/storeRef.js` instead of
   being imported by the accumulator, the eager (and unused) `config` export is gone, and
   `tests/unit/config-pipeline-order.test.js` fails if either half of the cycle returns.
 - The start-up banner spelled the **upstream** product name. `services/utils/print-message.js` now
   renders the name from a small block font, so the art follows a rename instead of going stale.
 - The welcome box was sized for the old, shorter name, which pushed its right-hand wall five columns
   past the corner. The box is now sized from the widest line it contains — art, text or address — so
   the walls, the art and the text always agree.
 - The status indicators never repainted: the health service wrote to a plain object outside Vue's
   reactivity, so a poll landed without a re-render. The state is reactive now, and the panes consume
   it (`design.md` D-2S).
 - All three panes loaded at start-up: `v-show` hides an `iframe` without preventing its `src` from
   being fetched. A pane's frame is now created on first activation only (`standards.md` S-P-2).
 - The Mail navigator produced `/SOGo/SOGo/…` because its row paths repeated the configured
   sub-path; rows are now relative to the application's own address, and the test that encoded the
   doubling was corrected (`design.md` D-4.3).
 - The sidebar's `navigate` event was dropped by the host, so a row could not move the pane; rows now
   navigate the pane they belong to, and only where a destination is real (`design.md` D-4.1).
 - `HealthService.apply()` discarded the `frameBlocked` and `authError` facts the broker reports, so
   a pane could not show `blocked` or `auth-error`; both are carried and consulted before a frame is
   awaited (`design.md` D-7.1).
 - A pane reported a framing refusal or an expired session only if the health state changed after
   mount; it now checks what is already known when it starts loading (`design.md` D-7.1).
 - **Zulip's `memcached` container never became healthy, and its health gate aborted every
   deployment.** Under Compose a `file:` secret is a **bind mount**: the container sees the host's
   ownership and mode, and the long syntax's `uid`/`gid`/`mode` keys are ignored outside Swarm —
   `docker compose` says so on every `up` ("secrets `uid`, `gid` and `mode` are not supported, they
   will be ignored"). The harness generated every Zulip secret `0600` owned by whoever ran it (root
   under `sudo`), but `memcached:alpine` is `USER memcache` (uid 11211) and builds its SASL database
   from `zulip__memcached_password` *before* it execs memcached, so it exited 1 with "the password
   secret at /run/secrets/zulip__memcached_password is not readable by uid 11211"; Compose then
   reported `dependency failed to start: container workcenter-memcached-1 is unhealthy`, and the run
   tore the stack down before any other service was ever judged. `scripts/e2e.sh` now hands each
   generated file to the uid that reads it inside its container — `zulip__memcached_password` to
   11211, `zuliprc` to the Workcenter image's uid 1000 — and keeps both at `0600`, so the owner is
   the consumer rather than the world. A harness that is not root cannot hand a file to another uid,
   so it leaves the file readable and says so, the same trade-off the mount-point ownership step
   already makes. `setup.sh` has the same obligation for a real deployment, which `production.md`
   §5.2 now states.
 - **The shell was unreachable through Traefik.** The `workcenter` service in `compose.yaml`
   declared the labels that route to it and name the `proxy` network
   (`traefik.docker.network=proxy`) but never joined that network, so Docker attached it to the
   project's default network only. Traefik had a router whose backend it could not resolve: every
   request to the shell's hostname hung until the client timed out — a `000`, not a 502 — while
   `docker compose ps` reported the container healthy, and Files, Chat and ONLYOFFICE, which do join
   `proxy`, answered normally. The service now joins `proxy` and `internal`, as `architecture.md`
   §7.1 (AR-28) requires.
 - **The test run left Zulip on the wrong hostname, distrusting the proxy, and unable to be
   framed.** Three settings have to follow the addresses the harness actually serves under test, and
   none of them did. (1) `SETTING_EXTERNAL_HOST` — Zulip's own address: its nginx `server_name` and
   the host its Traefik router rule matches — stayed at the `chat.example.com` its generated `.env`
   was copied from, so `chat.workcenter.local` fell through to Traefik's no-router 404. (2)
   `LOADBALANCER_IPS` listed only `127.0.0.1`, so Zulip answered HTTP 500 "Reverse proxy
   misconfiguration … this request did not come from a matching IP address — it came from
   172.19.0.3" to *every* request that arrived through Traefik, while `/health` on loopback answered
   200. (3) `WORKCENTER_ORIGIN`, which is substituted into the derived Zulip image's CSP
   `frame-ancestors` at build time, stayed `https://example.com`, so the Chat pane would have been
   blocked from framing at the shell's real origin in a browser. The harness now derives the first
   from `CHAT_HOST` (`production.md` §5.4 keeps the two equal), sets the third to the shell's base
   URL, and for the second brings Traefik up on its own first — the address it presents on `proxy`
   is assigned by Docker when the network is created, so it cannot be written into an `.env` in
   advance — reads that address, and starts the rest of the stack with it (`Zulip/.env.example`,
   `integration.md` IN-5.14).
 - **`scripts/e2e.sh` invoked `main` twice.** The script ended with two `main "$@"` calls, so a run
   that reached the end of the first pass built, deployed, waited for health and checked the whole
   stack a second time; only a failure inside the first pass, which exits, kept it hidden.
 - **`--down` did not remove what earlier runs created.** A standalone `./scripts/e2e.sh --down`
   creates nothing itself and read only the current run's manifest, so the generated `.env` files,
   the four application `.env` files and the local certificate survived a teardown that then
   reported nothing left behind — and the next run inherited them ("exists: leaving it alone")
   instead of regenerating them from the templates. It now reads every `created-*.manifest` in the
   run directory, which is the only record of what previous runs created: `--down` deletes that
   directory when it finishes.
 - **The Chat check asked Zulip for a page that cannot exist yet.** `run_checks` asserted that
   `chat.<domain>/` returns 200, but Zulip answers 404 there until an organization exists at that
   host and says so itself ("There is no Zulip organization at chat.<domain>"); creating one is
   application provisioning, which belongs with the administrator account and the realm-wide
   branding that `setup.sh` applies (`integration.md` IN-5.19, `production.md` §5.4). The check now
   asserts the portico login page (`/login/`), which Zulip serves as soon as it is up, so it still
   proves that the Chat host is routed and that Zulip answers on it.
 - **A second run could not build, because the stack's own runtime state was inside the build
   context.** `.dockerignore` excluded `node_modules`, `docs`, `tests`, `dist`, `.git` and `.github`
   but none of the bind-mount targets the stack fills at run time, and those directories belong to the
   **containers'** uids — postgres, rabbitmq, redis, ONLYOFFICE and FileBrowser all write as
   themselves. The next build therefore failed in the context sender with
   `ERROR: error from sender: open …/OnlyOffice/db: permission denied` for any user who is not root
   (`root`, and so `sudo ./scripts/e2e.sh`, can read them, which is why it stayed hidden), and even
   when it succeeded every build uploaded the whole database, cache and log tree to the builder. The
   root `.dockerignore` now excludes the Zulip, FileBrowser, ONLYOFFICE, Mailcow and Traefik runtime
   directories along with the generated secrets and harness state, and `Zulip/.dockerignore` does the
   same for the derived image's own context, which had the identical problem
   (`open …/Zulip/database: permission denied`). Neither image takes any of that as input:
   `user-data/conf.yml`, which the Workcenter image does carry, is deliberately kept.
 - **The shell reported every application unreachable in a test run, although every one of them
   answered.** The switcher's status indicators come from `GET /api/broker/health`, which probes each
   application through Traefik by the address in `conf.yml` and **verifies** the certificate it is
   given (`broker.md` §3.4, §10.2, `NODE_EXTRA_CA_CERTS`). Two things were missing on a machine with
   no DNS. (1) The local certificate the test profile serves named only `workcenter.local`,
   `localhost` and `127.0.0.1`, so a probe of `filebrowser.workcenter.local`,
   `chat.workcenter.local` or `mail.workcenter.local` failed hostname verification — and a browser
   got a hostname mismatch where the honest warning is only an untrusted issuer. (2) Docker's
   resolver knows service names, not `*.workcenter.local`, so the shell could not resolve them at
   all (`EAI_AGAIN`, reported as a timed-out check). `scripts/e2e.sh` now issues one certificate
   naming every hostname the run serves, and warns with the remedy when a certificate an operator
   put there already exists and does not cover them (it is not regenerated — an operator may have
   installed one they trust on purpose); `compose.test.yaml` attaches the test hostnames to Traefik
   as network aliases, so a lookup lands on the ingress and is routed by the `Host` header exactly as
   public DNS would. The same run also had to move the **framing allow-list**: Traefik *sets*
   `Content-Security-Policy` from `Traefik/dynamic/middlewares.yml` and overwrites whatever a backend
   sends, and that file names
   `https://example.com`, which `setup.sh` rewrites per deployment (`production.md` §5.4). The shell
   is served from `https://workcenter.local` in a test run, so every pane was blocked from being
   framed and the broker reported each application as `refusing to be framed`; the harness writes the
   same copy with this run's origin and `compose.test.yaml` mounts it over the original, exactly as it
   does for `conf.yml`.
 - **The switcher reported every pane as refusing to be framed, so the Files and Chat panes could not
   be opened.** `GET /api/broker/health` reads each application's response headers and sets
   `frameBlocked` when the application refuses to be framed; `AppPane` turns that flag into the
   `blocked` card instead of loading the frame. The check accepted only `frame-ancestors *` — the one
   value `production.md` P-23 and `integration.md` IN-8.5 **forbid** — so the mandated configuration,
   an allow-list naming the shell's origin, was itself reported as a refusal. `parseFraming` now takes
   the shell's own origin and accepts a directive that names it: `*` still passes, an unrelated
   origin and `'self'` still block (the latter is the *application's* origin, a different host here),
   and with no origin available the check keeps its previous, conservative answer. The broker reads
   that origin from `WORKCENTER_BASE_URL`, which `compose.yaml` declares for exactly this purpose and
   which nothing read until now. It also now reads `frame-ancestors` **before** `X-Frame-Options`, so a
   response carrying both is judged by the directive a browser actually honours — which is what lets
   the pane be framed by a Zulip that still sends `X-Frame-Options: DENY`, exactly as
   `integration.md` §5.4 specifies. `scripts/e2e.sh`'s framing check was reordered the same way, so it
   no longer reports the specified deployment as a pane that "cannot be embedded".
 - **The harness built and re-tagged a Zulip image it no longer needs.** `scripts/e2e.sh`'s "derived
   Zulip image" stage is replaced by a "Zulip release" stage: it reports the pinned tag, asks GitHub
   whether a newer release exists, and moves the pin in the generated `.env` files when one does
   (unless `--pin`) — it builds nothing, and it runs before the image step so a moved pin is what gets
   pulled. `--bump-zulip-pin` no longer rewrites a Dockerfile's build argument or a derived tag, and
   the overlay verification and tag-reconciliation steps are gone with the build.

 - **Every status indicator was grey, whatever the applications were doing.** `GET
   /api/broker/health` was answering correctly, but `HealthService.check()` read the payload from
   `res.apps` while `request.get` resolves to the axios-style envelope `{ data, status, statusText,
   headers }`. Nothing was read, `apply()` was handed the envelope, and every application stayed in
   the `unknown` state it starts in — a grey dot, tooltip "never checked", for an application that was
   healthy and answering. The payload is now read from `res.data` (a bare payload is still accepted),
   and the unit test that covered this mocks the real envelope shape instead of the unwrapped one that
   hid the bug.
 - **The Files and Chat panes were blank in Firefox — and the local certificate was the reason twice
   over.** Both defects were in the certificate the test profile serves, and either one alone was
   enough to leave a person with a warning page and two empty panes.
   - **It was a CA certificate used as a server certificate.** `openssl req -x509` writes
     `Basic Constraints: critical CA:TRUE` into the certificate it produces, and that certificate was
     then served as the TLS certificate. OpenSSL, curl, Chrome and NSS's own `certutil -V` all accept
     that, so every check the harness made passed. **Firefox verifies with mozillapkix, which refuses
     it** — `MOZILLA_PKIX_ERROR_CA_CERT_USED_AS_END_ENTITY` — and refuses the connection outright: no
     trust store can make it load, which is why installing the certificate into the profile's
     `cert9.db` with trust `C,,`, into the system store, and into Chromium's NSS database all changed
     nothing. The harness now generates **a local certificate authority and a leaf it signs**
     (`Traefik/certs/local-ca.{crt,key}` and `local.{crt,key}`): the authority is long-lived and is the
     only thing a trust store receives, and the leaf carries `CA:FALSE`, `keyUsage` and
     `extendedKeyUsage=serverAuth` with every hostname in its SAN. The broker's `NODE_EXTRA_CA_CERTS`
     points at the authority, the manual recipe in `Traefik/dynamic/tls.yml` was corrected too, and the
     harness now **asserts the shape of what Traefik serves** and that it chains to the local
     authority — the check that would have caught this on the day it was written, since it fails on a
     `CA:TRUE` server certificate regardless of how trusted it is.
   - **The browser certificate stores were never written.** Installing the authority into the system
     store is not enough for Firefox, which keeps its own database per profile and does not read the
     system store by default: on a machine where `trust list` showed the authority, the consolidated
     bundle contained it and `curl` verified every hostname, the profile's own database listed none of
     it. The harness now writes **every NSS database belonging to the invoking user** with `certutil` —
     Firefox profiles under `~/.config/mozilla/firefox/` (Firefox 129 and later, which is where
     Firefox 157 keeps them) and `~/.mozilla/firefox/` (older), the Snap and Flatpak trees, and
     Chromium's shared `~/.pki/nssdb` — as that user, taken from `SUDO_USER` when running under `sudo`
     because `$HOME` is then root's. The system store is still written, and is **detected, never
     assumed**: `/usr/local/share/ca-certificates` with `update-ca-certificates` on Debian and Ubuntu,
     `/etc/ca-certificates/trust-source/anchors` with `update-ca-trust` on Arch (CachyOS, Manjaro,
     EndeavourOS), `/etc/pki/ca-trust/source/anchors` on Fedora and RHEL, `/etc/pki/trust/anchors` on
     openSUSE, or p11-kit's `trust anchor --store` when none of those exists — never creating a store
     that is not there, which is how the first version of this step could have reported success while
     writing a file nothing reads. A running browser is named, because it does not re-read the database
     until it restarts, and `security.enterprise_roots.enabled` is documented as the alternative.
     **`--trust-cert`** does the certificate half on its own and exits, touching no container. `--down`
     removes what was installed, from every store it might be in (`Testing.md` §6.5, `production.md`
     P-36).
 - **`--down` aborted halfway through its own teardown.** Removing the certificate from the system
   store needs root and fails for a certificate that is not there, and removing a nickname that a
   profile does not have makes `certutil` exit non-zero; both ran unguarded under `set -e`, so an
   ordinary unprivileged `--down` stopped mid-teardown with a trust-store error instead of finishing.
   The removal is now failure-tolerant and reports what it actually removed.
 - **The credential-state guard treated an empty mount directory as state holding credentials.** It
   judged `Zulip/database`, `Zulip/rabbitmq` and `Zulip/redis` by existence, so a run that created the
   mount points and then failed — or whose contents an operator cleared — made every later run refuse
   to start with "that state still holds the previous credentials" when there was nothing in it. An
   empty directory has no password to disagree with, so the guard now requires content.
 - **The embedded FileBrowser Quantum and Zulip panes rendered blank.** The pane is positioned
   absolutely with `height: calc(100% - var(--header-height))` against `PaneHost`, and a percentage
   height needs a **definite** containing block — but the shell's workspace was `min-height: 100vh`,
   so its height stayed `auto`, the pane host's `height: 100%` resolved to zero, and every frame
   loaded into a zero-height box. The panes were not blocked or unreachable (the browser ran
   FileBrowser's and Zulip's own scripts), which is why no error card appeared and the health
   indicators stayed green: the content region was simply empty. The workspace now declares a
   definite `height: 100vh`, and the pane keeps subtracting `--header-height` itself, so that token
   is still honoured (design.md D-L1, D-7). The frame is also `display: block` now: as an inline
   replaced element it carried the line box's descender space below itself, which overflowed the
   pane by a few pixels once it had a real height. Measured in a browser: the pane host and frame
   fill the viewport, both applications render inside the shell, and the shell has no scrollbar; a
   regression guard in `tests/components/workspace.test.js` asserts both declarations.
 - **`--down` printed `basename: unrecognized option '--import'`.** `our_server_pids` sweeps the
   process table for this checkout's `node server.js` and read each process's arguments with
   `basename`, which GNU coreutils treats as an option when the value begins with `-`. A Node process
   launched as `node --import …` therefore made the search itself noisy on every teardown — and it was
   already a false negative for that process, because `basename` failed instead of returning the name.
   Both calls now pass `--` before the value, so an option-shaped argument is read as the path it is.
 - **A run could abort before it created the Zulip test admin.** The organization check reads `GET /`
   on the Chat host, and that request can answer 404 at a moment when the organization already exists;
   the step then ran `manage.py create_realm`, which answered "Subdomain is already in use." and ended
   the run before the admin account that follows it was made. That answer is now treated as the
   idempotent case the check was trying to detect, so the admin step always runs.
 - **`--hosts` aborted while writing the browser trust stores.** `trust_local_certificate` compares the
   stored authority's fingerprint with the one on disk, and both probes assumed the nickname was
   already there: `certutil -L -n <name>` exits non-zero with no output for a profile that does not
   hold it yet — the normal first run, and every fresh profile — so `openssl` failed on empty input,
   `pipefail` failed the assignment and the run stopped before the certificate was installed at all.
   The `certutil -D` that clears a previous entry failed the same way one line later. Both now
   tolerate the absent case, which the comparison already treats as "not stored", so a first run
   installs the certificate into every profile it finds.

### Documentation
 - `Testing.md` §6.5 rewritten for the Docker harness: the option table, the stage-by-stage behaviour, the
   ingress rule that keeps the unauthenticated phase on the loopback interface, the automated checks and
   what each one proves, the teardown contract, and the run artefacts. The phase table now records Phase 3
   as the current one and keeps `--shell-only` documented as the Phase 2 path.
 - **New: [`broker.md`](./broker.md) — the definitive document for the broker, and the completion of the
   file-movement specification.** Earlier revisions of the documentation described **four** transfer flows;
   the complete set is the **six ordered pairs** of the three applications (Mail → Files, Mail → Chat,
   Chat → Files, Chat → Mail, Files → Mail, Files → Chat), and [`broker.md`](./broker.md) §5 specifies all
   six — each with its route, the source chooser it starts from, the exact upstream mechanism, the audit
   flow name, and its own test cases. **Chat → Mail (F6) had no specification at all before this change:**
   it is now defined end to end (read the upload from Zulip with the user's own key, build the MIME message,
   `APPEND` it to Drafts, report the draft) and covered in the test matrix. `roadmap.md` (F1–F6, Phase 6, the
   milestone and U-13), `design.md` (D-8 and the design principles), `architecture.md`, `Readme.md`,
   `Testing.md`, `production.md`, `integration.md` and `contributions.md` were brought to the same six-flow
   set in this change; the documentation now presents the matrix as it was always meant to be, and this
   entry is the only place the correction is recorded.
   The same document covers identity and credentials (including why a cross-origin session cookie is *not*
   available to the broker, and the vault that replaces it), the appearance and language bridges with the
   exact upstream call per application and when a frame must be reloaded — including the OnlyOffice editor,
   whose presence cannot be detected from a URL and is therefore recorded as a limitation rather than hidden
   — the security model (threat table, SSRF and path-traversal rules, secret handling, rate limits, the
   refused designs), the test matrix and the Phase 6 exit criteria, operations, and a traceability table
   mapping every section to the `AR-*`/`IN-*`/`D-*`/`U-*` requirements it implements. It is registered in the
   documentation index and cross-referenced from `architecture.md` §4 and `Testing.md` §5.
 - Corrected three upstream facts the broker research re-verified: the pinned Mailcow ships **SOGo 5.12.11**,
   not 5.12.10 (`OIDC.md`, `roadmap.md` I-MC-7); the mail store is a **named Docker volume** owned by uid
   5000 and encrypted at rest, not a directory under `./Mailcow/data/` (`roadmap.md` I-MC-10); and the
   `X-Frame-Options` header is set at server scope, so the nested `/SOGo/so/*` location drops it
   (`integration.md` IN-6.31).
 - Fixed four documentation anchors that pointed at headings that no longer existed
   (`Agents.md` and `architecture.md` → §3.3, `Readme.md` → `OIDC.md` §12, `roadmap.md` →
   `architecture.md` §4). Every internal anchor in all 29 markdown files now resolves; the check is
   mechanical, so it can be re-run rather than eyeballed.
 - Correct the shell's element specification to match the implementation: the sidebar host selects
   the active navigator from the application registry rather than a slot (`design.md` §2.1, §10).
 - Record what a host page can and cannot tell about a pane: FileBrowser Quantum's own editor is
   visible in the reported navigation as `#edit` or `#preview`, but the OnlyOffice editor has **no**
   URL marker, so the Files pane's refresh is deferred only for the former
   (`design.md` D-T7, `integration.md` IN-3.23).
 - Record the verified deep-link grammar for each navigator: FileBrowser Quantum's routes and tool
   paths, Zulip's view fragments and channel/topic/DM forms, and SOGo's
   `/SOGo/so/<mailbox>/<Module>/view#!/…` form including the fact that no URL selects an individual
   calendar (`design.md` D-4.1 … D-4.3, `integration.md` IN-5.29).
 - Add risk **R14** and requirement **IN-6.31** for Mailcow's `X-Frame-Options: SAMEORIGIN`, which
   blocks the Mail pane in a cross-origin frame until the nginx override in roadmap Phase 3 replaces
   it with a CSP `frame-ancestors` allow-list (`roadmap.md` §15).
 - Correct the route form in the UI requirements and the test plan: panes are history-mode paths
   (`/files`, `/chat`, `/mail`), which is what the router, the server's single-page fallback and
   `Readme.md` already implement (`roadmap.md` U-12, `Testing.md`).
 - Correct the brand-string check in the agent requirements: the guard greps for the upstream name,
   not for Workcenter (`Agents.md` §4.1, §9).
 - Reconcile the standards with the code: a single root Vuex store with no modules, the npm scripts
   that actually exist, and the coverage floors that are not yet enforced
   (`standards.md` §3.3, §13).
 - Correct the documented `user-data/conf.yml` samples to the keys the schema actually accepts:
   `theme`, `language` and `applications.<app>.url`, with the appearance mode, the accent colours and
   the broker's own settings explicitly *not* part of the shell's configuration (`Readme.md`,
   `architecture.md` §6.2, AR-32). A unit test now asserts that the schema and
   `src/utils/apps/registry.js` cannot drift (`Testing.md` §4.2).
 - Move the shell's user-visible capability out of the "Planned" table in the overview, and document
   the manual verification harness (`Readme.md`, `Testing.md`).
 - Specify the user menu's appearance control: a light/dark switcher with dark as the documented
   default (`design.md` D-6.1, `roadmap.md` U-17).
 - Specify the user menu's language control: the language in use written in its own language, plus a
   flag button that opens the language menu (`design.md` D-6.2, `roadmap.md` U-18).
 - Specify the **theme bridge** — one switch in the shell changes the shell and all three embedded
   applications, through FileBrowser Quantum's per-user `darkMode`, Zulip's `color_scheme` and a
   Workcenter stylesheet supplied to SOGo (`design.md` §4.4, `roadmap.md` U-11, U-20).
 - Specify the **language bridge** for the applications that can accept one, and state plainly where
   the shell cannot drive the language rather than failing quietly (`design.md` §8.2, `roadmap.md`
   U-23).
 - Specify the `setup.sh` branding stage, which gives the embedded applications Workcenter's name,
   logo and palette so the deployment reads as one product (`production.md` §5.2a, `roadmap.md`
   U-22).
 - Add `POST /api/broker/preferences`, the same-origin route that fans a preference out to the
   applications on behalf of the calling user only (`architecture.md` AR-47, AR-48).
 - Add the application brand marks under `icons/`, and specify their use in the application switcher
   (`design.md` D-2I, `architecture.md` AR-46, `roadmap.md` U-19).
 - Repository foundation: `Dev`, `Beta` and `Stable` branches with `Stable` as the default branch
   and `Dev` as the target for every pull request.
 - Imported Dashy as the upstream baseline, at commit
   `6c56436d5f044d3c53371891c9d9a8c8df8c4606` (v4.6.14, "🔀 Merge pull request #2340 from
   lissy93/fix/status-check-ping-mem-limits", 2026-09-12). Workcenter is derived from this commit.
 - Initial documentation baseline for the Workcenter application: roadmap, architecture,
   design, agent, standards, contribution, OIDC, testing and production specifications.
 - Defined the single-pane Workcenter shell derived from the Dashy Workspace view
   (application switcher above a per-application sidebar).

 - Adopt FileBrowser Quantum's own light and dark palette as Workcenter's appearance standard, so
   the shell, the branding and the panes are derived from one source (`design.md` §4.3.1).
 - Record the per-application appearance, branding and language mechanisms against the pinned
   upstream versions (`integration.md` §3.6, §5.8, §6.9).
 - Withdraw design rule D-T2. It required that no pane ever reload on a theme change, which is not
   achievable for FileBrowser Quantum — it exposes no live channel — and the user-visible
   requirement is that the mode change reaches every application. Superseded by D-T5 and D-T6.
 - Add the tests that prove a mode switch reaches the embedded applications, asserted inside each
   pane against the application's own DOM rather than against the shell's state (`Testing.md`
   §8.3a, T-8.4 … T-8.8).
 - Remove three inherited guides that documented features Workcenter does not have: `docs/icons.md`,
   `docs/multi-language-support.md` and `docs/development-guides.md`. Inbound links now point at the
   specification that replaces each one.
 - Rebrand completed. Every file, path, identifier, asset and user-visible string that named
   the upstream project now names Workcenter. The only surviving reference is the
   acknowledgement that Workcenter was built from Dashy, which the MIT licence requires and
   which now appears in one consistent form.
 - Restore the Dashy attribution the rebrand overwrote. The rename replaced the upstream name
   inside the acknowledgements themselves, leaving `Agents.md`, `Readme.md`, `architecture.md`,
   `CHANGELOG.md`, `contributions.md`, `design.md`, `roadmap.md` and `standards.md` claiming that
   Workcenter is a derivative of Workcenter and pointing the MIT credit at this repository rather
   than at Dashy.
 - Record how the base branch of a pull request is chosen: `Stable` stays the GitHub default so it
   is what a visitor lands on, and `pr-base.yml` moves a new pull request to `Dev`
   (`contributions.md` C-3.9, §8.2).
 - `docs/credits.md` rewritten: it credits Dashy as the origin, lists the dependencies
   Workcenter actually uses, and drops the sponsor, stargazer and contributor widgets that
   pulled data from another project.
 - `docs/contributing.md` rewritten: the survey, donation, BountySource, share-button and
   sponsor sections are replaced with how to raise an issue, open a discussion and add a
   translation.
 - `docs/release-workflow.md` rewritten around the workflows this repository actually has —
   the CI jobs, the `Dev` → `Beta` → `Stable` promotion, and Dependabot against `Dev`. It no
   longer describes Docker, mirror, tag or docs-site pipelines that do not exist.
 - `docs/deployment/bare-metal.md` rewritten: building from source and the systemd unit are
   kept, and the pre-built release, checksum and attestation sections are removed because no
   release has been published.
 - `docs/deployment/docker.md` and `docs/deployment.md` rewritten. Neither presents the upstream
   project's image as Workcenter's. Both state that no image is published and show how to build
   `workcenter:dev` locally.
 - `docs/branch-protection.md` — the GitHub-side branch, ruleset and required-check
   configuration that roadmap step 0.1 requires, and `docs/readme.md` reindexed for Workcenter.
 - `roadmap.md` — goals, integration requirements, UI requirements and the phased build plan.
 - `architecture.md` — folder structure, file breakdown and repository layout inherited from Dashy.
 - `design.md` — UI element specification for the shell, switcher, sidebars and panes.
 - `Agents.md` — requirements for AI coding agents working in this repository.
 - `standards.md` — coding, formatting and documentation standards for all contributors.
 - `contributions.md` — pull-request guide, process and workflow, based on FileBrowser Quantum.
 - `Readme.md` — project overview, quick start and feature summary.
 - `OIDC.md` — Authentik OIDC provider/application setup and the `setup.sh` prompt contract.
 - `Testing.md` — unit, integration, end-to-end (Playwright), health and promotion test gates.
 - `production.md` — production deployment, `setup.sh` behaviour, volumes, TLS and upgrades.
 - `integration.md` — what each integrated application is, and exactly how it is wired in.
 - `CHANGELOG.md` — this running log of changes.
 - `tests/unit/workcenter-derivation.test.js` — fails the build if a removed view,
   subsystem, configuration key, server route or brand string is reintroduced.
 - The application switcher and the per-application status indicators are one element:
   a status indicator sits beneath each switcher button, under a `STATUS` label. There is no
   separate status strip and no `StatusStrip.vue` / `StatusPill.vue` component.
 - The `docs/` set is reorganized and condensed. `docs/authentication.md` becomes an index and the
   per-mechanism guides move under `docs/authentication/`; fourteen guides are rewritten in a
   terser style, and the Dashy-era prose that described behaviour Workcenter does not have is
   removed rather than carried: the widget and status-check catalogues, the hosted config-sync
   service, verifiable releases with signed provenance and an SBOM, Subresource Integrity, and the
   community and sponsor sections. The set loses 4,315 lines and gains 2,186 (#4).
 - `docs/api.md` rewritten around the routes that remain: enabling the API, the two credential
   paths, the five routes, the backup, schema and size rules, and worked `curl` examples (#4).
 - `production.md` §5.2 now records the ownership every generated Zulip secret needs. Compose mounts
   a `file:` secret as a bind mount and ignores the long syntax's `uid`/`gid`/`mode` outside Swarm,
   so the two secrets a non-root container reads have to be handed to that container's uid:
   `zulip__memcached_password` to the memcached image's uid 11211 and `zuliprc` to the Workcenter
   image's uid 1000. The failure it prevents is written down with it — a memcached container that
   exits with "the password secret … is not readable by uid 11211", which Compose's dependency gate
   reports as an unhealthy service.
 - `Testing.md` §6.5's stage table now describes what the harness actually does: the application
   `.env` step and what it exports, the shell-configuration step and the file it writes, the Zulip
   secret step with the ownership rule above, and a Deploy stage that brings the proxy up first in
   order to learn the address Zulip has to trust.
 - **The framing specification now documents the ingress settings a manual deployment needs.**
   `integration.md` §5.4 is rewritten around the mechanism instead of the derived image: the `zulip`
   router's `traefik.http.routers.zulip.middlewares: "security-headers@file"` label, the
   `contentSecurityPolicy: "frame-ancestors <shell origin>"` value it names, why a browser ignores
   Zulip's `X-Frame-Options: DENY` once `frame-ancestors` is present, and that both settings are
   required (IN-5.27). §8.4 states the same as a middleware contract, with IN-8.5a recording that
   Traefik *sets* rather than merges the header, so an application that must keep its own CSP needs a
   middleware of its own. `production.md` §5.3/§5.4 and the new **P-35** make `setup.sh` write the
   origin from the base URL, `Testing.md` §6.5 describes the Zulip release stage, and `roadmap.md`
   (I-ZU-9, R1), `architecture.md`, `OIDC.md`, `Readme.md`, `Agents.md`, `broker.md`, `design.md` and
   `docs/*` no longer describe a patched Zulip.
 - `integration.md` gains **IN-5.30** (the Zulip organization is provisioned, with the exact command
   and the idempotency rule), `production.md` gains **P-36** and the Stage F creation step, and
   `roadmap.md` gains **I-ZU-17**; `Zulip/.env.example` documents `ZULIP_ORGANIZATION_NAME`. `Testing.md`
   §6.5 documents the new harness stage, the framing check's precedence rule, and what `--hosts` now
   installs.

### Deployment
 - `.editorconfig` and `.gitignore` covering every secret, runtime volume and generated artefact   the integrated applications produce, including `**/.env`, `**/secrets/`, `**/data/` and `acme.json`.
 - `.github/workflows/ci.yml` — the regular-test workflow, run on every pull request: install,
   lint, typecheck, unit tests, locale check, config validation and production build.
 - `.github/workflows/promote.yml` — promotion of `Dev` → `Beta` and `Beta` → `Stable` by
   semantic version.
 - `.github/workflows/pr-base.yml` — retargets a pull request opened against `Beta` or `Stable` to
   `Dev`, so `Stable` can stay the branch a visitor lands on while every pull request still lands on
   `Dev` (`contributions.md` C-3.9). A promotion pull request is left alone.
 - `.github/ISSUE_TEMPLATE/` and `.github/pull_request_template.md`, covering the requirement-ID,
   changelog and test-evidence obligations.
 - **The test profile now gives the shell this machine's addresses.** Every pane address, and every
   address the broker probes for the switcher's status indicators, comes from
   `appConfig.applications` in `user-data/conf.yml` (`src/utils/apps/urls.js`, `broker.md` §3.4).
   That file is the operator's — committed with `example.com` defaults and rewritten in place by
   `setup.sh` (`production.md` §5.4) — so in a test run the shell embedded
   `https://filebrowser.example.com`, `https://chat.example.com` and `https://mail.example.com/SOGo`,
   which do not resolve on a test host: all three panes reported themselves unavailable and the
   status indicators showed every application unhealthy while the applications themselves answered
   normally through Traefik. `scripts/e2e.sh` now writes `user-data/conf.test.yml` (the committed
   file with the three addresses mapped to `FILEBROWSER_HOST`, `CHAT_HOST` and `MAIL_HOST`, and
   everything else carried through unchanged, gitignored and recorded in the run manifest) and
   `compose.test.yaml` mounts it over the tracked file with the long-syntax form and
   `create_host_path: false`, so the operator's file is never modified and a missing generated file
   fails loudly instead of becoming an empty directory.

## Release history

Workcenter has not yet cut its first release. Releases are created by promotion, in order:

| Version | Branch | Date | Notes |
| --- | --- | --- | --- |
| — | `Dev` | — | Integration branch; all PRs target here |
| — | `Beta` | — | Promoted from `Dev`; Playwright E2E verified |
| — | `Stable` | — | Promoted from `Beta`; default branch, production releases |
