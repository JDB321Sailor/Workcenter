# Release workflow

How a change becomes a release, and what CI runs along the way.

## Branches

Direction of travel, one way only:

```
feature branch ──PR──▶ Dev ──promote──▶ Beta ──promote──▶ Stable
```

| Branch | Role | Default? |
| --- | --- | --- |
| `Dev` | The base for every pull request, and where the application lives. | Default **PR base** |
| `Beta` | The promotion target for `Dev`. Receives the whole of `Dev` when production testing is ready. | — |
| `Stable` | The promotion target for `Beta`. **The GitHub default branch.** | GitHub default |

Workcenter has not cut a release yet. `Beta` and `Stable` hold the documentation until the
first promotion. The full model, including the rules enforced, is in
[`contributions.md`](../contributions.md) and [`branch-protection.md`](./branch-protection.md).

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request into `Dev`, `Beta` or `Stable`.

| Job | Command | Fails when |
| --- | --- | --- |
| Pull-request base branch | — | The base is not `Dev` and the title does not start with `chore(release): promote` |
| Install dependencies | `yarn install --frozen-lockfile` | The lockfile and `package.json` disagree |
| Lint | `yarn lint` | ESLint reports an error |
| Typecheck | `yarn typecheck` | `vue-tsc` reports a type error |
| Test | `yarn test` | A Vitest test fails |
| Locale check | `yarn validate-locales` | A locale file is missing, a key used in code is absent from `en.json`, or a locale is registered without a file |
| Config validation | `yarn validate-config` | `user-data/conf.yml` does not satisfy `ConfigSchema.json` |
| Build | `yarn build`, then verify `dist/index.html` | The bundle fails to build |

The `Test` job runs before `Build`, so it must pass without a prebuilt `dist/`. The SPA
fallback tests assert on the initialization page in that case.

## Promotion

Promotion is a maintainer action, performed with `.github/workflows/promote.yml`.

1. Confirm the full CI suite is green on the source branch.
2. Run the **promote** workflow with the source branch and a semantic version (`X.Y.Z`).
3. The workflow merges the source into the target with `--no-ff`, tags `Stable` with
   `vX.Y.Z` when the target is `Stable`, and prints the changelog step.
4. Cut `## [Unreleased]` in `CHANGELOG.md` into `## [vX.Y.Z]` on the promoted branch, and add a
   fresh `## [Unreleased]` heading above it.

The workflow refuses a version that is not `X.Y.Z`, refuses a missing source branch, and only
permits `Dev → Beta` and `Beta → Stable`.

Merge commits must stay enabled in the repository settings: the workflow's promotion merge
uses `--no-ff`.

## Releases

A release is cut when `Beta` is promoted into `Stable`. Until then there is **no published
Docker image, no GHCR package and no tarball**, and nothing on the repository should claim
otherwise. When the first release is cut it will add:

- an image published with an SBOM and build provenance,
- a Git tag `v1.0.0` on `Stable`,
- a GitHub release, drafted first and published by a maintainer.

## Dependencies

`.github/dependabot.yml` opens update pull requests against `Dev` for npm, GitHub Actions,
Docker and the dev container. A dependency bump is an ordinary pull request: it needs the
full CI suite and a `CHANGELOG.md` entry under `Dependencies`.

## Doing this by hand

If the workflow is unavailable, the same result comes from:

```bash
git checkout Beta && git merge --no-ff Dev \
  -m "chore(release): promote Dev to Beta vX.Y.Z"
git push origin Beta

git checkout Stable && git merge --no-ff Beta \
  -m "chore(release): promote Beta to Stable vX.Y.Z"
git push origin Stable
git tag -a vX.Y.Z -m "Workcenter vX.Y.Z" && git push origin vX.Y.Z
```
