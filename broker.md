# The Workcenter broker

> Three applications, one workspace. The broker is the part of Workcenter that makes that true:
> it is the only component allowed to act on more than one application at a time, and the only one
> that holds a user's credentials for another system. Everything the shell cannot do from inside an
> iframe — moving a file between two applications, changing how another application looks or speaks —
> is the broker's job, and this document is its definitive specification.

| | |
| --- | --- |
| **Status** | Specified (Phase 6 target). The health and preference routes are implemented; the transfer engine is not yet built — [§12](#13-implementation-status) marks exactly what exists |
| **Owner** | `services/utils/broker/` (runtime), `services/broker-server.js` (entry), `src/broker/` (shell client) |
| **Contractual siblings** | [`architecture.md`](./architecture.md) §4 (placement and decisions AR-46…AR-49), [`integration.md`](./integration.md) §9 (integrity rules IN-9.1…IN-9.8), [`design.md`](./design.md) D-6/D-8 (the UI the broker answers to), [`roadmap.md`](./roadmap.md) §7 and Phase 6 (the flows) |
| **Requirement family** | `BR-<section>.<n>` — this document. It **references** `AR-*`, `IN-*`, `D-*`, `U-*`, `I-*` and `T-*`; it never restates or overrides them |

---

## 1. Purpose and scope

### 1.1 What the broker is

The broker is a **server-side, same-origin control plane** mounted at `/api/broker` inside the
Workcenter process. The browser talks to it with the Workcenter session it already has; the broker
talks to FileBrowser Quantum, Zulip, Mailcow/SOGo and Authentik with credentials the browser never
sees.

It exists because two of the shell's requirements are impossible from the client:

1. **A cross-application file move.** The browser cannot read a message attachment from SOGo, a file
   from FileBrowser and an upload target in Zulip in one operation: three origins, three sessions,
   and no shared storage the page may touch. The broker has all three, so the move happens where the
   bytes already are.
2. **A preference that must reach inside another application.** A shell inside an iframe cannot write
   another application's user settings, and a cross-origin frame cannot be inspected to find out
   whether the write worked. The broker performs the write and reports the outcome per application.

### 1.2 What the broker is not

| Not | Because |
| --- | --- |
| A reverse proxy for the panes' UI | The panes are embedded directly (`design.md` D-7). Proxying their HTML would put every page load through the shell's process and break each application's own same-origin assumptions |
| A general API gateway for the applications | Only the routes in [§3](#3-runtime-and-routes) exist. There is no "call any endpoint on any app" route, and there will not be one (BR-2.2) |
| A credential *proxy* for the user's browsing | The broker never hands a credential back to the browser. It uses credentials server-side and returns results (BR-2.3) |
| A file store | Transfers stream through the broker; nothing is retained after the transfer ends, except the audit record and the destination itself (BR-2.4) |
| A way to bypass an application's permissions | Every operation is performed **as the signed-in user** against that application's own authorisation (BR-2.1) |

### 1.3 The five capabilities

| # | Capability | Direction / scope | Specified in |
| --- | --- | --- | --- |
| 1 | **File movement** | Four flows between Files, Chat and Mail | [§5](#5-file-movement) |
| 2 | **Appearance** | The shell's light/dark mode, applied to all three applications | [§6](#6-appearance-the-lightdark-bridge) |
| 3 | **Language** | The shell's language, applied to all three applications | [§7](#7-language-the-locale-bridge) |
| 4 | **Health** | Reachability and framing of each application, for the switcher indicators | [§3.4](#34-get-apibrokerhealth) |
| 5 | **Identity** | Which user the broker is acting for, and with what credentials | [§4](#4-identity-credentials-and-the-vault) |

### 1.4 Where it sits

```
   browser (one origin: https://workcenter.example.com)
   ┌──────────────────────────────────────────────────────────────────────────┐
   │  shell (Vue)                                                             │
   │    pane iframes ──► filebrowser.example.com │ chat.example.com │ mail.…  │
   │         │                                                                │
   │         │  same-origin fetch, session cookie                             │
   │         ▼                                                                │
   │  /api/broker/*  ──►  broker (Node, in the Workcenter process)            │
   └──────────────────────────────┬───────────────────────────────────────────┘
                                  │  server-to-server, never through the browser
        ┌─────────────────────────┼──────────────────────────┬─────────────────┐
        ▼                         ▼                          ▼                 ▼
  FileBrowser Quantum        Zulip API                 Dovecot IMAP      Authentik (verify)
  HTTP API + shared source   uploads + messages        Mailcow mailbox   token / userinfo
        │                         │                          │
        └─────── shared disk ─────┴──────────────────────────┘
             (the three applications' data lives on one storage domain)
```

Two properties of that picture decide most of this document:

- **The broker is on the same disk as the data.** Workcenter deploys FileBrowser Quantum's source
  directory, and reads Mailcow's mail store through its own APIs, on one host
  ([`integration.md` IN-9.6](./integration.md)). File bytes therefore move **by path** where the store
  is local, and **through an API** only where the store is genuinely remote — which for these three
  applications means Zulip's upload store and the IMAP mailbox (BR-5.2).
- **The broker is trusted; the browser is not.** Anything the browser sends is untrusted input,
  including the identity it claims to be (BR-2.1).

> **Rule BR-1.1:** the broker performs an action **as the signed-in user**, against that
> application's own authorisation. It never uses a privileged service account to reach user data.
> **Rule BR-1.2:** the broker is **not** a proxy. If a capability needs a new upstream call, it gets a
> named route with a typed contract, an authorisation test and an entry in this document — not a
> passthrough.
> **Rule BR-1.3:** every capability answers with a **per-application outcome**, so a partial success is
> reported as a partial success ([`design.md` D-6.1](./design.md)).

---

## 2. Invariants

These hold for every route, every adapter and every future transfer. A change that breaks one is a
security defect, not a feature (BR-2.8).

| # | Invariant | Why |
| --- | --- | --- |
| BR-2.1 | **Identity comes from the session, never the request.** The acting user is resolved from the verified OIDC token. No route accepts a username, mailbox, source or path that implies a different user, and no route acts on a user named in a body ([`architecture.md` AR-47](./architecture.md)) | A body-supplied identity is a privilege-escalation hole; this is the one an attacker will try first |
| BR-2.2 | **Addresses come from configuration, never from the request.** Every upstream URL is built from `appConfig.applications.*.url` or a value derived from it. A path, filename or id from the client is validated and then appended to a configured base — never treated as a URL | Server-side request forgery; a broker that can be pointed at `http://169.254.169.254` is worse than no broker |
| BR-2.3 | **Credentials never leave the server.** No route returns a password, API key, token or cookie; no log line, error message or audit record contains one ([`integration.md` IN-9.5](./integration.md)) | The browser is the least trustworthy place for another application's credential |
| BR-2.4 | **Transfers stream.** Memory use is bounded by a buffer, not by file size; the spool is a temporary file in a private directory, removed when the transfer ends, whatever the outcome ([IN-9.2](./integration.md)) | A 4 GB attachment must not become 4 GB of heap |
| BR-2.5 | **Nothing is written to another application's store behind its back.** Mailcow and Zulip are **read-only from the disk's point of view**; every write goes through IMAP or the Zulip API ([IN-9.7](./integration.md)) | Writing into Dovecot's or Zulip's storage directly corrupts indexes and caches |
| BR-2.6 | **The only direct writes are into the FileBrowser source**, and only with temp-file-then-atomic-rename in the destination directory ([IN-9.3](./integration.md)) | FileBrowser indexes that directory; a half-written file would be indexed as a real one |
| BR-2.7 | **Framing is never weakened by the broker.** No route rewrites `X-Frame-Options` or CSP, and a pane that an application refuses to frame is reported as `blocked`, never "fixed" by stripping a header ([`design.md` D-7.1](./design.md), [`roadmap.md` R14](./roadmap.md)) | Clickjacking protection belongs to the application that set it |
| BR-2.8 | **A new capability ships with its tests** — authorisation, SSRF-rejection, oversized input, secret-leak and failure-path tests, in the same change ([`architecture.md` AR-45](./architecture.md), [`Testing.md` §5](./Testing.md)) | The broker's blast radius is every user's data in three systems |

> **Rule BR-2.9:** an outcome the broker cannot determine is reported as `unknown`, never as success
> and never as failure ([`architecture.md` AR-49](./architecture.md)).

---

## 3. Runtime and routes

### 3.1 Process and placement

| Layer | Path | Responsibility |
| --- | --- | --- |
| Mount | `services/app.js` | Mounts the broker router **before** the opt-in `/api` router, so its own 404 gate cannot shadow it |
| Entry | `services/broker-server.js` | Builds the router, wires the adapters, resolves credentials per request |
| Router | `services/utils/broker/index.js` | Route table, input validation, authorisation, error mapping |
| Transport | `services/utils/broker/transport.js` | Outbound HTTP with timeouts and TLS verification; the only place a socket is opened |
| Adapters | `services/utils/broker/adapters/` | One module per application per capability: `preferences.js`, and (Phase 6) `files.js`, `mail.js`, `chat.js` |
| Engines | `services/utils/broker/engine/` | `preferences.js` (fan-out), and (Phase 6) `transfer.js`, `naming.js`, `audit.js` |
| Vault | `services/utils/broker/vault.js` (Phase 6) | Encrypted per-user credentials |
| Shell client | `src/broker/client.js`, `src/broker/preferences.js` | Typed fetch wrapper, bearer token, timeouts, typed results |

The broker runs **in the Workcenter process**, behind the same TLS terminator, on the same origin as
the shell. That is deliberate: it inherits the session, the CSRF posture and the network position of
the shell, and it needs no second certificate or second ingress rule (BR-3.1).

> **Rule BR-3.1:** the broker is reachable **only** from the Workcenter origin. It is not exposed on a
> second hostname, and no deployment may add one for it.

### 3.2 Route table

| Method | Route | Purpose | Auth | Capability |
| --- | --- | --- | --- | --- |
| `GET` | `/api/broker/health` | Reachability and framing of each application | **None** (no user data) | [§3.4](#34-get-apibrokerhealth) |
| `POST` | `/api/broker/preferences` | Appearance and language fan-out | Session | [§6](#6-appearance-the-lightdark-bridge), [§7](#7-language-the-locale-bridge) |
| `GET` | `/api/broker/files/list?path=` | List one directory of the user's FileBrowser source, for the picker | Session | [§5.7](#59-the-filebrowser-calls-the-engine-makes) |
| `GET` | `/api/broker/files/stat?path=` | Existence, size and hash of one path — the de-duplication probe | Session | [§5.9](#512-naming-collisions-and-de-duplication) |
| `GET` | `/api/broker/mail/messages/:id/attachments` | The attachment list for one message | Session | [§5.9](#510-listing-a-messages-attachments) |
| `POST` | `/api/broker/mail/attachments/save` | **F1** — save a mail attachment into the file source | Session | [§5.4](#54-f1--mail--files) |
| `POST` | `/api/broker/mail/attachments/attach` | **F2** — attach a file-source file to a mail draft | Session | [§5.5](#55-f2--files--mail) |
| `POST` | `/api/broker/chat/files/save` | **F3** — save a Zulip attachment into the file source | Session | [§5.6](#56-f3--chat--files-and-f4--files--chat) |
| `POST` | `/api/broker/chat/files/send` | **F4** — send a file-source file into a Zulip message | Session | [§5.6](#56-f3--chat--files-and-f4--files--chat) |
| `POST` | `/api/broker/chat/files/attach` | **F6** — attach a Zulip attachment to a mail draft | Session | [§5.8](#58-f6--chat--mail) |
| `POST` | `/api/broker/mail/attachments/send` | **F5** — send a mail attachment into a Zulip message | Session | [§5.7](#57-f5--mail--chat) |
| `GET` | `/api/broker/transfers/:id` | Progress and result of one transfer | Session | [§5.8](#511-progress-cancellation-and-retry) |
| `POST` | `/api/broker/transfers/:id/cancel` | Cancel an in-flight transfer | Session | [§5.8](#511-progress-cancellation-and-retry) |

Every route above is the one [`architecture.md` §4.3](./architecture.md#43-broker-api-surface) lists, with a
single addition: `GET /api/broker/mail/messages/:id/attachments`, which the Mail pane's attachment panel
needs ([design.md D-8.1](./design.md)) and which is added to that table in the same change. The flows
are per-flow routes rather than one `POST /transfers` with a `flow` field, so that each has its own
typed body, its own validation and its own authorisation test (BR-3.5).
> **Rule BR-3.2:** the route table is closed. `/api/broker/health` is the only unauthenticated route
> and it returns liveness and per-application reachability, never anything about a user
> ([`architecture.md` AR-15](./architecture.md)).
> **Rule BR-3.3:** an unknown id, a malformed body or a path that fails validation is rejected with a
> typed error **before** any adapter is called ([`Testing.md` §5](./Testing.md)).
> **Rule BR-3.4:** a `reason` is a stable code, not a sentence. Prose belongs in `en.json`, keyed by
> the code ([`design.md` D-I3](./design.md)).
> **Rule BR-3.5:** the per-flow routes exist so that each flow has its own contract: a new flow adds a
> route rather than a branch inside an existing one.
### 3.3 Request and response shape

Every authenticated route answers with the same envelope, so the shell's client has one shape to
handle and one place to look for a reason:

```jsonc
{
  "outcome": "ok",              // ok | partial | unavailable | unsupported | denied | failed
  "apps": {                     // per-application result, always present for fan-out routes
    "files": { "state": "ok" },
    "chat":  { "state": "unsupported", "reason": "no-language-setting" },
    "mail":  { "state": "unavailable" }
  },
  "reason": null                // a stable machine-readable code when outcome is not ok
}
```

`reason` values are a closed vocabulary (BR-3.4) so the shell can translate them
(`design.md` D-6.1's inline notes) without parsing prose, and so an operator can grep the audit log.

### 3.4 `GET /api/broker/health`

| Property | Behaviour |
| --- | --- |
| Auth | None. It reports only what an unauthenticated caller could learn from the applications' own front pages |
| Method | Server-side fetch of each configured address, per application |
| Reports | `state` (`healthy` / `degraded` / `unhealthy` / `unknown`), the failing `endpoint`, `since`, and `frameBlocked` when the response refuses framing |
| Never | A user's data, a credential, a session, or a check that requires one |
| Failure | A check that cannot run is `unknown` — never `unhealthy` ([AR-49](./architecture.md)) |

The shell's `HealthService` polls it and the switcher renders one indicator per application
([`design.md` D-2S](./design.md)). The `frameBlocked` flag is what lets a pane say "this application
refuses to be embedded" instead of showing a blank frame ([BR-2.7](#2-invariants)).

---

## 4. Identity, credentials and the vault

### 4.1 Who the broker is acting for

| Step | Source |
| --- | --- |
| Session | The Workcenter OIDC session (Authorization Code + PKCE, silent renew), verified server-side per request ([`OIDC.md`](./OIDC.md)) |
| Subject | `sub` — the stable user id |
| Username | `preferred_username` — matches the FileBrowser, Zulip and Mailcow account names in the standard deployment |
| Groups | `groups` — the `profile` scope must be requested or the claim is absent ([`integration.md` IN-7.6](./integration.md)) |
| Admin | membership of the configured `adminGroup` |

The broker resolves the identity itself from the verified token. It **never** reads a username from a
query string, body or header (BR-2.1).

### 4.2 Where credentials come from

The three applications live on their own origins (`files.example.com`, `chat.example.com`,
`mail.example.com`). Their session cookies are therefore **not** sent to the Workcenter origin, and
the broker cannot read them: a cookie belongs to the host that set it, and nothing in the browser
hands it to a sibling host. A design that assumes "the user is already signed in over there, so the
broker can borrow that session" is wrong, and building on it would produce a broker that works only
in the one deployment where an operator happened to widen a cookie domain (BR-4.4).

So the broker works from credentials it is *given*, in this order:

| Order | Strategy | Used for | At rest |
| --- | --- | --- | --- |
| 1 | **Per-user credential in the vault** — a purpose-built credential the user creates in that application for automation, and hands to the broker once | Zulip API key, FileBrowser API token, Mailcow IMAP password | Encrypted (BR-4.3) |
| 2 | **Session cookie on the Workcenter origin** — available only when the application shares the Workcenter *origin* (path-based routing, e.g. `example.com/files`), because that is the only way the browser sends its cookie to `/api/broker` | FileBrowser Quantum, once the operator fronts it on the same origin. **Not Zulip**: its `/api/…` routes reject a cookie outright, and its cookie-authenticated routes (`/json/…`, uploads, TUS) additionally need a CSRF token a broker cannot take from another origin | No |
| 3 | **Deployment service account** — only for operations that are *inherently* administrative and that return no user data. None of the five capabilities needs one today; the health probe needs no credential at all | — | Encrypted |

silently: one cookie valid for every subdomain is one cookie stolen with any of them, and it makes the
silently: one cookie valid for every subdomain is one cookie stolen with any of them, and it makes the
broker depend on the user having visited that application in this browser. It is supported because some
operators prefer SSO-everywhere to per-application tokens; it is not the default, and every flow reports
which strategy it used, so an operator can see what their deployment relies on.

> **Rule BR-4.1:** a credential the broker does not hold is a credential it cannot leak. Prefer the
> narrowest credential that can do the job, and one the user can revoke on its own.
> **Rule BR-4.2:** the broker never stores a user's **primary** password for any application. Only a
> credential created for this purpose — an API key, an app password, an IMAP password the user has
> entered knowingly — and never without telling the user what it is for.
> **Rule BR-4.3:** every stored credential is encrypted at rest with a key that exists only in `.env`
> ([IN-9.5](./integration.md)); the vault file is unreadable without it, including to someone who
> copies `user-data/`.
> **Rule BR-4.4:** no capability may depend on a cookie the browser would not send. A widened cookie
> domain is an operator's option, never a load-bearing assumption.
> **Rule BR-4.5:** a user-initiated action uses the user's own credential, never a bot's or a service
> account's. Where an upstream API refuses a bot outright — as Zulip's settings endpoint does — that is the
> design confirming itself, not an obstacle.
### 4.3 The vault

| Property | Specification |
| --- | --- |
| File | `user-data/broker/credentials.json` — one record per (user, application) |
| Cipher | AES-256-GCM, a fresh 96-bit nonce per write, the record's `user`+`app` as additional authenticated data so a record cannot be moved between users |
| Key | `BROKER_VAULT_KEY` (32 bytes, base64) from `.env`; the broker refuses to start without it and says why |
| Record | `{ user, app, kind, ciphertext, nonce, tag, created, lastUsed, label }` — `label` is the user's own note ("Zulip key, created 2026-03"), never the secret |
| Rotation | A key id per record; the broker decrypts with the matching key and re-encrypts on next use, so rotation is a config change plus time, not a migration outage |
| Never | Logged, returned, included in an audit record, or echoed in an error message |
| Missing credential | `unavailable` with reason `no-credential`, and the shell offers the setup link for that application. It is never a 500 |
| Deletion | User-initiated revocation removes the record; revoking in the application makes the record useless but does not remove it — the broker reports `denied` and prompts |

### 4.4 What each application needs

| Application | Credential | Obtained how | Used for | If absent |
| --- | --- | --- | --- | --- |
| FileBrowser Quantum | A **user API token**, sent as `Authorization: Bearer <jwt>` (never as the `?auth=` query parameter, which leaks into logs and referrers) | `POST /api/auth/token?name=<label>&days=<n>` on the user's own session — the API behind the "API keys" screen. It requires the user's global `api` permission, so a deployment either grants that to its users or has an administrator mint one per user | Listing the user's source, resolving the user's scope, reading metadata, refreshing a directory's index | Directory listings are `unavailable`; the flows that only touch the shared disk still work (BR-5.2) |
| Zulip | The user's **API key** (HTTP Basic `email:api_key` on `/api/…`, which is the only scheme that endpoint accepts) | The user copies it from Zulip's **Settings → Account & privacy → API key** | Uploading a file, sending the message that carries it, patching the user's own settings, reading the caller's own upload list | Chat writes are `unavailable` with reason `no-credential` |
| Mailcow / SOGo | A **Mailcow app password created with IMAP access**, over IMAP with TLS | The user creates it in Mailcow under *Mailbox → App Passwords* and ticks IMAP access — a credential made for this purpose, revocable on its own | Listing attachments, fetching a MIME part, appending a draft | Mail flows are `unavailable` with reason `no-credential` |
| Authentik | None (the broker verifies tokens) | — | Verifying the session, reading groups | The broker cannot authenticate anyone; every route is `denied` |

**On bots.** An earlier plan in [`roadmap.md`](./roadmap.md) had the Chat flows use a Zulip **bot** API key. That is not what this document specifies, and the reasons are upstream facts rather than preference: a message sent with a bot key appears as the **bot**; a bot cannot call `PATCH /api/v1/settings` at all (`@human_users_only`); a bot posts only where its *owner* may post, so the permission it needs is the owner's subscription list rather than the user's; and a bot cannot list another user's uploads. A bot key remains the right credential for **setup-time, realm-scoped** work — branding, realm defaults, the admin pass ([`integration.md` IN-5.22](./integration.md)) — where no user is being impersonated. It is the wrong credential for anything a user initiates (BR-4.5).

**On the mail credential.** Mailcow issues **app passwords**, and an app password can be created with
IMAP access alone ([§12](#12-upstream-verification)). That is the credential the broker asks for: it is
revocable on its own, and revoking it does not lock the user out of their mail. The mailbox password is
never requested; where a deployment's Mailcow predates app passwords, the mail flows are `unavailable`
rather than the broker starting to collect primary secrets.

Two credentials exist and are **refused**:

- **Dovecot's master user** (`auth_master_user_separator` with a `master = yes` passdb). It authenticates
  as *any* mailbox in one step — the "one credential that reads every user's mail" that BR-1.1 and BR-4.1
  exist to prevent. A deployment that enables it for its own administration is not a deployment the broker
  uses it in.
- **SOGo's proxy-authentication header.** Mailcow runs SOGo with proxy authentication trusted, and SOGo's
  proxy authenticator accepts `x-webobjects-remote-user` **without checking any password**. Anything on the
  mail network can become any user by asserting one header. The broker never sends it: that would not be an
  integration, it would be an impersonation exploit with a friendly name ([§8.7](#87-designs-that-are-refused)).

---

## 5. File movement

### 5.1 The six flows

Three applications, each of which can be the source or the destination of a file: that is **six
ordered pairs**, and all six are flows the shell offers. They are the reason the broker exists, and
none of them is optional — a matrix with a hole in it is a user who cannot do the obvious thing.

| Source ↓ / Destination → | **Files** | **Chat** | **Mail** |
| --- | --- | --- | --- |
| **Mail** | — | **F5** Mail → Chat | — |
| **Chat** | **F3** Chat → Files | — | **F6** Chat → Mail |
| **Files** | — | **F4** Files → Chat | **F2** Files → Mail |

| Flow | Direction | Where the user starts it | Requirement |
| --- | --- | --- | --- |
| **F1** | Mail → Files | **Save to files** in the shell's Mail attachment panel | [`roadmap.md` §7.2](./roadmap.md), [`design.md` D-8.1](./design.md) |
| **F2** | Files → Mail | **Attach from files** — the file picker opens on the mail draft | [`design.md` D-8.2](./design.md) |
| **F3** | Chat → Files | **Save to files** in the shell's chat attachment chooser | [`design.md` D-8.5](./design.md) |
| **F4** | Files → Chat | **Send from files** — the file picker opens on a chat target | [`design.md` D-8.2](./design.md) |
| **F5** | Mail → Chat | **Send to chat** in the shell's Mail attachment panel | [`design.md` D-8.1](./design.md) |
| **F6** | Chat → Mail | **Send to mail** in the shell's chat attachment chooser | [`design.md` D-8.5](./design.md) |

All six share one engine; only the two ends differ. Two flows read the shared disk (F2, F4) and four read
through an application's own API (IMAP for Mail, Zulip's API for Chat); each application is written to
exactly twice (Files by F1 and F3, Chat by F4 and F5, Mail by F2 and F6). The engine is therefore three
readers and three writers composed six ways (BR-5.19).

**Where the user starts a flow is a shell decision, not a pane decision.** None of the three
applications can be injected into from outside: each is a cross-origin frame, so the shell cannot add a
button beside an attachment in SOGo or an action beside a file in Zulip. The shell therefore owns one
**source chooser** per application — the Mail attachment panel, the chat attachment chooser, and the file
picker — and every flow begins in one of them ([`design.md` D-8](./design.md)). The broker supplies the
lists those choosers render ([§5.9](#510-listing-a-messages-attachments)) and performs the move.
### 5.2 How bytes move: by path, or by API

This is the decision the rest of §5 depends on, so it is stated once.

| Store | Where the bytes are | How the broker reaches them |
| --- | --- | --- |
| FileBrowser Quantum source | A directory on the host, mounted into the broker at the same path FileBrowser uses ([IN-9.6](./integration.md)) | **Directly, by filesystem path** — read and (for F1/F3) write with temp-file-then-atomic-rename |
| Mailcow mailbox | Dovecot's mail store — a **named Docker volume**, owned by the `vmail` user (uid 5000) with `0700` directories and `0600` files, encrypted at rest (`mail_crypt_save_version = 2`), quota-tracked in SQL, and read with `maildir_very_dirty_syncs` enabled | **IMAP over TLS only** — the broker treats Mailcow as read-only on disk ([IN-9.7](./integration.md)). Mounting that volume to read it would require running as uid 5000 and would hand the broker **every** mailbox; writing to it would corrupt a UID list, an index and a quota that only Dovecot maintains |
| Zulip uploads | Zulip's own store (local or object storage) | **Zulip HTTP API only** — upload, then attach |

> **Rule BR-5.1:** bytes move by path **only** where the path is the same file the application
> serves, and the equivalence is asserted at startup (BR-5.3). Everywhere else, the application's own
> API is used, even when a shorter filesystem route exists.

FileBrowser Quantum also offers an API route into the same directory — `POST /api/resources` with the
bytes as the **raw request body**, and a chunked variant driven by `X-File-Chunk-Offset`,
`X-File-Total-Size` and `X-File-Upload-Session` that writes `<dest>.<md5>.uploading.tmp`, verifies the
total size and then moves it into place ([§12](#12-upstream-verification)). It is a good protocol, and
it is **not** how F1 and F3 write: it would copy every byte through HTTP into the process that already
has those bytes on disk, purely to make the application re-index them. The broker writes by path and
then refreshes the index itself ([BR-5.7](#514-the-audit-record)) — the same guarantee without the copy
(BR-5.8).
> **Rule BR-5.2:** the broker never writes into another application's store, even where it has the
> permission to ([IN-9.7](./integration.md)).
> **Rule BR-5.8:** the by-path route is justified by *the same file*, not by speed. Where the mount is
> not provably the same directory (BR-5.3), the flow falls back to the application's API — and when it
> does, it uses the chunked upload protocol, never the header-less variant that writes straight to the
> destination with no size verification.

### 5.3 Startup assertion: one disk, two views

The by-path optimisation is only sound if FileBrowser and the broker are looking at the same
directory. The broker asserts it at startup, and refuses to offer the by-path routes if the assertion
fails:

| Check | Failure behaviour |
| --- | --- |
| `BROKER_FILES_ROOT` is set and exists, and is the mount FileBrowser serves | Log an error naming both paths; the three by-path flows report `unavailable` with reason `root-mismatch`, and the shell says so plainly instead of failing mid-transfer |
| The root is writable by the broker's user | Same, for the flows that write (F1, F3) |
| The root is not writable **by accident** — the write path goes through the naming engine, never a raw path from the client | Path validation ([§8.5](#85-path-traversal-and-filename-safety)) |

The assertion is a startup probe, not a one-time configuration hope: a mis-mounted volume is the most
likely deployment error, and it must fail loudly at boot rather than silently moving bytes to a
directory FileBrowser will never show (BR-5.3).

> **Rule BR-5.3:** the by-path flows are offered only while the startup assertion holds. A
> mis-mounted volume is a deployment error that must stop the flows that would silently write where
> nobody is looking — and must never degrade into "the transfer succeeded but the file is not there".

### 5.4 F1 — Mail → Files

**The highest-priority flow** (`roadmap.md` §7.2). From the user's point of view: open a mail, press
**Save to files** on an attachment, watch progress, get a toast with **Open folder**.

| Step | Actor | What happens |
| --- | --- | --- |
| 1 | Shell | The Mail pane lists the message's attachments ([§5.7](#59-the-filebrowser-calls-the-engine-makes)) and shows **Save to files** per attachment ([D-8.1](./design.md)) |
| 2 | Shell → broker | `POST /api/broker/mail/attachments/save` with `{ messageId, partId }` — **no path, no mailbox, no username** |
| 3 | Broker | Resolves the user, the mailbox (from the session, never the body), and the credential |
| 4 | Broker → Mail | IMAP `SELECT` the folder, `FETCH` the message's `BODYSTRUCTURE`, locate `partId`, `FETCH BODY.PEEK[partId]`, decode the transfer encoding |
| 5 | Broker | Streams the decoded part to a spool file in the private temp directory, hashing as it goes (SHA-256) |
| 6 | Broker | Resolves the destination directory inside the FileBrowser source, sanitises the filename, and applies the naming engine ([§5.9](#512-naming-collisions-and-de-duplication)) |
| 7 | Broker | Writes `.<name>.<random>.part` **in the destination directory**, `fsync`s, then `rename()`s it to the final name — atomic within one filesystem ([IN-9.3](./integration.md)) |
| 8 | Broker → FileBrowser | Refreshes the destination directory's index — see "the index gap" below. Skipping this step is why a by-path write can be invisible in the Files pane |
| 9 | Broker → shell | `done` with `{ path, bytes, sha256, deduplicated }`; the shell toasts **Open folder** deep-linking to that directory in the Files pane |
| 10 | Broker | Writes the audit record ([§5.11](#514-the-audit-record)), deletes the spool file |

Nothing is fetched from SOGo's web UI and no browser session is involved (BR-8.7).

**The index gap, and why step 8 exists.** FileBrowser Quantum has **no filesystem watcher**: it indexes
on a schedule whose tiers run from five minutes to twelve hours, and it exposes no rescan endpoint
([§12](#12-upstream-verification)). A file written straight to the source directory is therefore
*correct on disk and absent from the Files pane* until that directory is scanned — which, from the
user's side, looks exactly like a failed transfer.

The supported way to close the gap is the one the application itself uses: `GET /api/resources?path=<dir>`
on a directory makes FileBrowser re-stat **that directory level** before answering
(`processDirectoryMetadata` → `RefreshDirectory`), and it is non-recursive and suppressed by
`skipExtendedAttrs=true`. So the broker asks for the destination directory with
`skipExtendedAttrs` unset, discards the body, and only then reports `done`. That is one authenticated
request to the user's own FileBrowser, with the user's own token, for the user's own directory — no
privilege is borrowed and nothing is forced beyond the level that changed (BR-5.7).

### 5.5 F2 — Files → Mail

From the user's point of view: in SOGo's compose window press **Attach from files**, choose one or
more files, and they appear as attachments on the draft.

| Step | Actor | What happens |
| --- | --- | --- |
| 1 | Shell | Opens the picker ([D-8.2](./design.md)); folders and files come from `GET /api/broker/files/list` ([§5.7](#59-the-filebrowser-calls-the-engine-makes)) |
| 2 | Shell → broker | `POST /api/broker/mail/attachments/attach` with `{ paths: [...], draft: { to, subject, body } }` — the draft fields are the user's own compose state, not a credential |
| 3 | Broker | Validates every path against the user's source root ([§8.5](#85-path-traversal-and-filename-safety)), and the total size against the cap ([§5.10](#513-limits-and-backpressure)) |
| 4 | Broker | Builds a MIME message: the draft headers, a `multipart/mixed` body, one part per file with `Content-Disposition: attachment; filename=…` and the size-preserving transfer encoding |
| 5 | Broker → Mail | IMAP `APPEND` to the Drafts mailbox with the `\Draft` flag (and `\Seen` when the user should not see it as unread), streaming the message: `APPEND "Drafts" (\Draft) {<literal-size>}`. The mailbox is **resolved by its `\Drafts` SPECIAL-USE flag from `LIST`**, never by hard-coding a name — Dovecot creates localised aliases alongside it. The reply carries `APPENDUID`, which is the id the result reports |
| 6 | Broker → shell | `done` with `{ draftUid, folder }`; the shell toasts **Open draft**, deep-linking to the Drafts view in the Mail pane |
| 7 | Broker | Audit record; spool cleanup |

**Why a draft, and not a sent message.** The roadmap allows either ("SMTP submission via
`postfix-mailcow`, or the SOGo compose UI's own upload endpoint when available"). SMTP submission is
available with the mailbox credential and it is rejected as the default for one reason: sending mail is
not the user's action until the user says so. A broker that attaches a file *and* sends the message has
sent mail on someone's behalf from a button labelled **Attach**. A draft is the honest end state — the
file is attached, nothing has left the building, and the user completes the send in SOGo where they can
see the recipients (BR-5.15). A future "send this file to…" flow is welcome; it is a different button,
with an explicit recipient confirmation, and it is not this flow.

**What the message must look like for SOGo to open it as a draft.** SOGo decides "this is a draft" from
**folder membership, not the `\Draft` flag** — so the append target is what matters most — and it then
re-ingests the message from IMAP when the user presses **Edit**. The MIME structure therefore mirrors
what SOGo itself writes: a `multipart/mixed` container, the body as the first part (plain text, or
`multipart/alternative` for an HTML draft), then one part per file with the real filename in **both**
`Content-Type; name=` and `Content-Disposition; filename=`, `base64` transfer encoding, and `attachment`
disposition for everything that is not text or an image ([§12](#12-upstream-verification)). RFC 2231/2047
encoding is used for non-ASCII names.

**One limitation, stated rather than hidden.** SOGo keeps its own draft *spool* (a `.info.plist` and the
attachment files) beside the message. A draft the broker appended has no spool entry, so when the user
edits and saves it SOGo creates a **new** spool draft — which can leave the broker's appended message
behind as a stale copy in Drafts. Removing it from outside is not something the broker can do reliably,
because it cannot know when SOGo has finished with it. The design accepts the duplicate and says so; the
alternative — reaching into SOGo's internals — is refused in [§8.7](#87-designs-that-are-refused) (BR-5.18).

Why a **draft** rather than a sent message: attaching to a message that has not been sent is the
user's action to complete, and it is the only route that does not require the broker to hold SMTP
submission rights or to send mail on the user's behalf (BR-8.7). The roadmap allows either ("the SOGo
compose UI's own upload endpoint when available"); the compose endpoint is SOGo-internal and
session-driven, which BR-8.7 refuses, so IMAP `APPEND` is the specified method. When the user sends
the draft, SOGo sends it — with the user's own identity and the user's own signature.

### 5.6 F3 — Chat → Files, and F4 — Files → Chat

**F4 (Files → Chat).** The user presses **Send from files** in the Zulip compose box, picks a file, and
it arrives in the conversation as a message with the attachment.

**Two things this flow deliberately does *not* do, and why.** The roadmap's first wording for F4 had the
shell "insert the returned Markdown link into the message being composed" ([`roadmap.md` §7.2](./roadmap.md)).
That cannot work: the composer lives in a cross-origin frame, so the shell can neither read it nor type
into it, and Zulip exposes no inbound channel a host page may drive. The link would have nowhere to go.
For the same reason the upload cannot be attributed to a bot: a message posted by a bot key appears as the
bot, which is not the user's action. So the broker uploads with the **user's own** credential and sends
the message, and the roadmap's wording is corrected in the same change (BR-5.14).

| Step | Actor | What happens |
| --- | --- | --- |
| 1 | Shell → broker | `POST /api/broker/chat/files/send` with `{ path, target: { kind: "stream"|"dm", id, topic } }` |
| 2 | Broker | Reads the file **from the shared source by path** (BR-5.2) and validates it against the cap |
| 3 | Broker → Zulip | `POST /api/v1/user_uploads` — multipart, exactly one part, authenticated with the user's own API key as HTTP Basic `email:key`. The response carries `url` (a relative `/user_uploads/<path_id>`) and `filename`. Files at or above the endpoint's ceiling take the resumable path instead: `/api/v1/tus`, which the deployment's nginx does not size-cap ([§5.6.1](#561-the-two-zulip-write-paths)) |
| 4 | Broker → Zulip | `POST /api/v1/messages` with `content` containing the Markdown link `[filename](url)`. **There is no `file` parameter on Zulip's send endpoint** — an attachment travels as a link in the message body, and the server claims the upload to that message when it sees the path. Images and audio are prefixed with `!` so they render inline, exactly as Zulip's own client does |
| 5 | Broker → shell | `done` with `{ messageId, url, filename }` and the deep link the broker built for it — Zulip 12.2 returns no message URL, so the shell is given one |

#### 5.6.1 The two Zulip write paths

| Path | Used when | Why |
| --- | --- | --- |
| `POST /api/v1/user_uploads` | The file is below the deployment's multipart ceiling | Simplest; one request. Zulip's own limit for a self-hosted realm defaults to 100 MiB, but **nginx caps the plain multipart endpoint at 25 MiB** (`client_max_body_size 25m`), so the ceiling the broker obeys is the smaller of the two — and it is configuration, not a constant |
| `/api/v1/tus` | The file is at or above that ceiling | Zulip's resumable endpoint, served by tusd behind nginx with `client_max_body_size 0`. Required by the protocol: `Tus-Resumable: 1.0.0`, then `Upload-Length` and `Upload-Metadata` (`filename`, `filetype`) on the creation POST, then `PATCH` chunks with `Content-Type: application/offset+octet-stream` and `Upload-Offset`; a `HEAD` returns the current offset, which is how a retry resumes instead of restarting. The hook answers with `{url, filename}` — the same shape the simple path returns |

Two consequences the engine must respect:

- **The threshold is read, not guessed.** The broker takes the multipart ceiling from configuration and falls back to the documented 25 MiB; it does not assume 100 MiB because the API would accept it.
- **TUS is also the cheap path for rate limits.** Zulip rate-limits *API requests* per user (200 per minute by default, buckets per user, `X-RateLimit-*` headers, `429` with `Retry-After`), and tusd does not consume that budget. A large transfer that would spend dozens of requests goes through TUS and spends one.

> **Rule BR-5.16:** the broker chooses the upload path from the file's size and the deployment's ceiling, and it never assumes a limit it has not read. A `413` is a configuration fact to record, not a mystery to retry.
> **Rule BR-5.17:** the broker respects Zulip's per-user request budget: it reads `X-RateLimit-Remaining` and backs off on `429` using `Retry-After`. The 200/minute figure in [`integration.md` IN-9.8](./integration.md) is that budget, not a separate rule.


| Step | Actor | What happens |
| --- | --- | --- |
| 1 | Shell → broker | `POST /api/broker/chat/files/save` with `{ messageId, uri }` |
| 2 | Broker | Confirms the `uri` belongs to an upload the **user can see** (it resolves the message first and takes the uri from the message, rather than trusting a url from the client body — BR-2.2) |
| 3 | Broker → Zulip | Streams the attachment content with the user's credential |
| 4 | Broker | Hashes while streaming, spools, then atomic-renames into the FileBrowser source exactly as F1 steps 6–8, including the index refresh (F1 step 8). A file that exists on disk but not in the index is, to the user, a file that is missing |
| 5 | Broker → shell | `done` with `{ path, bytes, sha256 }` and the **Open folder** action |

Content de-duplication applies to both F1 and F3: an identical file already in the destination is
reported as `deduplicated` rather than written twice ([§5.11](#512-naming-collisions-and-de-duplication)).

> **Rule BR-5.19:** the flows are six compositions of three readers (FileBrowser's disk, IMAP, the Zulip
> API) and three writers (the same three, in the other direction). A flow that needs a *new* mechanism is a
> design change, not another row in the matrix.
> **Rule BR-5.14:** a transfer completes through an API the broker can call, with the user's own
> credential. A flow whose last step would have to be performed inside another application's UI is not a
> flow — it is two half-actions and a hope.

### 5.7 F5 — Mail → Chat

From the user's point of view: open a mail, press **Send to chat** on an attachment, choose the
conversation (a channel and topic, or a direct message), and the file arrives in Zulip as a message with
the attachment, sent **as the user**.

| Step | Actor | What happens |
| --- | --- | --- |
| 1 | Shell | The attachment row gains **Send to chat** beside **Save to files** ([`design.md` D-8.1](./design.md)); the target picker reuses the Chat pane's own channel/topic list |
| 2 | Shell → broker | `POST /api/broker/mail/attachments/send` with `{ messageId, partId, target: { kind: "stream"\|"dm", id, topic } }` — no mailbox, no username, no URL |
| 3 | Broker | Resolves the user, the mailbox from the session, and both credentials (IMAP for the read, the user's Zulip key for the write). If either is missing the transfer is `unavailable` / `no-credential` **before** anything is read |
| 4 | Broker → Mail | IMAP `SELECT`, `BODYSTRUCTURE`, then `FETCH BODY.PEEK[partId]` for that one part; the transfer never touches the rest of the message |
| 5 | Broker | Streams the decoded part through the spool, hashing as it goes, and enforces the size cap **before** the upload |
| 6 | Broker → Zulip | Uploads the spooled bytes exactly as F4 does — `POST /api/v1/user_uploads`, or `/api/v1/tus` above the ceiling — with the user's own API key ([§5.6.1](#561-the-two-zulip-write-paths)) |
| 7 | Broker → Zulip | Sends `POST /api/v1/messages` with the Markdown link `[filename](url)` in `content` to the chosen target, so the upload is claimed by that message |
| 8 | Broker → shell | `done` with `{ messageId, url, filename, sha256 }` and the broker-built deep link; the shell toasts **Open message** |
| 9 | Broker | Audit record (flow `mail-to-chat`), spool cleanup. Nothing is written to the mail store, and the message is never modified |

Two consequences worth stating, because they are what make F5 safe to offer:

- **The read is one part of one message, with the user's own credential.** F5 cannot be used to read a
  mailbox: the request carries a `messageId` and a `partId`, and the broker resolves both against the
  user's own folders (BR-5.12).
- **The write is a normal Zulip message from the user.** It is not a forward, not a bot post, and not a
  copy of the mail headers; the attachment is uploaded and a message the user composed carries it. If the
  user cancels before step 7, the upload is orphaned in Zulip's store rather than a message being sent —
  the broker reports `cancelled` and says the upload may need clearing by an administrator, which is the
  honest outcome (BR-5.13).

> **Rule BR-5.11:** the six ordered pairs are the flow set. Each has a route, a source chooser, an audit
> flow name and its own test cases ([§9.2](#92-the-six-flows)); a seventh "flow" that is not one of the six
> ordered pairs is a new capability and needs its own section here first.
> **Rule BR-5.12:** every attachment read is addressed by message id and part id and resolved against the
> caller's own mailbox. A request can never name a folder, a mailbox or a path on the mail side.
> **Rule BR-5.13:** an upload that is not followed by a message is reported as `cancelled` with the orphan
> named. The broker does not silently delete an upload it cannot be sure the user wants removed.

### 5.8 F6 — Chat → Mail

From the user's point of view: in the shell's chat attachment chooser, press **Send to mail** on a file
that was posted in a conversation, and it arrives as an attachment on a mail draft the user completes and
sends in SOGo.

| Step | Actor | What happens |
| --- | --- | --- |
| 1 | Shell | The chat attachment chooser lists the conversation's attachments — the files the user can already see in the pane ([§5.9](#510-listing-a-messages-attachments)) — with **Send to mail** beside **Save to files** ([`design.md` D-8.2](./design.md)) |
| 2 | Shell → broker | `POST /api/broker/chat/files/attach` with `{ messageId, url, draft: { to, subject, body } }`. The draft fields are the user's own compose state; the `url` is checked against the message before it is used (BR-2.2) |
| 3 | Broker | Resolves the user and both credentials — the Zulip key for the read, the Mailcow app password for the write. Either missing means `unavailable` / `no-credential`, before anything is read |
| 4 | Broker → Zulip | Streams the upload's bytes with the user's own key. Zulip authorises the read against the upload: the user may fetch files they own or that were posted where they can see them |
| 5 | Broker | Spools the bytes while hashing, and enforces the size cap before the mail side is touched |
| 6 | Broker | Builds the MIME message: the draft headers, a `multipart/mixed` body, one part per file with the real filename in both `name=` and `filename=`, exactly as F2 does ([§5.5](#55-f2--files--mail)) |
| 7 | Broker → Mail | IMAP `APPEND` to the Drafts mailbox with the `\Draft` flag, streaming the message |
| 8 | Broker → shell | `done` with `{ draftUid, folder, sha256, filename }`; the shell toasts **Open draft**, deep-linking into the Mail pane |
| 9 | Broker | Audit record (flow `chat-to-mail`), spool cleanup. Nothing is written to the chat side, and no message is sent |

F6 is the exact transpose of F5: one reads a single MIME part out of a mail message and writes to Chat, the
other reads a single upload out of Chat and writes a mail draft. Both are composed from the same two
readers and writers, so neither adds a new mechanism to the engine — which is the point of building the
six flows as a matrix rather than as six features (BR-5.19).

> **Rule BR-5.20:** the chat side of F6 is read-only. The broker fetches an upload the user can already
> see and never lists, searches or reads anything else in Zulip for this flow; the message the attachment
> came from is never modified or replied to.
> **Rule BR-5.21:** like F2, F6 produces a **draft**. The broker does not send mail, and the user completes
> the send in SOGo with the recipients in front of them (BR-5.15).

### 5.9 The FileBrowser calls the engine makes

Four calls, all with the user's own token, all against the configured Files address. They are listed
together because they are the whole of the broker's FileBrowser surface (BR-5.9).

| Call | Used for | Notes |
| --- | --- | --- |
| `GET /api/resources?path=<dir>&source=<src>` | Listing a directory for the picker, and **refreshing its index** after a by-path write | Returns the directory's `files[]`/`folders[]` with name, size, modified and type. Returns the whole level, so the picker does not need a second round trip |
| `GET /api/resources/items?path=<dir>&only=files\|folders` | A names-only listing, when the picker only needs to know what exists | Cheaper than the above; returns plain name arrays with no metadata |
| `GET /api/resources/download?source=<src>&file=<path>` | Streaming a file's bytes when the broker must read through the application rather than the disk | Supports `Range`, so a large read can resume; the broker never uses the `?auth=` query form ([§4.4](#44-what-each-application-needs)) |
| `GET /api/resources?path=<file>&checksum=sha256` | A checksum of an existing file, **only** when the by-path route is unavailable | Computed on demand by reading the whole file, so the broker prefers hashing locally |

The broker resolves the user's source and scope from the user's own record (`GET /api/users?username=self`)
rather than assuming a path structure, and it sends the token as `Authorization: Bearer`, never as a
query parameter that would land in a log (BR-5.10).

> **Rule BR-5.9:** these four calls are the entire FileBrowser surface. A capability that seems to need a
> fifth — a rescan, a share, a server setting — is a capability that needs a decision here first.
> **Rule BR-5.10:** a credential never appears in a URL. Query parameters are logged by proxies; the
> `?auth=` form FileBrowser accepts exists for its own share links, not for the broker.

### 5.10 Listing a message's attachments

Three read routes exist only to feed the UI — they are not general browsing APIs (BR-1.2).

| Route | Returns | Notes |
| --- | --- | --- |
| `GET /api/broker/files/list?path=…` | One directory: entries with name, size, modified, type, and whether the name is a directory | The `path` is resolved **inside the user's source root**; anything that escapes it is refused, not clamped (BR-8.5) |
| `GET /api/broker/mail/messages/:id/attachments` | The attachment list for one message: part id, filename, size, content type | Read over IMAP with the user's credential: `UID FETCH <uid> (BODYSTRUCTURE)`, then walk the part tree exactly as SOGo does (1-based indexes, `1.2`-style paths), taking the filename from `Content-Disposition`/`Content-Type` and treating a part with no filename as body rather than attachment. A fetch of the part returns the bytes **still transfer-encoded**, so the broker decodes base64 and quoted-printable itself; `BINARY[<part>]` would decode server-side but client support is uneven. Long parts are read in `<start.length>` slices, and a malformed message can drop the connection outright (`imap_fetch_failure = disconnect-immediately`), so the adapter reconnects and resumes rather than failing the transfer |
| `GET /api/broker/chat/messages/:id/attachments` | The attachment list for one Zulip message: filename, size, `url` | Zulip exposes **no attachment metadata on a message**: the broker fetches it with `apply_markdown=false` and reads the `/user_uploads/…` links out of the raw content, then matches them against the caller's own upload list for names and sizes. A message may reference an upload the caller cannot read — reported per attachment, not as a failure of the whole list |

All of them are `Cache-Control: no-store`: a directory listing and an attachment list are user data, and
caching them in a shared proxy would leak across users.

### 5.11 Progress, cancellation and retry

| Property | Specification |
| --- | --- |
| Identity | Every transfer gets an opaque id when it starts; the id is scoped to the user who created it (a foreign id is `denied`, not `not-found`, so ids cannot be probed) |
| Progress | `GET /api/broker/transfers/:id` returns `{ state, bytes, total, phase, reason }`. `phase` is one of `resolving`, `reading`, `writing`, `finalising` so the UI can say what is happening rather than showing an anonymous bar |
| States | `queued`, `running`, `finalising`, `done`, `cancelled`, `failed` — the same words the progress card uses ([D-8.3](./design.md)) |
| Cancellation | `POST /api/broker/transfers/:id/cancel` sets a cancellation flag **and** aborts the upstream request in flight; the partial `.part` file is removed and the destination is never left with a half-written file (BR-5.4) |
| Retry | Safe: a retry is a new transfer. The naming engine makes it idempotent in effect — a re-run that produces the same content in the same place reports `deduplicated` rather than creating `report (2).pdf` |
| Timeouts | Per-request connect/read timeouts on every outbound call, and an overall transfer deadline; a stalled upstream ends the transfer with `unavailable`, never hangs the UI |
| Concurrency | Bounded per user (default 3) and globally (default 12); the queue is in memory and is lost on restart, which is acceptable because a transfer is a user-initiated action, not a job |
| Restart | A transfer in flight when the broker restarts is gone; the spool directory is swept at startup so no `.part` file survives (BR-5.5) |

> **Rule BR-5.4:** cancellation must leave no residue — no partial file in the destination, no row in
> the mail store, no half-sent message.
> **Rule BR-5.5:** the spool directory is private (`0700`), swept at startup, and holds nothing after
> a transfer ends.

### 5.12 Naming, collisions and de-duplication

| Case | Behaviour |
| --- | --- |
| No collision | The file keeps its name |
| Name exists, different content | `report.pdf` → `report (2).pdf`, matching what every file manager does; the confirmation in the UI states the new name before the transfer starts ([D-8.1](./design.md)) |
| Name exists, identical content (same SHA-256) | `deduplicated: true`, no write; the toast says the file is already there and offers **Open folder** |
| Name is unsafe | Control characters, path separators, leading/trailing dots and Windows device names are removed or escaped; the result is never a path ([§8.5](#85-path-traversal-and-filename-safety)) |
| Name is very long | Truncated to the deployment's `BROKER_MAX_FILENAME` (default 200 bytes) preserving the extension |
| Destination directory is full or read-only | `failed` with reason `write-failed` and the OS error **code only** — never a path that leaks the host layout |

De-duplication is by content hash, not by name: that is what makes a retry safe and what stops the
same attachment being saved twice under two names ([`roadmap.md` F3 step 3](./roadmap.md)).

### 5.13 Limits and backpressure

| Limit | Default | Enforced |
| --- | --- | --- |
| Maximum transfer size | 512 MiB (`BROKER_MAX_TRANSFER_MIB`) | Before any read, from metadata where available; a stream that exceeds it is aborted mid-flight |
| Per-user concurrency | 3 | At `POST /api/broker/transfers` |
| Global concurrency | 12 | As above; excess is queued, and the queue is bounded (default 100) |
| Spool cap | 2 GiB total, 0700 directory | Before a spool file is created |
| Zulip upload rate | 200/minute/user ([IN-9.8](./integration.md)) | A token bucket per user, so the broker is a good citizen rather than a source of 429s |
| Upstream timeouts | connect 5 s, read 30 s idle | Transport layer, per request |

Streaming with backpressure is not an optimisation here, it is the requirement
([IN-9.2](./integration.md)): the broker reads as fast as the destination accepts, and pauses the
source when the destination slows. Memory use is a function of the buffer (64 KiB), never of the
file.

### 5.14 The audit record

One record per transfer, appended to `user-data/broker/audit.log` as JSON Lines
([IN-9.4](./integration.md)).

```jsonc
{
  "ts": "2026-03-04T09:15:22.481Z",
  "actor": "jane",                  // the session subject's username, from the verified token
  "flow": "mail-to-files",          // or files-to-mail | chat-to-files | files-to-chat
  "source": { "app": "mail", "folder": "INBOX", "messageId": "…", "partId": "2" },
  "destination": { "app": "files", "path": "/Documents/report.pdf" },
  "bytes": 482113,
  "sha256": "9f2c…",
  "outcome": "ok",                  // or deduplicated | cancelled | denied | failed | unavailable
  "reason": null,                   // the same closed vocabulary the API returns
  "durationMs": 812
}
```

Deliberately **absent**: credentials of any kind, mail bodies, message content, the user's mail
address beyond what the flow already names, and any host filesystem path outside the FileBrowser
source. The record is what an operator needs to answer "who moved what, when, and did it work" —
nothing more (BR-5.6).

> **Rule BR-5.6:** the audit record names the actor, the flow, both ends, the byte count, the digest,
> the outcome and the duration — and nothing else. No credential, no message body, no mail address the
> flow did not already name, no host path outside the FileBrowser source. It is written **after** the
> outcome is known, including for failures and cancellations: a transfer that fails silently is worse
> than one that fails loudly.
> **Rule BR-5.18:** the broker writes mail with IMAP `APPEND` and reads it with `UID FETCH`; it never
> touches the mail store on disk, never uses the Dovecot master user, and never asserts SOGo's
> proxy-authentication header.
> **Rule BR-5.15:** the broker never sends mail. It may create a draft carrying an attachment, and the
> user sends it. `SMTP` is not in the broker's credential set for any flow.
> **Rule BR-5.7:** a by-path write is not complete until the destination directory has been refreshed in
> FileBrowser and the refresh has succeeded. If the refresh fails, the transfer reports `ok` with
> `indexRefresh: "failed"` — the bytes are safe, and the shell says the Files pane may not show them yet
> rather than pretending the file is missing.

---

## 6. Appearance: the light/dark bridge

### 6.1 The contract

The shell owns the mode; each application owns how it expresses it (`design.md` D-T1, D-T6). The
broker's job is to *apply* the mode in each application and to report, per application, whether it
worked. The shell's job is to repaint itself instantly, tell the panes, and say what it could not do
([D-6.1](./design.md)).

Dark is the default ([`design.md` D-6.1](./design.md)), and the mode is stored per browser today
(`localStorage` + the `wc_mode` cookie) with a per-user profile as the Phase 6 target.

### 6.2 The exact call for each application

The three applications are not equally capable, and the broker must not pretend otherwise. Each row
below is the call the broker makes, or the reason there is no call to make; the ones marked
**verified** are taken from the pinned upstream and are recorded with their source in
[`integration.md`](./integration.md).

| Application | The call | Live without a reload? | Reported as |
| --- | --- | --- | --- |
| **FileBrowser Quantum** | `PATCH /api/users?username=<login>` with `{"which":["darkMode"],"data":{"darkMode":<bool>}}` → `204`. `darkMode` is non-admin-editable, so the **user's own** credential is enough and no admin token is used (**verified**, [`integration.md` IN-3.19](./integration.md)) | The setting is stored, but the running SPA read `darkMode` from its store at load and exposes **no inbound channel** (IN-3.20) → the frame must be reloaded | `ok` + `reload: files` |
| **Zulip** | `PATCH /api/v1/settings` with `color_scheme` as a **JSON-encoded integer** — `2` dark, `3` light (**verified**, [`integration.md` IN-5.21](./integration.md), [`roadmap.md` I-ZU-13](./roadmap.md)) | **Yes.** Zulip pushes a `user_settings` event to that user's open clients, which swap the `dark-theme` class on `:root`; the night logo swaps with it. No reload | `ok` |
| **Mailcow / SOGo** | No appearance API exists. The mode reaches Mail through the stylesheet hook the deployment installs ([§6.3](#63-mail-the-stylesheet-hook)); the shell sets the mode cookie, and the hook selects on it | Only on the next paint of the Mail frame | `ok` + `reload: mail`, or `unsupported` with reason `no-style-hook` |

**Zulip's settings endpoint is `@human_users_only`** (IN-5.23): a bot API key is refused by the API
itself. The per-user mode and language calls therefore use the **user's own** API key — which is also
why the broker cannot quietly substitute a service account for them (BR-1.1, BR-4.1).

> **Rule BR-6.1:** an application that cannot express the mode reports `unsupported` with a reason, and
> the shell says which application and why ([`design.md` D-6.1](./design.md)). The broker never reports
> `ok` for a write it did not perform.
> **Rule BR-6.2:** a write that succeeds but whose effect needs a reload is reported as `ok` **plus**
> `reload: <app>`, so the shell reloads that one pane instead of all three.
> **Rule BR-6.3:** the broker uses the user's own credential for a per-user setting. Where the upstream
> refuses anything else — as Zulip does — that is the design, not an inconvenience to work around.
### 6.3 Mail: the stylesheet hook

SOGo has no dark mode and no appearance API. The mode therefore reaches Mail one of two ways:

| Approach | Verdict |
| --- | --- |
| A small stylesheet, injected by a **JS file registered in SOGo's `SOGoUIAdditionalJSFiles`** — the only UI-extension hook SOGo 5.12 has. The file links the stylesheet (or inlines it) and selects on the mode the shell publishes for the SOGo origin | **Specified.** SOGo exposes **no** custom-CSS setting at all, so the JS indirection is not a preference, it is the mechanism Mailcow itself already uses (`js/theme.js`, `js/custom-sogo.js`). It follows the same mode contract as the shell, and is what [`roadmap.md` U-11](./roadmap.md) commits to ("SOGo through the Workcenter stylesheet supplied at setup") |
| Trying to inject styles into the Mail iframe from the shell | **Refused.** Cross-origin: the shell cannot reach into the frame, and a `postMessage` contract would need SOGo to cooperate. SOGo exposes no such channel (BR-8.7) |

The hook is a **deployment artefact**, not a per-user setting: changing the mode does not rewrite it.
The shell sets the mode for the SOGo origin through the same `wc_mode` cookie the bridge already uses,
and the stylesheet selects on it. Consequences the document must state plainly:

- Installing or changing the hook is a **deployment action** that requires restarting `sogo-mailcow`: at
  start-up the container regenerates SOGo's defaults plist from the configuration and database, and
  **rsyncs the web resources into the volume nginx serves from**. Without the restart, the old JS and CSS
  keep being served, and a mode change looks broken when it is merely not deployed.
- Until the hook is installed, the Mail pane's mode change is `unsupported` — reason
  `no-style-hook` — and the shell offers **Open in new tab** instead of pretending.
- The hook is version-pinned with the rest of the stack, and it may only set custom properties and
  styles; it may not hide, move or restyle controls in a way that changes what the user can do
  (BR-6.3).

> **Rule BR-6.3:** the appearance bridge may restyle, never re-purpose. A stylesheet that hides a
> control, changes a label or moves an action is a defect even if it looks better.

### 6.4 The reload mechanism

Some applications only repaint on load, so a mode change must restart their frame. The broker never
touches a frame — it cannot, and it must not ([BR-2.7](#2-invariants)). The sequence is:

| Step | Actor | Action |
| --- | --- | --- |
| 1 | Shell | Repaints its own tokens immediately; the user sees the shell change at once |
| 2 | Shell → broker | `POST /api/broker/preferences` with `{ mode: "light", adapters: { filebrowser: "…", zulip: "…" } }` |
| 3 | Broker → applications | Fan-out in parallel, per application, each with its own credential and its own timeout |
| 4 | Broker → shell | Per-application outcome, including `reload: files` when a write landed but the frame needs to be re-fetched |
| 5 | Shell | Reloads **only** the frames the broker named, one at a time, preserving the pane's current path |
| 6 | Shell | Shows the inline note for any application that could not be changed ([D-6.1](./design.md)) |

**The reload policy is the part that protects the user's work** (`design.md` D-T6, D-T7):

| Situation | Behaviour |
| --- | --- |
| Files pane is in FileBrowser's own text editor or Markdown preview | The reload is **deferred**; the shell says `Files will switch when you close the editor.` and applies it when the editor closes |
| Files pane is in an OnlyOffice document | **Deferred too, and the broker says so honestly**: OnlyOffice's editor is opened from a resource id and leaves no marker in the URL, so the shell cannot tell that a document is open. The deferral therefore cannot be guaranteed for that editor, which is recorded as a limitation rather than hidden ([`design.md` D-T7](./design.md), [`integration.md` IN-3.23](./integration.md)) |
| Any other pane state | Reload in place, restoring the reported path |
| A pane is showing an error card | Reload is safe; the card is replaced by the retry |

> **Rule BR-6.4:** the broker never reloads a frame itself and never instructs the shell to reload a
> frame while a document is open in an editor it can detect.
> **Rule BR-6.5:** one user action produces at most one visible transition per pane. A mode change
> must not produce a reload storm: the shell reloads each named pane once, after all the writes have
> returned.

---

## 7. Language: the locale bridge

### 7.1 The contract

The shell's language is chosen in the language menu ([`design.md` D-6.2](./design.md)); the mapping
from a shell locale to each application's own identifier is owned by the shell's registry
(`src/utils/languages.js`) and sent to the broker with the request ([`architecture.md`
AR-47](./architecture.md), [`design.md` D-I6](./design.md)). The broker keeps **no second copy** of
that mapping: if the shell does not send an identifier for an application, that application is
`unsupported` for that locale, by definition (BR-7.1).

### 7.2 The exact call for each application

| Application | The call | Live without a reload? | Reported as |
| --- | --- | --- | --- |
| **FileBrowser Quantum** | `PATCH /api/users?username=<login>` with `{"which":["locale"],"data":{"locale":"<key>"}}` → `204`, where `<key>` is FileBrowser's **own** key (`ptBR`, `zhCN`, `svSE`), never BCP-47 (**verified**, [`integration.md` IN-3.19](./integration.md), IN-3.21) | No: the SPA has already drawn its strings and has no inbound channel (IN-3.20) | `ok` + `reload: files` |
| **Zulip** | `PATCH /api/v1/settings` with the language setting, using the code form Zulip accepts. `PATCH /api/v1/settings` is `@human_users_only` (IN-5.23), so this is the user's own key | Text already rendered stays in the old language → **reload required** | `ok` + `reload: chat` |
| **Mailcow / SOGo** | **No call exists.** SOGo resolves the language from a per-user `SOGoLanguage` value (a language *name*, not a code) against the browser's `Accept-Language`, and that preference can be written only by a command-line tool inside the container — there is no HTTP surface for it | Cannot be changed by the broker at all. A deployment may set it out of band with `sogo-tool user-preferences`; that is an operator action, not a capability of the shell | `unsupported`, reason `no-language-setting` |

The server-side realm default (`PATCH /api/v1/realm` with `default_language`) is an **admin,
setup-time** action ([`integration.md` IN-5.25](./integration.md)) — it is not part of the per-user
language switch, and the broker does not use it for one. The per-user default that
`PATCH /api/v1/realm/user_settings_defaults` sets does **not** accept `default_language` at all
(IN-5.24), which is why the shell's language choice is a per-user write or nothing.
> **Rule BR-7.1:** the broker forwards only identifiers the shell resolved; an unmapped locale is
> `unsupported` for that application and the shell says so ([`design.md` D-I10](./design.md)).
> **Rule BR-7.2:** the broker never guesses a language for an application, and never sends an
> identifier that application would reject — a rejected write is a worse outcome than a stated
> limitation.

### 7.3 The reload, and why language differs from appearance

A language change invalidates text that is already on screen in every pane, so the reload rule is
stricter than §6.4:

| Situation | Behaviour |
| --- | --- |
| Files pane, no editor open | Reload once, preserving the path |
| Files pane, editor open (detected) | Defer, as in §6.4, and say so |
| Chat pane | Reload once. Zulip holds drafts client-side; the shell warns before reloading if the compose box has content, and never reloads a pane mid-send |
| Mail pane | Not reloaded: the broker did not change it. Reloading Mail would not change its language and would discard an open draft for nothing |
| `<html lang>` | Set by the shell immediately, for the shell's own document and for assistive technology ([`design.md` D-A9](./design.md)) |

The `wc_lang` cookie is written for the shared domain so that, where an application reads a
deployment-level locale rather than a per-user one, the next load picks the language up without the
broker holding anything (BR-7.3).

### 7.4 Persistence

| Layer | Today | Phase 6 target |
| --- | --- | --- |
| Shell | `localStorage` mirror + `wc_lang` cookie, so the first paint is correct and never flashes | Unchanged |
| Per user, across browsers | Not yet | The broker's per-user profile: the same write path, stored per subject, restored on any browser the user signs in from. The mode and the language share it, and it is subject-scoped exactly like a credential (BR-4.1) |

---

## 8. Security and integrity

### 8.1 Threat model

| # | Threat | Mitigation | Where |
| --- | --- | --- | --- |
| 1 | **Impersonation** — a caller asks the broker to act as someone else | Identity is resolved from the verified token only; no route accepts a user from the request | [§4.1](#41-who-the-broker-is-acting-for), BR-2.1 |
| 2 | **Cross-user data access** — user A reads B's file, mailbox or message | Every operation is performed with A's own credential against the application's own authorisation; the source root is resolved from A's record, never from a path | [§4.4](#44-what-each-application-needs), [`architecture.md` AR-45](./architecture.md) |
| 3 | **SSRF** — a client-supplied path or id steers an outbound request | Outbound URLs are built from configuration; a client value is appended to a configured base only after validation, never parsed as a URL; redirects are not followed to a different origin | BR-2.2, [§8.4](#84-ssrf-and-address-allow-listing) |
| 4 | **Path traversal** — `../../etc/passwd`, an absolute path, a symlink out of the root | Resolve-then-verify containment inside the source root, `O_NOFOLLOW` where the platform allows, no symlink following out of the root | [§8.5](#85-path-traversal-and-filename-safety) |
| 5 | **Credential theft at rest** | AES-256-GCM, per-record nonce, key only in `.env`, `0600` file, user+app as AAD | [§4.3](#43-the-vault) |
| 6 | **Credential leakage in logs or responses** | Redaction at the transport layer, a closed error vocabulary, an audit record with no secret fields, and a test that asserts it on captured output | [`Testing.md` §5](./Testing.md) |
| 7 | **Resource exhaustion** — a huge file, many transfers, a slow reader | Size cap, concurrency caps, spool cap, per-request timeouts, streaming with backpressure | [§5.10](#513-limits-and-backpressure) |
| 8 | **Quota abuse** — filling Zulip's upload store or the mail store | Per-user rate limits, the size cap, and the audit trail ([IN-9.8](./integration.md)) | [§5.10](#513-limits-and-backpressure) |
| 9 | **Malicious content** — a file that exploits its destination | The broker does not open, execute or render content; it moves bytes and preserves the declared type. It refuses to *guess* a type it needs for a write, and it never follows an archive | [§8.6](#86-content-integrity) |
| 10 | **Frame escape / clickjacking** | Framing headers are never rewritten; a refusing application is reported as `blocked` | BR-2.7 |
| 11 | **CSRF** — a third-party page drives the broker using the user's cookie | Same-origin policy plus the shell's CSRF posture for state-changing routes; `POST`/`DELETE` only, `SameSite` session cookie, and an `Origin` check | [§8.3](#83-authentication-and-csrf) |
| 12 | **Audit gaps** — an action with no record | Every transfer writes exactly one record, including failures and cancellations | BR-5.6 |

### 8.2 Trust boundaries

| Boundary | Trusted? | Rule |
| --- | --- | --- |
| Workcenter shell in the user's browser | Semi — it is *authenticated* but its input is untrusted | Validate everything (BR-2.1, BR-2.2) |
| Another origin in the user's browser | Untrusted | Never send it a credential; never accept a message from it without an origin check (`design.md` D-T8) |
| The applications themselves | Trusted to authorise, untrusted to be truthful about it | Verify responses; treat a 403 as `denied` for that user, not as a broker error |
| The broker's own configuration | Trusted | It is the source of addresses, limits and the vault key |
| The shared disk | Trusted for the FileBrowser source only | Everything else is API-only ([IN-9.7](./integration.md)) |

### 8.3 Authentication and CSRF

| Property | Specification |
| --- | --- |
| Route auth | Every route except `/api/broker/health` requires a verified Workcenter session; a missing or invalid session is `401`, before any adapter runs |
| Token verification | Issuer, audience, signature, expiry, and the subject's presence; failures are `401` with a reason code, never a partial action ([`Testing.md` §5](./Testing.md)) |
| CSRF | State-changing routes are `POST`/`DELETE`, the session cookie is `SameSite=Lax` or stricter, and the broker rejects a request whose `Origin`/`Sec-Fetch-Site` is not the Workcenter origin |
| Replay | Transfer ids are unguessable and user-scoped; a cancelled or finished transfer cannot be resumed by replaying a request |
| Session loss mid-transfer | The transfer fails with `denied` and leaves no residue (BR-5.4) |

### 8.4 SSRF and address allow-listing

The broker is a server that makes outbound requests on demand, which makes it an SSRF target by
construction. The defences are structural, not filtering-based:

| Defence | Detail |
| --- | --- |
| Configured origins only | Every outbound base URL comes from `appConfig.applications.*.url` or is derived from it (for example the Zulip upload URL from the chat address) |
| No client URLs | A route that takes a path takes a **path**, validated against the source root; a route that takes a message id takes an id, resolved against the user's own mailbox or the message the broker just fetched |
| No redirects off-origin | A redirect that leaves the configured origin ends the request with `unavailable`; the transport layer does not follow cross-origin redirects |
| No arbitrary headers | Upstream requests carry only the headers the adapter sets |
| Address families | An address that resolves to a loopback, link-local or metadata address **other than the configured one** is refused, so a DNS rebind cannot point the broker at the host |

> **Rule BR-8.1:** if a future capability needs a client-supplied URL, it does not ship until this
> section says how that URL is constrained. "We validate it" is not a design.

### 8.5 Path traversal and filename safety

| Stage | Rule |
| --- | --- |
| Receive | The client sends a path **relative to the user's source root**. Absolute paths, `..` segments, NUL bytes and over-long paths are rejected, not normalised into something acceptable |
| Resolve | The path is joined to the root and passed through `fs.realpath`; the result must still begin with the resolved root, compared as a path prefix with a separator, not as a string prefix |
| Symlinks | A symlink that resolves outside the root is refused; the broker does not "helpfully" follow it |
| Filenames | Sanitised for the destination's rules: separators, control characters, trailing dots/spaces, reserved device names, and a length cap preserving the extension |
| Write | The temporary file is created in the **destination directory** with `O_EXCL` and a random suffix, so a race cannot overwrite an existing file, and the rename is atomic within one filesystem |
| Mailbox names | Come from the broker's own configuration or the user's own mailbox listing; never from the request body |

**The application defends itself as well, and the broker relies on that only as a second line.**
FileBrowser Quantum rejects a residual `..` segment outright, joins every client path to the user's
scope so a leading `/` cannot discard it, and resolves symlinks before checking containment — a target
outside the source root is `403` ([§12](#12-upstream-verification)). The broker validates first because
the check must not depend on the upstream version staying as it is, and because a client should not be
able to use the broker to probe what the application would say (BR-8.4).

> **Rule BR-8.4:** an upstream refusal is a backstop, not the control. The broker performs its own
> validation on every path, every time, before an adapter is called.

### 8.6 Content integrity

| Property | Specification |
| --- | --- |
| Hashing | SHA-256 while streaming, on every transfer, for the audit record and for de-duplication. The digest is the **broker's own**: FileBrowser Quantum computes checksums only on request and by reading the whole file, so the broker hashes locally where it has the disk and treats an upstream checksum as a fallback, not as the source of truth |
| Size | Verified against metadata where available and against the streamed byte count always; a mismatch is `failed`, never silently truncated |
| Content type | Preserved, not invented: the source's declared type is carried to the destination. The broker refuses to guess a type it would have to act on (an archive it would expand, a document it would render) |
| Encoding | Transfer encodings are decoded for Mail→\* and preserved for \*→Mail; the broker never re-encodes content it does not have to |
| Verification after write | For by-path writes, the written length is checked against the streamed length before the rename; for API writes, the destination's own response is the confirmation |
| No transformation | The broker does not resize, convert, compress, or rewrite file content. What arrives is what is stored (BR-8.2) |

> **Rule BR-8.2:** a transfer is a **copy of bytes**, not a processing pipeline. Any future
> transformation is a new, named capability with its own section here.

### 8.7 Designs that are refused

Recorded so that they are not re-proposed as shortcuts:

| Refused | Why |
| --- | --- |
| Driving SOGo's web session (scraping its pages or replaying its internal endpoints) to attach a file or read a message | Undocumented, session-shaped, breaks on any SOGo update, and needs the user's web session rather than a scoped credential. IMAP is the supported protocol for exactly these operations |
| Sending SOGo's `x-webobjects-remote-user` proxy-authentication header | Mailcow runs SOGo with proxy authentication trusted, and SOGo's proxy authenticator accepts that header **without checking a password**. Using it would let the broker become any user — an impersonation bypass, not an integration. The broker authenticates with IMAP and nothing else |
| Using Dovecot's master user to reach a mailbox | One credential that opens every mailbox, which is precisely the blast radius [BR-4.1](#42-where-credentials-come-from) exists to prevent. Per-user app passwords exist, so there is no reason to accept it |
| Reading or writing the mail store on disk (`/var/vmail`, the `vmail-vol-1` volume) | It is a `0700` tree owned by uid 5000, encrypted at rest with `mail_crypt`, tracked by a UID list and a SQL quota that only Dovecot updates, and read with `maildir_very_dirty_syncs` enabled — whose own configuration warns that it is unsafe if the files are modified by hand. Mounting it would also expose every user's mail to the broker container |
| Storing a user's primary password for FileBrowser or Zulip | It is not needed: both can issue a purpose-built credential the user can revoke (BR-4.2) |
| Writing into Dovecot's or Zulip's storage on the shared disk, even though the broker often can | Bypasses indexes, caches and quota accounting; [IN-9.7](./integration.md) forbids it |
| Using a Zulip bot with broad permissions for user transfers | The message would appear as the bot, the credential would be far more powerful than the action requires (BR-1.1) — and the settings endpoint the bridge needs is `@human_users_only`, so a bot key cannot perform it at all ([`integration.md` IN-5.23](./integration.md)) |
| Stripping or rewriting `X-Frame-Options`/CSP to make a pane embeddable | Security-relevant behaviour of the application that set it; the deployment-level override in [`roadmap.md` R1/R14](./roadmap.md) is a documented deviation, made once, in the application's own configuration |
| A wildcard `postMessage` target, or trusting any message the pane posts | Cross-origin frames are untrusted input; messages are posted to exact origins and verified on receipt ([`design.md` D-T8](./design.md)) |
| Disabling TLS verification to reach an internal service | `NODE_EXTRA_CA_CERTS` and a proper internal CA exist for this ([`architecture.md` AR-40](./architecture.md)) |
| Buffering a whole file in memory "because it is usually small" | The one time it is not small is the time it takes the deployment down (BR-2.4) |

### 8.8 Rate limiting and abuse

| Control | Value | On breach |
| --- | --- | --- |
| Transfers started per user | 30/minute | `429` with `Retry-After`, and an audit record per refusal |
| Concurrent transfers | 3 per user, 12 global | Queued; the queue is bounded and a full queue is `429` |
| Zulip uploads | 200/minute/user ([IN-9.8](./integration.md)) | Throttled by the broker before Zulip sees it |
| Password prompts | 5/minute/user | `429`, with a delay — this is also the brute-force control for the mail credential |
| Health probe | 1 request per application per interval | The shell polls; the broker does not amplify |

### 8.9 Preserving each application's integrity

The broker's relationship with each application is deliberately asymmetric, and this is the summary
that keeps it honest:

| Application | The broker may | The broker may **not** |
| --- | --- | --- |
| FileBrowser Quantum | Read and write files in the user's source, list directories, read metadata, patch the user's own preferences | Touch another user's source, change permissions or users, change server settings |
| Zulip | Upload a file as the user, send the message the user composed, read the attachment metadata of a message the user can see, patch the user's own settings | Post as anyone else, read channels the user cannot see, administer the realm, delete messages |
| Mailcow / SOGo | Select the user's own folders, fetch a message's MIME parts, append a draft to the user's Drafts, read the user's own attachment list | Read another mailbox, delete or move mail, send mail on the user's behalf, change account settings, use the Mailcow admin API |
| Authentik | Verify a token, read the caller's own claims | Create users, change groups, impersonate, read another user's profile |

> **Rule BR-8.3:** this table is the broker's permission boundary. A new capability must be added to
> it *before* it is implemented, with the reason it cannot be done as the user.

---

## 9. Testing

### 9.1 Layers

| Layer | Scope | Where |
| --- | --- | --- |
| **Unit** | Naming, de-duplication, path validation, hash, spool lifecycle, outcome mapping, the vault's encrypt/decrypt, the rate limiter | `tests/unit/` |
| **Route** | The real Express app with `supertest`: auth, validation, the envelope, status codes, the closed reason vocabulary, secret redaction on captured output | `tests/server/broker.test.js` and successors ([`Testing.md` §5](./Testing.md)) |
| **Adapter** | Each adapter against a **fake upstream** that speaks the real protocol (an HTTP fake for FileBrowser and Zulip, an IMAP fake for Mailcow) | `tests/server/adapters/` |
| **End-to-end (manual, today)** | The six flows by hand against the deployed stack | [`Testing.md` §6.5](./Testing.md), `scripts/e2e.sh` |
| **End-to-end (automated, Phase 7)** | Playwright drives each flow against seeded fixtures | [`Testing.md` §10](./Testing.md) |

Fakes are not mocks of the broker's own code: they are minimal servers that implement the *upstream*
contract (status codes, body shapes, IMAP responses) as verified in [§12](#12-upstream-verification),
so a change in the broker that would break against the real application breaks the test.

### 9.2 The six flows

| Case | Expected | Layer |
| --- | --- | --- |
| F1 happy path | Attachment written to the destination, bytes and hash match the source part | Adapter + manual |
| F1 attachment larger than the cap | `failed`, reason `too-large`, **before** any read of the part | Route |
| F1 name collision, different content | Written as `report (2).pdf`, no overwrite | Unit |
| F1 name collision, identical content | `deduplicated: true`, no write, destination mtime unchanged | Unit |
| F1 cancellation mid-stream | `cancelled`, no `.part` file, no destination file, audit record present | Adapter |
| F1 destination read-only | `failed`, reason `write-failed`, OS code only in the message | Unit |
| F2 one file | A draft appears in Drafts with the attachment, correct filename and size | Adapter + manual |
| F2 multiple files | All attachments present, in the order selected | Adapter |
| F2 draft with no recipient | Still a draft; the broker does not validate mail semantics | Unit |
| F2 append rejected by the server (quota) | `failed`, reason `write-failed`, draft not created | Adapter |
| F3 message with one attachment | File in the destination, name from the upload's filename | Adapter + manual |
| F3 message with several attachments | Each saved independently; the others are unaffected by one failure | Adapter |
| F3 a `uri` the user cannot see | `denied`; no request is made to the upload store | Route |
| F4 small file | Message sent with the attachment, attributed to the **user** | Adapter + manual |
| F4 file above the destination's limit | `failed`, reason `too-large`, nothing uploaded | Adapter |
| Any flow, second user's session | `denied`; nothing read, nothing written | Route (authorisation) |
| **F5** happy path | A message in Zulip carries the file, attributed to the user, with the attachment's real filename | Adapter + manual |
| **F5** the mail part is larger than the cap | `failed`, reason `too-large`, **nothing uploaded** | Adapter |
| **F5** the Zulip credential is missing | `unavailable`, reason `no-credential`, **nothing read from the mailbox** | Route |
| **F5** cancelled after upload, before send | `cancelled`, no message sent, the orphaned upload is named in the result | Adapter |
| **F5** a `partId` that does not exist in the message | `failed`, reason `part-not-found`; no upload attempted | Adapter |
| **F6** happy path | A draft appears in the Mail pane's Drafts with the chat file attached under its real name | Adapter + manual |
| **F6** an upload the user cannot see | `denied`; no request is made to the upload store, no draft created | Route |
| **F6** the mail credential is missing | `unavailable`, reason `no-credential`, **nothing read from Chat** | Route |
| **F6** a file above the mail-side cap | `failed`, reason `too-large`, nothing appended | Adapter |
| **F6** the Zulip key is revoked mid-transfer | `denied`; no draft, no residue, audit record present | Adapter |
| Any flow, broker restarted mid-transfer | The transfer is gone, no residue, the UI shows it as failed on next poll | Manual |

### 9.3 Security cases

| Case | Expected |
| --- | --- |
| `path: "../../etc/passwd"`, `"/etc/passwd"`, a symlink out of the root | `denied`, reason `path-outside-root`; **no** outbound request is made |
| A configured address pointing at a loopback/metadata address at runtime | The outbound call is refused; `unavailable` |
| A body naming another user (`username`, `mailbox`, `source`) | The field is ignored or rejected; the action still applies to the caller |
| An unauthenticated or expired token on every route | `401`; `/api/broker/health` still answers |
| A body containing a credential-shaped field | Not logged, not echoed; asserted on captured output |
| 100 transfers in a minute | `429` with `Retry-After`; the first N still complete |
| A transfer whose upstream stalls | Ends by timeout with `unavailable`, no hang, no partial file |
| A cancelled transfer's id replayed | `denied`/`not-found`; no second action |
| `Origin` header from another site on a `POST` | `403` |

### 9.4 The preference bridge

| Case | Expected |
| --- | --- |
| Files: `PATCH` accepted | `ok` + `reload: files` |
| Files: 401 from upstream (stale credential) | `denied`, reason `credential-rejected`, with the setup prompt |
| Chat: colour scheme accepted | `ok`, **no** reload |
| Chat: language accepted | `ok` + `reload: chat` |
| Mail: stylesheet hook installed | `ok` + `reload: mail` |
| Mail: hook absent | `unsupported`, reason `no-style-hook` — a normal outcome, not an error |
| No credential for an application | `unavailable`, reason `no-credential` |
| Locale with no mapping for an application | `unsupported`, reason `no-language-setting` (the shell did not send an identifier) |
| Upstream unreachable | `unavailable`, reason `unreachable`, others still applied (partial success) |
| A mode switch while the Files editor is open | Broker reports `ok` + `reload: files`; the **shell** defers and says so ([D-T7](./design.md)) |

### 9.5 Exit criteria for Phase 6

The broker is done when all of the following are true, and each is a test rather than a claim:

1. All six flows complete in the page against the deployed stack, with correct filenames, sizes and
   hashes, and an audit record for each.
2. The authorisation suite shows user A cannot read or write anything of user B's through any route
   ([`architecture.md` AR-45](./architecture.md)).
3. The security matrix in [§9.3](#93-security-cases) passes, including the no-secret-on-captured-output
   assertion.
4. Cancellation and failure leave no residue: no `.part` file, no orphan draft, no half-sent message.
5. A mode change and a language change each reach every application that can accept them, with the
   per-application outcome the shell renders, and no reload storm.
6. The startup assertion ([§5.3](#53-startup-assertion-one-disk-two-views)) fails loudly when the
   FileBrowser root is mis-mounted.

---

## 10. Operations

### 10.1 Configuration

| Key | Where | Default | Purpose |
| --- | --- | --- | --- |
| `BROKER_VAULT_KEY` | `.env` | — (required for Phase 6) | 32-byte base64 key for the credential vault |
| `BROKER_FILES_ROOT` | `.env` | — (required for the by-path flows) | The FileBrowser source directory as the broker sees it |
| `BROKER_MAX_TRANSFER_MIB` | `.env` | `512` | Maximum size of one transfer |
| `BROKER_MAX_FILENAME` | `.env` | `200` | Filename length cap in bytes |
| `BROKER_SPOOL_DIR` | `.env` | `user-data/broker/spool` | Private spool directory (`0700`) |
| `BROKER_AUDIT_LOG` | `.env` | `user-data/broker/audit.log` | JSON Lines audit log |
| `BROKER_CONCURRENCY` | `.env` | `3` per user, `12` global | Transfer concurrency |
| `BROKER_IMAP_HOST`, `BROKER_IMAP_PORT` | `.env` | `dovecot-mailcow`, `993` | Mail endpoint inside the compose network |
| `BROKER_IMAP_TLS_SERVERNAME` | `.env` | the value of `MAILCOW_HOSTNAME` | The name the mail certificate actually carries, so TLS is verified rather than skipped (see the certificate note below) |
| `BROKER_IMAP_CA` | `.env` | `Mailcow/data/assets/ssl/cert.pem` | The deployment's own certificate, trusted explicitly because it is self-signed |
| `applications.*.url` | `conf.yml` | — | The addresses every outbound request is derived from (BR-2.2) |

Secrets never appear in `conf.yml` ([`architecture.md` AR-33](./architecture.md)); addresses never
appear in `.env`, because the shell needs them too.

### 10.2 Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| Every Mail flow is `unavailable` / `no-credential` | The user has not supplied a mail credential | Offer the prompt; check `BROKER_IMAP_HOST` resolves inside the network |
| Mail flows fail with a TLS error | Mailcow's generated certificate is self-signed and carries **only a CN** (`MAILCOW_HOSTNAME`), with **no subject alternative name**. Verification therefore fails for `dovecot`, for `dovecot-mailcow` and for every IP address, and some clients reject a SAN-less certificate outright | Point `BROKER_IMAP_TLS_SERVERNAME` at the name in the certificate, trust it with `BROKER_IMAP_CA`, and — as a deployment fix rather than a workaround — issue a certificate with a SAN for the names actually used, or add Dovecot's per-domain SNI certificate. **Never** disable verification to make this go away ([BR-8.5](#86-content-integrity)) |
| Files flows report `root-mismatch` | The broker's `BROKER_FILES_ROOT` is not the directory FileBrowser serves | Fix the mount; the check exists to catch exactly this |
| Zulip uploads return `429` | The per-user upload rate ([IN-9.8](./integration.md)) | Expected under bulk use; the broker throttles before Zulip does |
| A transfer is `denied` with `credential-rejected` | The stored credential was revoked in the application | Remove the vault record and prompt for a new one |
| Mode changes reach Chat but not Mail | The SOGo hook is not installed, or it was installed without restarting the container | Deployment action: install the JS hook and **restart `sogo-mailcow`**, which regenerates SOGo's defaults and rsyncs the web resources nginx serves |
| A language change does not reach Mail | Expected: SOGo has no language API, and its per-user language is settable only from inside the container (BR-7.1) | Nothing to fix; the shell states the limitation. An operator who wants a fixed language can set it with `sogo-tool user-preferences` |
| Audit log missing entries | The broker process was killed rather than restarted | Records are written per completed transfer; a kill loses the in-flight one, which is documented |
| `.part` files in the source directory | A previous run was killed mid-write | The startup sweep removes them; check why the process was killed |

### 10.3 Data the broker owns

| Artefact | Contains | Backup? | Retention |
| --- | --- | --- | --- |
| `user-data/broker/credentials.json` | Encrypted per-user credentials | Yes — it is user configuration | Until the user revokes |
| `user-data/broker/audit.log` | Transfer records ([§5.11](#514-the-audit-record)) | Optional | Owner's policy; the default is no rotation, and rotation is an operator decision |
| `user-data/broker/spool/` | Nothing, at rest | No | Swept at startup and after every transfer |
| `user-data/broker/profile.json` (Phase 6) | Per-user mode and language | Yes | Until the user changes them |

Losing the vault key makes the credentials unreadable — by design. The recovery path is re-entering
them, never recovering them (BR-10.1).

> **Rule BR-10.1:** the broker must start and serve the shell even when the vault is unreadable or
> absent: it reports the affected capabilities as `unavailable` rather than failing to boot.

---

## 11. Traceability

| This document | Requirement it implements |
| --- | --- |
| [§1.2](#12-what-the-broker-is-not) not-a-proxy, not-a-store | [`architecture.md` AR-46](./architecture.md)–AR-49, [`roadmap.md` §7.3](./roadmap.md) |
| [§2](#2-invariants) invariants | [`integration.md` IN-9.1–IN-9.8](./integration.md), [`architecture.md` AR-45](./architecture.md), AR-47 |
| [§3.2](#32-route-table) route table | [`architecture.md` §4.3](./architecture.md), AR-15 |
| [§3.4](#34-get-apibrokerhealth) health | AR-49, [`integration.md` IN-10.4](./integration.md), [`design.md` D-2S](./design.md) |
| [§4](#4-identity-credentials-and-the-vault) identity and vault | IN-9.5, [`OIDC.md`](./OIDC.md), [`roadmap.md` U-20](./roadmap.md) |
| [§5.4–§5.8](#54-f1--mail--files) the six flows | [`roadmap.md` §7.2](./roadmap.md) F1–F6, Phase 6 steps 6.2–6.6, [`design.md` D-8](./design.md), BR-5.11 and BR-5.19 |
| [§5.8](#511-progress-cancellation-and-retry) progress and cancellation | D-8.3, IN-9.2 |
| [§5.9](#512-naming-collisions-and-de-duplication) naming and de-duplication | [`roadmap.md` F3 step 3](./roadmap.md), D-8.1 |
| [§5.11](#514-the-audit-record) audit | IN-9.4 |
| [§6](#6-appearance-the-lightdark-bridge) appearance | [`design.md` D-6.1](./design.md), D-T1, D-T6, D-T7, D-T8, [`roadmap.md` U-17](./roadmap.md) |
| [§7](#7-language-the-locale-bridge) language | [`design.md` D-6.2](./design.md), D-I6, D-I8, D-I10, AR-47, [`roadmap.md` U-18](./roadmap.md) |
| [§8](#8-security-and-integrity) security | IN-9.1, IN-9.5, IN-9.7, AR-15, AR-45, BR-2.x |
| [§9](#9-testing) testing | [`Testing.md` §5](./Testing.md), §10, AR-45 |
| [§10](#10-operations) operations | [`production.md`](./production.md), AR-33, AR-40 |

---

## 12. Upstream verification

Every upstream fact this document relies on is verified against the pinned version and recorded with
its source, so a future reader can re-check it rather than trusting it. The pins are the ones in
[`integration.md` §2](./integration.md) and [`roadmap.md` §6](./roadmap.md).

| Application | Pin | What was verified for this document |
| --- | --- | --- |
| FileBrowser Quantum | `v2.0.9-beta` (`gtsteffaniak/filebrowser`, commit `7a06fb1e…`) — see the tag caveat below | **Preferences:** the user-record patch (`PATCH /api/users?username=…` with `{which,data}` → `204`; `darkMode` and `locale` are non-admin-editable), and the absence of any inbound message channel, so a preference change needs a frame reload ([IN-3.19](./integration.md), IN-3.20). **Files:** download is `GET /api/resources/download?source=&file=` and honours `Range` (single files are served through `http.ServeContent`); listing is `GET /api/resources` (with metadata) or `GET /api/resources/items` (names only); a write is `POST /api/resources?path=&override=` with a **raw body**, and a chunked variant (`X-File-Chunk-Offset`, `X-File-Total-Size`, `X-File-Upload-Session`) that stages a `.uploading.tmp`, verifies the total and moves it into place. **Automation:** `POST /api/auth/token` mints a long-lived per-user token (it requires the user's `api` permission); tokens are validated against a server-side registry, so one cannot be forged. **Indexing:** there is **no filesystem watcher and no rescan endpoint** — a scheduled poller runs on tiers from five minutes to twelve hours, and the only way to bring a directory up to date on demand is to read it (`GET /api/resources?path=<dir>`, which re-stats that level unless `skipExtendedAttrs=true`). **Traversal:** the API rejects a residual `..`, joins client paths to the user's scope so a leading `/` cannot discard it, and resolves symlinks before a containment check that answers `403`. **Errors:** a `403` may carry an empty body, so the broker must not assume JSON when it maps an upstream refusal |
| Zulip | **12.2** — `ghcr.io/zulip/zulip-server:12.2-0` (server commit `1e73e1d7…`, API feature level 500). The concrete pin lives in [`architecture.md`](./architecture.md); the `<version>` placeholders in [`integration.md`](./integration.md) and [`roadmap.md` I-ZU-1](./roadmap.md) are not pins | **Upload:** `POST /api/v1/user_uploads` is multipart (one part), authenticated with **HTTP Basic `email:api_key` only** — a session cookie is *not* accepted on `/api/…` — and answers `{url, filename}`; `uri` is a deprecated alias of `url`. The multipart endpoint is capped by **nginx at 25 MiB** even though the realm default is 100 MiB, so larger files use `/api/v1/tus` (`Tus-Resumable`, `Upload-Length`, `Upload-Metadata`, `PATCH` + `Upload-Offset`, `{url, filename}` on completion), which nginx does not size-cap and which does not consume the API rate budget. **Send:** `POST /api/v1/messages` has **no `file` parameter** in this version or in main — an attachment is carried by a Markdown link to the upload in `content`, and the server claims the path to the message; the broker builds the deep link itself because no message URL is returned before Zulip 13. **Settings:** `PATCH /api/v1/settings` takes `color_scheme` 1/2/3 and applies it live through a `user_settings` event; `default_language` must be a code the server has translations for, and the settings UI itself tells the user a **reload** is required. The endpoint is `@human_users_only`, so a bot key cannot call it. **Rate limit:** 200 requests/minute per user (`api_by_user`), `X-RateLimit-*` advertised, `429` with `Retry-After`. **Attachments:** `GET /api/v1/messages/<id>?apply_markdown=false` returns raw content with upload links but no attachment metadata; `GET /api/v1/attachments` lists only the caller's own uploads. **Framing:** the nginx header at server scope, with no supported way to relax it ([IN-5.26](./integration.md)) |
| Mailcow / SOGo | Mailcow `2026-09` (server `master`), with **Dovecot 2.3.21** and **SOGo 5.12.11** | **IMAP:** the service is `dovecot-mailcow`, reachable on the compose network as `dovecot:993`; plaintext auth is refused except from SOGo's own address, so TLS is mandatory. The generated certificate is self-signed with **CN only and no SAN**, so it verifies for `MAILCOW_HOSTNAME` and for nothing else — a deployment fix, not a reason to skip verification. Credentials: the mailbox password, an **app password with `imap_access`** (the broker's choice), or a Dovecot **master user** (refused). Mailboxes use the `/` separator and carry `\Drafts`, `\Sent`, `\Trash`, `\Junk`, `\Archive` SPECIAL-USE flags, so the broker resolves them by flag rather than name. **Appending:** `APPEND "Drafts" (\Draft) {n}` returns `APPENDUID`; there is no Dovecot message-size limit (the 100 MB figure is Postfix and governs SMTP, not APPEND), and the mailbox quota does apply. **SOGo's draft detection is folder membership, not the `\Draft` flag**; editing an appended draft can leave the appended message behind as a stale copy, because SOGo keeps its own spool. **Fetching:** `UID FETCH (BODYSTRUCTURE)` then `BODY.PEEK[part]`, which returns the part transfer-encoded, so the broker decodes it; `BINARY` exists but is unevenly supported; RFC 9394 `PARTIAL` is absent, so long reads are sliced with the classic `<start.length>` form; a malformed message can disconnect the session by design. **No API:** SOGo's JSON surface covers calendars and contacts, with only folder actions and UID listing for mail — the message endpoints are undocumented internals. Mailcow's own `/api/v1` is **admin-scoped** and cannot read a mailbox. **Appearance:** there is **no custom-CSS setting** in SOGo 5.12.11; the hook is a JS file in `SOGoUIAdditionalJSFiles`, and any change needs a `sogo-mailcow` restart because the container regenerates its defaults and rsyncs the web volume. **Language:** per-user `SOGoLanguage` (a language name) is written only by `sogo-tool` inside the container — there is no HTTP route. **Framing:** `add_header X-Frame-Options "SAMEORIGIN" always;` at server scope, inherited by `/SOGo` but **not** by the nested `/SOGo/so/*.(xml\|js\|html\|xhtml)` location, which sets its own `add_header` and therefore drops it |
| Authentik | the pin in [`roadmap.md` §6](./roadmap.md) | The `groups` claim requires the `profile` scope; per-user credentials for downstream applications are issued by those applications, not by Authentik |

The per-fact citations live in the sections above. Where a fact is *not* verified against the pin, the
section says so in place, and the limitation is carried as a risk rather than as a promise.

One protocol detail is still being confirmed against its pinned source at the time of writing, and is
marked here rather than asserted: the IMAP specifics of appending a draft that carries an attachment and of
fetching one MIME part out of a message ([§5.5](#55-f2--files--mail), [§5.9](#510-listing-a-messages-attachments)).
The **method** is fixed — IMAP over TLS to the mail server, with the user's own mailbox credential — and
those sections state what each step must achieve; only the literal command details are pending, and they
are recorded here the moment they are verified. Everything else in this section was read from the pinned
tree.

### 12.1 One pin caveat, recorded

The FileBrowser Quantum tag `v2.0.9-beta` and the tag `v2.0.8-beta` point at the **same commit**
(`7a06fb1e5fb3063dd34d9a62f1bfe14a890a144f`, whose subject reads `Beta/v2.0.8 (#2992)`). Workcenter
pins `v2.0.9-beta` because it is the newest 2.x beta tag, and gets that tree: the tag is a re-tag, not
a release. No behaviour in this document may be justified by the *tag name*; every fact above was read
from the tree. The relationship is recorded as [`integration.md` IN-3.25](./integration.md) so the next
person to move the pin starts from the commit, not the label.

---

## 13. Implementation status

| Capability | State | Where |
| --- | --- | --- |
| Health route | **Implemented** | `services/utils/broker/health/integrations.js`, `GET /api/broker/health` |
| Preference fan-out (appearance + language) | **Implemented** for Files and Chat; Mail reports `unsupported` | `services/utils/broker/engine/preferences.js`, `adapters/preferences.js` |
| Credential vault | **Specified** — not built | [§4.3](#43-the-vault) |
| Transfer engine, naming, audit | **Specified** — not built | [§5](#5-file-movement) |
| `files`, `mail`, `chat` adapters | **Specified** — not built | [§5](#5-file-movement) |
| Per-user profile (mode/language across browsers) | **Specified** — not built | [§7.4](#74-persistence) |
| Mail stylesheet hook | **Specified** — deployment artefact, Phase 4 | [§6.3](#63-mail-the-stylesheet-hook) |
| Playwright coverage of the six flows | **Specified** — Phase 7 | [§9](#9-testing) |

The transfer routes in [`architecture.md` §4.3](./architecture.md) are deliberately **absent rather
than stubbed**: a route that exists but does nothing invites a caller to depend on it
(BR-13.1).

> **Rule BR-13.1:** this document is the contract. When the implementation disagrees with it, one of
> the two is wrong, and the disagreement is resolved in the same change — never by leaving the
> document describing a system that does not exist.
