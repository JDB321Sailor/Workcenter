# Releases and Workflows

> This document outlines our release schedule, workflows/automations, repository conventions and standards

- [Versioning and Releases](#versioning-and-releases)
  - [High-level tag process](#high-level-tag-process)
  - [Creating a Release](#creating-a-release)
  - [Versioning](#versioning)
- [Workflows](#workflows)
  - [CI](#ci)
  - [Docker](#docker)
  - [Release](#release)
  - [Tag](#tag)
  - [Mirror](#mirror)
  - [Docs](#docs)
- [Git Strategy](#git-strategy)
  - [Commits](#commits)
  - [Branches](#branches)
  - [Pull Requests](#pull-requests)

---

## Versioning and Releases

### High-level tag process
- All new features, fixes and updates happen via pull request to `master`
- After a PR is merged, the `version` in the package.json will automatically be bumped by it's patch value (unless the PR already updated the version)
- Whenever the `version` is updated, a new git tag and also Docker tag is created and pushed
- If the major or minor version (not patch version) was bumped, then a release is also drafted

The tagging process is managed via GitHub actions, using our [`tag.yml`](https://github.com/lissy93/dashy/blob/master/.github/workflows/tag.yml) workflow.
This workflow can also be manually triggered by a maintainer to make and push a new tag (either specify tag version, or leave blank for auto-bump of patch version).

### Creating a Release
Only repository maintainers can publish releases. The process typically happens automatically whenever the major or minor version is updated (via tag workflow). But a release can also be triggered manually via the [`release.yml`](https://github.com/lissy93/dashy/blob/master/.github/workflows/release.yml) workflow's manual dispatch, by passing it an (already existing, not yet released) tag version. Note that the bot only creates a Draft Release, so you'll then need to head to the releases tab, review it looks correct, and hit Publish.

### Versioning

Typically Workcenter has multiple patch versions per week, bi-weekly minor releases, and quarterly major releases.

Workcenter uses a form of semantic versioning ([semver](https://semver.org/)), whereby we push a:
- Patch (e.g. `4.6.9`) - New patch version published for every change
- Minor (e.g. `4.7.0`) - New minor version published for groups of features
- Major (e.g. `5.0.0`) - Large releases, possibly not backward compatible

<img width="500" src="https://pixelflare.cc/alicia/images/semver.png" />

### Changelog
You can view a list of recent changes at [dashy.to/updates](https://dashy.to/updates) or subscribe to the [`rss.xml`](https://dashy.to/rss.xml) feed.
Likewise, on GitHub you can view all of our [Tags](https://github.com/lissy93/dashy/tags) and [Releases](https://github.com/lissy93/dashy/releases)

---

## Workflows

### CI

> Runs checks on pull request to catch obvious/critical issues

This runs a series of checks against the PR. A path-filter step first works out what changed, so most checks only run when their relevant files were modified (the rest are skipped):

- **Lint** - Confirms the code is clean and consistent, with ESLint
  - _Runs when:_ source or config changes
- **Typecheck** - Confirms TypeScript types are valid, with `vue-tsc`
  - _Runs when:_ any code or config changes
- **Test** - Runs the unit test suite
  - _Runs when:_ every PR
- **Locale check** - Validates the translation files are complete and well-formed
  - _Runs when:_ any languages or locale content ([`src/assets/locales`](https://github.com/lissy93/dashy/blob/master/src/assets/locales/)) is updated
- **Spellcheck** - Catches typos in the source strings ([`en.json`](https://github.com/lissy93/dashy/blob/master/src/assets/locales/en.json))
  - _Runs when:_ English locale file is updated
- **Build check** - Builds Workcenter and checks the `dist` output is all good
  - _Runs when:_ every PR
- **Docker smoke test** - Builds the Docker image and checks it starts and serves correctly
  - _Runs when:_ every PR
- **Dependency audit** - Scans dependency changes for known vulnerabilities (fails on moderate+)
  - _Runs when:_ Package is added/updated in [`yarn.lock`](https://github.com/lissy93/dashy/blob/master/yarn.lock)
- **Secret scanning** - Scans the PR diff for committed secrets/keys/credentials, with TruffleHog
  - _Runs when:_ every PR
- **Workflow audit** - Lints and security-audits the GitHub Actions, with actionlint + zizmor
  - _Runs when:_ a workflow file changes (`.github/workflows/**`)

| | |
|---|---|
| **Workflow** | [`ci.yml`](https://github.com/lissy93/dashy/blob/master/.github/workflows/ci.yml) |
| **Status** | [![🚦 PR Check](https://github.com/lissy93/dashy/actions/workflows/ci.yml/badge.svg)](https://github.com/lissy93/dashy/actions/workflows/ci.yml) |
| **Triggers** | Pull request (PR opened/updated on master) |
| **Inputs** | _None_ |
| **Outputs** | _None_ |


### Docker

> The Docker workflow builds and publishes the Docker image.

Uses our [`Dockerfile`](https://github.com/lissy93/dashy/blob/master/Dockerfile). This is a multi-arch (amd64, arm64) build, with each run as a matrix. The image is published to both GHCR ([`ghcr.io/lissy93/dashy`](https://github.com/lissy93/dashy/pkgs/container/dashy)) and DockerHub ([`lissy93/dashy`](https://hub.docker.com/r/lissy93/dashy/)). It also runs a trivy security scan, and if critical issues are present the scheduled job will fail, and results published under the Security tab. The job also attests both the build provenance and SBOM, which are published alongside the image. The Docker tags are computed from the values in the Dockerfile.

| | |
|---|---|
| **Workflow** | [`docker.yml`](https://github.com/lissy93/dashy/blob/master/.github/workflows/docker.yml) |
| **Status** | [![🐳 Docker](https://github.com/lissy93/dashy/actions/workflows/docker.yml/badge.svg)](https://github.com/lissy93/dashy/actions/workflows/docker.yml) |
| **Triggers** | Tag creation, schedule, manual dispatch |
| **Inputs** | Tag (optional, inferred from git tag) |
| **Outputs** | SHA, manifest, digest, SBOM, attestation |

### Release

> Builds the app and drafts a GitHub release with the packaged tarball

Triggered by a major/minor (`X.Y.0`) tag push, or by manual dispatch against an existing tag. It builds Workcenter, packages a release tarball (the built `dist` plus the server files needed to run it), then generates a SHA256 checksum and an SLSA build-provenance attestation. Finally it drafts a GitHub release with auto-generated notes (diffed against the previous `X.Y.0` tag). The release is only a draft - a maintainer reviews it and hits Publish.

| | |
|---|---|
| **Workflow** | [`release.yml`](https://github.com/lissy93/dashy/blob/master/.github/workflows/release.yml) |
| **Status** | [![🚀 Release](https://github.com/lissy93/dashy/actions/workflows/release.yml/badge.svg)](https://github.com/lissy93/dashy/actions/workflows/release.yml) |
| **Triggers** | Major/minor tag push (`*.*.0`), manual dispatch |
| **Inputs** | Tag (required on manual dispatch, must already exist) |
| **Outputs** | Draft release, tarball, SHA256 checksum, provenance attestation |

### Tag

> Bumps the version and pushes a new git tag

When a PR with code changes is merged into master, this bumps the patch version in the package.json (unless the PR already bumped it), commits the change, then creates and pushes a git tag for the new version. That tag push is what kicks off the Docker and Release workflows downstream. It also labels and comments on any issues referenced in the PR, and pings the docs site to rebuild. It can also be triggered manually - either pass a specific version, or leave it blank to auto-bump the patch.

| | |
|---|---|
| **Workflow** | [`tag.yml`](https://github.com/lissy93/dashy/blob/master/.github/workflows/tag.yml) |
| **Status** | [![🔖 Tag](https://github.com/lissy93/dashy/actions/workflows/tag.yml/badge.svg)](https://github.com/lissy93/dashy/actions/workflows/tag.yml) |
| **Triggers** | PR merged to master, manual dispatch |
| **Inputs** | Version (optional, leave blank to auto-bump patch) |
| **Outputs** | Version-bump commit, git tag, issue labels/comments |

### Mirror

> Mirrors the repo over to our Codeberg instance

Pushes a full copy of the repo to our Codeberg mirror, over at [codeberg.org/alicia/dashy](https://codeberg.org/alicia/dashy), so the project isn't solely hosted on GitHub. Runs weekly. Uses the [`lissy93/repo-mirror-action`](https://github.com/Lissy93/repo-mirror-action) action for keeping mirrors in-sync.

| | |
|---|---|
| **Workflow** | [`mirror.yml`](https://github.com/lissy93/dashy/blob/master/.github/workflows/mirror.yml) |
| **Status** | [![🪞 Mirror](https://github.com/lissy93/dashy/actions/workflows/mirror.yml/badge.svg)](https://github.com/lissy93/dashy/actions/workflows/mirror.yml) |
| **Triggers** | Schedule (weekly, Sun 03:30 UTC), manual dispatch |
| **Inputs** | _None_ |
| **Outputs** | _None_ |

### Docs

> Keeps the docs site and GitHub wiki in sync with the `/docs` directory

Mirrors the markdown content from [`/docs`](https://github.com/lissy93/dashy/tree/master/docs) to the `WEBSITE/docs-site-source`, where it's then formatted and the Docusaurus site is re-built and deployed to [dashy.to](https://dashy.to/). Runs whenever docs are updated on master.

| | |
|---|---|
| **Workflow** | [`update-docs-site.yml`](https://github.com/lissy93/dashy/blob/master/.github/workflows/update-docs-site.yml) |
| **Status** | [![📝 Sync Docs](https://github.com/lissy93/dashy/actions/workflows/update-docs-site.yml/badge.svg)](https://github.com/lissy93/dashy/actions/workflows/update-docs-site.yml) |
| **Triggers** | Push to `docs/**` on master, schedule (weekly), manual dispatch |
| **Inputs** | _None_ |
| **Outputs** | Updated docs on the `WEBSITE/docs-site-source` branch |

---

## Git Strategy

### Commits
We use [gitmoji](https://gitmoji.dev/) for commits (because it's fun!).
Whereby each commit message starts with an emoji which indicates the change type.

### Branches
Most branches are named with their type, followed by short description.
E.g. `feat/adds-awesome-feature`, `ref/language-deduplication`, `fix/resolves-missing-icons`.

### Pull Requests
Like most Git repos, we are following the [Github Flow](https://guides.github.com/introduction/flow) standard.

1. Create a branch (or fork if you don't have write access)
2. Code some awesome stuff, then add and commit your changes
3. Create a Pull Request, filling in the template
4. Follow up with any reviews on your code
5. Merge 🎉
