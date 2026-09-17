<!--
Base branch: Dev. Every pull request targets Dev.
Beta and Stable receive promotion merges only.
See contributions.md sections 8 and 11 for the PR guide and the commit format.
-->

## What this changes

<!-- One paragraph. What will a user or operator notice? -->

## Why

Closes #<issue>. <!-- or: Implements the requirement IDs below -->

## Requirement IDs

<!--
The specification set numbers its requirements so this PR, its tests and the docs can
cite each other. See standards.md section 10 for the prefixes.
Example: U-2, U-3, U-12, D-A2, I-ZU-9
-->

## Category

<!-- Bugfix / Feature / Docs / Refactor / Test / Chore / Performance / CI / Deployment -->

## How it was tested

- [ ] `yarn install --frozen-lockfile` on a clean clone
- [ ] `yarn lint`
- [ ] `yarn typecheck`
- [ ] `yarn test`
- [ ] `yarn validate-locales`
- [ ] `yarn validate-config`
- [ ] `yarn build`
- [ ] End-to-end suite - specs: `<names>` (required for any user-visible flow)
- [ ] Manual verification: `<what you did, and on what host or stack>`
- [ ] Idempotency: `setup.sh` run three times with no change on runs 2 and 3 (deployment changes only)

## Screenshots or recordings

<!-- Required for any UI change. Before | After, two columns, same viewport and theme. -->

| Before | After |
| --- | --- |
|  |  |

## Documentation

- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]`, in the right category
- [ ] The specification set is updated: `<which files>`
- [ ] `.env.example` updated for any new setting
- [ ] Every new user-visible string is in `src/assets/locales/en.json`
- [ ] No identifier (config key, env var, route, service name) was invented - each was verified in the source

## Risk and rollback

<!-- What could break, and how a maintainer reverses it. -->

## Deliberately not done

<!-- Anything a reviewer might expect to change, that this PR intentionally leaves alone. -->
