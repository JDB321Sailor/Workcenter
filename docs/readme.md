# Workcenter documentation

This is the index of every document in the repository. Four files live at the repository root —
[`Readme.md`](../Readme.md), [`Agents.md`](../Agents.md), [`roadmap.md`](../roadmap.md) and
[`CHANGELOG.md`](../CHANGELOG.md) — and everything else is grouped by subject under `docs/`.

| Folder | What it holds |
| --- | --- |
| [`architecture/`](#architecture) | How the system is built and why |
| [`authentication/`](#authentication) | Identity, sign-in and the OIDC stack |
| [`deployment/`](#deployment) | Installing, running and operating the stack |
| [`development/`](#development) | Working on the code and shipping it |
| [`guides/`](#guides) | Task-oriented configuration and troubleshooting |
| [`reference/`](#reference) | The HTTP API, and the projects Workcenter builds on |
| [`research/`](#research) | The feasibility studies behind the integrations |
| [`security/`](#security) | Threat model, hardening and privacy |

---

## At the repository root

- [Readme](../Readme.md) — project overview, features, quick start and the documentation map
- [Agents](../Agents.md) — requirements for AI coding agents
- [Roadmap](../roadmap.md) — goals, integration requirements, UI requirements and the build plan
- [Changelog](../CHANGELOG.md) — the running log of changes

## architecture

- [Architecture](./architecture/architecture.md) — folder structure, file breakdown, layout and configuration model
- [Design](./architecture/design.md) — every UI element, state, token and interaction
- [Integration](./architecture/integration.md) — what each integrated application is, and how it is wired in
- [Broker](./architecture/broker.md) — the broker: the six file flows, the appearance and language bridges, security and test criteria

## authentication

- [Authentication](./authentication/authentication.md) — how authentication works, and what each mechanism covers
- [OIDC](./authentication/OIDC.md) — OIDC mechanics, the Authentik setup and the `setup.sh` prompt contract
- [Authentik](./authentication/authentik.md) — Authentik as the identity provider for the whole workspace
- [OIDC client](./authentication/oidc-client.md) — the OIDC client settings, the admin group claim and server-side verification
- [Header auth](./authentication/header-auth.md) — trusting a username header from an upstream proxy
- [Built-in auth](./authentication/built-in.md) — the user list in `conf.yml`, and what it does and does not cover
- [Other auth methods](./authentication/other-auth-methods.md) — Keycloak, and what Workcenter leaves to a proxy

## deployment

- [Deployment](./deployment/deployment.md) — deployment options and requirements
- [Production](./deployment/production.md) — the full production stack, the `setup.sh` contract, upgrades, backup and restore
- [Docker](./deployment/docker.md) — the shell alone, in a container
- [Bare metal](./deployment/bare-metal.md) — running the shell directly on a host

## development

- [Developing](./development/developing.md) — running the development server locally, and the general workflow
- [Contributing](./development/contributing.md) — how to contribute, and where documentation lives
- [Contributions](./development/contributions.md) — branching, the PR guide, review and promotion
- [Standards](./development/standards.md) — coding, naming, documentation and security standards
- [Testing](./development/Testing.md) — test strategy, the Playwright harness and the merge gates
- [Branch protection](./development/branch-protection.md) — GitHub-side branch, ruleset and check configuration
- [Release workflow](./development/release-workflow.md) — releases, CI and automated tasks

## guides

- [Quick start](./guides/quick-start.md) — the shortest path to a running instance
- [Configuring](./guides/configuring.md) — every option in `user-data/conf.yml`
- [Management](./guides/management.md) — day-2 operations, updating and web server configuration
- [Theming](./guides/theming.md) — applying, writing and modifying themes
- [Troubleshooting](./guides/troubleshooting.md) — common errors and how to fix them

## reference

- [REST API](./reference/api.md) — reading and updating configuration over HTTP
- [Credits](./reference/credits.md) — the projects Workcenter is built on

## research

- [Authentik API feasibility](./research/authentik-api-feasibility.md) — automating Authentik providers and applications
- [Mailcow automation feasibility](./research/mailcow-automation-feasibility.md) — automating the Mailcow deployment and its post-boot configuration

## security

- [Security](./security/security.md) — security features, threat model and hardening
- [Privacy](./security/privacy.md) — network requests and data storage

---

## assets

- `docs/assets/` — logos, diagrams and recordings used across these documents

## Also in the repository

- [License](../LICENSE) — MIT
- [Code of Conduct](../.github/CODE_OF_CONDUCT.md) — Contributor Covenant
