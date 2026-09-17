# Workcenter — Architecture

> **Scope:** folder structure, file breakdown and layout requirements for the Workcenter repository.
> **Starting point:** [Dashy](https://github.com/lissy93/dashy). Workcenter keeps Dashy's folder
> conventions, build pipeline, theming layout and documentation layout, and removes everything that
> serves the Default and Minimal views.
> **Companions:** [`roadmap.md`](./roadmap.md) · [`design.md`](./design.md) · [`standards.md`](./standards.md) ·
> [`integration.md`](./integration.md) · [`production.md`](./production.md) · [`Testing.md`](./Testing.md)

---

## 1. Architectural summary

Workcenter is a **two-part application shipped from one repository**:

| Part | What it is | Where it lives | Runs as |
| --- | --- | --- | --- |
| **Shell** | Vue 3 + Vite SPA: the application switcher, the swappable sidebars, the pane surfaces, theming and the OIDC client | `src/` | Static assets served by `server.js` inside the Workcenter container |
| **Broker** | OIDC-protected HTTP API that performs cross-application file movement and reports integration health | `src/broker/` and `services/` | The same container, a second Node process managed by the entrypoint |

Derived Dashy subsystems that **remain** because the shell depends on them: the Vuex store and
config accumulator, the configuration schema, the authentication utilities, the theming styles, the
i18n locales, the Express server, and the healthcheck service.

Derived Dashy subsystems that are **removed**: the Default view, the Minimal view, the widget engine,
the status/ping monitoring engine, the tile grid, and the multi-view router.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Browser (one tab)                               │
│                                                                              │
│   ┌──────────────────────────────────────────────────────────────────────┐   │
│   │                    Workcenter shell  (Vue 3 SPA)                     │   │
│   │  ┌────────────────┐  ┌──────────────────────────────────────────┐    │   │
│   │  │ AppSwitcher    │  │  Content surface (persistent iframes)    │    │   │
│   │  │ Files│Chat│Mail│  │  ┌────────────────────────────────────┐  │    │   │
│   │  ├────────────────┤  │  │ Files  → filebrowser.example.com   │  │    │   │
│   │  │ AppSidebar     │  │  │ Chat   → chat.example.com          │  │    │   │
│   │  │ (swaps with    │  │  │ Mail   → mail.example.com/SOGo     │  │    │   │
│   │  │  active app)   │  │  └────────────────────────────────────┘  │    │   │
│   │  ├────────────────┤  │                                          │    │   │
│   │  │ (status in the │  │                                          │    │   │
│   │  │  switcher)     │  │                                          │    │   │
│   │  │ User menu      │  │                                          │    │   │
│   │  └────────────────┘  └──────────────────────────────────────────┘    │   │
│   └──────────────────────────────────────────────────────────────────────┘   │
│                    │ same-origin fetch (OIDC bearer token)                   │
└────────────────────┼─────────────────────────────────────────────────────────┘
                     ▼
        ┌────────────────────────────┐        ┌──────────────────────┐
        │  Workcenter broker API     │───────▶│  Authentik (OIDC)    │
        │  /api/broker/*             │        └──────────────────────┘
        └───────┬──────────┬─────────┘
                │          │
   ┌────────────▼──┐  ┌────▼─────────┐  ┌──────────────────────┐
   │ FileBrowser   │  │ Zulip        │  │ Mailcow / SOGo       │
   │ Quantum files │  │ REST API     │  │ IMAP(S) + SMTP       │
   │ (bind mount)  │  │ (HTTPS)      │  │ (Dovecot/Postfix)    │
   └───────────────┘  └──────────────┘  └──────────────────────┘
                └──────────┬─────────────┘
                           ▼
              shared host filesystem under the repo root
```

---

## 2. Top-level repository layout

Workcenter's repository root **is** the Workcenter application folder. Dashy's top-level entries are
preserved in name and purpose wherever they still apply; new entries are marked **NEW**.

```
Workcenter/                          # repository root == the Workcenter application folder
├── .devcontainer/                   # Dev container definition              [kept from Dashy]
├── .github/                         # CI/CD, templates, CODEOWNERS          [kept, rewritten]
│   ├── workflows/                   # lint, test, e2e, build, promote
│   ├── ISSUE_TEMPLATE/
│   └── PULL_REQUEST_TEMPLATE.md
├── docs/                            # Long-form documentation site source   [kept from Dashy]
│   ├── assets/
│   ├── authentication/
│   ├── deployment/
│   └── *.md
├── public/                          # Static assets copied verbatim to web root [kept]
├── scripts/                         # NEW: provisioning + ops helpers
│   ├── lib/                         # shared bash functions sourced by setup.sh
│   ├── bootstrap-filebrowser.sh
│   ├── bootstrap-zulip.sh
│   ├── bootstrap-mailcow.sh
│   ├── bootstrap-authentik.sh
│   ├── bootstrap-traefik.sh
│   └── healthcheck-all.sh
├── services/                        # Node services run beside the SPA      [kept + extended]
│   ├── healthcheck.js               # container healthcheck                  [kept from Dashy]
│   ├── utils/
│   │   ├── auth-oidc.js             # server-side token verification         [kept from Dashy]
│   │   ├── config-validator         # config schema validation               [kept from Dashy]
│   │   └── broker/                  # NEW: broker runtime
│   └── broker-server.js             # NEW: broker HTTP entry point
├── src/                             # the SPA                              [kept, heavily pruned]
├── tests/                           # unit + integration tests               [kept from Dashy]
│   ├── locales/
│   ├── unit/
│   ├── integration/
│   └── fixtures/
├── e2e/                             # NEW: Playwright end-to-end suite
│   ├── specs/
│   ├── fixtures/
│   ├── support/
│   └── playwright.config.ts
├── icons/                           # NEW: application marks (SVG), one per integrated app
├── user-data/                       # runtime config + user assets            [kept from Dashy]
│   ├── conf.yml                     # the Workcenter configuration file
│   └── broker/                      # NEW: broker token store (gitignored)
├── Filebrowser/                     # NEW: FileBrowser Quantum deployment
├── Zulip/                           # NEW: Zulip deployment
├── Mailcow/                         # NEW: Mailcow + SOGo deployment
├── OnlyOffice/                      # NEW: OnlyOffice DocumentServer deployment
├── Authentik/                       # NEW: Authentik deployment
├── Traefik/                         # NEW: Traefik deployment
├── compose.yaml                     # NEW: root stack composition
├── compose.test.yaml                # NEW: deterministic test profile
├── setup.sh                         # NEW: bootstrap script (see production.md)
├── .dockerignore
├── .editorconfig
├── .env.example                     # NEW: root env template
├── .gitignore
├── Dockerfile                       # Workcenter image (kept from Dashy, extended)
├── docker-compose.yml               # single-service convenience compose  [kept from Dashy]
├── eslint.config.mjs
├── index.html
├── package.json
├── README.md                        # GitHub landing page -> Readme.md content
├── Dockerfile-postgresql            # (removed: Dashy-only Postgres variant)
├── server.js                        # Express static server + API host      [kept from Dashy]
├── tsconfig.json
├── vite.config.mjs
├── vitest.config.mjs
├── yarn.lock
├── CNAME / netlify.toml / render.yaml   # (removed: Dashy hosting artifacts)
└── *.md                             # the Workcenter specification set (see §8)
```

### 2.1 Rules for the top level

| Ref | Rule |
| --- | --- |
| AR-1 | The repository root is the Workcenter application folder. Everything Workcenter *is* lives here. |
| AR-2 | Every **integrated application** gets exactly one top-level folder, named for the application (`Filebrowser/`, `Zulip/`, `Mailcow/`, `OnlyOffice/`, `Authentik/`, `Traefik/`). |
| AR-3 | Every file an integrated application owns — configuration, secrets, volumes, logs — lives **inside that application's folder**. Nothing is written outside it. |
| AR-4 | Volumes are **bind mounts** expressed as `./<AppFolder>/<subpath>:<container path>`, never anonymous volumes, for anything Workcenter must back up or inspect. |
| AR-5 | Dashy top-level names are preserved where the purpose is unchanged. Renaming a kept entry requires an entry in [`CHANGELOG.md`](./CHANGELOG.md). |
| AR-6 | No generated artifact (`.env`, `node_modules/`, `dist/`, `*.sqlite`, `acme.json`) is committed. |
| AR-7 | Documentation Markdown lives at the repository root (the specification set) or in `docs/` (the long-form guides). Nothing else may be added to the root. |
| AR-46 | `icons/` holds exactly one SVG per integrated application, named for the application, and is the **single source of truth** for every application mark in the shell. Components reach it through the `@icons` build alias, never by a relative path and never from a remote URL. See [`design.md` D-2I](./design.md#d-2i--switcher-icons). |

---

## 3. `src/` — the shell

Dashy's `src/` layout is the template. Directories that survive are kept with their names; removed
directories are listed in [§3.3](#33-removed-from-dashy).

```
src/
├── App.vue                     # root component: shell frame, router outlet, theme provider
├── main.js                     # bootstrap: store, router, i18n, directives, plugins
├── router.js                   # single-view router: /files, /chat, /mail (+ /login, /404)
├── store.js                    # Vuex root: config, apps, health, user, ui modules
├── assets/
│   ├── interface-icons/        # SVG UI icons (kept subset: switcher, status, user, theme)
│   ├── locales/                # i18n JSON, English master          [kept from Dashy]
│   └── *.svg / *.png           # product marks and pane placeholders
├── broker/                     # NEW: shell-side broker client
│   ├── client.js               # typed fetch wrapper, token attaching, error mapping
│   ├── transfers.js            # the four transfer actions, progress events
│   ├── preferences.js          # NEW: appearance/language fan-out call (see §4.3)
│   └── types.ts                # shared transfer/health types
├── components/
│   ├── AppMark.vue             # NEW: brand mark from icons/, never recoloured (D-2I)
│   ├── AppSwitcher/            # NEW: the three-button switcher with status indicators
│   │   ├── AppSwitcher.vue     # button row + indicator row + STATUS label
│   │   ├── AppSwitchButton.vue
│   │   ├── StatusIndicator.vue # one per application, directly beneath its button
│   │   └── AppSwitcher.scss
│   ├── AppSidebar/             # NEW: sidebar host + the three sidebar surfaces
│   │   ├── AppSidebar.vue      # slot host, scroll container, width/sticky behaviour
│   │   ├── FilesSidebar.vue    # FileBrowser sources / folders / links
│   │   ├── ChatSidebar.vue     # Zulip channels / topics / DMs
│   │   ├── MailSidebar.vue     # SOGo mail folders / calendars / address books
│   │   └── SidebarItem.vue     # shared row primitive (icon + label + optional badge)
│   ├── Panes/                  # NEW: the content surface
│   │   ├── PaneHost.vue        # keeps all panes mounted, toggles visibility
│   │   ├── AppPane.vue         # one iframe + loading + error + retry states
│   │   └── PaneErrorCard.vue   # diagnostic card for a failed pane
│   ├── Transfers/              # NEW: cross-application file movement UI
│   │   ├── FilePickerModal.vue # "choose a file from my files"
│   │   ├── AttachmentRow.vue   # "save to files" affordance in the mail pane
│   │   ├── TransferProgress.vue
│   │   └── TransferToasts.vue
│   ├── User/                   # NEW: user menu, identity, admin badge, logout
│   │   ├── UserMenu.vue
│   │   └── UserBadge.vue
│   └── Settings/               # theme, language, per-user preferences       [kept, pruned]
│       ├── ThemeSwitcher.vue   # light/dark segmented control (D-6.1)
│       ├── LanguageSwitcher.vue# language in use + flag button (D-6.2)
│       └── LanguageMenu.vue    # the language listbox opened by the flag button
├── directives/                 # v-tooltip and friends                      [kept from Dashy]
├── mixins/                     # shared component behaviour                  [kept, pruned]
│   ├── AppLaunchMixin.js       # opening methods: same pane, new tab
│   └── HealthMixin.js          # NEW: subscribe a component to health state
├── plugins/                    # Vue plugin registration                     [kept from Dashy]
├── styles/                     # SCSS: tokens, themes, layout               [kept from Dashy]
│   ├── color-palette.scss      # CSS custom properties, incl. --side-bar-*
│   ├── color-themes.scss
│   ├── dimensions.scss         # --side-bar-width, --header-height, --switcher-height
│   ├── global-styles.scss
│   ├── media-queries.scss
│   ├── style-helpers.scss
│   ├── typography.scss
│   ├── themes/
│   └── workcenter/             # NEW: shell-specific partials
│       ├── switcher.scss
│       ├── sidebar.scss
│       ├── panes.scss
│       └── status.scss
├── utils/
│   ├── auth/                   # OIDC client                               [kept from Dashy]
│   │   ├── Auth.js             # session, user, isAdmin, guest access
│   │   ├── OidcAuth.js         # oidc-client-ts PKCE flow, silent renew
│   │   ├── getApiAuthHeader.js # bearer token for broker calls
│   │   └── Logout.js           # RP-initiated logout                       [NEW]
│   ├── config/                 # configuration pipeline                    [kept, pruned]
│   │   ├── ConfigSchema.json   # trimmed Workcenter schema
│   │   ├── ConfigAccumalator.js
│   │   ├── ConfigHelpers.js
│   │   └── defaults.js
│   ├── health/                 # NEW: health polling + status derivation
│   │   └── HealthService.js
│   ├── apps/                   # NEW: the integrated-application registry
│   │   ├── registry.js         # id, name, icon, accent, url, sidebar, healthKey
│   │   └── urls.js             # build public URLs from the configured base URL
│   ├── logging/
│   │   ├── ErrorHandler.js     # kept from Dashy
│   │   └── CoolConsole.js
│   ├── i18n.js
│   ├── languages.js            # locale registry: endonym, flag, per-application id (D-I6)
│   ├── request.js
│   ├── Sanitizer.js            # URL sanitising for pane targets
│   ├── Theming.js              # mode state, wc_mode cookie, pane message, bridge call
│   ├── Toast.js
│   └── yaml.js
└── views/
    ├── Workspace.vue           # THE view: switcher + sidebar + pane host
    ├── Login.vue               # OIDC landing / error surface              [kept from Dashy]
    └── 404.vue                 # kept from Dashy
```

### 3.1 File-level requirements

| Ref | Requirement |
| --- | --- |
| AR-8 | `src/views/Workspace.vue` remains the single functional view and is the direct descendant of Dashy's `src/views/Workspace.vue`. Its three children are `AppSwitcher`, `AppSidebar` and `PaneHost`. `AppSwitcher` renders both the application buttons and their status indicators, plus the `STATUS` label; there is no separate status component or rail region. |
| AR-9 | `src/utils/apps/registry.js` is the **single source of truth** for the three applications. Adding or renaming an application is a one-file change plus locale strings. |
| AR-10 | Every component directory contains at most one `.vue` per exported component, a co-located `.scss` when the styles exceed ~40 lines, and a co-located `.test.js` for unit-tested components. |
| AR-11 | All user-visible strings live in `src/assets/locales/en.json` and are referenced with `$t('...')`. No literal user-facing text in components. |
| AR-12 | All colours, spacing and radii come from `src/styles/` custom properties. No hard-coded hex values in components. |
| AR-13 | The sidebar contract from Dashy is preserved: `--side-bar-width`, `--side-bar-background`, `--side-bar-color` and `--header-height` remain the layout tokens; the pane surface is positioned relative to them. |

### 3.2 Files inherited from Dashy and their status

| Dashy path | Workcenter status |
| --- | --- |
| `src/views/Workspace.vue` | **Kept** — becomes the only view, extended with the switcher and pane host |
| `src/views/Home.vue` | **Removed** |
| `src/views/Minimal.vue` | **Removed** |
| `src/views/Login.vue`, `src/views/404.vue` | **Kept** |
| `src/views/DownloadConfig.vue` | **Removed** (no user-authored config export) |
| `src/components/Workspace/SideBar.vue` | **Kept** — refactored into `components/AppSidebar/AppSidebar.vue` |
| `src/components/Workspace/SideBarSection.vue`, `SideBarItem.vue` | **Kept** — become the shared `SidebarItem.vue` primitive |
| `src/components/Workspace/WebContent.vue` | **Kept** — becomes `components/Panes/AppPane.vue` |
| `src/components/Workspace/MultiTaskingWebComtent.vue` | **Kept** — becomes `components/Panes/PaneHost.vue` (the persistent-pane behaviour is the default, not an option) |
| `src/components/Workspace/WidgetView.vue` | **Removed** |
| `src/components/MinimalView/*` | **Removed** |
| `src/components/PageStrcture/*` | **Removed** |
| `src/components/LinkItems/Item.vue`, `ItemContextMenu.vue` | **Removed** (tile rendering); icon helpers reused inside `SidebarItem.vue` |
| `src/components/Widgets/*` | **Removed** |
| `src/components/Settings/ViewSwitcher.vue` | **Removed** |
| `src/components/Settings/*` (theme, language) | **Kept**, pruned |
| `src/components/Settings/OptionsPanel.vue`, `SettingsContainer.vue`, `SearchBar.vue`, `LayoutSelector.vue`, `ItemSizeSelector.vue`, `NavLinksSwitcher.vue`, `LocalConfigWarning.vue`, `CustomThemeMaker.vue` | **Removed** — the settings tree is only ever mounted from the Default view, so in a workspace-only application it is already dead code |
| `src/components/InteractiveEditor/*`, `src/components/Configuration/JsonEditor*` | **Removed** — only reachable from the Default view. Workcenter configuration is a file (`user-data/conf.yml`) validated at startup and by `yarn validate-config`, not an in-app editor. `Configuration/RemoteConfigLoader.vue` is **kept** |
| `src/components/LinkItems/ItemIcon.vue` | **Kept** — the sidebar renders icons through it |
| `src/components/LinkItems/Item.vue`, `ItemContextMenu.vue`, `SectionContextMenu.vue`, `ItemOpenMethodIcon.vue`, `IframeModal.vue` | **Removed** (tile grid and home-only) |
| `src/components/LinkItems/StatusIndicator.vue` (Dashy's per-item status badge) | **Removed** with the status-check subsystem. Its file name is reused in the new shell for `src/components/AppSwitcher/StatusIndicator.vue`, which is an unrelated component driven by Docker healthchecks rather than per-item HTTP probes |
| `src/utils/auth/*` | **Kept** — extended with `Logout.js` |
| `src/utils/config/*` | **Kept** — `ConfigSchema.json` trimmed |
| `src/mixins/HomeMixin.js` | **Kept but trimmed** — `Workspace.vue` mixes it in; home-only helpers (`filterTiles`, `checkIfResults`, `getBackgroundImage`) are removed |
| `src/mixins/MasonryItem.js`, `ChartingMixin.js`, `GlancesMixin.js`, `NextcloudMixin.js`, `WidgetMixin.js` | **Removed** with the widget engine |
| `src/utils/IsVisibleToUser.js`, `CheckPageVisibility.js` | **Removed** — replaced by group-based application authorisation |
| `src/utils/health/…` (status checks) | **Removed** — replaced by `HealthService.js` reading compose healthchecks |

### 3.3 Removed from Dashy

Anything that exists only to serve the Default view, the Minimal view, widgets or status monitoring
is deleted rather than disabled. A lint/test guard (see [`Testing.md`](./Testing.md)) fails the build
if any of these paths reappear:

```
src/views/Home.vue
src/views/Minimal.vue
src/views/DownloadConfig.vue
src/components/MinimalView/
src/components/PageStrcture/            # (kept only: Header, Nav, PageTitle, Footer, LoadingScreen, CriticalError)
src/components/Widgets/
src/components/Workspace/WidgetView.vue
src/components/LinkItems/StatusIndicator.vue   # Dashy's per-item badge; the shell's own lives in AppSwitcher/
src/components/Settings/ViewSwitcher.vue
src/components/Settings/OptionsPanel.vue
src/components/Settings/SettingsContainer.vue
src/components/InteractiveEditor/
src/components/Configuration/JsonEditor*
src/mixins/MasonryItem.js
src/mixins/WidgetMixin.js
src/mixins/ChartingMixin.js
src/mixins/GlancesMixin.js
src/mixins/NextcloudMixin.js
services/endpoints/status-check.js
services/endpoints/ping-check.js
Dockerfile-postgresql
CNAME
netlify.toml
render.yaml
```

Removing the status/ping endpoints also removes the `pingman` dependency and the
`iputils-ping` + `setcap cap_net_raw` steps from the Dockerfile, since nothing in Workcenter performs
ICMP checks.

> **Note on `PageStrcture`:** the directory name contains a typo inherited from Dashy. Workcenter keeps
> the directory but renames it to `PageStructure/` in the same commit that deletes the Default view,
> and updates every import. The typo is not carried forward.

---

## 4. The broker

The broker is what makes Workcenter more than an iframe host. It is specified functionally in
[`roadmap.md` §7](./roadmap.md#7-the-headline-capability-cross-application-file-movement) and
contractually in [`integration.md`](./integration.md).

### 4.1 Placement

| Layer | Path | Responsibility |
| --- | --- | --- |
| HTTP entry | `services/broker-server.js` | Express app mounted by `server.js` under `/api/broker`, OIDC bearer verification |
| Runtime | `services/utils/broker/` | Adapters, transfer engine, token vault, audit log |
| Shell client | `src/broker/` | Typed client, progress events, UI glue |

### 4.2 Broker file breakdown

```
services/utils/broker/
├── index.js              # wires adapters + engine, exports the router
├── router.js             # route table (see §4.3)
├── engine/
│   ├── transfer.js       # stream, size cap, cancel, atomic write, hash, audit
│   ├── naming.js         # collision-safe naming, extension preservation
│   ├── preferences.js    # appearance/language fan-out (see §4.3)
│   └── audit.js          # structured transfer records
├── adapters/
│   ├── files.js          # FileBrowser Quantum: source root resolution, read/write
│   ├── mail.js           # Mailcow/SOGo: IMAP(S) fetch, SMTP submit
│   └── chat.js           # Zulip: /api/v1/user_uploads, /api/v1/tus, attachment fetch
├── auth/
│   ├── verify.js         # token verification against Authentik JWKS
│   ├── authorize.js      # per-user, per-source authorisation
│   └── vault.js          # encrypted per-user credential store
└── health/
    └── integrations.js   # composes per-application health into one payload
```

### 4.3 Broker API surface

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/broker/health` | Per-application health for the application switcher status indicators |
| `GET` | `/api/broker/files/list?path=` | List the user's FileBrowser tree (for the picker) |
| `GET` | `/api/broker/files/stat?path=` | Existence, size, hash — used for de-duplication |
| `POST` | `/api/broker/mail/attachments/save` | **F1** — save a mail attachment into the file source |
| `POST` | `/api/broker/mail/attachments/attach` | **F2** — attach a file-source file to a mail draft |
| `POST` | `/api/broker/chat/files/save` | **F3** — save a Zulip attachment into the file source |
| `POST` | `/api/broker/chat/files/send` | **F4** — send a file-source file into a Zulip message |
| `GET` | `/api/broker/transfers/:id` | Transfer status and progress |
| `POST` | `/api/broker/transfers/:id/cancel` | Cancel an in-flight transfer |
| `POST` | `/api/broker/preferences` | Forward the user's appearance and/or language choice into the embedded applications ([`design.md` §4.4](./design.md#44-the-theme-bridge-forwarding-the-mode-switch), [§8.2](./design.md#82-the-language-bridge)) |

| Ref | Requirement |
| --- | --- |
| AR-14 | The broker is same-origin with the shell (`/api/broker/*`) so no CORS relaxation is needed and the OIDC session cookie/token applies directly. |
| AR-15 | Every broker route is authenticated and authorised per user; there is no unauthenticated route except `/api/broker/health` returning liveness only. |
| AR-16 | The broker is the only component allowed to write into the FileBrowser source tree on behalf of another application. |
| AR-17 | Adapters are pure modules with injected transports, so they are unit-testable without a live Mailcow or Zulip. |
| AR-47 | `POST /api/broker/preferences` acts **only** on the calling user, resolved from the verified token — never on a user named in the request body. It accepts `mode` and `locale`, fans out to the adapters in parallel, and answers with a per-application result so the shell can report a partial failure (`design.md` D-6.1) instead of pretending the switch succeeded. |
| AR-48 | The preference fan-out is implemented in `services/utils/broker/engine/preferences.js` and uses the existing adapters. An adapter that has no preference surface reports `unsupported`; that is a normal outcome, not an error. |

---

## 5. Integrated-application folders

Each folder is self-contained: configuration, secrets, volumes and (where applicable) its own compose
file. The root `compose.yaml` references them.

### 5.1 `Filebrowser/`

```
Filebrowser/
├── .env.example              # IMAGE_TAG, source path, OIDC + OnlyOffice secrets
├── config.yaml               # FileBrowser Quantum v2 schema (AUTHORITATIVE, committed template)
├── config.local.yaml         # generated, gitignored, holds secrets expanded by setup.sh
├── data/                     # bind mount -> /home/filebrowser/data
│   ├── database.sqlite
│   └── cache/                # -> /home/filebrowser/data/cache
├── office-cache/             # OnlyOffice working cache
├── compose.yaml              # FileBrowser Quantum service + Traefik labels + healthcheck
└── README.md                 # folder-local notes, points at OIDC.md / production.md
```

| Ref | Requirement |
| --- | --- |
| AR-18 | `config.yaml` uses only the **v2** schema keys (`server`, `http`, `auth.methods`, `frontend`, `userDefaults`, `integrations`, `sources`). |
| AR-19 | Secrets are injected via environment (`FILEBROWSER_OIDC_CLIENT_ID`, `FILEBROWSER_OIDC_CLIENT_SECRET`, `FILEBROWSER_JWT_TOKEN_SECRET`, `FILEBROWSER_ONLYOFFICE_SECRET`) rather than committed to `config.yaml`. |
| AR-20 | The user file source is declared under `server.sources[]` with a `path` that resolves to the shared host file tree also used by the broker. |

### 5.2 `Zulip/`

```
Zulip/
├── .env.example              # image tag, EXTERNAL_HOST, admin email, SMTP settings
├── compose.yaml              # database, memcached, rabbitmq, redis, zulip (docker-zulip)
├── compose.override.yaml     # Workcenter-specific: volumes, Traefik labels, healthchecks
├── secrets/                  # zulip__* secret files + zuliprc for the broker bot (gitignored)
├── data/                     # -> /data                (Zulip application state + uploads)
├── database/                 # -> /var/lib/postgresql/data
├── rabbitmq/                 # -> /var/lib/rabbitmq
├── redis/                    # -> /data
└── README.md
```

| Ref | Requirement |
| --- | --- |
| AR-21 | The **full** docker-zulip service set is deployed; no service is removed to save resources. |
| AR-22 | All five services receive explicit healthchecks in `compose.override.yaml`, since upstream relies on image defaults. |
| AR-23 | Uploaded files live on the bind-mounted `./Zulip/data`, which the broker reads for F3 and writes to for F4 — subject to Zulip's own storage layout. |

### 5.3 `Mailcow/`

```
Mailcow/
├── mailcow.conf              # generated by generate_config.sh (tracked upstream, gitignored here)
├── .env -> mailcow.conf      # symlink created by Mailcow's own repo
├── docker-compose.yml        # UPSTREAM, NEVER EDITED
├── docker-compose.override.yml  # the ONLY Workcenter change: Traefik labels, healthchecks
├── generate_config.sh        # upstream
├── update.sh                 # upstream
├── data/                     # upstream runtime tree (web, conf, assets, hooks)
│   ├── conf/sogo/            # SOGo configuration templates
│   └── assets/ssl/           # certificates (Traefik-dumped or mailcow-managed)
└── README.md
```

| Ref | Requirement |
| --- | --- |
| AR-24 | `docker-compose.yml` and `generate_config.sh` are treated as read-only upstream files. Workcenter's changes live **only** in `docker-compose.override.yml`. |
| AR-25 | Mailcow is always driven with `docker compose` from inside `Mailcow/` with **no `-f` flag**, so the override auto-merges and `update.sh` keeps working. |
| AR-26 | The override removes public port publishing in favour of `expose` and the shared `proxy` network, and sets `TRUSTED_PROXIES`. |

### 5.4 `OnlyOffice/`

```
OnlyOffice/
├── .env.example              # image tag, JWT_ENABLED, JWT_SECRET, JWT_HEADER
├── compose.yaml              # onlyoffice/documentserver + Traefik labels + healthcheck
├── data/  logs/  lib/  db/   # bind-mounted DocumentServer state
└── README.md
```

### 5.5 `Authentik/`

```
Authentik/
├── .env.example              # AUTHENTIK_TAG, PG_PASS, AUTHENTIK_SECRET_KEY, bootstrap vars
├── compose.yaml              # server, worker, postgresql, redis (+ LDAP outpost)
├── data/
│   ├── postgres/  redis/  media/  certs/  templates/
└── README.md
```

### 5.6 `Traefik/`

```
Traefik/
├── .env.example              # ACME_EMAIL, domain, dashboard host
├── compose.yaml              # traefik:v3 + ping healthcheck + dashboard router
├── traefik.yml               # static configuration: entrypoints, providers, ACME, metrics
├── dynamic/
│   ├── middlewares.yml       # security headers, forward-auth, rate limits
│   ├── tls.yml               # TLS options, internal CA trust
│   └── dashboard.yml         # traefik.example.com + Authentik forward-auth
├── acme.json                 # gitignored, chmod 600
├── certs/                    # internal CA / self-signed material for backend TLS
└── logs/
```

### 5.7 Root composition

```
compose.yaml            # bring up everything: include/extends the per-app compose files
compose.test.yaml       # deterministic profile for the Playwright harness
```

```yaml
# compose.yaml — shape, not final content
name: workcenter

include:
  - Traefik/compose.yaml
  - Authentik/compose.yaml
  - Filebrowser/compose.yaml
  - OnlyOffice/compose.yaml
  - Zulip/compose.yaml

services:
  workcenter:
    build: .
    env_file: [.env]
    depends_on:
      filebrowser:  { condition: service_healthy }
      onlyoffice:   { condition: service_healthy }
      zulip:        { condition: service_healthy }
      authentik:    { condition: service_healthy }
    networks: [proxy, internal]
    labels: [ "traefik.enable=true", "..." ]
```

> **Mailcow is deliberately excluded from `include:`.** It is brought up by its own compose file
> from inside `Mailcow/`, because Mailcow's `update.sh` and `generate_config.sh` are the supported
> lifecycle tools. `setup.sh` sequences "bring up Mailcow" then "bring up Workcenter"; Workcenter's
> readiness for Mail is asserted by the broker's health check, not by a compose dependency.

| Ref | Requirement |
| --- | --- |
| AR-27 | Exactly **one** root `compose.yaml`, which references the per-application compose files. |
| AR-28 | Two shared Docker networks: `proxy` (Traefik-facing, external) and `internal` (service-to-service). |
| AR-29 | Every service carries Traefik labels using recommended v3 defaults and a `traefik.docker.network` entry. |
| AR-30 | Every service has an explicit `healthcheck`, and Workcenter gates on `condition: service_healthy`. |
| AR-31 | All persistent data is a bind mount inside the owning application's folder. |

---

## 6. Configuration model

### 6.1 Root `.env`

Single source of operator configuration. Committed as `.env.example`; `.env` is gitignored.

```env
# --- Base URL ---------------------------------------------------------------
BASE_DOMAIN=example.com
WORKCENTER_URL=https://example.com
FILEBROWSER_URL=https://filebrowser.example.com
AUTH_URL=https://auth.example.com
MAIL_URL=https://mail.example.com
CHAT_URL=https://chat.example.com
TRAEFIK_URL=https://traefik.example.com

# --- Image pins -------------------------------------------------------------
FILEBROWSER_IMAGE=gtstef/filebrowser:2.0.6-beta
ZULIP_IMAGE=ghcr.io/zulip/zulip-server:12.2-0
ONLYOFFICE_IMAGE=onlyoffice/documentserver:8.2
AUTHENTIK_TAG=2024.12
TRAEFIK_TAG=v3.1
MAILCOW_BRANCH=master

# --- Authentik / OIDC -------------------------------------------------------
AUTHENTIK_HOST=auth.example.com
WORKCENTER_OIDC_CLIENT_ID=workcenter
WORKCENTER_OIDC_CLIENT_SECRET=
FILEBROWSER_OIDC_CLIENT_ID=filebrowser
FILEBROWSER_OIDC_CLIENT_SECRET=
ZULIP_OIDC_CLIENT_ID=zulip
ZULIP_OIDC_CLIENT_SECRET=
MAILCOW_OIDC_CLIENT_ID=mailcow
MAILCOW_OIDC_CLIENT_SECRET=

# --- Workspace groups (identical across every application) ------------------
WORKCENTER_USER_GROUP=workspaceusers
WORKCENTER_ADMIN_GROUP=workspaceadmin

# --- Traefik / TLS ----------------------------------------------------------
ACME_EMAIL=admin@example.com
ACME_CASERVER=https://acme-v02.api.letsencrypt.org/directory
ENABLE_INTERNAL_TLS=false
```

### 6.2 `user-data/conf.yml`

Workcenter's application configuration, derived from Dashy's `conf.yml` but trimmed to the shell.

```yaml
pageInfo:
  title: Workcenter
  description: Files, chat and mail in one place

appConfig:
  defaultTheme: dark
  defaultLanguage: en
  baseDomain: example.com          # drives src/utils/apps/urls.js
  enableMultiTasking: true         # panes stay mounted — the Workcenter default
  auth:
    enableOidc: true
    oidc:
      clientId: workcenter
      endpoint: https://auth.example.com/application/o/workcenter/
      adminGroup: workspaceadmin
      scope: openid profile email groups
      enableSilentRenew: true
  applications:                    # mirrors src/utils/apps/registry.js
    files:
      url: https://filebrowser.example.com
      accent: blue
      healthKey: filebrowser
    chat:
      url: https://chat.example.com
      accent: violet
      healthKey: zulip
    mail:
      url: https://mail.example.com/SOGo
      accent: teal
      healthKey: mailcow

broker:
  enabled: true
  transfer:
    maxSizeMiB: 512
    timeoutSeconds: 300
    deduplicate: true
  audit:
    enabled: true
    retentionDays: 30
```

| Ref | Requirement |
| --- | --- |
| AR-32 | `appConfig.applications` mirrors `src/utils/apps/registry.js`; a unit test asserts they cannot drift. |
| AR-33 | Secrets never appear in `conf.yml`; they are read from `.env` by `server.js` and injected at runtime. |
| AR-34 | `ConfigSchema.json` validates `conf.yml` at startup and on save; an invalid config fails fast with a readable error. |

---

## 7. Build, runtime and network layout

### 7.1 Container layout

| Container | Built from | Exposure | Network |
| --- | --- | --- | --- |
| `workcenter` | `Dockerfile` (Dashy's multi-stage, extended) | Traefik → `:8080` | `proxy`, `internal` |
| `filebrowser` | `gtstef/filebrowser:2.0.6-beta` | Traefik → `:80` | `proxy`, `internal` |
| `onlyoffice` | `onlyoffice/documentserver` | `internal` only (or Traefik if public editing is required) | `internal`, `proxy` |
| `zulip` `database` `memcached` `rabbitmq` `redis` | docker-zulip images | `zulip` via Traefik → `:80`; the rest internal | `internal` |
| `postgresql` `redis` `server` `worker` `ldap` (Authentik) | Authentik images | `server` via Traefik → `:9000` | `proxy`, `internal` |
| `traefik` | `traefik:v3` | `:80`, `:443` published | `proxy` |
| Mailcow services | Mailcow images | `nginx-mailcow` via Traefik → `:8080`; mail ports published as configured | `mailcow-network` + `proxy` |

### 7.2 Shared volumes for the broker

The broker needs to see the same bytes as FileBrowser and Mailcow. That is achieved by mounting the
same host directories into the Workcenter container **read-write**:

```yaml
services:
  workcenter:
    volumes:
      - ./user-data:/app/user-data
      - ./Filebrowser/data:/srv/filebrowser-data
      - ${FILEBROWSER_SOURCE_PATH:-./user-data/files}:/srv/files
      - ./Mailcow/data:/srv/mailcow:ro
      - ./Zulip/data:/srv/zulip:ro
```

| Ref | Requirement |
| --- | --- |
| AR-35 | The broker's file source mount and FileBrowser's source mount must resolve to the **same host directory**, asserted at broker startup. |
| AR-36 | Mailcow and Zulip mounts are **read-only** for the broker; all writes go through the network APIs of those applications. |
| AR-37 | The Workcenter container never mounts `/var/run/docker.sock`. Health is read through the compose health endpoints, not the Docker API. |

### 7.3 Dockerfile

Dashy's three-stage Dockerfile is kept and extended:

| Stage | Change |
| --- | --- |
| `build` | Add the broker TypeScript build; keep `yarn build` for the SPA |
| `deps` | Add broker runtime dependencies |
| final | Keep `tini`, non-root `node` user, `EXPOSE 8080`, `HEALTHCHECK`; add `docker-entrypoint.sh` that starts the broker then `server.js`, and `NODE_EXTRA_CA_CERTS` support for the internal-TLS option |

| Ref | Requirement |
| --- | --- |
| AR-38 | The image runs as the non-root `node` user, exactly as Dashy's does. |
| AR-39 | The image ships a `HEALTHCHECK` invoking `services/healthcheck.js`, exactly as Dashy's does. |
| AR-40 | The image supports `NODE_EXTRA_CA_CERTS` so it can trust the optional internal CA (roadmap D-7). |

---

## 8. Documentation layout

The specification set lives at the repository root; long-form guides live in `docs/`.

```
Workcenter/
├── Readme.md            # overview + quick start (GitHub landing page)
├── roadmap.md           # goals, integrations, UI, phased build plan
├── architecture.md      # this file
├── design.md            # UI element specification
├── integration.md       # what each integrated application is and how it is wired in
├── OIDC.md              # Authentik setup + setup.sh prompt contract
├── Testing.md           # test strategy, harness and gates
├── production.md        # deployment, setup.sh contract, upgrades, backups
├── standards.md         # coding and documentation standards
├── contributions.md     # PR guide, process, workflow
├── Agents.md            # AI coding agent requirements
├── CHANGELOG.md         # running log of changes
└── docs/
    ├── readme.md        # documentation index
    ├── authentication/  # per-provider notes beyond OIDC.md
    ├── deployment/      # docker, bare-metal, reverse-proxy specifics
    ├── management.md    # day-2 operations
    ├── security.md      # threat model and hardening
    ├── theming.md       # writing themes
    └── troubleshooting.md
```

| Ref | Requirement |
| --- | --- |
| AR-41 | Every file listed above must exist and must be linked from `docs/readme.md` and, where operator-facing, from `Readme.md`. |
| AR-42 | `docs/` keeps Dashy's kebab-case file naming and task-oriented headings. |
| AR-43 | Documentation for a removed Dashy feature is deleted, not left describing something that no longer exists. |

---

## 9. Extension points

Workcenter is deliberately closed to arbitrary tiles but open in three controlled places:

| Extension | Where | Rules |
| --- | --- | --- |
| **Add an application pane** | `src/utils/apps/registry.js` + `appConfig.applications` + a sidebar component | Must ship with a healthcheck, an OIDC story, a Traefik router and Playwright coverage |
| **Add a broker transfer** | `services/utils/broker/adapters/` + a route + a UI entry point | Must be streaming, cancellable, audited, deduplicated and unit-tested with fixtures |
| **Add a theme** | `src/styles/themes/` | Must define every token in `color-palette.scss`; no component edits |

| Ref | Requirement |
| --- | --- |
| AR-44 | Adding an application pane is not permitted in a minor release; it requires a roadmap change and a design document update. |
| AR-45 | A new broker transfer must not weaken per-user authorisation; the authorisation tests must be extended in the same PR. |

---

## 10. Architecture decision summary

| # | Decision | Rationale |
| --- | --- | --- |
| AD-1 | Keep Dashy's top-level folder layout | Lowest-risk derivation; upstream docs, build and theming keep working |
| AD-2 | One view, three panes, panes always mounted | Preserves sessions; matches Dashy's `enableMultiTasking` semantics |
| AD-3 | One repository, one root folder per integrated application | Satisfies the "files used by the application live within its named folder" requirement, and makes backup a single `rsync` |
| AD-4 | Mailcow is orchestrated by its own tooling, customised only by `docker-compose.override.yml` | Keeps `update.sh` working; upstream-endorsed mechanism |
| AD-5 | Broker rather than direct iframe scripting | Cross-origin isolation makes any other approach impossible |
| AD-6 | Broker co-located in the Workcenter container | Same-origin API, no CORS, one OIDC session, one deployable |
| AD-7 | Traefik as the only ingress | Single TLS termination point, one ACME resolver, uniform label contract |
| AD-8 | Authentik as the only IdP, with a unified two-group model | One login, one authorisation model, one place to revoke |
| AD-9 | Bind mounts, never anonymous volumes, for anything backed up | Operators can see, back up and restore state without Docker archaeology |
| AD-10 | FileBrowser Quantum pinned to v2.0.6-beta with a recorded digest | The v2 config/API surface is what Workcenter is written against |

---

<p align="center"><sub>Workcenter architecture · derived from <a href="https://github.com/lissy93/dashy">Dashy</a></sub></p>
