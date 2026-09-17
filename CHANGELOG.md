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
 - Repository foundation: `Dev`, `Beta` and `Stable` branches with `Stable` as the default branch
   and `Dev` as the target for every pull request.
 - Imported Dashy as the upstream baseline, at commit
   `6c56436d5f044d3c53371891c9d9a8c8df8c4606` (v4.6.14, "🔀 Merge pull request #2340 from
   lissy93/fix/status-check-ping-mem-limits", 2026-09-12). Workcenter is derived from this commit.
 - Initial documentation baseline for the Workcenter application: roadmap, architecture,
   design, agent, standards, contribution, OIDC, testing and production specifications.
 - Defined the single-pane Workcenter shell derived from the Workcenter Workspace view
   (application switcher above a per-application sidebar).

### Deployment
 - `.editorconfig` and `.gitignore` covering every secret, runtime volume and generated artefact
   the integrated applications produce, including `**/.env`, `**/secrets/`, `**/data/` and `acme.json`.
 - `.github/workflows/ci.yml` — the regular-test workflow, run on every pull request: install,
   lint, typecheck, unit tests, locale check, config validation and production build.
 - `.github/workflows/promote.yml` — promotion of `Dev` → `Beta` and `Beta` → `Stable` by
   semantic version.
 - `.github/ISSUE_TEMPLATE/` and `.github/pull_request_template.md`, covering the requirement-ID,
   changelog and test-evidence obligations.

### Documentation
 - Rebrand completed. Every file, path, identifier, asset and user-visible string that named
   the upstream project now names Workcenter. The only surviving reference is the
   acknowledgement that Workcenter was built from Dashy, which the MIT licence requires and
   which now appears in one consistent form.
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

### Notes
 - Workcenter is a **derivative of Workcenter**: the Default and Minimal views are intentionally
   discarded; only the Workspace view is carried forward.

---

## Release history

Workcenter has not yet cut its first release. Releases are created by promotion, in order:

| Version | Branch | Date | Notes |
| --- | --- | --- | --- |
| — | `Dev` | — | Integration branch; all PRs target here |
| — | `Beta` | — | Promoted from `Dev`; Playwright E2E verified |
| — | `Stable` | — | Promoted from `Beta`; default branch, production releases |
