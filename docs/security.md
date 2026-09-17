# Security

Workcenter is a self-hosted workspace: one page that embeds three applications behind one
identity provider. This page describes what protects it, what the trust boundaries are, and what
it does not protect.

## Contents

- [Dependencies](#dependencies)
- [Securing your environment](#securing-your-environment)
- [Security features](#security-features)
- [Threat model](#threat-model)
- [Known limitations](#known-limitations)
- [Reporting a security issue](#reporting-a-security-issue)

---

## Dependencies

Workcenter is built on open source packages. Their advisories are tracked by Dependabot, which
opens a pull request against `Dev` when one needs attention. See
[`release-workflow.md`](./release-workflow.md).

The integrated applications — FileBrowser Quantum, Zulip, Mailcow/SOGo, ONLYOFFICE, Authentik and
Traefik — carry their own security models. Workcenter deploys them and does not patch them. Each
is pinned in `.env` and updated deliberately.

## Securing your environment

| Ref | Practice |
| --- | --- |
| S-1 | **Terminate TLS at Traefik for every hostname.** No service is published to the internet except Traefik and Mailcow's mail ports. See [`production.md`](../production.md). |
| S-2 | **Authenticate every application with Authentik.** The shell, FileBrowser Quantum, Zulip and Mailcow each use OIDC. The Traefik dashboard sits behind Authentik forward-auth. |
| S-3 | **Restrict access by group.** Bind `workspaceusers` to each application so that authenticating is not the same as being authorised. |
| S-4 | **Generate every secret, and never commit one.** `setup.sh` generates them with `openssl rand`, and they are gitignored. |
| S-5 | **Keep the stack updated.** `git pull` for Workcenter, `./update.sh` for Mailcow, and the pinned tags in `.env` for everything else. |
| S-6 | **Do not enable `Ignore SSL Errors` or `disableVerifyTLS`.** Both exist for testing only. A failing certificate is fixed, not ignored. |
| S-7 | **Back up, and restore once.** A backup that has never been restored is not a backup. |

## Security features

### Sign-in

Authentik is the only identity provider, using the **authorization code flow with PKCE**. Only
**signed** tokens are accepted; an encrypted token is rejected. The server verifies each token
against Authentik's published keys and checks the issuer, audience and expiry.

Administrative access is granted by group membership — `workspaceadmin` — not by a shared
password.

### Server-side token verification

The Express server verifies the bearer token on every protected route. A request carrying no
token is served a **bootstrap subset** of the configuration, so an anonymous visitor cannot read
your configuration; a request carrying an invalid token is rejected.

Authenticated configuration responses are sent with `Cache-Control: private, no-store` and
`Vary: Authorization`, so a shared cache cannot serve one user's configuration to another.

### Framing

Each application is embedded in an iframe. That is a deliberate decision, and it has a security
consequence: an embedded application is only as isolated as its own origin. Workcenter therefore:

- embeds applications only on their own subdomains, never on the Workcenter origin,
- requires each application to permit Workcenter as a frame ancestor, rather than removing the
  protection entirely,
- offers **Open in new tab** from every pane, so a user is never trapped inside a frame.

### Containers

| Control | Where |
| --- | --- |
| Containers run as non-root where the image permits | The Workcenter image runs as the `node` user |
| No container mounts the Docker socket | Except Mailcow's `dockerapi-mailcow` and `ofelia-mailcow`, which require it upstream and are documented |
| No `privileged: true` | Except Mailcow's `netfilter-mailcow`, which requires it upstream |
| Images are pinned | Every tag lives in `.env`, never inline |
| Healthchecks on every service | So a failing service is visible rather than silent |

### Secrets

Secrets live in gitignored `.env` files and `secrets/` directories inside each application's
folder. They are never committed, never logged and never returned by an API. The broker stores
per-user credentials encrypted at rest, keyed by a secret held only in `.env`.

### The file broker

The broker is the only component permitted to write into the file source on behalf of another
application. It authenticates every request against Authentik, authorises each transfer per user,
validates its input before touching an adapter, and records what it did.

## Threat model

### Intended deployment

Workcenter is designed to be **exposed to the internet through Traefik, with Authentik in front of
every application**. That is the supported configuration, and it is what `setup.sh` builds.

The shell is not a security boundary of its own: it is a frame around three applications and a
broker. Each application is responsible for protecting its own data, and Authentik is responsible
for deciding who gets in.

### Trust boundaries

| Boundary | Trusted | Untrusted |
| --- | --- | --- |
| The host | Everything running on it, including the Docker daemon | — |
| The reverse proxy | Traefik's routing and TLS | Anything it forwards |
| The identity provider | Authentik's tokens and group claims | A token that fails verification |
| The embedded application | Its own origin and its own session | Workcenter, and the other panes |
| The browser | The signed-in user's own session | Any script not served by Workcenter |
| The configuration | The operator who writes `conf.yml` | Anything the shell renders from it |

The shell does **not** trust an embedded application. It cannot read inside a pane, which is also
why it cannot help an application that misbehaves.

### Assets

| Asset | Where it lives | Protected by |
| --- | --- | --- |
| Files | FileBrowser Quantum's source directory | FileBrowser's own OIDC and access rules, plus the broker's authorisation |
| Mail | Mailcow's vmail store | Mailcow, and the mailbox's own credentials |
| Chat | Zulip's database and uploads | Zulip's own OIDC and permissions |
| Identity | Authentik's database | Authentik, and the database password in `.env` |
| Session token | The browser's `localStorage` | The origin's integrity. See [`privacy.md`](./privacy.md). |
| Configuration and secrets | `.env`, `conf.yml`, `secrets/` | File permissions and the fact that they are not tracked |
| Certificates | `Traefik/acme.json` | Mode 600, and a backup that is encrypted |

### When Workcenter is not the right choice

- You need **per-file audit trails** across the applications. The broker logs transfers; the
  applications log their own activity separately.
- You want to expose **one application to one group and another to another**, with separate
  hostnames and separate sessions, without a shared shell. Workcenter's value is the shared
  session.
- You require **FIPS-validated or SOC 2 certified** software.
- You cannot run an identity provider. The built-in password fallback is a convenience for a
  private network, not a substitute for Authentik.

## Known limitations

| Limitation | Consequence |
| --- | --- |
| **The session token is in `localStorage`** | Any script on the Workcenter origin can read it. Do not serve third-party scripts from it. |
| **Embedded applications share the browser** | They are separate origins, so they cannot read each other, but they share the device and its cookie jar. |
| **The shell cannot see inside a pane** | It cannot enforce anything inside an application, and cannot tell a working session from an expired one except by the pane showing a login page. |
| **Mailcow's OIDC does not cover mail protocols** | IMAP, SMTP, POP3 and SIEVE authenticate with an app password or LDAP. See [`OIDC.md` §7](../OIDC.md). |
| **SOGo has no native OIDC wired by Mailcow** | The Mailcow UI is the authenticated front door, and SOGo is reached through its session. |
| **No published release yet** | There is no signed image and no SBOM until the first release is cut from `Stable`. |
| **The Playwright suite is not built yet** | Roadmap Phase 7. Until then, CI runs lint, typecheck, the unit and server suites, locale and config validation, and the build. |

## Reporting a security issue

Please **do not open a public issue**. Use
[GitHub's private security advisory](https://github.com/JDB321Sailor/Workcenter/security/advisories/new),
which is the channel described in [`SECURITY.md`](../.github/SECURITY.md).

Include what you found, how to reproduce it, what you think the impact is, and the version or
commit you tested. A report about one of the integrated applications belongs with that project,
unless Workcenter's own configuration is what exposes it.

## Read next

- [`privacy.md`](./privacy.md) — what is stored and what is sent
- [`OIDC.md`](../OIDC.md) — the identity setup
- [`production.md`](../production.md) — TLS, volumes and the production checklist
- [`troubleshooting.md`](./troubleshooting.md) — auth, certificates, and what to check first
