# Contributing to Workcenter

Thank you for considering a contribution. Workcenter is a self-hosted workspace application that
brings **FileBrowser Quantum**, **Zulip** and **SOGo on Mailcow** into one page with one sign-in and
one set of cross-application file actions. It is a derivative of [Dashy](https://github.com/lissy93/dashy).

This guide is the **process** document: how to set up, how to branch, how to raise a pull request, how
it is reviewed, and how a release reaches `Stable`.

> **The version-control and pull-request standard for this repository is
> [FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser)'s.** Its
> [feature-development guide](https://filebrowserquantum.com/en/docs/contributing/features/feature-development/)
> and its promotion workflows (`create-dev-branch`, `promote-dev-to-beta`) are the model Workcenter
> follows, adapted to the branch names in [§3](#3-branching-model). Where this document and FileBrowser
> Quantum disagree, **this document wins**, because Workcenter has three branches rather than four.

| Companion documents |
| --- |
| [`standards.md`](./standards.md) — coding, naming, commit and documentation rules |
| [`Agents.md`](./Agents.md) — the same rules for AI coding agents |
| [`Testing.md`](./Testing.md) — what tests a PR must carry |
| [`architecture.md`](./architecture.md) — where code lives |
| [`design.md`](./design.md) — UI conventions and the design review checklist |
| [`CHANGELOG.md`](./CHANGELOG.md) — the running log of changes |
| [`production.md`](./production.md) — deployment and `setup.sh` |
| [`OIDC.md`](./OIDC.md) — authentication setup |

---

## Table of contents

1. [Ways to contribute](#1-ways-to-contribute)
2. [Prerequisites](#2-prerequisites)
3. [Branching model](#3-branching-model)
4. [Development setup](#4-development-setup)
5. [Making a change](#5-making-a-change)
6. [Testing your change](#6-testing-your-change)
7. [The running log of changes](#7-the-running-log-of-changes)
8. [Pull-request guide](#8-pull-request-guide)
9. [Review process](#9-review-process)
10. [Promotion and release](#10-promotion-and-release)
11. [Commit format](#11-commit-format)
12. [Contributing to the documentation](#12-contributing-to-the-documentation)
13. [Contributing to the deployment](#13-contributing-to-the-deployment)
14. [Reporting bugs](#14-reporting-bugs)
15. [Requesting features](#15-requesting-features)
16. [Becoming a maintainer](#16-becoming-a-maintainer)
17. [Code of conduct](#17-code-of-conduct)
18. [Licence and attribution](#18-licence-and-attribution)

---

## 1. Ways to contribute

| Contribution | Where it goes | Weight |
| --- | --- | --- |
| Bug fix | PR into `Dev` | Small, always welcome |
| Regression test for an existing bug | PR into `Dev` | Very welcome — a failing test is a complete contribution |
| Documentation correction | PR into `Dev` | Very welcome |
| New integration capability (a fifth flow, a new adapter) | PR into `Dev`, after an issue is agreed | Medium |
| New UI element in the shell | PR into `Dev`, with design review | Medium |
| Deployment improvement (`compose.yaml`, `setup.sh`, Traefik labels) | PR into `Dev`, with a dry-run on a disposable host | Medium |
| New integrated application pane | PR into `Dev`, **after a roadmap change is agreed** | Large |
| Translations | PR into `Dev` adding a locale JSON | Small |
| Theme | PR into `Dev` adding a theme partial | Small |
| Security report | **Private** — see [`SECURITY.md`](../.github/SECURITY.md) | — |

> **Not accepted:** PRs that reintroduce a removed Dashy subsystem (Default view, Minimal view,
> widgets, status/ping monitoring), PRs that fork and patch a bundled application, and PRs that weaken
> authentication, TLS or authorisation.

---

## 2. Prerequisites

### To work on the shell (most contributions)

| Requirement | Version | Check |
| --- | --- | --- |
| Node.js | 24.x (minimum `^22.18.0`) | `node --version` |
| Yarn | 1.22.22 (Classic) | `yarn --version` |
| Git | any recent | `git --version` |

### To work on the deployment or the broker

Everything above, plus:

| Requirement | Version | Check |
| --- | --- | --- |
| Docker Engine | 24+ | `docker --version` |
| Docker Compose | v2.20+ | `docker compose version` |
| Bash | 5+ | `bash --version` |
| ShellCheck | latest | `shellcheck --version` |

### Optional tools

| Tool | For |
| --- | --- |
| OpenSSL | Generating secrets exactly as `setup.sh` does |
| A disposable Linux host or VM | Dry-running `setup.sh` and the full stack |
| Postman / `curl` | Exercising the broker API directly |

A full local stack needs **at least 8 GB RAM and 4 vCPU** (Zulip alone wants 2 GB, OnlyOffice 2 GB).
Most contributions do not need the full stack — the shell runs with `yarn dev` and a stub config.

---

## 3. Branching model

Workcenter uses **three long-lived branches**, promoted in one direction only.

```
                 ┌──────────────────────────────────────────────────────────────┐
                 │                                                              │
  feature/*      │   pull request        promotion        promotion             │
  fix/*     ─────┼──▶  Dev  ──────────▶  Beta  ──────────▶  Stable  ──────────▶ releases
  docs/*         │   (default PR         (E2E verified)     (GitHub default      (tags,
  chore/*        │    target)                               branch, production)   images)
                 │                                                              │
                 └──────────────────────────────────────────────────────────────┘
```

| Branch | Role | Default? |
| --- | --- | --- |
| **`Dev`** | **The default target for every pull request.** Integration branch. May be temporarily broken between merges. | Default **PR base** |
| **`Beta`** | Promoted from `Dev` once the E2E suite is green. Release candidates. | — |
| **`Stable`** | Promoted from `Beta`. **The GitHub default branch** and the source of production images and tags. | GitHub default |

### The rules

| Ref | Rule |
| --- | --- |
| C-3.1 | **All PRs merge into `Dev`.** Never open a feature PR against `Beta` or `Stable`. |
| C-3.2 | Promotion is strictly `Dev → Beta → Stable`, one step at a time, each with a green E2E run. |
| C-3.3 | Bug fixes for `Beta` or `Stable` go through the same `Dev → Beta → Stable` path. Fix forward; do not branch off a release. |
| C-3.4 | **The only exception:** non-functional changes (documentation, workflow configuration, issue templates) may target `Beta` or `Stable` directly, with maintainer approval recorded in the PR. |
| C-3.5 | `Stable` is the default branch, so a fresh `git clone` gives you production code. **Switch to `Dev` before you start work.** |
| C-3.6 | Promotion is performed by maintainers using the `promote.yml` workflow with a semantic version argument (`X.Y.Z`), mirroring FileBrowser Quantum's `promote-dev-to-beta` workflow. |
| C-3.7 | Never force-push a long-lived branch. Never rewrite published history. |
| C-3.8 | Release branches, if ever needed for a hotfix, are named `hotfix/vX.Y.Z` and merge back into `Dev` as well as the release branch. |

### Branch naming

| Prefix | Use |
| --- | --- |
| `feat/<short-description>` | A new capability |
| `fix/<short-description>` | A defect fix |
| `docs/<short-description>` | Documentation only |
| `chore/<short-description>` | Build, tooling, dependencies |
| `refactor/<short-description>` | Behaviour-preserving restructure |
| `test/<short-description>` | Tests only |

Use kebab-case, keep it under 50 characters, and describe the change rather than the ticket:
`feat/application-switcher`, not `feat/issue-42`.

---

## 4. Development setup

### 4.1 Clone and branch

```bash
# 1. Clone
git clone https://github.com/<your-org>/workcenter.git
cd workcenter

# 2. Stable is the default branch — switch to the integration branch
git checkout Dev
git pull origin Dev

# 3. Create your branch
git checkout -b feat/application-switcher
```

### 4.2 Install and run the shell

```bash
yarn install --frozen-lockfile

# Development server with hot reloading on http://localhost:8080
yarn dev
```

The dev server serves `user-data/` directly, so edits to `user-data/conf.yml` are picked up without a
rebuild. If you need a config that differs from the committed one, copy it and point the app at it:

```bash
cp user-data/conf.yml user-data/conf.local.yml
VITE_APP_CONFIG_PATH=/conf.local.yml yarn dev
```

### 4.3 Run the whole stack locally

Some changes (integration wiring, OIDC, the broker, deployment) need real services. Use the test
profile, never a real deployment:

```bash
cp .env.example .env          # fill in the minimum values
docker compose -f compose.test.yaml up -d
docker compose -f compose.test.yaml ps      # wait for every service to be healthy
```

Tear it down **without** deleting volumes unless you mean to:

```bash
docker compose -f compose.test.yaml down          # keeps volumes
```

### 4.4 First-run checklist for a new contributor

```bash
git checkout Dev && git pull
yarn install --frozen-lockfile
yarn check-all            # lint + typecheck + tests + locales + config
yarn dev                  # confirm the shell loads
```

If `yarn check-all` fails on a clean `Dev`, that is a bug — please open an issue.

### 4.5 Project architecture (the short version)

| Area | Path | What lives there |
| --- | --- | --- |
| Shell UI | `src/` | Vue 3 SPA: switcher, sidebars, panes |
| Broker | `services/utils/broker/`, `services/broker-server.js` | Cross-application file movement, OIDC-protected |
| Server | `server.js`, `services/app.js` | Express 5: static assets, config API, health |
| Unit tests | `tests/` | Vitest |
| E2E tests | `e2e/` | Playwright |
| Integrated apps | `Filebrowser/`, `Zulip/`, `Mailcow/`, `OnlyOffice/`, `Authentik/`, `Traefik/` | One folder per application; config, secrets and volumes inside |
| Orchestration | `compose.yaml`, `setup.sh` | One root composition and one bootstrap script |

Full breakdown: [`architecture.md`](./architecture.md).

---

## 5. Making a change

### 5.1 The loop

```bash
git checkout Dev && git pull
git checkout -b fix/sidebar-scroll-position

# ... make the change ...

yarn check-all                    # must pass
git add -A
git commit -m "fix(sidebar): preserve scroll position when switching apps"
git push -u origin fix/sidebar-scroll-position
```

Then open a PR **against `Dev`**.

### 5.2 Before you write code

* Find the requirement ID that covers the change ([`standards.md` §10](./standards.md#10-requirement-id-convention)).
  If no requirement covers it, the specification set is incomplete — say so in the issue.
* Read the file you are about to change, plus the file that calls it.
* Find the existing test for that behaviour. If there is none, you are about to add the first one.

### 5.3 While you write code

* Follow [`standards.md`](./standards.md). Match the surrounding code.
* Add every new user-visible string to `src/assets/locales/en.json`.
* Add every new colour or dimension as a CSS custom property.
* Never invent a config key, env var or route — read the source
  ([`Agents.md` §4](./Agents.md#4-repository-facts-an-agent-must-not-get-wrong)).

### 5.4 The "new config option" checklist

Inherited from Dashy and still binding. Any PR that adds or changes a configuration option must
complete **all** of these:

- [ ] Confirm the option is genuinely necessary and nothing similar already exists.
- [ ] Add it to `src/utils/config/ConfigSchema.json` with a `description` (the schema is also the docs source).
- [ ] Set a sensible default or fallback (`src/utils/config/defaults.js`, or in the component's `computed`).
- [ ] Document it in `docs/configuring.md`, and in the relevant root document.
- [ ] Keep it **backwards compatible** — nothing may break when the option is absent.
- [ ] Add a test that the default applies when the key is missing.
- [ ] Add a `Documentation` entry to [`CHANGELOG.md`](./CHANGELOG.md).

### 5.5 Changing the deployment

* Never edit `Mailcow/docker-compose.yml`, `Mailcow/generate_config.sh` or `Mailcow/update.sh`.
* Every new service needs: a pinned image tag from `.env`, a `healthcheck`, Traefik labels using the
  shared network, and bind-mounted state inside its own application folder.
* Every new setting needs a commented entry in the matching `.env.example`.
* `setup.sh` changes must remain idempotent — run it three times and prove convergence.
* Quote the requirement IDs from [`production.md`](./production.md) that your change implements.

---

## 6. Testing your change

The full strategy is in [`Testing.md`](./Testing.md). The minimum for any PR:

| Change | Required |
| --- | --- |
| Shell logic (store, utils, broker client) | Unit test (`tests/unit/**`) |
| Vue component behaviour | Component test (`tests/components/**`) |
| Server or broker route | Server test (`tests/server/**`, `// @vitest-environment node` + `supertest`) |
| Any user-visible flow | Playwright spec (`e2e/specs/**`) |
| A bug fix | The regression test that fails before your fix |
| Deployment or `setup.sh` | Idempotency run plus the compose validity check |
| Documentation only | `yarn validate-locales` (if locale keys changed) and a link check |

```bash
yarn test               # unit + component + server
yarn test:coverage      # coverage floors
yarn test:e2e           # end-to-end against the test stack
```

> **Rule C-6.1:** a PR that changes behaviour without a test is incomplete. If a test is genuinely
> impossible, state why in the PR and get a maintainer to agree **before** merge.
>
> **Rule C-6.2:** never delete or weaken an existing test to make a change pass. If a test is wrong,
> fix the test and explain why in the PR.

---

## 7. The running log of changes

[`CHANGELOG.md`](./CHANGELOG.md) is the repository's running log. **Every PR adds an entry**, in the
same PR, under `## [Unreleased]`.

```markdown
## [Unreleased]

### New Features
 - Save a SOGo attachment straight into the user's FileBrowser source (#142).

### Bugfixes
 - Preserve sidebar scroll position when switching applications (#158).

### Notes
 - `WORKCENTER_ZULIP_API_KEY` is now required in `.env`; see `OIDC.md` (#151).
```

| Ref | Rule |
| --- | --- |
| C-7.1 | Put your entry under the correct category, creating it if it does not exist. |
| C-7.2 | Reference the issue or PR number at the end of each line: `(#123)`. |
| C-7.3 | **Never create a version heading.** Release sections are cut by maintainers during promotion. |
| C-7.4 | **Never edit a released section.** Released history is immutable; corrections go in a new patch. |
| C-7.5 | Anything an operator must act on (a new `.env` key, a changed volume, a changed port, a new Authentik setting) goes under `Notes` **and** into [`production.md`](./production.md). |

---

## 8. Pull-request guide

### 8.1 Before opening

- [ ] `git checkout Dev && git pull` — your branch is current with `Dev`.
- [ ] `yarn check-all` passes locally.
- [ ] `yarn test:e2e` passes for any user-visible change.
- [ ] `shellcheck setup.sh scripts/**/*.sh` passes if shell files changed.
- [ ] `docker compose -f compose.yaml config` parses if compose files changed.
- [ ] `CHANGELOG.md` has an `## [Unreleased]` entry.
- [ ] Every affected specification document is updated in this PR.
- [ ] No secret, credential or personal datum is anywhere in the diff.
- [ ] No debugging artefact (`console.log`, `debugger`, commented-out code, unreferenced `TODO`) remains.
- [ ] The branch is rebased on the latest `Dev` (do **not** merge `Dev` into your branch).
- [ ] Commits are coherent and follow [§11](#11-commit-format).

### 8.2 Opening the PR

* **Base branch: `Dev`.** Always.
* **Title:** Conventional Commit format, ≤ 72 characters — it becomes the merge commit subject.
  `feat(switcher): add three-button application switcher above the rail`
* **Draft early** if you want feedback before the change is finished. Draft PRs still get CI.

### 8.3 PR description template

```markdown
## What this changes
<!-- One paragraph. What a user or operator will notice. -->

## Why
Closes #<issue>. <!-- or: Implements <requirement IDs> -->

## Requirement IDs
<!-- e.g. U-2, U-3, U-12, D-A2 -->

## How it was tested
- [ ] `yarn check-all`
- [ ] `yarn test:e2e` — specs: <names>
- [ ] Manual: <what you did, on what host/stack>
- [ ] Idempotency: `setup.sh` run 3× with no change on runs 2 and 3

## Screenshots / recordings
<!-- Required for any UI change. Before | After in a two-column table. -->

| Before | After |
| --- | --- |
| <img width="400" ...> | <img width="400" ...> |

## Documentation
- [ ] `CHANGELOG.md` updated
- [ ] Specification set updated (<which files>)
- [ ] `.env.example` updated (if new settings)

## Risk and rollback
<!-- What could break, and how a maintainer reverses it. -->

## Not done / deliberately out of scope
<!-- Anything a reviewer might expect but that this PR intentionally leaves alone. -->
```

### 8.4 PR requirements

A PR is **mergeable** only when all of these hold:

| Ref | Requirement |
| --- | --- |
| C-8.1 | The base branch is `Dev` (or a documented, maintainer-approved exception). |
| C-8.2 | The description explains **why** the PR exists, not only what it does. |
| C-8.3 | The title is short, descriptive and Conventional-Commit formatted. |
| C-8.4 | All required CI checks are green. |
| C-8.5 | Unit, component and server tests cover the change; E2E covers user-visible flows. |
| C-8.6 | Functionality not covered by tests is explained in the description. |
| C-8.7 | The `CHANGELOG.md` entry exists and is categorised. |
| C-8.8 | Documentation is updated in the same PR. |
| C-8.9 | No new linting errors; no new dependency without justification. |
| C-8.10 | At least one maintainer approval. Two approvals for changes to authentication, the broker's authorisation, `setup.sh` or a compose file. |
| C-8.11 | Conversations are resolved — every review comment is answered or addressed. |
| C-8.12 | The branch is up to date with `Dev`. |

### 8.5 Screenshots for UI changes

Follow the convention inherited from the specification set ([`design.md` §11](./design.md#11-design-review-checklist)):

* Capture at a **fixed viewport** (1440×900) with the same theme and zoom for before and after.
* Present them side by side in a two-column table.
* Include a **light and a dark** capture for anything colour-related.
* Never include real personal data, real mail content, real filenames or real hostnames — use the
  seeded test fixtures.
* Keep the images reasonably small; a screenshot is evidence, not a gallery.

---

## 9. Review process

### 9.1 What a reviewer checks

In order: correctness (including failure paths) → scope → requirement IDs → tests → security →
accessibility → standards → documentation → changelog. The full list is in
[`standards.md` §14](./standards.md#14-review-standards).

### 9.2 Expectations on both sides

| For authors | For reviewers |
| --- | --- |
| Keep the PR focused; split unrelated work out | Review within a few days, or say when you will |
| Answer every comment, even with "done" | Distinguish blockers from suggestions, and label them |
| Push fixes as new commits while under review; rebase and tidy **after** approval | Do not block on personal preference; if it is not written down and not linted, it is a suggestion |
| Mark the PR ready only when the checklist is complete | Approve explicitly, or request changes explicitly — never leave it ambiguous |
| Do not force-push during review (it destroys the comment anchors) | Re-review only the delta, not the whole diff |

### 9.3 Stale PRs

A PR with no author activity for **30 days** is marked stale, then closed after a further **14 days**.
It can always be reopened; the branch simply needs rebasing on `Dev`.

---

## 10. Promotion and release

Promotion is a maintainer action. It mirrors FileBrowser Quantum's model, adapted to three branches.

### 10.1 Promote `Dev` → `Beta`

1. Confirm `Dev` is green: lint, unit, E2E, compose validity.
2. Trigger the **Promote Dev to Beta** workflow with a version argument in `X.Y.Z` form.
3. The workflow validates the version, verifies `Dev` exists and is ahead, merges `Dev` into `Beta`,
   and pushes.
4. `CHANGELOG.md`'s `## [Unreleased]` section is renamed to `## [vX.Y.Z]` on `Beta`, and a fresh
   `## [Unreleased]` heading is added above it.
5. `Beta` builds and publishes candidate images tagged `vX.Y.Z-beta.N`.

### 10.2 Promote `Beta` → `Stable`

1. Soak `Beta` for the agreed window; the E2E suite runs nightly.
2. Trigger the **Promote Beta to Stable** workflow with the same version.
3. `Stable` (the GitHub default branch) receives the merge; the commit is tagged `vX.Y.Z`.
4. Production images are published to GHCR with SBOM and provenance, tagged `vX.Y.Z`, `X.Y` and `latest`.
5. A GitHub release is created as a **draft**; a maintainer reviews and publishes it.

### 10.3 Versioning

Semantic versioning, adapted from FileBrowser Quantum's cadence:

| Change | Bump |
| --- | --- |
| Bug fix, documentation, internal refactor | **patch** |
| New capability, new setting, new UI element | **minor** |
| Breaking change to configuration, volume layout or deployment procedure | **major** |

### 10.4 What may bypass promotion

Only documentation and workflow-configuration changes, with maintainer approval referenced in the PR.

---

## 11. Commit format

Conventional Commits, as used by FileBrowser Quantum:

```
type(scope): description

Body explaining why, wrapped at 100 characters, when the reason is not obvious.

Refs: #123
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

**Scopes:** `switcher`, `sidebar`, `panes`, `broker`, `auth`, `oidc`, `config`, `i18n`, `styles`,
`compose`, `setup`, `traefik`, `filebrowser`, `zulip`, `mailcow`, `onlyoffice`, `authentik`,
`docs`, `tests`, `ci`.

**Examples**

```
feat(switcher): add three-button application switcher above the rail
fix(broker): stream mail attachments instead of buffering them in memory
docs(oidc): document the mailcow generic-oidc provider fields
chore(compose): pin filebrowser quantum to 2.0.6-beta
refactor(sidebar): extract the shared SidebarItem row primitive
test(broker): cover collision-safe naming for duplicate attachments
```

> **Rule C-11.1:** the summary is imperative, ≤ 72 characters, no trailing period.
> **Rule C-11.2:** one coherent change per commit. "wip", "fixes" and "address review" commits are
> squashed before merge.
> **Rule C-11.3:** breaking changes are marked `!` after the type/scope plus a `BREAKING CHANGE:`
> footer, and require a minor-or-major bump and a `Notes` changelog entry.

---

## 12. Contributing to the documentation

Documentation is a deliverable, not an afterthought. It is reviewed with the same rigour as code.

### 12.1 Where documentation lives

| Location | Contents |
| --- | --- |
| Repository root (`*.md`) | The **specification set**: `Readme.md`, `roadmap.md`, `architecture.md`, `design.md`, `integration.md`, `OIDC.md`, `Testing.md`, `production.md`, `standards.md`, `contributions.md`, `Agents.md`, `CHANGELOG.md` |
| `docs/` | Long-form, task-oriented guides (kebab-case filenames) |
| Application folders | A short `README.md` per integrated application, pointing at the root documents |
| `.env.example` files | Inline comments for every setting |

### 12.2 Rules

* Follow [`standards.md` §9](./standards.md#9-documentation-standards) — sentence-case headings,
  one H1, fenced code blocks with a language, real config key names, links to upstream sources.
* Update the document **in the same PR** as the behaviour it describes.
* Do not document a feature that does not exist. This is the most damaging documentation error.
* Add new root documents to the index in [`Readme.md`](./Readme.md) and `docs/readme.md`.
* Keep `CHANGELOG.md` honest: an entry for the documentation change itself, under `Documentation`.

---

## 13. Contributing to the deployment

`setup.sh`, `compose.yaml` and the six application folders are the highest-risk part of the
repository. Extra conditions apply.

| Ref | Requirement |
| --- | --- |
| C-13.1 | Never edit an upstream file inside `Mailcow/`. Use `docker-compose.override.yml`. |
| C-13.2 | `setup.sh` must remain idempotent and must keep its prompt contract identical to [`OIDC.md`](./OIDC.md). If you change a prompt, change `OIDC.md` in the same PR. |
| C-13.3 | Every image reference is a pinned tag, sourced from `.env`. |
| C-13.4 | Every new service has a healthcheck, Traefik labels, and bind-mounted state in its own folder. |
| C-13.5 | Every new secret is generated with `openssl rand -hex 32` and written with `umask 077`. |
| C-13.6 | A deployment PR must include a dry-run report: the commands you ran, the host type, and the observed result. |
| C-13.7 | Destructive operations in scripts require confirmation or an explicit `--force` flag. |
| C-13.8 | Secrets never appear in a PR description, a log excerpt or a screenshot. Redact them. |

---

## 14. Reporting bugs

Open an issue using the **Bug report** template and include:

| Field | Why it matters |
| --- | --- |
| Workcenter version / commit | Reproducibility |
| Deployment method (`setup.sh`, manual compose, existing Traefik) | Most bugs are deployment-shaped |
| Which pane (Files / Chat / Mail) and which action | Narrows the surface immediately |
| Exact steps to reproduce | Required |
| Expected vs actual | Required |
| Browser console output and the relevant service logs | The fastest route to a fix |
| `docker compose ps` health output | Reveals a failing upstream in one line |
| Screenshot or recording | Required for UI bugs |

**Redact** hostnames, email addresses, tokens, cookies and anything else sensitive. If a secret may
have leaked, treat it as a security report instead.

---

## 15. Requesting features

Use the **Feature request** template and state:

1. The problem, in user terms — what you cannot do today.
2. Which panes or integrations are involved.
3. Which goal in [`roadmap.md` §3](./roadmap.md#3-application-goals) it serves, or whether it needs a
   new goal.
4. Whether it is already in the roadmap's build plan.

Feature requests that require a new integrated application, or that reintroduce a removed Dashy
subsystem, must be agreed **before** a PR is opened.

---

## 16. Becoming a maintainer

Contributors with a sustained record — several merged PRs across more than one area, thoughtful
reviews, and reliable follow-through — may be invited to become maintainers. Maintainers gain write
access, triage issues, review PRs, and run promotions.

Maintainers are expected to:

* Review within a few days, or state when they will.
* Keep `Dev` green; a red `Dev` blocks everyone.
* Never promote with a failing E2E run.
* Record every release in [`CHANGELOG.md`](./CHANGELOG.md).

---

## 17. Code of conduct

Be respectful, assume good faith, and critique the change rather than the person. Harassment,
personal attacks and discriminatory language are not tolerated. Report concerns privately to the
maintainers.

---

## 18. Licence and attribution

Workcenter is a derivative work of [Dashy](https://github.com/lissy93/dashy), which is MIT licensed.
By contributing, you agree that your contribution is licensed under the same terms as this repository.

Workcenter integrates, but does not vendor, the following projects. Their licences apply to their own
code:

| Project | Licence |
| --- | --- |
| [Dashy](https://github.com/lissy93/dashy) | MIT |
| [FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser) | Apache-2.0 |
| [Zulip](https://github.com/zulip/zulip) | Apache-2.0 |
| [Mailcow Dockerized](https://github.com/mailcow/mailcow-dockerized) | GPL-3.0 |
| [SOGo](https://github.com/Alinto/sogo) | LGPL-2.1 |
| [ONLYOFFICE Docs](https://github.com/ONLYOFFICE/DocumentServer) | AGPL-3.0 |
| [Authentik](https://github.com/goauthentik/authentik) | MIT / GPL-3.0 (mixed) |
| [Traefik](https://github.com/traefik/traefik) | MIT |

Check the licence of any new dependency before adding it, and record it here if it is a new
integrated application.

---

<p align="center"><sub>Workcenter contribution guide · PR and version-control standard after <a href="https://filebrowserquantum.com/en/docs/contributing/features/feature-development/">FileBrowser Quantum</a></sub></p>
