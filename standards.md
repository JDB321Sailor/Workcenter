# Workcenter — Coding & Documentation Standards

> **Applies to:** every file in this repository — application source, deployment files, shell scripts,
> tests and documentation.
> **Enforced by:** ESLint, Stylelint, ShellCheck, Prettier, `markdownlint`, Vitest coverage gates and CI.
> **Companions:** [`contributions.md`](./contributions.md) · [`Agents.md`](./Agents.md) ·
> [`Testing.md`](./Testing.md) · [`architecture.md`](./architecture.md)

---

## 0. The one rule

> **Write code that looks like the code already next to it.**

Workcenter is a derivative of [Dashy](https://github.com/lissy93/dashy) and follows
[FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser)'s contribution discipline. Where
this document is silent, match the surrounding file. Where a linter and this document disagree, the
linter wins and this document is corrected in the same PR.

---

## 1. Toolchain versions

| Tool | Version | Source of truth |
| --- | --- | --- |
| Node.js | **24.x in Docker and CI**; `package.json` engines `^22.18.0 \|\| >=24.11.0` | `package.json`, `Dockerfile`, CI |
| Package manager | **Yarn 1.22.22** (`packageManager` field) | `package.json`, `yarn.lock` |
| Vue | 3.5+ (**Options API**) | `package.json` |
| Vuex | 4 (single root store, `modules: {}`) | `src/store.js` |
| Vue Router | 5 (`routePaths` are declared in `src/utils/config/defaults.js`, not in the router) | `src/router.js`, `defaults.js` |
| Vite | 8 | `package.json` |
| Vitest | 4 + `happy-dom` + `@vue/test-utils` + `supertest` | `vitest.config.mjs` |
| Playwright | 1.4x | `e2e/package.json` |
| ESLint | 10, **flat config** (`eslint.config.mjs`) | `eslint.config.mjs` |
| TypeScript | 6 (`vue-tsc` for `typecheck`) | `package.json` |
| Express | 5 (the Workcenter server) | `services/app.js` |
| Bash | 5+ (for `setup.sh` and `scripts/`) | `setup.sh` shebang guard |
| Docker Engine | 24+ | `production.md` |
| Docker Compose | v2.20+ (supports `include:`) | `compose.yaml` |

> **Note:** Dashy configures **no Prettier, no Stylelint and no markdownlint**. Formatting is governed by
> `.editorconfig` plus the written style guide, and Markdown is reviewed by humans. Workcenter inherits
> that position deliberately: adding a formatter is a separate, changelog-recorded decision, not a
> drive-by change. The linters that *do* run are listed in [§13](#13-tooling-configuration).

`setup.sh` and every script under `scripts/` must fail fast with a readable message when a required
version is missing.

---

## 2. General principles

| # | Principle |
| --- | --- |
| S1 | **Explicit over clever.** A reader should not need to run the code to know what it does. |
| S2 | **Delete, don't disable.** Removed Dashy subsystems are deleted, not feature-flagged. |
| S3 | **No secrets in the repository.** Ever — not in code, tests, fixtures, screenshots or logs. |
| S4 | **Errors are handled, never swallowed.** Every `catch` either recovers, retries, or reports with context. |
| S5 | **Small, single-purpose modules.** If a file needs a table of contents to navigate, split it. |
| S6 | **Comments explain *why*.** The code already says *what*. |
| S7 | **User-visible text is a translation key.** No string literals in components. |
| S8 | **Configuration is data, not code.** Behaviour that an operator may change belongs in `.env` or `conf.yml`. |
| S9 | **Idempotence for anything operational.** Scripts and compose files converge on re-run. |
| S10 | **Accessibility and security are requirements, not enhancements.** |

---

## 3. JavaScript and Vue standards

### 3.1 Language and syntax

| Ref | Rule |
| --- | --- |
| S-JS-1 | ES2022+. Use `const` by default, `let` when reassignment is required, **never `var`**. |
| S-JS-2 | Use `async`/`await`. Do not mix promise chains and `await` in the same function. |
| S-JS-3 | Prefer `for...of` and array methods over `for...in` and index loops. |
| S-JS-4 | Use optional chaining (`?.`) and nullish coalescing (`??`) instead of `&&`/`||` guards for nullability. |
| S-JS-5 | Never use `==`/`!=`; use `===`/`!==`. |
| S-JS-6 | No `eval`, no `new Function`, no dynamic `import()` of a computed path. |
| S-JS-7 | Destructure at the point of use; avoid deep property chains beyond three levels. |
| S-JS-8 | One export style per file. Named exports are preferred; `export default` only for Vue SFCs and entry points. |

### 3.2 Vue components

| Ref | Rule |
| --- | --- |
| S-VUE-1 | **Options API**, matching Dashy's existing components and the rest of the codebase. Workcenter does **not** introduce `<script setup>` or the Composition API anywhere; new components follow the same Options API shape as the ones they sit beside. (Dashy's only non-Options code is an inline `createApp({ render })` inside the multi-tasking host and one `defineAsyncComponent`; neither is a pattern to extend.) |
| S-VUE-2 | One component per file. File name and `name` option match (`AppSwitcher.vue` → `name: 'AppSwitcher'`). |
| S-VUE-3 | Props are declared with types **and** defaults. Emitted events are declared in `emits`. |
| S-VUE-4 | Template order: `<template>`, `<script>`, `<style>`. |
| S-VUE-5 | Styles are `<style scoped lang="scss">`. Global styles belong in `src/styles/`. |
| S-VUE-6 | No business logic in templates. Anything beyond a single expression moves to a computed property or method. |
| S-VUE-7 | `v-for` always has a `:key` that is stable and unique — never the array index for a mutable list. |
| S-VUE-8 | Never mutate props. Never mutate Vuex state outside a mutation. |
| S-VUE-9 | Clean up in `beforeUnmount`: timers, listeners, observers, mounted child apps. |
| S-VUE-10 | Components must render deterministically from props + store, with no reliance on mount order. |
| S-VUE-11 | Any `.vue` file over 300 lines must justify its size in the PR, or be split. |

### 3.3 State and data flow

| Ref | Rule |
| --- | --- |
| S-ST-1 | Vuex modules are the only shared state. Module names: `config`, `apps`, `health`, `user`, `ui`. |
| S-ST-2 | Mutations are synchronous and named `SET_*` / `UPDATE_*`; asynchronous work belongs in actions. |
| S-ST-3 | Getters are pure. No side effects, no fetching. |
| S-ST-4 | The `apps` module reads from `src/utils/apps/registry.js`; components never hard-code application URLs. |
| S-ST-5 | Sidebar data is cached with an explicit TTL and a documented invalidation trigger. |

### 3.4 Broker and Node code

| Ref | Rule |
| --- | --- |
| S-ND-1 | Every adapter exports a plain object with `list`, `read`, `write` (as applicable) and receives its transport by injection. |
| S-ND-2 | Streams are never fully buffered. Use `pipeline()` with backpressure and an explicit size cap. |
| S-ND-3 | Every filesystem write is temp-file-then-rename within the same directory, so no partial file is ever visible. |
| S-ND-4 | Every broker route validates its input with an explicit schema before touching an adapter. |
| S-ND-5 | Every broker route is wrapped in the auth + authorisation middleware; there is no opt-out. |
| S-ND-6 | Log lines are structured (`{ level, event, userId, transferId, ... }`) and never contain file contents, tokens or passwords. |
| S-ND-7 | Outbound HTTP uses a shared client with explicit timeouts, a `User-Agent`, and TLS verification **enabled** by default. |

### 3.5 Naming

| Kind | Convention | Example |
| --- | --- | --- |
| Files: components | PascalCase `.vue` | `AppSwitcher.vue` |
| Files: modules | camelCase `.js` / `.ts` | `HealthService.js` |
| Files: styles | kebab-case `.scss` | `color-palette.scss` |
| Files: docs | kebab-case `.md` (specification set keeps its published names) | `troubleshooting.md` |
| Variables, functions | camelCase | `resolveSourceRoot()` |
| Constants | `SCREAMING_SNAKE_CASE` | `MAX_TRANSFER_BYTES` |
| Vuex mutations | `SCREAMING_SNAKE_CASE`, verb-first | `SET_ACTIVE_APP` |
| CSS custom properties | kebab-case, `--wc-` prefix for shell tokens | `--wc-accent-chat` |
| i18n keys | dot-namespaced | `transfer.save.success` |
| Env vars | `SCREAMING_SNAKE_CASE`, app-prefixed where app-specific | `FILEBROWSER_OIDC_CLIENT_ID` |
| Docker services | kebab-case, application-named | `nginx-mailcow`, `onlyoffice` |
| Traefik routers | `<app>-<purpose>` | `filebrowser-web`, `mailcow-autodiscover` |

---

## 4. Styling standards

| Ref | Rule |
| --- | --- |
| S-CSS-1 | SCSS, one partial per concern, imported from a single entry. |
| S-CSS-2 | Nesting is limited to **three** levels. |
| S-CSS-3 | BEM-ish class names: `.wc-switcher__button--active`. The `wc-` prefix marks shell chrome. |
| S-CSS-4 | Components use **semantic tokens only** (`--wc-*`, `--side-bar-*`). No hex literals in `.vue` files. |
| S-CSS-5 | Spacing uses the shared scale (`0.25/0.5/0.75/1/1.5/2/3rem`). No arbitrary values. |
| S-CSS-6 | Prefer flexbox; use CSS grid for two-dimensional layout only. |
| S-CSS-7 | Never use `!important` outside of a documented override of an embedded application's CSS. |
| S-CSS-8 | `@media` queries use the shared breakpoints in `media-queries.scss`, not raw pixel values. |
| S-CSS-9 | Animations must be disabled under `prefers-reduced-motion: reduce`. |
| S-CSS-10 | Dashy token names (`--side-bar-*`, `--curve-factor`, `--workspace-web-content-background`) are preserved for compatibility and not renamed. |

---

## 5. Configuration and secrets standards

| Ref | Rule |
| --- | --- |
| S-CF-1 | Every operator-facing setting exists in an `.env.example` with a comment explaining it and a safe default. |
| S-CF-2 | Every optional setting has a documented default **in code**, so a missing value never crashes the app. |
| S-CF-3 | `.env`, `*.local.yaml`, `*/secrets/*`, `acme.json` and `**/data/` are gitignored. |
| S-CF-4 | Secrets are generated with `openssl rand -hex 32` (or an equivalent CSPRNG) by `setup.sh`; never invented by hand in documentation. |
| S-CF-5 | `config.yaml` files committed to the repository contain **no** secrets; secrets arrive through environment variables. |
| S-CF-6 | Every image reference is a **pinned tag**, and the tag lives in `.env`, never inline in a compose file. |
| S-CF-7 | Never modify an upstream application's own compose file; extend it with `*.override.yml` or `include:`. |
| S-CF-8 | Every service defines a `healthcheck`, and every dependent service waits with `condition: service_healthy`. |
| S-CF-9 | Every persistent path is a bind mount expressed as `./<AppFolder>/<subpath>:<container path>`. |

---

## 6. Shell script standards

Applies to `setup.sh` and everything in `scripts/`.

| Ref | Rule |
| --- | --- |
| S-SH-1 | `#!/usr/bin/env bash` and `set -Eeuo pipefail` at the top of every script. |
| S-SH-2 | ShellCheck-clean at `--severity=warning`; CI runs it. |
| S-SH-3 | `IFS=$'\n\t'` and every expansion quoted (`"${var}"`). |
| S-SH-4 | Every script supports `--help` and prints usage. |
| S-SH-5 | Every destructive action is guarded: it either detects the existing state and skips, or asks for confirmation. |
| S-SH-6 | Idempotent: running twice must not change the result of the first run. |
| S-SH-7 | Coloured, prefixed output: `ℹ` info, `✔` success, `⚠` warning, `✖` error. Warnings and errors also go to stderr. |
| S-SH-8 | A trap on `ERR` prints the failing line number and the command. |
| S-SH-9 | Prompts read from `/dev/tty` and supply a default in `[brackets]`; non-interactive mode is honoured via an env var. |
| S-SH-10 | Generated secrets are written with `umask 077`. |
| S-SH-11 | No `curl | bash`. Downloaded scripts are written to a file, verified, then executed. |
| S-SH-12 | No hard-coded container names, hostnames or domains — everything comes from `.env`. |
| S-SH-13 | Shared helpers live in `scripts/lib/*.sh` and are sourced, not duplicated. |

---

## 7. Testing standards

Full strategy in [`Testing.md`](./Testing.md). The standards that bind every PR:

| Ref | Rule |
| --- | --- |
| S-T-1 | **No PR merges without tests** for changed behaviour. |
| S-T-2 | Coverage floor: **80%** lines for `src/broker/**` and `services/utils/**`; **70%** for `src/utils/**` and `src/components/**`; configuration files are exempt. Coverage is collected with Vitest's `v8` provider (`yarn test:coverage`), configured in `vitest.config.mjs` to exclude `node_modules`, `tests`, `*.config.js`, `dist`, `.github` and `docs`. |
| S-T-3 | Unit tests live beside the code they test or under `tests/unit/`, named `*.test.js`. Dashy's existing layout is kept: `tests/unit/` for utilities and config, `tests/components/` for component tests, `tests/server/` for server tests. |
| S-T-4 | Playwright specs live in `e2e/specs/`, named `<area>.spec.ts`. |
| S-T-5 | Tests never depend on the public internet; external edges are stubbed or seeded. |
| S-T-6 | Tests are deterministic: fixed clocks, fixed fixtures, no reliance on wall-clock ordering. |
| S-T-7 | A bug fix ships with the regression test that fails before the fix. |
| S-T-8 | A flaky test is fixed or deleted, never retried into silence. |
| S-T-9 | Fixtures contain no real personal data, credentials or customer content. |

### Inherited test conventions

These are Dashy's, and Workcenter keeps them:

| Convention | Detail |
| --- | --- |
| Explicit imports | `import { describe, it, expect } from 'vitest'` — do not rely on `globals` |
| Test names | Behaviour sentences: `it('hides an item the current user cannot see')` |
| Fixtures | Factory functions with an override argument: `const item = (over = {}) => ({ ...defaults, ...over })` |
| Component mounting | `shallowMount` + a real `createStore`, never a full mount |
| Boundaries are mocked | `vi.mock('@/utils/request')`, `vi.mock('@/router')`, `vi.mock('@/utils/logging/ErrorHandler')` |
| Server tests | Start the file with `// @vitest-environment node`, use `supertest` against `services/app`, and point `process.env.USER_DATA_DIR` at a `mkdtemp()` directory |
| Environment shims | `tests/setup.js` mocks `localStorage`, `sessionStorage` and `matchMedia`, and silences `console.info` |
| Locale integrity | `yarn validate-locales` fails the build when a `$t('…')` key used in code is missing from `en.json` |

---

## 8. Git and commit standards

### 8.1 Commits

Conventional Commits, as used by FileBrowser Quantum and Dashy:

```
type(scope): description
```

| Type | Use for |
| --- | --- |
| `feat` | A new capability |
| `fix` | A defect fix |
| `docs` | Documentation only |
| `refactor` | Behaviour-preserving restructure |
| `test` | Tests only |
| `chore` | Build, tooling, dependencies |
| `perf` | Performance |
| `style` | Formatting only |
| `ci` | Workflows |
| `revert` | A revert |

| Ref | Rule |
| --- | --- |
| S-G-1 | Summary is imperative, ≤ 72 characters, no trailing period. |
| S-G-2 | Scope names the area: `switcher`, `sidebar`, `broker`, `auth`, `compose`, `setup`, `filebrowser`, `zulip`, `mailcow`, `traefik`, `onlyoffice`, `docs`. |
| S-G-3 | The body explains **why**, wrapping at 100 characters; the diff already shows what. |
| S-G-4 | Breaking changes are marked with `!` after the type/scope and a `BREAKING CHANGE:` footer. |
| S-G-5 | One coherent change per commit; no "wip" or "fixes" commits in the final history. |
| S-G-6 | The upstream Dashy import is one commit with the exact upstream commit hash in the body. |
| S-G-7 | Never commit generated artifacts, editor configuration or OS files. |

Examples:

```
feat(switcher): add three-button application switcher above the rail
fix(broker): stream mail attachments instead of buffering them in memory
docs(oidc): document the mailcow generic-oidc provider fields
chore(compose): pin filebrowser quantum to 2.0.6-beta
```

### 8.2 Branches

| Branch | Purpose |
| --- | --- |
| `Dev` | **Default PR target.** Integration branch. |
| `Beta` | Promoted from `Dev`; release candidates. |
| `Stable` | Promoted from `Beta`; GitHub default branch; production. |
| Feature branches | `feat/<short-description>`, `fix/<short-description>`, `docs/<short-description>`, `chore/<short-description>` |

Full workflow in [`contributions.md`](./contributions.md).

---

## 9. Documentation standards

Workcenter's documentation is part of the product. It inherits Dashy's house style.

### 9.1 Structure

| Ref | Rule |
| --- | --- |
| S-D-1 | Markdown (CommonMark) with GitHub-flavoured tables, task lists and `<details>` blocks. |
| S-D-2 | Exactly one `#` H1 per file; heading levels never skip. |
| S-D-3 | Every file opens with a short scope statement and a **Companions** line linking related documents. |
| S-D-4 | The specification set at the repository root keeps its published file names (`Readme.md`, `OIDC.md`, `Agents.md`, `Testing.md`, `CHANGELOG.md`). Long-form guides under `docs/` are kebab-case. |
| S-D-5 | A table of contents is required for any document longer than ~300 lines. |
| S-D-6 | Documentation is versioned with the code and updated in the **same PR** as the behaviour it describes. |

### 9.2 Writing style

| Ref | Rule |
| --- | --- |
| S-D-7 | Imperative, second person, present tense: "Run `./setup.sh`", not "The user should run…". |
| S-D-8 | Sentence-case headings. No Title Case, no ALL CAPS. |
| S-D-9 | One idea per paragraph; prefer a table or a list over a wall of prose. |
| S-D-10 | Every command is in a fenced code block with its language (`bash`, `yaml`, `env`, `json`, `text`). |
| S-D-11 | Every configuration key is shown with its **real** name and a realistic value. |
| S-D-12 | Every external claim links to its upstream source. |
| S-D-13 | Admonitions use the standard labels: **Note**, **Warning**, **Tip**, **Rule**, **Example**. |
| S-D-14 | No marketing voice, no exclamation marks, no emoji in operational documents. |
| S-D-15 | Define an acronym on first use: "OpenID Connect (OIDC)". |
| S-D-16 | Screenshots are current, have a caption, and contain no real personal data. |
| S-D-17 | ASCII diagrams are preferred over images for architecture, so they survive diffs and greps. |

### 9.3 Required sections

| Document type | Must contain |
| --- | --- |
| Feature doc | Purpose, prerequisites, configuration, usage, verification, troubleshooting |
| Operator doc | Prerequisites, step-by-step commands, expected output, rollback, troubleshooting |
| Reference doc | Complete key/option table with types, defaults and examples |
| Specification doc (this set) | Scope, requirement IDs with `Ref` columns, cross-links, review checklist |

---

## 10. Requirement-ID convention

Every specification document numbers its requirements so tests and PRs can cite them.

| Prefix | Area |
| --- | --- |
| `G` | Goal (roadmap) |
| `U` | UI requirement (roadmap) / `D-*` design element |
| `I-<app>` | Integration requirement (`I-FB`, `I-ZU`, `I-MC`, `I-OO`, `I-AK`, `I-X`) |
| `B-` | Broker requirement |
| `D-` | Deployment requirement / design element |
| `A-` | Authentication requirement |
| `AR-` | Architecture requirement |
| `S-` | Coding standard |
| `T-` | Testing requirement |
| `P-` | Production requirement |

Rules: IDs are **stable and never reused**; a removed requirement is marked `(withdrawn)` rather than
renumbered; every Playwright spec header cites the IDs it asserts.

---

## 11. Security standards

| Ref | Rule |
| --- | --- |
| S-SEC-1 | No secret, token, password or key in the repository, in logs, in error messages or in screenshots. |
| S-SEC-2 | All secrets are generated, stored in an application folder's `.env`/`secrets/`, and gitignored. |
| S-SEC-3 | Containers run as non-root wherever the image permits; no `privileged: true` except where upstream requires it (Mailcow's `netfilter-mailcow`), and that exception is documented. |
| S-SEC-4 | No container mounts the Docker socket except `dockerapi-mailcow` and Mailcow's `ofelia-mailcow`, which require it upstream. |
| S-SEC-5 | TLS verification is never disabled by default; the `disableVerifyTLS`-style options are documented as testing-only. |
| S-SEC-6 | Every HTTP surface is behind Traefik with valid TLS; no service is published directly to the internet. |
| S-SEC-7 | OIDC uses the authorization code flow with PKCE; implicit flow is never used. |
| S-SEC-8 | OIDC providers use **signed** tokens only, never encrypted (JWE). |
| S-SEC-9 | Untrusted input that reaches a URL is sanitised (`sanitizeUrl`), and untrusted HTML is sanitised (`DOMPurify`). |
| S-SEC-10 | Dependencies are audited in CI; a new high/critical advisory blocks the merge until triaged. |
| S-SEC-11 | Any deliberate security trade-off is recorded in `docs/security.md` with its rationale. |

---

## 12. Performance standards

| Ref | Rule |
| --- | --- |
| S-P-1 | The shell's own bundle stays under **250 KB gzipped**; CI reports the delta on every PR. |
| S-P-2 | Panes lazy-create their iframes on first activation, then keep them mounted. |
| S-P-3 | No blocking work on the main thread longer than 50ms. |
| S-P-4 | Sidebar lists render with virtual scrolling above 200 rows. |
| S-P-5 | Health polling backs off exponentially while healthy; it never polls faster than every 15s. |
| S-P-6 | Broker transfers are streamed; memory use must not scale with file size. |
| S-P-7 | Every new dependency is justified in the PR; prefer a small utility over a framework. |

---

## 13. Tooling configuration

| Tool | Config file | Scope |
| --- | --- | --- |
| ESLint (flat config) | `eslint.config.mjs` | **`src/**/*.{js,vue,ts}`** — and, new in Workcenter, `services/**/*.js`, `tests/**/*.js`, `e2e/**/*.ts`. Dashy lints only `src/`, leaving `services/` and `server.js` unlinted; Workcenter closes that gap. |
| TypeScript | `tsconfig.json` | `vue-tsc --noEmit` |
| Vitest | `vitest.config.mjs` | unit and integration tests (`happy-dom`, `globals: true`, setup file, `@` alias → `./src`) |
| Playwright | `e2e/playwright.config.ts` | end-to-end suite |
| ShellCheck | CI invocation | `setup.sh`, `scripts/**/*.sh` |
| Locale check | `tests/locales/check-locales.js` | fails on missing/extra locale files, code keys absent from `en.json`, unregistered locales |
| Spellcheck | `crate-ci/typos` (CI) | source and `en.json` |
| Dependency audit | `improved-yarn-audit --ignore-dev-deps` | runtime dependencies |
| Secret scanning | TruffleHog (CI) | every push and PR |

### Inherited ESLint posture

Workcenter keeps Dashy's flat ESLint config, including these inherited settings, and states them
explicitly so nobody "fixes" them by accident:

| Setting | Value | Why |
| --- | --- | --- |
| `no-console` | `off` | The server and scripts legitimately log; the frontend uses `ErrorHandler` by convention |
| `no-unused-vars` | `warn`, `argsIgnorePattern: '^_'` | Unused positional arguments are sometimes required by a signature |
| `vue/multi-word-component-names` | `off` | Short names like `Header` and `Footer` are inherited |
| `vue/no-v-html` | `warn`, `ignorePattern: '(?:^\|\\.)(sanitized\|safeHtml)'` | Sanitised HTML is sometimes required |
| `import-x/order`, `import-x/newline-after-import` | `warn` | Keeps import blocks readable |
| `import-x/no-duplicates` | `error` | — |
| `vue/html-indent`, `attributes-order`, `html-self-closing`, `order-in-components`, and ~13 other formatting rules | `off` | **Inherited as off.** Workcenter does not re-enable them in bulk; enable one at a time, with the codebase already conforming, in its own PR. |

### Required npm scripts

Yarn is the package manager; the scripts below are invoked as `yarn <script>`.

```jsonc
{
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview",
    "start": "node server",
    "lint": "eslint \"src/**/*.{js,vue,ts}\" \"services/**/*.js\" \"tests/**/*.js\" \"e2e/**/*.ts\"",
    "lint:fix": "yarn lint -- --fix",
    "lint:sh": "shellcheck setup.sh scripts/**/*.sh",
    "typecheck": "vue-tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "test:ui": "vitest --ui",
    "test:coverage": "vitest run --coverage",
    "test:e2e": "playwright test --config e2e/playwright.config.ts",
    "check-all": "yarn lint && yarn typecheck && yarn test && yarn validate-locales && yarn validate-config",
    "validate-locales": "node tests/locales/check-locales.js",
    "validate-config": "node services/utils/config-validator",
    "health-check": "node services/healthcheck",
    "dependency-audit": "npx improved-yarn-audit --ignore-dev-deps"
  }
}
```

> **Rule S-TL-1:** `yarn check-all` must pass before a PR is opened. It is the same gate CI runs.
> **Rule S-TL-2:** `validate-config` requires a valid `user-data/conf.yml`; CI supplies one from `tests/fixtures/valid-config.yml`.

---

## 14. Review standards

A reviewer checks, in order:

1. **Correctness** — does it do what the PR claims, including the failure paths?
2. **Scope** — is the change limited to what the PR describes?
3. **Requirements** — does it satisfy and cite the relevant requirement IDs?
4. **Tests** — do they exist, do they fail without the change, and are they deterministic?
5. **Security** — secrets, input validation, authorisation, TLS.
6. **Accessibility** — keyboard, focus, contrast, announcements.
7. **Standards** — this document; naming, structure, tokens, i18n.
8. **Documentation** — updated in the same PR, and accurate.
9. **Changelog** — an entry exists under `## [Unreleased]`.

A reviewer does not block on personal preference. If a rule is not written down and the linter does
not catch it, it is not a blocker — it is a suggestion, or a proposal to amend this document.

---

## 15. Compliance quick reference

Run before every push:

```bash
yarn check-all                                        # lint + typecheck + unit tests + locales + config
yarn test:coverage                                    # coverage floors
yarn test:e2e                                         # end-to-end (requires the test stack)
shellcheck setup.sh scripts/**/*.sh                   # shell scripts
docker compose -f compose.yaml config >/dev/null       # compose validity
docker compose -f compose.test.yaml config >/dev/null   # test profile validity
```

Every one of these is a required CI check on the `Dev` branch.

---

<p align="center"><sub>Workcenter standards · commit and branch discipline after <a href="https://github.com/gtsteffaniak/filebrowser">FileBrowser Quantum</a> · documentation style after <a href="https://github.com/lissy93/dashy">Dashy</a></sub></p>
