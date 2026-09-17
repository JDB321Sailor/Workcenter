# Privacy

What Workcenter stores, and what it sends over the network.

Workcenter is self-hosted. Nothing in it reports to a third party unless you turn it on
deliberately, and the shell adds no analytics of its own.

## Contents

- [What is stored in the browser](#what-is-stored-in-the-browser)
- [Cookies](#cookies)
- [Sign-in](#sign-in)
- [What the shell sends over the network](#what-the-shell-sends-over-the-network)
- [What the server stores](#what-the-server-stores)
- [What the embedded applications do](#what-the-embedded-applications-do)
- [Turning off what can be turned off](#turning-off-what-can-be-turned-off)

---

## What is stored in the browser

Workcenter keeps its own state in `localStorage`. None of it leaves the browser, and clearing
site data removes all of it.

| Key | What it holds | Why |
| --- | --- | --- |
| `theme` | The selected theme name | Remember the theme without a round trip |
| `primaryTheme` | The theme in use before an override | Restore the previous theme |
| `customColors` | Colour overrides you set | Apply them on the next load |
| `iconSize` | `small`, `medium` or `large` | Remember the size |
| `layoutOrientation` | The sidebar orientation | Remember it |
| `language` | The selected locale code | Localise without a round trip |
| `appConfig` | A cached copy of the shell configuration | Render before the config is refetched |
| `pageInfo` | A cached copy of the page metadata | The document title on first paint |
| `mostUsed` | The entries you use most | Sort a list by use |
| `lastUsed` | The entry you used last | Reopen it |
| `confSections`, `confPages` | Cached configuration sections | Survive a config fetch failure |
| `disableCriticalWarning` | Whether you dismissed the critical-error notice | Do not show it again |

When OIDC is enabled, the authenticated session is also kept in `localStorage`:

| Key | What it holds |
| --- | --- |
| `idToken` | The signed identity token from Authentik |
| `username` | The signed-in user's name |
| `isAdmin` | Whether the user is in the administrative group |
| `keycloakInfo` | The groups and roles from the token |

> **What this means.** A token in `localStorage` is readable by any script running on the
> Workcenter origin. That is inherent to a single-page application that talks to an
> identity provider directly. It is why the shell must not run untrusted third-party scripts,
> and why `scripts/` restricts what the server will serve.

Clearing the cache and site data removes every one of these.

## Cookies

Workcenter sets one cookie, and only when the built-in password authentication is used instead
of OIDC:

| Cookie | Purpose |
| --- | --- |
| `workcenterAuthToken` | A session token derived from the username and password hash, so the browser can present it on each request |

With OIDC enabled — the supported configuration — no Workcenter cookie is set. Authentik sets its
own session cookie on its own domain.

The embedded applications set their own cookies on their own subdomains. Workcenter cannot read
them, and they are not shared with it.

## Sign-in

Authentication is delegated to **Authentik**. See [`OIDC.md`](../OIDC.md).

Workcenter never sees a password when OIDC is used. It receives a signed token that states the
user's name, email and group membership. The token is verified against Authentik's published
keys, and it expires.

With the built-in fallback, the password is hashed in the browser with SHA-256 and compared
against a hash in the configuration. The plaintext password is never stored.

## What the shell sends over the network

| Request | When | Carries |
| --- | --- | --- |
| `GET /conf.yml` | On load | Your session token, so the server can return the full configuration rather than the bootstrap subset |
| `GET /healthz` | Container healthcheck | Nothing |
| `GET /api/broker/health` | Every 30 seconds, backing off to 5 minutes | Your session token |
| The embedded applications | Continuously | Whatever those applications send. See below. |
| Authentik's discovery document and keys | On sign-in | Nothing |

There is **no analytics, no telemetry and no third-party script** in the shell. The only outbound
request Workcenter itself can make is a crash report, and only when you set
`appConfig.enableErrorReporting: true`, in which case it goes to the Sentry DSN you provide.

When configuration is fetched, the server strips it to a bootstrap subset for an unauthenticated
request, so an anonymous visitor cannot read the configuration. Authenticated responses are
marked `Cache-Control: private, no-store` and `Vary: Authorization`.

## What the server stores

| Item | Where | Purpose |
| --- | --- | --- |
| `user-data/conf.yml` | The mounted data directory | The configuration |
| Config backups | `user-data/config-backups/` | A copy before each write |
| Container logs | Docker's log driver | Diagnostics, rotated by size |

The server holds no database of its own. It does not record who visits, and it keeps no session
store: the session lives in the token the browser holds.

## What the embedded applications do

The three panes embed **FileBrowser Quantum**, **Zulip** and **SOGo on Mailcow**. Each is in an
iframe on its own subdomain, and Workcenter cannot read what is inside it.

Those applications have their own privacy behaviour, their own storage and their own cookies.
This document does not describe them. Their documentation does:

- [FileBrowser Quantum](https://filebrowserquantum.com/en/docs/)
- [Zulip](https://zulip.com/policies/)
- [SOGo](https://www.sogo.nu/) and [Mailcow](https://docs.mailcow.email/)

What Workcenter does control is the **file broker**, which moves files between them. It:

- authenticates you against Authentik and only acts on your own files and mailbox,
- stores per-user credentials **encrypted at rest**, keyed by a secret held only in `.env`,
- records each transfer — who, what, from where, to where, how many bytes, when — in an audit log,
- never stores the contents of a file it moves.

The audit log is in `user-data/broker/`. It is yours, it is on your host, and deleting it is safe.

## Turning off what can be turned off

| Behaviour | How to stop it |
| --- | --- |
| Crash reporting | Leave `appConfig.enableErrorReporting` unset. It is off by default. |
| The service worker cache | Leave `appConfig.enableServiceWorker` unset, or clear site data |
| Health polling | Not user-selectable. It is a local request to your own server. |
| The auth cookie | Use OIDC, which sets no Workcenter cookie |

## Read next

- [`security.md`](./security.md) — the threat model and hardening
- [`OIDC.md`](../OIDC.md) — how sign-in works
- [`configuring.md`](./configuring.md) — every configuration option
