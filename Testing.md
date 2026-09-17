# Workcenter — Testing

> **Scope:** what is tested, how it is tested, the automated harness that brings the whole stack up
> with deterministic defaults, and the gates every merge into `Dev` must pass.
> **Companions:** [`contributions.md`](./contributions.md) · [`standards.md`](./standards.md) ·
> [`production.md`](./production.md) · [`integration.md`](./integration.md) · [`Agents.md`](./Agents.md)

---

## Table of contents

1. [Purpose and principle](#1-purpose-and-principle)
2. [Test pyramid](#2-test-pyramid)
3. [Tooling](#3-tooling)
4. [Unit and component tests](#4-unit-and-component-tests)
5. [Server and broker tests](#5-server-and-broker-tests)
6. [The end-to-end harness](#6-the-end-to-end-harness)
7. [Deterministic fixtures](#7-deterministic-fixtures)
8. [The Playwright suite](#8-the-playwright-suite)
9. [Running the tests](#9-running-the-tests)
10. [CI gates](#10-ci-gates)
11. [Coverage requirements](#11-coverage-requirements)
12. [Flake policy](#12-flake-policy)
13. [Reporting and artefacts](#13-reporting-and-artefacts)
14. [Testing without the full stack](#14-testing-without-the-full-stack)
15. [Release and promotion testing](#15-release-and-promotion-testing)
16. [Definition of tested](#16-definition-of-tested)

---

## 1. Purpose and principle

Workcenter is a **composition** of six systems. Its failure modes are overwhelmingly integration
failures: a redirect URI that does not match, a header that blocks framing, a source that is not
enabled for a user, a 25 MiB upload cap nobody knew about. Unit tests cannot catch any of those.

> **The governing principle: if a bug can only be caught by running the real stack, then the real
> stack must run automatically.**

That is what the end-to-end harness exists for. It brings the entire deployment up — Traefik,
Authentik, FileBrowser Quantum, OnlyOffice, Zulip and Mailcow — with **deterministic defaults**, and
drives it with Playwright, so a breaking integration is caught on the pull request that caused it
rather than by a user.

---

## 2. Test pyramid

```
                        ┌───────────────────────────────┐
                        │      End-to-end (Playwright)  │   ~30 specs
                        │  the whole stack, real HTTP,  │   minutes
                        │  real SSO, real file movement │
                        └───────────────┬───────────────┘
                                        │
                 ┌──────────────────────┴──────────────────────┐
                 │        Server & broker (Vitest+supertest)   │   ~120 tests
                 │  routes, OIDC verification, authorisation,  │   seconds
                 │  adapters against recorded fixtures         │
                 └──────────────────────┬──────────────────────┘
                                        │
   ┌────────────────────────────────────┴────────────────────────────────────┐
   │                     Unit & component (Vitest + happy-dom)               │   ~400 tests
   │   store modules, config pipeline, transfer engine, naming, audit, UI     │   seconds
   └─────────────────────────────────────────────────────────────────────────┘
```

| Level | Runs in | Must pass before |
| --- | --- | --- |
| Unit / component | Every commit, every PR | Merge |
| Server / broker | Every commit, every PR | Merge |
| End-to-end | Every PR into `Dev`; nightly on `Beta` and `Stable` | Merge into `Dev`; promotion |

---

## 3. Tooling

| Purpose | Tool | Config |
| --- | --- | --- |
| Unit, component and server tests | **Vitest 4** with `happy-dom` | `vitest.config.mjs` |
| Component mounting | `@vue/test-utils` (`shallowMount`) | — |
| HTTP assertions | `supertest` | — |
| Coverage | Vitest `v8` provider | `vitest.config.mjs` |
| End-to-end | **Playwright** | `e2e/playwright.config.ts` |
| Locale integrity | `node tests/locales/check-locales.js` | `yarn validate-locales` |
| Config integrity | `services/utils/config-validator` | `yarn validate-config` |
| Shell scripts | ShellCheck | CI invocation |
| Compose validity | `docker compose config` | CI invocation |

Workcenter keeps Workcenter's Vitest conventions exactly: `environment: 'happy-dom'`, `globals: true`, a
setup file at `tests/setup.js`, `@` aliased to `./src`, and an explicit
`import { describe, it, expect } from 'vitest'` in every test file.

---

## 4. Unit and component tests

### 4.1 Layout

```
tests/
├── setup.js                 # localStorage / sessionStorage / matchMedia shims; console.info silenced
├── fixtures/
│   ├── valid-config.yml     # a schema-valid conf.yml
│   └── *.json               # recorded API payloads
├── unit/                    # pure modules
│   ├── apps-registry.test.js
│   ├── transfer-naming.test.js
│   ├── config-helpers.test.js
│   ├── theming.test.js          # mode state, cookie, pane message, default
│   ├── languages.test.js        # locale registry and per-application mapping
│   └── …
├── components/              # Vue components
│   ├── app-switcher.test.js
│   ├── app-sidebar.test.js
│   ├── pane-host.test.js
│   ├── theme-switcher.test.js
│   ├── language-switcher.test.js
│   └── …
└── server/                  # Express + broker, node environment
    ├── broker-auth.test.js
    ├── broker-transfers.test.js
    ├── broker-preferences.test.js
    ├── oidc-verify.test.js
    └── health.test.js
```

### 4.2 What must be unit-tested

| Area | Examples |
| --- | --- |
| **Application registry** | The three applications exist; their URLs derive correctly from the base domain; `appConfig.applications` cannot drift from `registry.js` |
| **Store modules** | `SET_ACTIVE_APP` preserves pane state; sidebar cache TTL and invalidation |
| **Transfer engine** | Streaming, size cap, cancellation, atomic rename, content-hash de-duplication, collision naming (`report (2).pdf`) |
| **Broker authorisation** | User A can never read user B's source, mailbox or chat identity |
| **Adapters** | FileBrowser, Mail and Zulip adapters against recorded fixtures — including the Zulip 25 MiB boundary that selects `/api/v1/tus` |
| **Config pipeline** | A missing key falls back to its default; an unknown key in `config.yaml` is rejected |
| **Theming** | Dark is the default with no stored preference; a switch sets `data-wc-mode`, writes the `wc_mode` cookie with `Secure`/`SameSite=Lax` and no identity in its value, and posts `workcenter:mode` to each pane **with that pane's exact origin**, never `'*'` |
| **Theme bridge** | The broker fan-out calls FileBrowser with `{"which":["darkMode"]}` and Zulip with `color_scheme` 2/3; an application without a preference surface reports `unsupported` rather than failing; one failing application does not prevent the others; the bridge is advisory and never overwrites a user's explicit in-app choice |
| **Pane refresh** | The Files pane refreshes only after a `204`, restores the path last reported by `filebrowser:navigation`, and is **deferred** while the pane is in an editor (D-T7). Zulip and SOGo are never refreshed for a mode change |
| **Preference route** | `POST /api/broker/preferences` acts only on the caller from the verified token and ignores any user identifier in the body (AR-47) |
| **Language** | The registry maps one shell locale to FileBrowser's key, Zulip's code and a flag glyph; a language with no mapping is still offered; changing language never changes the mode |
| **i18n** | Every `$t('…')` key used in code exists in `en.json` (`yarn validate-locales`) |

### 4.3 Conventions

| Rule | Detail |
| --- | --- |
| Explicit imports | `import { describe, it, expect } from 'vitest'` — do not rely on `globals` |
| Behaviour test names | `it('saves report.pdf as report (2).pdf when the name is taken')` |
| Fixture factories | `const item = (over = {}) => ({ ...defaults, ...over })` |
| Shallow mounting | `shallowMount` plus a real `createStore`; never a full mount |
| Mock every boundary | `vi.mock('@/utils/request')`, `vi.mock('@/router')`, `vi.mock('@/utils/logging/ErrorHandler')` |
| No network | Unit tests never touch the internet |

---

## 5. Server and broker tests

Server tests run in Node, not happy-dom, and drive the real Express app.

```js
// @vitest-environment node
import { describe, it, expect, beforeAll } from 'vitest';
import request from 'supertest';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

process.env.USER_DATA_DIR = mkdtempSync(join(tmpdir(), 'wc-test-'));
const app = require('../../services/app');
```

### 5.1 What must be server-tested

| Area | Assertion |
| --- | --- |
| **OIDC verification** | A token signed by the test issuer is accepted; a wrong `aud`, a wrong `iss`, an expired token and a token with no signature are each rejected |
| **Authorisation** | Every broker route refuses an unauthenticated request and a request from the wrong user |
| **Health** | `/healthz` returns `{status:'ok'}` with `Cache-Control: no-store` |
| **Broker transfer routes** | Input validation rejects a missing/invalid path before any adapter is called |
| **Secret handling** | No route echoes a secret; no log line contains one (asserted on captured output) |
| **Config validation** | An invalid `conf.yml` fails startup with a readable error |

---

## 6. The end-to-end harness

### 6.1 Goal

Bring the **entire stack** up on a single machine, with deterministic defaults, no internet
dependency, and no manual steps — then drive it with Playwright.

### 6.2 The test compose profile

`compose.test.yaml` composes the same services as production with test-appropriate settings:

| Aspect | Production | Test profile |
| --- | --- | --- |
| Domain | a real domain | `*.wc.test`, resolved by hosts entries or a local resolver |
| TLS | Let's Encrypt (HTTP-01) | A committed test CA, or Traefik's internal self-signed certificate |
| Traffic source | the internet | **No outbound network** — Mailcow's `netfilter`, `acme`, `watchdog` and `dockerapi` are disabled, and Zulip's outbound email is redirected to a local sink |
| Secrets | generated by `setup.sh` | fixed, committed **test-only** values, clearly marked as such |
| Users | real Authentik users | a seeded test user set |
| Data | real | seeded fixtures ([§7](#7-deterministic-fixtures)) |
| Mailcow | full 18 containers | the subset needed for Mail: `nginx`, `php-fpm`, `sogo`, `dovecot`, `postfix`, `mysql`, `redis`, `memcached` |
| Certificates | real | a fixed test certificate so browser trust is stable |

```bash
docker compose -f compose.test.yaml up -d --wait
```

> **Rule T-6.1:** the test profile must be **hermetic**. A test that requires an outbound internet
> connection is a broken test. Outbound edges — SMTP delivery, ACME, the Zulip push service — are all
> stubbed or disabled.

> **Rule T-6.2:** test secrets are committed **only** in the test profile, are obviously fake
> (`test-only-not-a-secret-…`), and are never valid anywhere else.

### 6.3 Bring-up sequence

The harness brings services up in dependency order and waits for real health, not for a sleep:

```
1. proxy network
2. Traefik                       → wait: /ping returns 200
3. Authentik (postgresql, server, worker)
                                 → wait: /-/health/ready/
4. Authentik bootstrap           → seed: groups, scope mappings, the five providers,
                                          the five applications, the two test users
                                 → wait: the discovery document is reachable
5. FileBrowser Quantum + OnlyOffice
                                 → wait: /health, /healthcheck
6. Zulip (database, memcached, rabbitmq, redis, zulip)
                                 → wait: /health from an address in LOADBALANCER_IPS
                                 → seed: the broker bot, the test channels, a message with an attachment
7. Mailcow subset                → wait: nginx 200 on /
                                 → seed: the mail domain, the test mailboxes, one mail with an attachment
8. Workcenter (shell + broker)   → wait: /healthz
9. Seed the file source          → deterministic files for the picker tests
```

| Ref | Rule |
| --- | --- |
| T-6.3 | Waiting is **health-based**, never `sleep`. `docker compose up -d --wait` plus per-service probes. |
| T-6.4 | Seeding is **idempotent**: running the harness twice converges, and a re-run does not duplicate users, channels or mail. |
| T-6.5 | The harness must be able to run from a clean checkout with a single command, with no manual browser step. |
| T-6.6 | Authentik's provider seeding uses its **API** with the bootstrap token — not the Web UI. This is what makes the E2E suite possible at all, and it is the automation that [`OIDC.md`](./OIDC.md) documents manually for operators. |

### 6.4 Teardown

```bash
docker compose -f compose.test.yaml down          # keeps volumes; fast restart
docker compose -f compose.test.yaml down -v       # full reset; used by CI
```

CI always uses `-v` so every run starts clean.

---

## 7. Deterministic fixtures

Every test run must be byte-identical at the start.

### 7.1 Users

| Username | Password | Groups | Purpose |
| --- | --- | --- | --- |
| `admin@wc.test` | fixed test password | `workspaceusers`, `workspaceadmin` | Admin-path tests |
| `user@wc.test` | fixed test password | `workspaceusers` | Normal-path tests |
| `outsider@wc.test` | fixed test password | *(none)* | Denied-access tests |

### 7.2 Files (in the FileBrowser source)

| Path | Size | Purpose |
| --- | --- | --- |
| `/documents/report.pdf` | 12 KB | Attachment save/open tests |
| `/documents/notes.docx` | 24 KB | OnlyOffice editing test |
| `/documents/large.bin` | **26 MiB** | Forces the Zulip `/api/v1/tus` path |
| `/documents/small.txt` | 1 KB | Zulip small-upload path |
| `/documents/report.pdf` *(duplicate content)* | — | De-duplication test |

### 7.3 Mail

| Fixture | Purpose |
| --- | --- |
| One message in `user@wc.test`'s inbox with a PDF attachment | **F1** (save attachment to files) and the attachment-list test |
| One empty draft | **F2** (attach from files) |

### 7.4 Chat

| Fixture | Purpose |
| --- | --- |
| Channel `workcenter-test` | Message and upload target |
| One message carrying a text attachment | **F3** (save Zulip attachment to files) |
| The broker bot, subscribed and able to post | **F4** (send file to Zulip) |

### 7.5 Rules

| Ref | Rule |
| --- | --- |
| T-7.1 | Fixtures contain **no real personal data, credentials or customer content**. Names, addresses and file contents are obviously synthetic. |
| T-7.2 | Fixture content is generated deterministically (fixed seeds), so hashes and byte counts are stable. |
| T-7.3 | The seeded `26 MiB` file exists specifically to exercise the Zulip upload cap boundary — do not shrink it. |
| T-7.4 | Fixtures are created through the **applications' own APIs**, not by writing into their databases. |

---

## 8. The Playwright suite

### 8.1 Layout

```
e2e/
├── playwright.config.ts
├── specs/
│   ├── auth.spec.ts             # OIDC sign-in, groups, admin badge, logout
│   ├── switcher.spec.ts         # three buttons, keyboard shortcuts, accents, aria-current
│   ├── sidebar.spec.ts          # sidebar swaps per application; search filters
│   ├── panes.spec.ts            # panes load, stay mounted, deep links, error cards
│   ├── framing.spec.ts          # each pane renders real application content
│   ├── transfer-mail-to-files.spec.ts     # F1
│   ├── transfer-files-to-mail.spec.ts     # F2
│   ├── transfer-zulip-to-files.spec.ts    # F3
│   ├── transfer-files-to-zulip.spec.ts    # F4
│   ├── zulip-large-upload.spec.ts         # the >25 MiB tus path
│   ├── status-indicators.spec.ts # per-application indicators in the switcher
│   ├── admin.spec.ts            # Traefik dashboard allowed for admin, denied for user
│   ├── theme.spec.ts            # the shell's own light/dark switch
│   ├── theme-bridge.spec.ts     # the switch reaches all three embedded applications
│   ├── language.spec.ts         # language in use, flag menu, forwarding
│   ├── branding.spec.ts         # the applications carry Workcenter's name, logo and palette
│   └── a11y.spec.ts             # keyboard traversal, focus visibility, contrast spot checks
├── fixtures/
└── support/
    ├── login.ts                 # reusable OIDC sign-in helper
    ├── seed.ts                  # fixture setup helpers
    └── assertions.ts            # pane-loaded / transfer-complete assertions
```

### 8.2 Configuration

```ts
// e2e/playwright.config.ts
export default defineConfig({
  testDir: './specs',
  timeout: 60_000,
  expect: { timeout: 10_000 },
  fullyParallel: false,          // the stack is shared state
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,
  reporter: process.env.CI
    ? [['html', { open: 'never' }], ['github'], ['json', { outputFile: 'results.json' }]]
    : [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.WORKCENTER_URL ?? 'https://example.com.wc.test',
    ignoreHTTPSErrors: true,     // the test CA
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    viewport: { width: 1440, height: 900 },
  },
});
```

### 8.3 Spec requirements

Every spec header cites the requirement IDs it asserts, so a failure points straight at the
specification:

```ts
/**
 * Requirements: G3, B-2, B-4, I-X-1, I-MC-7a
 * Flow F1 — save a SOGo mail attachment into the user's FileBrowser source.
 */
test.describe('F1 — mail attachment to files', () => {
  test('saves the attachment and links to the destination folder', async ({ page }) => {
    await login(page, 'user@wc.test');
    await page.getByRole('tab', { name: 'Mail' }).click();
    // …
  });
});
```

### 8.3a Asserting *inside* a pane

The mode-switch specs only mean something if they observe the **embedded application**, not
Workcenter's own state. Asserting that the shell wrote a preference proves nothing about what the
user sees in the pane.

Playwright drives the browser through CDP rather than through page script, so it reads a
cross-origin iframe directly — `frameLocator()` crosses the origin boundary that `postMessage` exists
to work around. The assertion is therefore the real DOM of the real application:

| Pane | The thing to assert | Why that specific thing |
| --- | --- | --- |
| Files | `dark-mode` present on, or absent from, the frame's `<html>` | It is the class FileBrowser Quantum itself toggles; nothing else sets it |
| Chat | `dark-theme` on the frame's `:root` | It is the class Zulip's own `theme` module sets when it processes the `user_settings` event |
| Mail | `data-wc-mode` on the frame's `<html>`, **plus** a changed computed background colour | SOGo has no theme of its own, so the attribute alone would only prove Workcenter's script ran — the colour proves the stylesheet applied |

| Ref | Requirement |
| --- | --- |
| T-8.4 | A mode or language spec asserts the state of the **application** inside the pane. A spec that stops at the shell's `data-wc-mode`, at `localStorage`, or at a 200 response does not satisfy the requirement. |
| T-8.5 | The Chat assertion runs **without reloading the frame**, because "changed without a reload" is the behaviour being tested. Reloading first would pass even if the live path were broken. |
| T-8.6 | Where an application's stored preference is also checked (FileBrowser's `darkMode`, Zulip's `color_scheme`), it is checked **in addition to** the DOM, never instead of it — a stored value that the UI ignores is exactly the failure this suite exists to catch. |
| T-8.7 | Every mode spec runs in **both directions** (dark → light → dark) and asserts the starting state, so a pane that was already in the target mode cannot produce a false pass. |
| T-8.8 | The partial-failure spec stops one application's container and asserts the shell still switches, the remaining applications still change, and the failure is named in the UI. A silent failure is a test failure. |



| # | Area | Assertion |
| --- | --- | --- |
| 1 | **Authentication** | A `workspaceusers` member signs in once and reaches all three panes; an outsider is denied; an admin sees the admin badge |
| 2 | **Switcher** | Three buttons; the active one carries the accent and `aria-current`; `Alt+1/2/3` switch; the sidebar body changes with the application. Each button has exactly one status indicator directly beneath it, plus a centred `STATUS` label |
| 3 | **Pane persistence** | Typing in one pane, switching away and back preserves the input — proving the pane was not reloaded |
| 4 | **Deep links** | `/#/files`, `/#/chat`, `/#/mail` restore the right pane on reload |
| 5 | **Framing** | Each pane renders **real application content**, not an error page. This is the assertion that catches a Zulip header regression |
| 6 | **FileBrowser source** | A newly created OIDC user sees a populated tree (`config.defaultEnabled`) |
| 7 | **OnlyOffice** | A `.docx` opens in the editor |
| 8 | **F1** | A mail attachment lands in the source; a duplicate gets a de-duplicated name; the success toast links to the folder |
| 9 | **F2** | A source file attaches to a draft with its real filename and size |
| 10 | **F3** | A Zulip attachment lands in the source |
| 11 | **F4** | A source file uploads and its Markdown link is inserted into the message |
| 12 | **Large upload** | A 26 MiB file succeeds via `/api/v1/tus` (proving the 25 MiB boundary is handled) |
| 13 | **Transfer failure** | A cancelled or failed transfer leaves **no residue** in the source |
| 14 | **Status indicators** | All three indicators report healthy beneath their respective buttons; stopping a service flips its indicator and shows the diagnostic card; clicking a non-healthy indicator does not change the active application |
| 15 | **Admin surfaces** | Admin reaches the Traefik dashboard; a normal user is denied |
| 16 | **Cascade** | A pane that cannot load shows the error card with **Retry** and **Open in new tab** — never a blank frame |
| 17 | **Mode, shell** | Dark is what a fresh user gets; the user menu labels it as the default; switching repaints the shell with no page reload and no full pane remount |
| 18 | **Mode → Files** | After switching to light, FileBrowser's stored `darkMode` is `false` **and** the Files frame's `<html>` has lost the `dark-mode` class. Switching back restores both |
| 19 | **Mode → Chat** | After switching, `:root` inside the Chat frame gains or loses `dark-theme` — asserted **without reloading the frame**, which is what proves Zulip's live event path is being used |
| 20 | **Mode → Mail** | After switching, `<html data-wc-mode>` inside the Mail frame matches the shell, and SOGo's computed background colour changes — the proof that the supplied stylesheet, not a SOGo feature, is doing the work |
| 21 | **Mode, state preserved** | Text typed into the Chat and Mail panes survives a mode switch; the Files pane refresh returns to the same path; a mode switch while a document editor is open defers the Files refresh and does not lose the document |
| 22 | **Mode, partial failure** | With one application stopped, the shell still switches, the other two still change, and the user menu names the one that did not |
| 23 | **Language** | The row shows the language in use in its own language; the flag button opens the menu; choosing German translates the shell, sets `<html lang>`, and updates the stored locale in FileBrowser and Zulip |
| 24 | **Branding** | Each application shows the Workcenter name and logo, and its background matches the palette for the active mode |
| 25 | **Keyboard** | The rail and switcher are fully traversable; focus is always visible |

> **Rule T-8.1:** every spec asserts something a **user** can observe. A spec that only checks that a
> request returned 200 belongs in the server tests.
>
> **Rule T-8.2:** a spec that touches an integration must have a **negative** counterpart — the
> failure path, not just the happy path.
>
> **Rule T-8.3:** no `waitForTimeout`. Wait on a state, a response or an element.

---

## 9. Running the tests

### 9.1 Unit and component

```bash
yarn test                 # one run
yarn test:watch           # watch mode
yarn test:ui              # Vitest UI
yarn test:coverage        # with the coverage report
```

### 9.2 Server

```bash
yarn test tests/server    # or simply yarn test
```

### 9.3 End-to-end

```bash
# 1. Bring the stack up
cp .env.test.example .env.test
docker compose -f compose.test.yaml up -d --wait

# 2. Seed fixtures
./scripts/seed-test-fixtures.sh

# 3. Run the suite
yarn test:e2e

# 4. Inspect a failure
yarn playwright show-report e2e/playwright-report

# 5. Tear down
docker compose -f compose.test.yaml down -v
```

A convenience script wraps all of it:

```bash
./scripts/e2e.sh            # up → seed → test → report; leaves the stack up on failure
./scripts/e2e.sh --clean    # tear down first
./scripts/e2e.sh --down     # tear down afterwards
```

### 9.4 Everything at once

```bash
yarn check-all              # lint + typecheck + unit + locales + config
```

---

## 10. CI gates

Every gate below is **required** on pull requests into `Dev`.

| # | Gate | Command | Trigger |
| --- | --- | --- | --- |
| 1 | **Lint** | `yarn lint` | always |
| 2 | **Typecheck** | `yarn typecheck` | always |
| 3 | **Unit + component + server tests** | `yarn test` | always |
| 4 | **Locale check** | `yarn validate-locales` | always |
| 5 | **Config validation** | `yarn validate-config` | always |
| 6 | **Build check** | `yarn build` and verify `dist/` exists | always |
| 7 | **ShellCheck** | `shellcheck setup.sh scripts/**/*.sh` | `setup.sh`/`scripts/**` changed |
| 8 | **Compose validity** | `docker compose -f compose.yaml config` and `-f compose.test.yaml config` | compose files changed |
| 9 | **End-to-end (Playwright)** | `./scripts/e2e.sh` | always on PRs into `Dev` |
| 10 | **Docker build** | build the Workcenter image | `Dockerfile`, `package.json` changed |
| 11 | **Dependency audit** | `yarn dependency-audit` | dependency files changed |
| 12 | **Secret scanning** | TruffleHog | always |

### 10.1 Scheduled runs

| Schedule | Job |
| --- | --- |
| Nightly | Full E2E on `Beta` |
| Nightly | Full E2E on `Stable` |
| Weekly | Dependency audit and image vulnerability scan |
| On promotion | Full E2E, required, before the merge |

### 10.2 The E2E gate in CI

The harness runs inside the CI runner with Docker available:

```yaml
# .github/workflows/e2e.yml (shape)
name: e2e
on:
  pull_request:
    branches: [Dev]
jobs:
  e2e:
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4
      - name: Bring up the stack
        run: docker compose -f compose.test.yaml up -d --wait
      - name: Seed fixtures
        run: ./scripts/seed-test-fixtures.sh
      - name: Run Playwright
        run: yarn test:e2e
      - name: Upload artefacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: playwright-artifacts
          path: |
            e2e/playwright-report
            e2e/test-results
      - name: Service logs on failure
        if: failure()
        run: docker compose -f compose.test.yaml logs --no-color > service-logs.txt
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: service-logs
          path: service-logs.txt
      - name: Tear down
        if: always()
        run: docker compose -f compose.test.yaml down -v
```

> **Rule T-10.1:** a red E2E gate **blocks** the merge into `Dev`. It is not advisory.
> **Rule T-10.2:** a red E2E gate on `Dev` blocks **every** other merge until it is fixed.

---

## 11. Coverage requirements

| Path | Minimum line coverage |
| --- | --- |
| `src/broker/**` | **80%** |
| `services/utils/**` (including broker adapters and the transfer engine) | **80%** |
| `src/utils/**` | **70%** |
| `src/components/**` | **70%** |
| Deployment files, compose, `setup.sh` | exempt (covered by the E2E harness) |

```bash
yarn test:coverage      # text + json + html reports
```

| Ref | Rule |
| --- | --- |
| T-11.1 | Coverage must not **decrease** in a PR. A drop requires justification in the PR description. |
| T-11.2 | Coverage is a floor, not a goal. A test that asserts nothing to raise the number is worse than no test. |
| T-11.3 | The authorisation paths in the broker are held to 100% branch coverage. They are the security boundary. |

---

## 12. Flake policy

A flaky suite is worse than no suite, because it teaches people to ignore red.

| Ref | Rule |
| --- | --- |
| T-12.1 | **A flaky test is fixed or deleted.** It is never retried into silence. |
| T-12.2 | `retries: 1` in CI exists to absorb genuine infrastructure timing, not to mask a race. A test that only passes with a retry is filed as a bug. |
| T-12.3 | Any test that fails intermittently is quarantined within one working day: moved to `e2e/quarantine/`, excluded from the gate, and given an issue. Quarantine is temporary and tracked. |
| T-12.4 | No `waitForTimeout`, no arbitrary sleeps, no reliance on wall-clock ordering. Wait on state. |
| T-12.5 | Tests must be order-independent. `fullyParallel` is off because the stack is shared, so no spec may depend on another having run first. |
| T-12.6 | Fixtures are reset between runs, so a test never depends on residue from a previous one. |

---

## 13. Reporting and artefacts

On every run — pass or fail — CI uploads:

| Artefact | Contents |
| --- | --- |
| `playwright-report/` | HTML report with traces |
| `test-results/` | Traces, screenshots and videos for failures |
| `service-logs.txt` | `docker compose logs` for the whole stack, **failure only** |
| `coverage/` | Vitest coverage report |

### 13.1 Failure triage order

1. Open the Playwright report and read the failing assertion.
2. Watch the trace — it shows the DOM, network and console at the moment of failure.
3. Check `service-logs.txt` for the application the spec was driving.
4. Reproduce locally with `./scripts/e2e.sh --clean`.
5. If it reproduces, fix it. If it does not, it is a flake: quarantining it is a valid, expected action.

### 13.2 Writing a good failure message

```ts
await expect(pane).toHaveAttribute('data-pane-state', 'ready', {
  message: 'Chat pane did not reach "ready" — check the Zulip framing header (I-ZU-9)',
});
```

---

## 14. Testing without the full stack

The full stack takes minutes and several gigabytes. Most changes do not need it.

| You are changing | Run |
| --- | --- |
| A store module, utility or config helper | `yarn test` |
| A Vue component's logic | `yarn test tests/components` |
| A broker adapter | `yarn test tests/server` |
| A route or middleware | `yarn test tests/server` |
| A label, colour, spacing or icon | `yarn dev` and look at it; the E2E gate covers regressions |
| Anything touching an integration | **the full harness** — do not skip it |
| `setup.sh` or a compose file | The harness, plus a three-run idempotency check |

### 14.1 Idempotency check

```bash
./setup.sh --base-domain wc.test --non-interactive
./setup.sh --base-domain wc.test --non-interactive   # must make no change
./setup.sh --base-domain wc.test --non-interactive   # must still make no change
./setup.sh --brand                                   # must also make no change
git status --porcelain                               # must be empty apart from gitignored files
```

The `--brand` run is included deliberately: branding writes into files the applications own, so it is
the stage most likely to append twice, duplicate a block or rewrite a file it has already written
(P-29, P-31).

### 14.2 Testing stubs

For developing broker behaviour without any stack, adapters accept injected transports, so a test can
substitute a recorded fixture:

```js
const files = createFilesAdapter({ root: tmpSourceDir, fs: memfs });
const chat  = createChatAdapter({ transport: replayingTransport('fixtures/zulip-upload.json') });
```

| Ref | Rule |
| --- | --- |
| T-14.1 | Adapters must remain injectable. A change that makes an adapter require a live service breaks the unit suite and will be rejected. |

---

## 15. Release and promotion testing

| Stage | Required |
| --- | --- |
| Merge into `Dev` | The full gate set in [§10](#10-ci-gates) |
| Promote `Dev` → `Beta` | The full E2E suite green on `Dev`, plus a clean `setup.sh` run on a disposable host |
| `Beta` soak | Nightly E2E for the agreed window |
| Promote `Beta` → `Stable` | E2E green on `Beta`; a fresh-host Quick Start completed end to end; the production checklist in [`production.md` §16](./production.md#16-production-checklist) walked through |
| Release | Images published with an SBOM; a restore drill recorded |

> **Rule T-15.1:** no promotion with a failing or quarantined-and-unresolved E2E suite.

---

## 16. Definition of tested

A change is tested when **all** of the following hold:

- [ ] Unit, component or server tests cover the new behaviour.
- [ ] A bug fix ships with a regression test that fails before the fix.
- [ ] Coverage floors in [§11](#11-coverage-requirements) are met, with no decrease.
- [ ] A user-visible change has a Playwright spec asserting it, plus a negative case.
- [ ] The spec header cites the requirement IDs it asserts.
- [ ] The full E2E suite passes on the PR into `Dev`.
- [ ] No new flake was introduced, and no existing test was weakened or deleted to pass.
- [ ] Fixtures remain synthetic and deterministic.
- [ ] If the change touches `setup.sh` or a compose file, the three-run idempotency check passes.
- [ ] If the change touches appearance, language or branding, the assertion is made **inside the pane**, against the embedded application's own DOM (T-8.4).

---

<p align="center"><sub>Workcenter testing · Playwright against the whole stack, on every PR into <code>Dev</code></sub></p>
