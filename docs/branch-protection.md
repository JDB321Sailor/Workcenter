# Branch protection and repository settings

> **Scope:** the GitHub-side repository settings that Phase 0.1 requires and that no local
> commit can establish. Apply these once, when the repository is first pushed.
> **Companions:** [`contributions.md`](../contributions.md) §3 and §10 · [`Testing.md`](../Testing.md) §10

---

## 1. Branch model

```
feature branch ──PR──▶ Dev ──promote──▶ Beta ──promote──▶ Stable
```

| Branch | Role | Default? |
| --- | --- | --- |
| `Dev` | The base for every pull request, and where the application lives. | Default **PR base** |
| `Beta` | The promotion target for `Dev`. Receives the whole of `Dev` when production testing is ready. | — |
| `Stable` | The promotion target for `Beta`. **The GitHub default branch** and the source of production releases. | GitHub default |

Direction of travel, one way only:

```
feature branch ──PR──▶ Dev ──promote──▶ Beta ──promote──▶ Stable
```

The `Pull-request base branch` job in `ci.yml` enforces this: a pull request whose base
is not `Dev` fails, unless its title starts with `chore(release): promote`.

Both settings below are required by roadmap step 0.1.

---

## 2. First push

Push `Stable` first, so the repository's default branch is correct from the moment it exists:

```bash
git remote add origin git@github.com:<your-org>/workcenter.git

git push -u origin Stable      # first, so GitHub adopts it as the default branch
git push -u origin Dev
git push -u origin Beta
```

If `Stable` was not the first branch pushed, set the default explicitly:

```bash
gh repo edit --default-branch Stable
```

Confirm:

```bash
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
# Stable
```

---

## 3. Set Dev as the default pull-request base

GitHub has no API for a "default PR base branch". The pull-request template is the mechanism: it
states the base branch at the top, and the checklist below is enforced by review. A `CODEOWNERS`
entry and a branch ruleset keep it honest.

### 3.1 Pull-request template

`.github/pull_request_template.md` opens with the base-branch statement, so every new pull request
tells the author where it belongs. Nothing further is required for the template.

### 3.2 Rulesets

Create three rulesets under **Settings → Rules → Rulesets**.

**`protect-stable`** — target `Stable`

| Setting | Value |
| --- | --- |
| Require a pull request before merging | On |
| Required approvals | 1 (2 for `setup.sh`, `compose.yaml`, or anything under `services/utils/broker/auth/`) |
| Dismiss stale approvals on new commits | On |
| Require review from Code Owners | On |
| Require status checks to pass | On — see §3.3 |
| Require branches to be up to date before merging | On |
| Require conversation resolution | On |
| Block force pushes | On |
| Restrict deletions | On |
| Bypass list | Repository admins only, for promotions |

**`protect-beta`** — target `Beta`

Same as `protect-stable`, except the bypass list includes the promotion workflow.

**`protect-dev`** — target `Dev`

| Setting | Value |
| --- | --- |
| Require a pull request before merging | On |
| Required approvals | 1 |
| Require status checks to pass | On — see §3.3 |
| Require conversation resolution | On |
| Block force pushes | On |
| Restrict deletions | On |
| Allow bypass | Maintainers, for unblocking a red `Dev` |

### 3.3 Required status checks

Set these as required on all three branches. They are the job names from
`.github/workflows/ci.yml`.

| Check | Workflow job |
| --- | --- |
| `Install dependencies` | `install` |
| `Lint` | `lint` |
| `Typecheck` | `typecheck` |
| `Test` | `test` |
| `Locale check` | `locales` |
| `Config validation` | `config` |
| `Build` | `build` |

> **Note:** a check only becomes selectable in the ruleset UI after it has run at least once.
> Open a throwaway pull request to populate the list, then configure the rulesets.

---

## 4. Repository settings

| Setting | Value | Where |
| --- | --- | --- |
| Default branch | `Stable` | Settings → General → Default branch |
| Allow squash merging | **On** (default) | Settings → General → Pull requests |
| Allow merge commits | **On** — required by the promotion workflow's `--no-ff` merge | Settings → General → Pull requests |
| Allow rebase merging | Off — keeps one merge strategy | Settings → General → Pull requests |
| Automatically delete head branches | On | Settings → General → Pull requests |
| Require contributors to sign off | Off | Settings → General |
| Actions permissions | Allow select actions, plus `actions/*` and `docker/*` | Settings → Actions → General |
| Workflow permissions | Read repository contents; workflows that need write access declare it | Settings → Actions → General |
| Dependabot alerts and security updates | On | Settings → Security |
| Secret scanning and push protection | On | Settings → Security |

---

## 5. Dependabot

`.github/dependabot.yml` is tracked in the repository. Review its pull requests weekly; a
dependency bump is a normal pull request and requires a `CHANGELOG.md` entry under
`Dependencies`.

---

## 6. Verification

After the first push and the ruleset configuration, confirm:

```bash
# Stable is the default branch
gh repo view --json defaultBranchRef --jq .defaultBranchRef.name

# Dev exists and is the documented PR target
gh api "repos/{owner}/{repo}/branches" --jq '.[].name'

# The CI workflow is registered
gh workflow list

# A pull request opened without a base defaults to Stable, so authors must
# retarget to Dev — the PR template states this, and protect-dev requires it.
```

Checklist:

- [ ] `Stable` is the default branch.
- [ ] `Dev` and `Beta` exist.
- [ ] The seven required checks are selected on all three branches.
- [ ] Force pushes and deletions are blocked on all three branches.
- [ ] Merge commits are enabled, so `promote.yml` can perform `--no-ff` merges.
- [ ] Dependabot alerts, secret scanning and push protection are on.
