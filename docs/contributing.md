# Contributing

Thank you for considering a contribution to Workcenter. Contributions of any size are
welcome, and every one is credited — see [`credits.md`](./credits.md).

## Ways to help

| Contribution | Where it goes |
| --- | --- |
| Bug fix, or a regression test for an existing bug | A pull request into `Dev` |
| Documentation correction | A pull request into `Dev` |
| Translation | A new locale file in `src/assets/locales/` — see below |
| Theme | A theme partial in `src/styles/themes/` |
| Deployment improvement | A pull request into `Dev`, with a dry run on a disposable host |
| A security report | Privately — see [`SECURITY.md`](../.github/SECURITY.md) |

## Add a translation

Every string in the shell lives in [`src/assets/locales/en.json`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/assets/locales/en.json),
which is the master locale. Adding a language means copying that file and translating the
values, leaving the keys alone. A missing key falls back to English, so a partial translation
is useful.

Run `yarn validate-locales` before opening the pull request: it fails if a locale file is
missing, if a key used in code is absent from `en.json`, or if a locale is registered in
`src/utils/languages.js` without a file. The i18n requirements the shell must satisfy — the
user menu's language control among them — are in
[the design specification](../design.md#8-i18n).

## Submit a pull request

A bug fix, a feature or a documentation correction is welcome. Read
[`contributions.md`](../contributions.md) for the branch model, the pull-request requirements
and the review process, and [`standards.md`](../standards.md) for the conventions.

Every pull request targets `Dev`. The short version:

```bash
git checkout Dev && git pull
git checkout -b fix/short-description
# ... make the change ...
yarn check-all
```

Then open the pull request against `Dev`.

## Raise an issue or open a discussion

- [Open an issue](https://github.com/JDB321Sailor/Workcenter/issues/new/choose) for a bug or a
  feature request. The templates ask for the information a maintainer needs.
- [Start a discussion](https://github.com/JDB321Sailor/Workcenter/discussions) for a question, a
  design idea, or a configuration you want to share.
- [Report a vulnerability privately](https://github.com/JDB321Sailor/Workcenter/security/advisories/new)
  rather than in a public issue.

## Improve the documentation

Documentation is a deliverable in this repository, so a pull request that improves it is as
welcome as a code change. The specification set lives at the repository root and the long-form
guides are under `docs/`. Both ship in the same pull request as the behaviour they describe.

## Where to read next

| Document | Contents |
| --- | --- |
| [`contributions.md`](../contributions.md) | The PR guide, review process and branch promotion |
| [`standards.md`](../standards.md) | Coding, naming and documentation standards |
| [`Testing.md`](../Testing.md) | The test strategy and the merge gates |
| [`Agents.md`](../Agents.md) | Requirements for AI coding agents |
| [`architecture.md`](../architecture.md) | Where code lives |
| [`docs/developing.md`](./developing.md) | Running the app locally |
