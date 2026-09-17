# Workcenter — OIDC and Authentik

> **Scope:** how authentication works across Workcenter and every application it deploys, what you
> must create in **Authentik** before bringing Workcenter up, the exact values each application needs,
> and the verbatim prompts `setup.sh` uses to collect them.
> **Audience:** the operator deploying Workcenter.
> **Companions:** [`roadmap.md`](./roadmap.md) · [`integration.md`](./integration.md) ·
> [`production.md`](./production.md) · [`Readme.md`](./Readme.md) · [`architecture.md`](./architecture.md)

---

## Table of contents

1. [The short version](#1-the-short-version)
2. [How OIDC works, and how Workcenter uses it](#2-how-oidc-works-and-how-workcenter-uses-it)
3. [The group model](#3-the-group-model)
4. [What Authentik must provide](#4-what-authentik-must-provide)
5. [Setting up Authentik: the full walkthrough](#5-setting-up-authentik-the-full-walkthrough)
6. [Per-application OIDC configuration](#6-per-application-oidc-configuration)
7. [SOGo, Mailcow and the OIDC reality](#7-sogo-mailcow-and-the-oidc-reality)
8. [The `setup.sh` prompt contract](#8-the-setupsh-prompt-contract)
9. [Environment variable reference](#9-environment-variable-reference)
10. [Verifying the setup](#10-verifying-the-setup)
11. [Session lifetime, renewal and logout](#11-session-lifetime-renewal-and-logout)
12. [Troubleshooting](#12-troubleshooting)
13. [Security notes](#13-security-notes)

---

## 1. The short version

1. Deploy **Authentik** at `auth.example.com` (or let `setup.sh` do it).
2. In Authentik, create **two groups**: `workspaceusers` and `workspaceadmin`.
3. In Authentik, create a **`groups` scope mapping** so group membership appears in the id_token.
4. In Authentik, create **one OAuth2/OpenID provider and one application** for each of:
   `workcenter`, `filebrowser`, `zulip`, `mailcow` — plus a **proxy provider** for `traefik`.
5. Copy each provider's **Client ID**, **Client Secret** and **Issuer URL**.
6. Run `./setup.sh` and paste those values when prompted — the script writes them into the correct
   `.env` and `config.yaml` files.
7. Sign in once at `https://example.com`. Every pane accepts the same session.

> **The only manual step is step 1–5.** Everything else is scripted. That is by design: Authentik's
> provider configuration is a Web UI workflow that cannot be safely scripted from outside without
> storing an admin API token, so `setup.sh` deliberately stops and asks.

---

## 2. How OIDC works, and how Workcenter uses it

### 2.1 OpenID Connect in one page

**OpenID Connect (OIDC)** is a thin identity layer on top of OAuth 2.0. It lets an application (the
**Relying Party**, or RP) learn who a user is, without ever seeing their password.

The flow Workcenter uses — the **authorization code flow with PKCE** — works like this:

```
  Browser                Workcenter (RP)              Authentik (IdP)
     │                        │                              │
     │  GET /                 │                              │
     ├───────────────────────▶│                              │
     │  no session → redirect │                              │
     │◀───────────────────────┤                              │
     │                                                       │
     │  GET /application/o/authorize/?client_id=…            │
     │      &redirect_uri=…&scope=openid profile email       │
     │      &response_type=code&code_challenge=…             │
     ├──────────────────────────────────────────────────────▶│
     │                                                       │
     │            user signs in (+ MFA if configured)        │
     │                                                       │
     │  302 back to redirect_uri?code=AUTHORIZATION_CODE     │
     │◀──────────────────────────────────────────────────────┤
     │                        │                              │
     │  POST /token (code + code_verifier + client credentials)
     │                        ├─────────────────────────────▶│
     │                        │  id_token (signed JWT) +      │
     │                        │  access_token + refresh_token │
     │                        │◀─────────────────────────────┤
     │  session established   │                              │
     │◀───────────────────────┤                              │
```

The **id_token** is a signed JSON Web Token (JWT) carrying *claims*: `sub` (the stable user id),
`preferred_username`, `email`, and — because Workcenter asks for it — `groups`. Workcenter verifies
the signature against Authentik's published keys (JWKS) and checks the issuer, audience and expiry.

Key terms used throughout this document:

| Term | Meaning |
| --- | --- |
| **Issuer URL** | The provider's base URL, e.g. `https://auth.example.com/application/o/workcenter/`. Workcenter appends `/.well-known/openid-configuration`. |
| **Client ID** | The public identifier of the application, from the provider. |
| **Client Secret** | The confidential half of the credential. A secret, stored only in `.env`. |
| **Redirect URI** | Where the provider sends the user back. Must match **exactly**. |
| **Scope** | What is being requested: `openid` (required), `profile`, `email`, `groups`, `offline_access`. |
| **Claim** | A field inside the id_token, e.g. `groups`. |
| **PKCE** | Proof Key for Code Exchange — protects the code exchange. Always on. |

### 2.2 How Workcenter uses it

| Surface | Client | Notes |
| --- | --- | --- |
| **Workcenter shell** | `oidc-client-ts` (`src/utils/auth/OidcAuth.js`, inherited from Dashy) | Authorization code + PKCE, silent renewal, `adminGroup` check |
| **Workcenter broker** | `jose` (server-side, `services/utils/auth-oidc.js`) | Verifies the bearer token against Authentik's JWKS on every request |
| **FileBrowser Quantum** | Built-in OIDC (`auth.methods.oidc`) | Server-side verification; `adminGroup`, `userGroups`, `groupsClaim` |
| **Zulip** | `GenericOpenIdConnectBackend` | `auto_signup`, group/role sync |
| **Mailcow (incl. SOGo entry)** | Built-in **Generic-OIDC** identity provider | Auto-provisions mailboxes; the front door to SOGo |
| **Traefik dashboard** | Authentik **forward-auth** proxy provider | Not OIDC in the app; the proxy gates it |

> **Two different patterns are in play.** Four services are *OIDC clients*. The Traefik dashboard is
> *not* an OIDC client — it sits behind Authentik's forward-auth outpost, which authenticates the
> request before it reaches Traefik. Both patterns are configured in §5.

---

## 3. The group model

Workcenter uses **two groups, defined once in Authentik, consumed identically everywhere**.

| Group | Purpose | Grants |
| --- | --- | --- |
| **`workspaceusers`** | General access | Sign-in to Workcenter and all three applications |
| **`workspaceadmin`** | Administrative access | Everything above, **plus** administrative rights in each application and access to the Traefik dashboard, Mailcow UI and Authentik admin |

| Ref | Rule |
| --- | --- |
| O-3.1 | The names are exactly `workspaceusers` and `workspaceadmin`. They are configurable in `.env` (`WORKCENTER_USER_GROUP`, `WORKCENTER_ADMIN_GROUP`) but **must be identical across every application** — that is the point of the model. |
| O-3.2 | `workspaceadmin` is **additive**. An administrator is also a user and should be a member of both groups. |
| O-3.3 | Access control and privilege are separate concerns. Binding `workspaceusers` to an Authentik **application** controls *who may sign in*. Being in `workspaceadmin` controls *what they may do*. |
| O-3.4 | A user removed from `workspaceusers` loses access everywhere on their next token refresh, and immediately on any action that revalidates the token. |
| O-3.5 | Users may belong to other groups for other purposes; Workcenter ignores them. |

How the groups reach each application:

| Application | Mechanism |
| --- | --- |
| Workcenter | `groups` claim in the id_token → `adminGroup` match → `isAdmin` |
| FileBrowser Quantum | `groupsClaim: groups` → `adminGroup: workspaceadmin`, `userGroups: [workspaceusers]` |
| Zulip | `zulip_groups` claim via `SOCIAL_AUTH_SYNC_ATTRS_DICT` (Zulip 13+); otherwise admin asserted by `setup.sh` |
| Mailcow | The OIDC login itself; per-mailbox admin is Mailcow's own domain-admin model |
| Traefik dashboard | Authentik group binding on the proxy provider's application — `workspaceadmin` only |

---

## 4. What Authentik must provide

Before Workcenter can start, Authentik must contain **all** of the following. This is the checklist
`setup.sh` is asking about.

### 4.1 Objects

| # | Object | Type | Name | Notes |
| --- | --- | --- | --- | --- |
| 1 | Group | Directory → Groups | `workspaceusers` | Members may use Workcenter |
| 2 | Group | Directory → Groups | `workspaceadmin` | Members administer everything |
| 3 | Property mapping | Customization → Property Mappings → **Scope Mapping** | `groups` | Emits the user's group names as a claim |
| 4 | Provider | Applications → Providers → **OAuth2/OpenID** | `workcenter` | Shell + broker |
| 5 | Application | Applications → Applications | `workcenter` (slug `workcenter`) | Binds provider 4 |
| 6 | Provider | OAuth2/OpenID | `filebrowser` | Files pane |
| 7 | Application | Applications | `filebrowser` (slug `filebrowser`) | Binds provider 6 |
| 8 | Provider | OAuth2/OpenID | `zulip` | Chat pane |
| 9 | Application | Applications | `zulip` (slug `zulip`) | Binds provider 8 |
| 10 | Provider | OAuth2/OpenID | `mailcow` | Mail pane front door |
| 11 | Application | Applications | `mailcow` (slug `mailcow`) | Binds provider 10 |
| 12 | Provider | Applications → Providers → **Proxy** | `traefik-dashboard` | Forward-auth for the dashboard |
| 13 | Application | Applications | `traefik` (slug `traefik`) | Binds provider 12 |
| 14 | Outpost | Applications → Outposts | `authentik Embedded Outpost` | Runs the forward-auth check; must include application 13 |
| 15 | Optional: Outpost | Applications → Outposts | `ldap` | **LDAP** outpost, only if you want Mailcow's LDAP identity provider (§7.4) |

### 4.2 The `groups` scope mapping

Authentik does **not** put group membership in the id_token by default. Without this mapping, every
`adminGroup` check silently fails.

1. Go to **Customization → Property Mappings**.
2. Click **Create → Scope Mapping**.
3. **Name:** `groups`
4. **Scope name:** `groups`
5. **Description:** `Workcenter: exposes the user's Authentik groups as a claim`
6. **Expression:**

   ```python
   return {"groups": [g.name for g in request.user.ak_groups.all()]}
   ```

7. Click **Finish**.

Then, on **every** OIDC provider you create, add `groups` to **Selected Scopes** under
*Advanced protocol settings*.

### 4.3 Values you will need from each provider

For each OIDC provider, record four values. `setup.sh` asks for exactly these.

| Value | Where to find it | Example |
| --- | --- | --- |
| **Issuer URL** | On the provider page, once it is bound to an application — labelled *OpenID Configuration Issuer URL* | `https://auth.example.com/application/o/workcenter/` |
| **Client ID** | Provider → *Protocol settings* → **Client ID** | `workcenter` |
| **Client Secret** | Provider → *Protocol settings* → **Client Secret** (click to reveal/copy) | `3f9a…` (64 hex chars) |
| **Redirect URI(s)** | You supply them; they are registered on the provider | `https://example.com` |

> **Warning:** use the **bare issuer** — `https://auth.example.com/application/o/workcenter/` — not
> the `/.well-known/openid-configuration` URL. Clients append the discovery path themselves, and
> including it produces a redirect loop.

### 4.4 Provider settings that apply to all five

| Setting | Value | Why |
| --- | --- | --- |
| **Authorization flow** | `default-provider-authorization-implicit-consent` | Avoids a consent screen on every sign-in. Use `…explicit-consent` if you want users to confirm each time. |
| **Invalidation flow** | `default-provider-invalidation-flow` | Required on Authentik 2024.10 and newer. |
| **Client type** | `Confidential` for every Workcenter client | All of them are server-side and can hold a secret. **Zulip in particular requires `Confidential`** — it sends both client_id and secret. |
| **Signing Key** | **A certificate-key pair — never leave this empty** | **Critical.** With no signing key, Authentik signs with HS256 using the client secret and **publishes no public key through JWKS**. Zulip (python-social-auth) verifies the id_token against `jwks_uri` and fails; FileBrowser and the Workcenter broker verify against JWKS too. Generate one at **System → Certificates** if none exists. |
| **Encryption Key** | **Leave empty** | **Critical.** An encryption key makes Authentik return an encrypted JWE, which Workcenter's client rejects with *"Workcenter needs signed JWT tokens, not encrypted JWE tokens"*. |
| **Selected Scopes** | `openid`, `profile`, `email-verified` (custom — see §4.5), `groups` (+ `offline_access` if you enable silent renewal) | `groups` is mandatory, and it is the **`profile`** scope that emits it |
| **Include claims in id_token** | **On** | Otherwise the claims live only in the userinfo response |
| **Redirect URI matching** | `Strict` | Register the exact URL, including whether it has a trailing slash |
| **Issuer mode** | Per-provider (default) | Gives `iss = https://auth.example.com/application/o/<slug>/`. Global mode also works — clients validate against the discovery document's `issuer` either way |
| **Subject mode** | Default (hashed user id) | Zulip identifies users by email, not `sub`, so the default is fine |

### 4.5 The two Authentik defaults that silently break logins

These are the most common cause of "the provider looks correctly configured but login fails anyway".

#### Trap 1 — `email_verified` defaults to `False`

Since **Authentik 2025.10**, the built-in **`email` scope hardcodes `email_verified: False`**. Zulip
12.2 added a check — part of the `GHSA-xw9h-9rcm-hx4m` security fix — that rejects exactly that:

```python
# Zulip, after the security fix
email_verified = details.get("email_verified")
if email_verified is not None and not email_verified:
    return []      # → "Social auth (OIDC) failed because user has no verified emails"
```

Note the `is not None` guard: a **missing** claim is accepted; only an explicit `false` is rejected.

**Fix — replace the built-in `email` scope with a custom mapping:**

1. **Customization → Property Mappings → Create → OAuth2/OIDC Scope Mapping**.
2. **Name:** `email-verified`
3. **Scope name:** `email`
4. **Expression:**

   ```python
   return {"email": request.user.email, "email_verified": True}
   ```

5. On **every** provider, **deselect** the built-in `email` scope and select `email-verified` instead.

> **Warning:** a provider should carry only one mapping per scope name. If Authentik reports a
> conflict, the built-in `email` scope is still selected — remove it.

#### Trap 2 — no signing key means no JWKS

With **no Signing Key** selected, Authentik signs with **HS256 using the client secret** and does
**not** publish a public signing key through JWKS. Every client that verifies tokens against
`jwks_uri` — Zulip via python-social-auth, FileBrowser Quantum, and the Workcenter broker — fails
token verification.

**Fix:** create a certificate-key pair (**System → Certificates → Generate**) and select it as the
provider's **Signing Key**. Authentik's built-in `authentik Self-signed Certificate` is also
acceptable: it signs tokens, and is unrelated to the TLS certificate terminating HTTPS.

### 4.6 The `groups` claim and the `profile` scope

| Fact | Consequence |
| --- | --- |
| The `groups` claim is emitted only by the **`profile`** scope | A provider whose Selected Scopes omit `profile` never delivers groups, and every `adminGroup` check silently fails |
| Zulip 13+ reads a claim named **`zulip_groups`**, not `groups` | Group sync in Zulip needs its own scope mapping; `groups` alone is not enough |
| Role sync needs a **`zulip_role`** claim plus `extra_attrs` | And it is Zulip 13+ only — see [§6.3](#63-zulip-zulipcomposeyaml--zulipsecrets) |

### 4.7 Endpoint shapes

| Endpoint | Path |
| --- | --- |
| Discovery | `https://auth.example.com/application/o/<slug>/.well-known/openid-configuration` |
| Issuer (`iss`) | `https://auth.example.com/application/o/<slug>/` |
| JWKS | `https://auth.example.com/application/o/<slug>/jwks/` |
| End session | `https://auth.example.com/application/o/<slug>/end-session/` |
| Authorization | `https://auth.example.com/application/o/authorize/` — **global** |
| Token | `https://auth.example.com/application/o/token/` — **global** |
| User info | `https://auth.example.com/application/o/userinfo/` — **global** |
| Introspect / revoke / device | `https://auth.example.com/application/o/{introspect,revoke,device}/` — **global** |

| Ref | Rule |
| --- | --- |
| O-4.1 | Which value an application needs depends on the application. **FileBrowser Quantum** wants the **per-application issuer *with* a trailing slash** (`issuerUrl`). **Zulip's `oidc_url` wants the base path with *no* trailing slash** — python-social-auth appends `/.well-known/openid-configuration` itself, and a trailing slash yields a doubled separator. |
| O-4.2 | Mailcow's Generic-OIDC asks for the authorize, token and userinfo endpoints **separately** — use the **global** paths above, not per-application paths. |
| O-4.3 | These application slugs are **reserved** and cannot be used: `authorize`, `token`, `device`, `userinfo`, `introspect`, `revoke`. |
| O-4.4 | **Zulip's OIDC is SP-initiated only.** python-social-auth enforces the `state` parameter and Zulip stores `oidc_state` in Redis, so an Authentik-initiated launch does not work. Start Zulip at `https://chat.example.com/login/oidc/?idp=oidc`, or from Workcenter's own session. Do not design around an IdP-initiated flow. |

---

## 5. Setting up Authentik: the full walkthrough

The operations below are performed **in the Authentik Web UI**. Work through them once; then run
`setup.sh` and paste the values.

### 5.1 Deploy Authentik (if you do not have one)

`setup.sh` offers to do this. To do it manually:

```bash
cd Authentik
cp .env.example .env
# generate strong values
sed -i "s|^PG_PASS=.*|PG_PASS=$(openssl rand -hex 32)|"                     .env
sed -i "s|^AUTHENTIK_SECRET_KEY=.*|AUTHENTIK_SECRET_KEY=$(openssl rand -hex 32)|" .env
sed -i "s|^AUTHENTIK_BOOTSTRAP_PASSWORD=.*|AUTHENTIK_BOOTSTRAP_PASSWORD=$(openssl rand -base64 24)|" .env
sed -i "s|^AUTHENTIK_BOOTSTRAP_TOKEN=.*|AUTHENTIK_BOOTSTRAP_TOKEN=$(openssl rand -hex 32)|" .env
sed -i "s|^AUTHENTIK_BOOTSTRAP_EMAIL=.*|AUTHENTIK_BOOTSTRAP_EMAIL=admin@example.com|" .env
docker compose up -d
```

Then open `https://auth.example.com` and sign in as `akadmin` with the bootstrap password.

> **Important for reverse proxies:** set `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` to include Traefik's
> Docker network, and make sure Traefik forwards `X-Forwarded-Proto: https`. Without it, Authentik
> advertises an `http://` issuer in its discovery document and every client fails with
> `unexpected "iss" claim value`.

### 5.2 Create the groups

1. **Directory → Groups → Create**.
2. Name: `workspaceusers` → **Create**.
3. Repeat for `workspaceadmin`.
4. Optionally create a user and add them to both, so you can test.

### 5.3 Create the `groups` scope mapping

As described in [§4.2](#42-the-groups-scope-mapping).

### 5.4 Create the Workcenter provider and application

**Provider**

1. **Applications → Providers → Create** → **OAuth2/OpenID Provider** → **Next**.
2. **Name:** `workcenter`
3. **Authorization flow:** `default-provider-authorization-implicit-consent`
4. **Invalidation flow:** `default-provider-invalidation-flow`
5. **Protocol settings:**
   * **Client type:** `Confidential`
   * **Client ID:** `workcenter` (or accept the generated value and copy it)
   * **Client Secret:** copy the generated value
   * **Redirect URIs** (matching mode **Strict**), one per line:
     ```
     https://example.com
     https://example.com/
     ```
6. **Advanced protocol settings:**
   * **Signing Key:** `authentik Self-signed Certificate`
   * **Encryption Key:** *(leave empty)*
   * **Selected Scopes:** `openid`, `profile`, `email`, `groups`
   * **Include claims in id_token:** on
   * **Access Token validity:** `hours=1` (or your policy)
   * **Refresh Token validity:** `days=30`
7. **Finish**.

**Application**

1. **Applications → Applications → Create**.
2. **Name:** `Workcenter`
3. **Slug:** `workcenter` → the issuer becomes `https://auth.example.com/application/o/workcenter/`
4. **Provider:** `workcenter` → **Create**.
5. Re-open the provider and **copy the OpenID Configuration Issuer URL**.

**Restrict access (recommended)**

1. Open the `Workcenter` application → **Policy / Group / User Bindings**.
2. **Bind existing policy** → switch to the **Group** tab → choose `workspaceusers` → **Enabled** → **Create**.

Anyone outside `workspaceusers` is now refused sign-in.

### 5.5 Create the FileBrowser provider and application

Repeat [§5.4](#54-create-the-workcenter-provider-and-application) with these differences:

| Field | Value |
| --- | --- |
| Provider name | `filebrowser` |
| Client type | `Confidential` |
| Client ID | `filebrowser` |
| Redirect URIs | `https://filebrowser.example.com` and `https://filebrowser.example.com/` |
| Selected Scopes | `openid`, `profile`, `email`, `groups` |
| Application name / slug | `FileBrowser` / `filebrowser` |
| Group binding | `workspaceusers` |

> FileBrowser Quantum also accepts additional redirect paths if you serve it under a sub-path. Keep
> `http.baseURL` in `Filebrowser/config.yaml` consistent with whatever you register here.

### 5.6 Create the Zulip provider and application

| Field | Value |
| --- | --- |
| Provider name | `zulip` |
| Client type | `Confidential` |
| Client ID | `zulip` |
| Redirect URIs | `https://chat.example.com/complete/oidc/` |
| Selected Scopes | `openid`, `profile`, `email`, `groups` |
| Application name / slug | `Zulip` / `zulip` |
| Group binding | `workspaceusers` |

> **The Zulip redirect URI is not the bare hostname.** Zulip's OIDC callback path is
> `/complete/oidc/`, and it must be registered exactly.

If you want Zulip to sync group membership and roles from Authentik, you need claims named
`zulip_groups` and (optionally) `zulip_role`, listed in the IdP dictionary's `extra_attrs`. Create
additional scope mappings alongside `groups`, add them to the provider's Selected Scopes, and
configure `SOCIAL_AUTH_SYNC_ATTRS_DICT` in `ZULIP_CUSTOM_SETTINGS`:

```python
SOCIAL_AUTH_SYNC_ATTRS_DICT = {
    "chat.example.com": {          # the Zulip realm (EXTERNAL_HOST)
        "oidc": {
            "groups": ["workspaceusers", "workspaceadmin"],
            "role": "zulip_role",
            "full_name": True,
        }
    }
}
```

> **Warning — version requirement.** OpenID Connect group sync was added in **Zulip 13**. Zulip 11
> added it for **SAML only**. On the currently pinned `12.2-0` image this configuration is accepted
> but has no effect, and `workspaceadmin` must be propagated out of band (see
> [§7](#7-sogo-mailcow-and-the-oidc-reality) and roadmap I-ZU-6). Verify your image's version before
> relying on it:
>
> ```bash
> docker compose -f Zulip/compose.yaml exec zulip cat /etc/zulip/zulip.conf | grep -i version
> ```

### 5.7 Create the Mailcow provider and application

| Field | Value |
| --- | --- |
| Provider name | `mailcow` |
| Client type | `Confidential` |
| Client ID | `mailcow` |
| Redirect URIs | `https://mail.example.com` and `https://mail.example.com/` |
| Selected Scopes | `openid`, `profile`, `email`, `mailcow_template` |
| Application name / slug | `Mailcow` / `mailcow` |
| Group binding | `workspaceusers` |

> **Note:** Mailcow wants a `mailcow_template` claim so it can decide which mailbox template to apply
> when it auto-provisions a mailbox on first login. Create a scope mapping named `mailcow_template`
> that returns a fixed value for members of `workspaceusers` (for example `default`), and add it to
> the provider's scopes. Then in the Mailcow UI, map the attribute value `default` to a mailbox
> template (see [§7.3](#73-configuring-mailcows-generic-oidc)).

> **The Mailcow UI is an OIDC client, not a forward-auth target.** Do **not** put
> `mail.example.com` behind an Authentik forward-auth proxy; that would break Mailcow's own identity
> provider flow and its API. The only forward-auth surface in Workcenter is the Traefik dashboard.

### 5.8 Create the Traefik dashboard proxy provider

1. **Applications → Providers → Create** → **Proxy Provider** → **Next**.
2. **Name:** `traefik-dashboard`
3. **Authorization flow:** `default-provider-authorization-implicit-consent`
4. **Authentication flow:** `default-authentication-flow`
5. **External host:** `https://traefik.example.com`
6. **Finish**.
7. **Applications → Applications → Create**: name `Traefik`, slug `traefik`, provider `traefik-dashboard`.
8. Bind **only** `workspaceadmin` to this application — this is what restricts the dashboard to admins.
9. **Applications → Outposts**: ensure the **authentik Embedded Outpost** includes the `Traefik`
   application, and that the outpost is reachable by Traefik on the shared Docker network.

`setup.sh` writes the outpost's forward-auth address into `Traefik/dynamic/middlewares.yml` as the
`forwardauth` middleware's `address`.

### 5.9 Record what you created

Fill this in as you go — `setup.sh` asks for these values.

```text
Base domain ......................... example.com
Authentik issuer host ............... https://auth.example.com

workcenter    Issuer: https://auth.example.com/application/o/workcenter/    Client ID: workcenter    Secret: __________
filebrowser   Issuer: https://auth.example.com/application/o/filebrowser/   Client ID: filebrowser   Secret: __________
zulip         Issuer: https://auth.example.com/application/o/zulip/         Client ID: zulip         Secret: __________
mailcow       Issuer: https://auth.example.com/application/o/mailcow/       Client ID: mailcow       Secret: __________

Groups .............................. workspaceusers / workspaceadmin
zulip_groups claim .................. created?  yes / no
mailcow_template claim .............. created?  yes / no
LDAP outpost (optional) ............. deployed? yes / no   Bind DN: __________  Bind password: __________
```

---

## 6. Per-application OIDC configuration

`setup.sh` writes these. They are documented here so you can verify or hand-edit them.

### 6.1 Workcenter (`user-data/conf.yml` + root `.env`)

```yaml
appConfig:
  auth:
    enableOidc: true
    oidc:
      clientId: workcenter
      endpoint: https://auth.example.com/application/o/workcenter/
      adminGroup: workspaceadmin
      scope: openid profile email groups
      enableSilentRenew: true
```

```env
# .env
WORKCENTER_OIDC_CLIENT_ID=workcenter
WORKCENTER_OIDC_CLIENT_SECRET=<secret>
WORKCENTER_USER_GROUP=workspaceusers
WORKCENTER_ADMIN_GROUP=workspaceadmin
```

`enableSilentRenew: true` adds the `offline_access` scope, so make sure that scope is selected on the
provider.

### 6.2 FileBrowser Quantum (`Filebrowser/config.yaml` + `Filebrowser/.env`)

FileBrowser Quantum **v2** schema:

```yaml
auth:
  methods:
    oidc:
      enabled: true
      issuerUrl: "https://auth.example.com/application/o/filebrowser/"
      clientId: ""            # injected from FILEBROWSER_OIDC_CLIENT_ID
      clientSecret: ""        # injected from FILEBROWSER_OIDC_CLIENT_SECRET
      scopes: "openid email profile groups"
      groupsClaim: "groups"
      userIdentifier: "preferred_username"
      adminGroup: "workspaceadmin"
      userGroups:
        - "workspaceusers"
      logoutRedirectUrl: "https://auth.example.com/application/o/filebrowser/end-session/"
```

```env
# Filebrowser/.env
FILEBROWSER_OIDC_CLIENT_ID=filebrowser
FILEBROWSER_OIDC_CLIENT_SECRET=<secret>
FILEBROWSER_JWT_TOKEN_SECRET=<openssl rand -hex 32>
```

| Ref | Rule |
| --- | --- |
| O-6.1 | `scopes` **must** include `groups`, and `groupsClaim` must match the scope mapping's name, or `adminGroup` never matches. |
| O-6.2 | `userGroups` restricts sign-in to `workspaceusers`. Remove it to allow any Authentik user. |
| O-6.3 | `server.trustProxyHeaders: true` must be set, since FileBrowser sits behind Traefik. |
| O-6.4 | Never set `disableVerifyTLS: true` outside a disposable test host. |

### 6.3 Zulip (`Zulip/compose.yaml` + `Zulip/secrets/`)

Zulip's OIDC backend is `zproject.backends.GenericOpenIdConnectBackend`, registered by docker-zulip as
`oidc`. The configuration has two parts because docker-zulip's `SETTING_*` convention can only express
**scalars** — a dict-valued setting must be supplied as raw Python through `ZULIP_CUSTOM_SETTINGS`.

```yaml
services:
  zulip:
    environment:
      # --- scalars: SETTING_* is fine ---
      SETTING_EXTERNAL_HOST: "chat.example.com"
      SETTING_ZULIP_ADMINISTRATOR: "admin@example.com"
      SETTING_LOADBALANCER_IPS: '["172.16.0.0/12"]'
      SETTING_USE_X_FORWARDED_HOST: "True"
      SETTING_SOCIAL_AUTH_OIDC_FULL_NAME_VALIDATED: "True"
      # bare class names; docker-zulip prepends "zproject.backends."
      ZULIP_AUTH_BACKENDS: "EmailAuthBackend,GenericOpenIdConnectBackend"

      # --- dict-valued: must go through ZULIP_CUSTOM_SETTINGS ---
      ZULIP_CUSTOM_SETTINGS: |
        SOCIAL_AUTH_OIDC_ENABLED_IDPS = {
            "oidc": {
                "display_name": "Authentik",
                # NOTE: base path with NO trailing slash
                "oidc_url": "https://auth.example.com/application/o/zulip",
                "client_id": "zulip",
                "secret": "<secret>",
                "auto_signup": True,
                "extra_attrs": ["groups"],
            }
        }
```

| Ref | Rule |
| --- | --- |
| O-6.5 | The redirect URI is `https://chat.example.com/complete/oidc/` and must be registered in Authentik exactly. Login is initiated at `/login/oidc/?idp=oidc`. |
| O-6.6 | `auto_signup: True` creates the Zulip account on first OIDC login. Without it, users are asked whether to create an account. |
| O-6.7 | **There is no `SOCIAL_AUTH_OIDC_ENABLED`, `SOCIAL_AUTH_OIDC_CLIENT_ID`, `SOCIAL_AUTH_OIDC_SECRET` or `SOCIAL_AUTH_OIDC_URL` setting in Zulip.** The only OIDC settings are `SOCIAL_AUTH_OIDC_ENABLED_IDPS` and `SOCIAL_AUTH_OIDC_FULL_NAME_VALIDATED`. Any documentation that uses the other names is wrong. |
| O-6.8 | `ZULIP_CUSTOM_SETTINGS` is raw Python appended to `settings.py`. Treat it as code: it is reviewed, and a syntax error prevents Zulip from starting. Keep secrets out of it by reading them from a file in `Zulip/secrets/` if you prefer. |
| O-6.9 | If your Authentik uses a private CA, set `custom_ca_path` in Zulip's settings so it trusts the issuer. |
| O-6.10 | **Zulip sends `X-Frame-Options: DENY` and cannot be embedded as shipped.** There is no Django `X_FRAME_OPTIONS` setting and no `XFrameOptionsMiddleware`. Workcenter therefore deploys a thin derived image that overrides the nginx header include via `custom_zulip_files/`, replacing `X-Frame-Options` with a CSP `frame-ancestors` allow-list (see [`integration.md` §5.4](./integration.md#54-the-framing-problem)). There is nothing to configure in Zulip itself for this. |
| O-6.11 | **OIDC group→role sync requires Zulip 13.** On the currently pinned 12.2 image, group sync exists for **SAML only**; Zulip 12.2's own settings template states *"Sync for other backends is not currently supported."* `workspaceadmin` is therefore propagated out of band via `PATCH /api/v1/users/{user_id}` by `setup.sh`. |
| O-6.12 | **`CSRF_TRUSTED_ORIGINS` is not a Zulip production setting.** It appears only in Zulip's development settings. Zulip's CSRF protection rests on trusting the proxy: pass the client `Host` through unchanged, set the forwarded proto, and list the proxy's address in `SETTING_LOADBALANCER_IPS`. Fix CSRF by making Traefik trusted — not by inventing a setting. |
| O-6.13 | Do not set `ALLOWED_HOSTS`. Zulip derives it automatically from `SETTING_EXTERNAL_HOST`. |

### 6.4 Mailcow (`Mailcow/`, configured in the Mailcow UI)

See [§7.3](#73-configuring-mailcows-generic-oidc). The values come from the `mailcow` provider you
created in [§5.7](#57-create-the-mailcow-provider-and-application), and `setup.sh` writes them into
`Mailcow/workcenter-oidc.env` for your reference while you type them into the UI.

---

## 7. SOGo, Mailcow and the OIDC reality

This is the most commonly misunderstood part of the stack, so it is stated plainly.

### 7.1 The problem

**SOGo ≥ 5.12 does support OpenID Connect natively** — `SOGoAuthenticationType = openid` with
`SOGoOpenIdConfigUrl`, `SOGoOpenIdClient`, `SOGoOpenIdClientSecret` and friends — and Mailcow *ships*
SOGo 5.12.10, so the OIDC code is compiled in.

**But Mailcow does not configure it, and it cannot be made to work without changes Mailcow does not
support.** The blocker is not the web UI, it is the **mail protocols**:

* Under OIDC, SOGo has no user password. It needs **XOAUTH2** to reach Dovecot.
* That requires an OAuth2 passdb in Dovecot, which Mailcow does not have.
* It also requires an `OCSOpenIdURL` pointing at a `sogo_openid` table that does not exist in
  Mailcow's schema.

Mailcow's own documentation states the consequence plainly: users who authenticate through an
identity provider *"can only log in to SOGo through the mailcow UI. Directly logging in through SOGo
will not work."*

> **Therefore Workcenter uses the Mailcow-UI front door.** This is not a workaround invented here — it
> is Mailcow's supported identity-provider pattern, and it is what makes SSO into SOGo work.

| Ref | Rule |
| --- | --- |
| O-7.1 | The Mailcow UI must **not** be placed behind an Authentik forward-auth proxy. It is an OIDC client in its own right. |
| O-7.2 | Changing a mailbox's identity provider to `Generic-OIDC` **does not erase** the existing SQL password. Switching back to `mailcow` restores password login, which is a useful fallback. The mailbox's `authsource` column is an enum of `mailcow`, `keycloak`, `generic-oidc`, `ldap`, so `setup.sh` can switch a mailbox with a single `UPDATE`. |
| O-7.3 | Attribute mapping is mandatory for auto-provisioning. Without it, login fails for a user whose mailbox does not already exist. |
| O-7.4 | Do **not** write configuration against `SOGoAuthenticationMethod` or `SOGoWebAuthentication` — those settings do not exist in SOGo. The real keys are the `SOGoOpenId*` family. Mailcow sets `SOGoTrustProxyAuthentication = YES`, which is the mechanism the SSO session relies on. |
| O-7.5 | If you ever attempt native SOGo OIDC anyway, set `SOGoOpenIdTokenCheckInterval` to a non-zero value (for example `60`). Its default of `0` causes a token check on every request and a large slowdown. Do not rely on `SOGoOpenIdEnableRefreshToken` or `SOGoOpenIdLogoutEnabled`, whose defaults are `NO`. |

### 7.2 How the Mailcow SSO session actually works

Understanding this is what makes the Mail pane's behaviour predictable.

```
   Browser ──▶ Traefik ──▶ nginx-mailcow
                              │
                              ├── /            → mailcow UI (its own login, or Generic-OIDC)
                              │
                              └── /SOGo        → auth_request /sogo-auth-verify
                                                   │  → http://127.0.0.1:65510/sogo-auth
                                                   ▼
                                          data/web/sogo-auth.php
                                                   │
                     ┌─────────────────────────────┼─────────────────────────────┐
                     ▼                             ▼                             ▼
        HTTP Basic present →            mailcow session exists →        neither →
        validate and inject             inject Authorization:           send EMPTY headers →
        x-webobjects-remote-user        Basic <email>:<sogo-sso.pass>   SOGo shows its OWN login form
```

Key consequences:

| Consequence | Why |
| --- | --- |
| **Clicking "Login to Webmail" in the Mailcow UI is what establishes the SOGo session** | It calls `/sogo-auth.php?login=<address>`, which sets `$_SESSION['sogo-sso-user-allowed']` |
| **Opening `/SOGo` directly, without that session, shows SOGo's own login form** | The auth proxy has nothing to inject |
| The shared `sogo-sso.pass` is **regenerated on every Dovecot container start** | It lives in `Mailcow/data/conf/phpfpm/sogo-sso/sogo-sso.pass`; Dovecot's static passdb accepts it only from SOGo's container IP |
| **App passwords are mandatory for IMAP/SMTP** | An OIDC-authenticated mailbox has no password, and Mailcow's login helper has no `generic-oidc` branch for mail protocols |

This is why Workcenter's Mail pane shows the `auth-error` state with **Sign in again** when it lands on
SOGo's login form: the fix is to establish the Mailcow session first.

### 7.3 Configuring Mailcow's Generic-OIDC

Mailcow — which *deploys* SOGo — **does** have a first-class identity-provider feature. This is the
supported path.

1. Sign in to the Mailcow UI as an administrator.
2. Go to **System → Configuration → Access → Identity Provider**.
3. Select **Generic-OIDC** from the dropdown.
4. Fill in the fields from your Authentik `mailcow` provider:

   | Mailcow field | Value |
   | --- | --- |
   | **Authorization Endpoint** | `https://auth.example.com/application/o/authorize/` |
   | **Token Endpoint** | `https://auth.example.com/application/o/token/` |
   | **User Info Endpoint** | `https://auth.example.com/application/o/userinfo/` |
   | **Client ID** | `mailcow` |
   | **Client Secret** | *(the secret from the provider)* |
   | **Redirect URL** | `https://mail.example.com` |
   | **Client Scopes** | `openid profile email mailcow_template` |
   | **Attribute Mapping** | `default` → a mailbox template you have created |
   | **Ignore SSL Errors** | **off** |

5. Click **Test Connection** and confirm it succeeds.
6. Under **E-Mail → Configuration → Mailboxes**, edit each mailbox and set **Identity Provider** to
   `Generic-OIDC`.

What this gives you: users sign in to the Mailcow UI (and through it, reach SOGo at
`https://mail.example.com/SOGo`) with their Authentik credentials. Mailboxes are **auto-provisioned**
on first login when the `mailcow_template` claim matches an attribute mapping.

| Ref | Rule |
| --- | --- |
| O-7.1 | The Mailcow UI must **not** be placed behind an Authentik forward-auth proxy. It is an OIDC client in its own right. |
| O-7.2 | Changing a mailbox's identity provider to `Generic-OIDC` **does not erase** the existing SQL password. Switching back to `mailcow` restores password login, which is a useful fallback. |
| O-7.3 | Attribute mapping is mandatory for auto-provisioning. Without it, login fails for a user whose mailbox does not already exist. |

### 7.4 Mail protocol credentials (IMAP, SMTP, POP3, SIEVE)

OIDC covers the **web UI only**. Mail protocols authenticate with a password. Two supported options:

**Option A — app passwords (default, no extra infrastructure)**

Each user signs in to the Mailcow UI, goes to **Mailbox Settings → App Passwords**, and generates a
password per device/client. This is per-user, per-device and revocable, and it is what `OIDC.md`
recommends and what Workcenter's broker uses unless LDAP is configured.

**Option B — Mailcow's LDAP identity provider (single source of truth)**

Deploy Authentik's **LDAP outpost**, then configure Mailcow's LDAP identity provider
(**System → Configuration → Access → Identity Provider → LDAP**):

| Mailcow field | Value |
| --- | --- |
| **Host** | The LDAP outpost's hostname on the shared Docker network |
| **Port** | `389` (or `636` with TLS) |
| **Use SSL/TLS** | As appropriate for your outpost |
| **Base DN** | The outpost's base, e.g. `dc=ldap,dc=goauthentik,dc=io` |
| **Username Field** | `mail` (or `cn`, matching your outpost's mapping) |
| **Filter** | e.g. `(objectClass=user)` |
| **Attribute Field** | The attribute carrying the mail address |
| **Bind DN / Bind Password** | The outpost's service account |
| **Attribute Mapping** | Template to apply on import |
| **Periodic Full Sync** | Enable if you want membership changes to propagate without a login |
| **Import Users** | Enable to pre-create mailboxes |

With LDAP enabled, Mailcow performs an LDAP bind for IMAP/SMTP as well as the UI, so Authentik
becomes the single source of truth for both.

| Ref | Rule |
| --- | --- |
| O-7.4 | Choose one option and document it in `.env` (`MAILCOW_AUTH_MODE=oidc+apppasswords` or `oidc+ldap`). |
| O-7.5 | If LDAP is enabled, the broker authenticates IMAP/SMTP with the user's Authentik credentials — never with a stored administrator password. |

### 7.5 How the Workcenter Mail pane is wired

| Aspect | Behaviour |
| --- | --- |
| Pane URL | `https://mail.example.com/SOGo` |
| SSO entry | If the pane lands on a login page, the shell shows the `auth-error` state with **Sign in again**, which opens `https://mail.example.com` so the Mailcow UI can establish the SSO session |
| Attachment save (F1) | The broker uses **IMAP over TLS** to `dovecot-mailcow` with the user's app password (Option A) or LDAP credentials (Option B) |
| Attachment attach (F2) | The broker streams the file into the compose flow via SMTP submission to `postfix-mailcow` |
| Why not the SOGo API | SOGo exposes no stable public REST API for attachment extraction; IMAP is the reliable, standards-based path |

---

## 8. The `setup.sh` prompt contract

This section is **normative**: `setup.sh` must ask exactly these questions, in this order, with this
wording. It is reproduced here so an operator knows what to expect, and so a contributor changing the
script knows what must not drift.

### 8.1 Stage A — Folders and application files

```text
ℹ  Checking Workcenter folders…
✔  Filebrowser/ exists
✔  Zulip/ exists
✔  Mailcow/ exists
ℹ  Mailcow/ is empty — cloning mailcow-dockerized and running generate_config.sh…
✔  Mailcow prepared
```

If the script **created** a folder or its files in this run, it records that fact and **skips** the
`.env` and OIDC checks for that application — there is nothing to check yet — and proceeds directly to
the Authentik deployment question in [§8.4](#84-stage-d--authentik-deployment).

### 8.2 Stage B — Traefik

```text
ℹ  Checking for a running Traefik instance…
```

* **Found:** `✔  Existing Traefik detected on network 'proxy' — Workcenter will use it.`
* **Not found:**

  ```text
  ⚠  No running Traefik instance detected.
  ?  Deploy Traefik as part of the Workcenter stack? [Y/n]
  ```

  On **yes**, `Traefik/` is created and added to the stack.

### 8.3 Stage C — Base URL

```text
?  What is the base domain for Workcenter (the root URL)? [example.com]
```

The script then derives and **prints** the hostnames before continuing:

```text
ℹ  Workcenter will be deployed at:
     Workcenter .......... https://example.com
     FileBrowser ......... https://filebrowser.example.com
     Authentik ........... https://auth.example.com
     Mailcow / SOGo ...... https://mail.example.com
     Zulip ............... https://chat.example.com
     Traefik dashboard ... https://traefik.example.com
?  Proceed with these hostnames? [Y/n]
```

Derivation rule: `filebrowser.`, `auth.`, `mail.`, `chat.` and `traefik.` are prefixed to the base
domain. If the base already has a subdomain (for example `work.example.com`), the prefixes are applied
to the registrable domain (`work.example.com` → `filebrowser.work.example.com`).

At this point the script has written every configuration file and the compose files. **The only thing
left is OIDC.**

### 8.4 Stage D — Authentik deployment

```text
ℹ  Checking whether the Workcenter .env files contain OIDC configuration…
⚠  OIDC configuration is incomplete (WORKCENTER_OIDC_CLIENT_SECRET is empty).
?  Have you already created the required OIDC applications and providers in Authentik? [y/N]
```

#### If the answer is **yes**

The script creates `Authentik/` in the Workcenter root (for Authentik's own files) and continues:

```text
✔  Authentik/ created
ℹ  You will now be asked for the values from each provider you created.
   See OIDC.md §5 for the exact steps if you have not created them yet.
   Issuer URLs look like:  https://auth.example.com/application/o/<slug>/
   Use the bare issuer — do NOT include /.well-known/openid-configuration
```

**Workcenter**

```text
?  Workcenter — OIDC issuer URL: 
?  Workcenter — OIDC client ID [workcenter]: 
?  Workcenter — OIDC client secret: 
?  Workcenter — general user group [workspaceusers]: 
?  Workcenter — admin group [workspaceadmin]: 
```

**FileBrowser Quantum**

```text
?  FileBrowser — OIDC issuer URL: 
?  FileBrowser — OIDC client ID [filebrowser]: 
?  FileBrowser — OIDC client secret: 
ℹ  FileBrowser JWT signing secret: generated automatically (openssl rand -hex 32)
```

**Zulip**

```text
?  Zulip — OIDC issuer URL: 
?  Zulip — OIDC client ID [zulip]: 
?  Zulip — OIDC client secret: 
?  Zulip — administrator email address (receives the first owner account): 
```

**Mailcow / SOGo**

```text
?  Mailcow — OIDC issuer URL: 
?  Mailcow — OIDC client ID [mailcow]: 
?  Mailcow — OIDC client secret: 
?  Mailcow — mail protocol authentication: app passwords, or LDAP? [apppasswords/ldap] (apppasswords)
```

If **ldap** is chosen, the script additionally asks for the LDAP outpost's bind DN and bind password,
and writes them into `Mailcow/workcenter-oidc.env` for the Mailcow UI configuration.

**Traefik dashboard** *(only if Traefik was newly deployed)*

```text
?  Traefik dashboard — Authentik proxy provider outpost URL (e.g. http://authentik-server:9000/outpost.goauthentik.io/auth/traefik): 
```

The script writes every value into the correct file, prints a summary with secrets masked, and moves to
[§8.5](#85-stage-e--bring-up).

#### If the answer is **no** (the default)

```text
ℹ  Checking whether Authentik is running on this host…
```

**Authentik is running:**

```text
✔  Authentik appears to be running on this host.
?  Configure the Workcenter OIDC values now? [y/N]
```

* **Yes** → the same prompts as the "yes" branch above.
* **No** → the script stops with the guidance message in [§8.6](#86-the-stop-message).

**Authentik is not running:**

```text
⚠  No Authentik instance detected on this host.
?  Deploy Authentik now as part of the Workcenter stack? [y/N]
```

* **Yes** → the script requests the values needed to deploy Authentik securely:

  ```text
  ?  Authentik admin email address: 
  ℹ  The following secrets will be generated automatically with openssl rand -hex 32:
       PG_PASS, AUTHENTIK_SECRET_KEY, AUTHENTIK_BOOTSTRAP_TOKEN
  ?  Authentik admin (akadmin) bootstrap password (leave blank to generate): 
  ?  Pin a specific Authentik version? [2024.12]: 
  ```

  It then writes `Authentik/.env`, brings Authentik up, waits for it to become healthy, and **stops**
  with:

  ```text
  ✔  Authentik is running at https://auth.example.com
  ℹ  Sign in as 'akadmin' and complete the OIDC setup:
       1. Create the groups: workspaceusers, workspaceadmin
       2. Create the 'groups' scope mapping
       3. Create the providers and applications for:
          workcenter, filebrowser, zulip, mailcow, traefik
     Full instructions: OIDC.md §5

  Create required OIDC application and provider per OIDC.md in authentik.
  Once complete rerun setup.sh to input the .env variables as necessary for Workcenter.
  ```

* **No** → the script stops immediately with the same message, deploying nothing further.

### 8.5 Stage E — Bring-up

Only reached when the folders and files already existed **and** the `.env` files contain complete OIDC
configuration.

```text
ℹ  All configuration present. Bringing the Workcenter stack up…
   docker compose up -d
ℹ  Waiting for services to become healthy…
✔  traefik        healthy
✔  authentik      healthy
✔  filebrowser    healthy
✔  onlyoffice     healthy
✔  zulip          healthy
✔  workcenter     healthy
⚠  mailcow        started by its own tooling — run 'cd Mailcow && docker compose up -d'
✔  Workcenter is up at https://example.com
```

The script exits non-zero if any service fails to become healthy, and prints the failing service's
last 50 log lines.

### 8.6 The stop message

This is the **exact** text the script must print whenever it stops because Authentik is not yet
configured. Do not paraphrase it.

```text
Create required OIDC application and provider per OIDC.md in authentik.
Once complete rerun setup.sh to input the .env variables as necessary for Workcenter.
```

### 8.7 Non-interactive mode

`setup.sh --non-interactive` reads every value from the environment or from existing `.env` files and
never prompts. In that mode, a missing required value is a **fatal error**, and the script stops with
the guidance message above rather than guessing. This is the mode CI and the Playwright harness use.

---

## 9. Environment variable reference

### 9.1 Root `.env`

| Variable | Required | Description |
| --- | --- | --- |
| `BASE_DOMAIN` | Yes | The root domain, e.g. `example.com` |
| `WORKCENTER_URL` | Yes | `https://<base>` |
| `FILEBROWSER_URL` | Yes | `https://filebrowser.<base>` |
| `AUTH_URL` | Yes | `https://auth.<base>` |
| `MAIL_URL` | Yes | `https://mail.<base>` |
| `CHAT_URL` | Yes | `https://chat.<base>` |
| `TRAEFIK_URL` | Yes | `https://traefik.<base>` |
| `WORKCENTER_OIDC_CLIENT_ID` | Yes | From the `workcenter` provider |
| `WORKCENTER_OIDC_CLIENT_SECRET` | Yes | **Secret** |
| `FILEBROWSER_OIDC_CLIENT_ID` | Yes | From the `filebrowser` provider |
| `FILEBROWSER_OIDC_CLIENT_SECRET` | Yes | **Secret** |
| `ZULIP_OIDC_CLIENT_ID` | Yes | From the `zulip` provider |
| `ZULIP_OIDC_CLIENT_SECRET` | Yes | **Secret** |
| `MAILCOW_OIDC_CLIENT_ID` | Yes | From the `mailcow` provider |
| `MAILCOW_OIDC_CLIENT_SECRET` | Yes | **Secret** |
| `MAILCOW_AUTH_MODE` | No | `apppasswords` (default) or `ldap` |
| `WORKCENTER_USER_GROUP` | No | Default `workspaceusers` |
| `WORKCENTER_ADMIN_GROUP` | No | Default `workspaceadmin` |
| `WORKCENTER_ZULIP_BOT_EMAIL` | Yes | Zulip bot used by the broker for F4 |
| `WORKCENTER_ZULIP_BOT_API_KEY` | Yes | **Secret** |
| `TRAEFIK_FORWARDAUTH_ADDRESS` | Yes* | Outpost forward-auth URL (*required if the dashboard is deployed) |
| `ENABLE_INTERNAL_TLS` | No | `false` (default) or `true` |

### 9.2 `Filebrowser/.env`

| Variable | Required | Description |
| --- | --- | --- |
| `FILEBROWSER_OIDC_CLIENT_ID` | Yes | OIDC client ID |
| `FILEBROWSER_OIDC_CLIENT_SECRET` | Yes | **Secret** |
| `FILEBROWSER_JWT_TOKEN_SECRET` | Yes | **Secret**, `openssl rand -hex 32` |
| `FILEBROWSER_ONLYOFFICE_SECRET` | Yes | **Secret**, must match the OnlyOffice `JWT_SECRET` |
| `FILEBROWSER_ADMIN_PASSWORD` | No | Only for the bootstrap password path; not used with OIDC |

### 9.3 `Zulip/secrets/`

| File | Description |
| --- | --- |
| `zulip__postgres_password` | Generated |
| `zulip__memcached_password` | Generated |
| `zulip__rabbitmq_password` | Generated |
| `zulip__redis_password` | Generated |
| `zulip__secret_key` | Generated |
| `zulip__email_password` | Your SMTP password |
| `zuliprc` | Broker bot credentials (F4) |

### 9.4 `Mailcow/workcenter-oidc.env`

Written by `setup.sh` as a reference for the values you type into the Mailcow UI. It is a
**convenience copy**, not read by Mailcow — Mailcow stores identity-provider settings in its database.

| Variable | Description |
| --- | --- |
| `MAILCOW_OIDC_AUTHORIZE_URL` | `https://auth.<base>/application/o/authorize/` |
| `MAILCOW_OIDC_TOKEN_URL` | `https://auth.<base>/application/o/token/` |
| `MAILCOW_OIDC_USERINFO_URL` | `https://auth.<base>/application/o/userinfo/` |
| `MAILCOW_OIDC_CLIENT_ID` | `mailcow` |
| `MAILCOW_OIDC_CLIENT_SECRET` | **Secret** |
| `MAILCOW_OIDC_REDIRECT_URL` | `https://mail.<base>` |
| `MAILCOW_OIDC_SCOPES` | `openid profile email mailcow_template` |

---

## 10. Verifying the setup

Work through this after `setup.sh` completes.

| # | Check | Command or action | Expected |
| --- | --- | --- | --- |
| 1 | Discovery document is reachable and advertises HTTPS | `curl -s https://auth.example.com/application/o/workcenter/.well-known/openid-configuration \| grep issuer` | `"issuer": "https://auth.example.com/application/o/workcenter/"` |
| 2 | Workcenter redirects to Authentik | Open `https://example.com` | Browser lands on Authentik's login |
| 3 | The id_token carries groups | Sign in; decode the token at [jwt.io](https://jwt.io) | A `groups` array containing `workspaceusers` |
| 4 | Admin privilege works | Add yourself to `workspaceadmin`, sign out and in | The `Admin` badge appears in the user menu |
| 5 | FileBrowser SSO | Open the Files pane | No second login; the file tree loads |
| 6 | Zulip SSO | Open the Chat pane | No second login; the channel list loads |
| 7 | Zulip is frameable | The Chat pane renders the app | Not a "refused to connect" error |
| 8 | Mailcow OIDC | Open `https://mail.example.com` | Authentik login, then the Mailcow UI |
| 9 | SOGo reachable | Open `https://mail.example.com/SOGo` | SOGo loads within the SSO session |
| 10 | Mailcow connection test | Mailcow UI → System → Configuration → Access → Identity Provider → **Test Connection** | Success |
| 11 | Traefik dashboard is admin-only | Open `https://traefik.example.com` as a non-admin | Denied |
| 12 | Traefik dashboard works for admins | Open as a `workspaceadmin` member | Dashboard loads |

---

## 11. Session lifetime, renewal and logout

| Aspect | Behaviour |
| --- | --- |
| **Access token** | Default 1 hour, set on the Authentik provider |
| **Refresh token** | Default 30 days, requires the `offline_access` scope |
| **Silent renewal** | `enableSilentRenew: true` in `conf.yml` refreshes in the background; if it fails, the client falls back to a normal sign-in |
| **Renewal loop guard** | Workcenter refuses more than one silent renewal within 30 seconds, and one sign-in attempt within 5 seconds, to prevent redirect loops |
| **Logout** | Clears the local session, then calls Authentik's end-session endpoint (RP-initiated logout) |
| **Logout prompt** | Authentik's default invalidation flow may ask for confirmation. To remove the prompt, change the provider's **Invalidation flow** to one without a consent stage |
| **Clock skew** | Workcenter tolerates 30 seconds. Keep both hosts on NTP — a drifted clock is the most common cause of `"exp" claim timestamp check failed` immediately after login |

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| **Redirect loop** between Workcenter and Authentik | The issuer URL includes `/.well-known/openid-configuration` | Use the bare issuer only |
| **Redirect loop**, issuer looks right | Authentik advertises an `http://` issuer behind Traefik | Set `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` and ensure `X-Forwarded-Proto: https` |
| `invalid redirect URI` | The URL is not registered, or differs by scheme, host, port or trailing slash | Register both the bare and trailing-slash forms; matching mode `Strict` |
| **Logged in, but saving/configuring returns 403** | The id_token has no `groups` claim | Add the `groups` scope mapping to the provider's **Selected Scopes** and enable **Include claims in id_token** |
| **"SSO token is encrypted"** | The provider has an **Encryption Key** set | Clear the Encryption Key; keep only the Signing Key |
| `unexpected "iss" claim value` | The browser reaches Authentik over HTTPS but the token's issuer is HTTP | Same fix as the redirect loop: trusted proxy ranges and forwarded proto |
| `unexpected "aud" claim value` | `clientId` does not match the provider's Client ID exactly | Copy the exact value, including case. Wrap long numeric IDs in quotes in YAML |
| **Authentik 502 / never loads right after `up -d`** | First-boot migrations | Wait; `docker compose logs -f server` until the startup line appears |
| **Self-signed Authentik certificate rejected** | A private CA the client does not trust | Use a real certificate, or mount your CA and set `NODE_EXTRA_CA_CERTS` in the Workcenter container |
| **Zulip: `invalid_client`** | Secret mismatch between the provider and `Zulip/.env` | Recopy the secret; restart the `zulip` service |
| **Zulip: "refused to connect" in the pane** | `X-Frame-Options` blocks framing | Set `SETTING_X_FRAME_OPTIONS` / CSP `frame-ancestors` for the Workcenter origin |
| **Zulip: CSRF error on login** | Missing trusted origin | Set `SETTING_CSRF_TRUSTED_ORIGINS` to include `https://chat.<base>` |
| **Mailcow: login fails after switching to Generic-OIDC** | No attribute mapping, or the mail domain does not exist | Configure the attribute mapping; ensure the domain exists and has capacity |
| **Mailcow: "Test Connection" fails** | Wrong endpoints, or `Ignore SSL Errors` masking a real certificate problem | Verify all three endpoints, then fix the certificate rather than enabling the ignore flag |
| **Mail client cannot authenticate after OIDC** | Mail protocols do not use OIDC | Create an **app password**, or enable Mailcow's LDAP identity provider |
| **SOGo shows its own login page** | The Mailcow SSO session is not established | Open `https://mail.<base>` first, then the SOGo pane |
| **Traefik dashboard 403 for everyone** | The outpost does not include the `Traefik` application, or the group binding excludes you | Add the application to the embedded outpost; check the binding |
| **Silent renewal never refreshes** | `offline_access` is not granted | Add the `offline_access` scope to the provider's Selected Scopes |
| **`"exp" claim timestamp check failed`** | Clock skew | Sync NTP on both hosts |

---

## 13. Security notes

| Ref | Requirement |
| --- | --- |
| O-13.1 | Every client secret is generated by Authentik and stored only in a gitignored `.env` or `secrets/` file. Never in a tracked file, a screenshot, a log or an issue. |
| O-13.2 | Only the **authorization code flow with PKCE** is used. Implicit flow is never enabled. |
| O-13.3 | Only **signed** tokens are accepted. Encryption keys on providers are not used. |
| O-13.4 | Access to each application is restricted by a **group binding** to `workspaceusers`. Being able to authenticate is not the same as being authorised. |
| O-13.5 | The Mailcow UI, Authentik admin interface and Traefik dashboard are administrative surfaces. Do not expose them beyond the group that needs them. |
| O-13.6 | `Ignore SSL Errors` in Mailcow and `disableVerifyTLS` in FileBrowser Quantum are **testing-only** switches. Neither may be enabled in a production deployment; a failing certificate is fixed, not ignored. |
| O-13.7 | Rotating a client secret means updating it in both Authentik and the application's `.env`, then restarting that service. Record the rotation in [`CHANGELOG.md`](./CHANGELOG.md) under `Notes` if it affects operators. |
| O-13.8 | A user removed from `workspaceusers` keeps access only until their current token expires. Shorten the access-token validity if you need faster revocation. |

---

<p align="center"><sub>Workcenter OIDC guide · Authentik setup, the group model, and the <code>setup.sh</code> prompt contract</sub></p>
