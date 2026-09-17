# Workcenter documentation

The specification set lives at the repository root. These are the long-form guides.

## The specification set

- [Readme](../Readme.md) - Project overview, features, quick start and documentation index
- [Roadmap](../roadmap.md) - Goals, integration requirements, UI requirements and the build plan
- [Architecture](../architecture.md) - Folder structure, file breakdown, layout and configuration model
- [Design](../design.md) - Every UI element, state, token and interaction
- [Integration](../integration.md) - What each integrated application is, and how it is wired in
- [OIDC](../OIDC.md) - OIDC mechanics, Authentik setup, and the `setup.sh` prompt contract
- [Testing](../Testing.md) - Test strategy, the Playwright harness, and the merge gates
- [Production](../production.md) - Deployment, the `setup.sh` contract, upgrades, backup and restore
- [Standards](../standards.md) - Coding, naming, documentation and security standards
- [Contributions](../contributions.md) - Branching, the PR guide, review and promotion
- [Agents](../Agents.md) - Requirements for AI coding agents
- [Changelog](../CHANGELOG.md) - The running log of changes

## Development and contributing

- [Branch protection](./branch-protection.md) - GitHub-side branch, ruleset and check configuration
- [Developing](./developing.md) - Running the development server locally, and the general workflow
- [Development guides](./development-guides.md) - Common development tasks
- [Release workflow](./release-workflow.md) - Releases, CI and automated tasks

## Running Workcenter

- [Quick start](./quick-start.md) - The shortest path to a running instance
- [Deployment](./deployment.md) - Deployment options
- [Configuring](./configuring.md) - Every option in `user-data/conf.yml`
- [Management](./management.md) - Day-2 operations, updating and web server configuration
- [Troubleshooting](./troubleshooting.md) - Common errors and how to fix them

## Features

- [Authentication](./authentication.md) - How authentication works, and per-provider notes
- [Theming](./theming.md) - Applying, writing and modifying themes
- [Language switching](./multi-language-support.md) - Switching language, and adding a locale
- [REST API](./api.md) - Reading and updating configuration over HTTP
- [Security](./security.md) - Security features, threat model and hardening
- [Privacy](./privacy.md) - Network requests and data storage
- [Icons](./icons.md) - Available icon types

## Misc

- [Credits](./credits.md) - The projects Workcenter is built on
- [License](../LICENSE) - MIT
- [Code of Conduct](../.github/CODE_OF_CONDUCT.md) - Contributor Covenant
