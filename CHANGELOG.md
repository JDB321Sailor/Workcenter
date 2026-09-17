<div align="center">

# Changelog

The running log of changes to Workcenter.

</div>

---

Entries are added under `## [Unreleased]` in the same pull request that makes the change, following
[`contributions.md` §7](./contributions.md#7-the-running-log-of-changes). Version headings are cut by
maintainers during promotion; contributors never create one.

Categories, in order: **New Features**, **Bugfixes**, **Documentation**, **Notes**.

---

## [Unreleased]

### New Features

 - Specify the user menu's appearance control: a light/dark switcher with dark as the documented
   default (`design.md` D-6.1, `roadmap.md` U-17).
 - Specify the user menu's language control: the language in use written in its own language, plus a
   flag button that opens the language menu (`design.md` D-6.2, `roadmap.md` U-18).
 - Specify the **theme bridge** — one switch in the shell changes the shell and all three embedded
   applications, through FileBrowser Quantum's per-user `darkMode`, Zulip's `color_scheme` and a
   Workcenter stylesheet supplied to SOGo (`design.md` §4.4, `roadmap.md` U-11, U-20).
 - Specify the **language bridge** for the applications that can accept one, and state plainly where
   the shell cannot drive the language rather than failing quietly (`design.md` §8.2, `roadmap.md`
   U-23).
 - Specify the `setup.sh` branding stage, which gives the embedded applications Workcenter's name,
   logo and palette so the deployment reads as one product (`production.md` §5.2a, `roadmap.md`
   U-22).
 - Add `POST /api/broker/preferences`, the same-origin route that fans a preference out to the
   applications on behalf of the calling user only (`architecture.md` AR-47, AR-48).
 - Add the application brand marks under `icons/`, and specify their use in the application switcher
   (`design.md` D-2I, `architecture.md` AR-46, `roadmap.md` U-19).

### Documentation

 - Adopt FileBrowser Quantum's own light and dark palette as Workcenter's appearance standard, so the
   shell, the branding and the panes are derived from one source (`design.md` §4.3.1).
 - Record the per-application appearance, branding and language mechanisms against the pinned
   upstream versions (`integration.md` §3.6, §5.8, §6.9).
 - Withdraw design rule D-T2. It required that no pane ever reload on a theme change, which is not
   achievable for FileBrowser Quantum — it exposes no live channel — and the user-visible requirement
   is that the mode change reaches every application. Superseded by D-T5 and D-T6.
 - Add the tests that prove a mode switch reaches the embedded applications, asserted inside each
   pane against the application's own DOM rather than against the shell's state (`Testing.md` §8.3a,
   T-8.4 … T-8.8).
 - Remove three inherited Dashy guides that documented features Workcenter does not have:
   `docs/icons.md`, `docs/multi-language-support.md` and `docs/development-guides.md`. Inbound links
   now point at the specification that replaces each one.
 - Start this changelog.

### Notes

 - `setup.sh` gains `--brand`, which re-applies the branding on its own. Run it after
   `Mailcow/update.sh`: Mailcow tracks everything under `data/conf/sogo/` and merges with
   `-X theirs`, so an upgrade can revert the Mail pane's styling
   ([`production.md` §10.2](./production.md#102-mailcow)).
 - Mailcow's light and dark logos are uploaded by hand in **Configuration → Customize**. They are
   stored in Redis by a form POST and Mailcow exposes no API for it, so `setup.sh` prints the step
   instead of reporting a success it did not achieve.
 - The realm-wide Zulip appearance pass needs a **human** administrator account. Zulip's settings
   endpoint rejects bot API keys, so the file-broker bot cannot perform it.

---

<p align="center"><sub>Workcenter changelog · entries are added in the pull request that makes the change</sub></p>
