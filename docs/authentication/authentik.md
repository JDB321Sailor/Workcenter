# Authentik OIDC

[Authentik](https://goauthentik.io/) is the identity provider for the supported Workcenter
configuration: one login for the shell and for the three applications it embeds. It is open source,
runs in Docker, speaks OIDC, OAuth 2.0, SAML 2.0 and LDAP, and has an admin UI with MFA and
per-application group policies.

[`OIDC.md`](../../OIDC.md) is the authoritative document for the whole stack — every provider, every
application and the `setup.sh` prompts. This page is the Authentik side of it: the objects to create
and the values Workcenter needs.

## What you are building

| Object | Name | Purpose |
| --- | --- | --- |
| Group | `workspaceusers` | Everyone who may use the workspace |
| Group | `workspaceadmin` | The people who administer it |
| Scope mapping | `groups` | Puts group membership into the id_token |
| Provider and application | `workcenter` | The shell itself |
| Provider and application | `filebrowser`, `zulip`, `mailcow` | One pair for each embedded application |
| Proxy provider and application | `traefik-dashboard`, `traefik` | Forward auth for the Traefik dashboard |

The shell needs the first four. The rest make the workspace single-sign-on rather than three separate
logins; [`OIDC.md` §5](../../OIDC.md) covers them.

## Deploy Authentik

`setup.sh` offers to deploy Authentik, which is the shortest path: it writes `Authentik/.env`,
generates the database password, the secret key and the bootstrap token with `openssl rand`, and
brings the stack up. Before deploying it also needs an admin email address, an `akadmin` password and
the version to pin.

To deploy it yourself, use Authentik's own Docker Compose guide:
<https://docs.goauthentik.io/docs/install-config/install/docker-compose>. Then open the instance and
sign in as `akadmin`.

**Behind a reverse proxy, Authentik must trust it.** Set `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` to
include the proxy's network, and make sure the proxy forwards `X-Forwarded-Proto: https`. Without it
Authentik advertises an `http://` issuer in its discovery document, and every client fails with
`unexpected "iss" claim value`.

First boot runs database migrations and takes a minute or two. A `502` or a login page that never
loads immediately after `docker compose up -d` is usually just that; wait and check the logs.

## Create the groups

1. **Directory → Groups → Create**.
2. Name the group `workspaceusers`.
3. Repeat for `workspaceadmin`.
4. Optionally create a test user and add them to both.

| Ref | Rule |
| --- | --- |
| A-1 | The names are exactly `workspaceusers` and `workspaceadmin`. They are configurable in the environment, but every application must use the same names or the model breaks. |
| A-2 | `workspaceadmin` is additive. An administrator is also a user, and belongs in both groups. |
| A-3 | Binding `workspaceusers` to an application decides **who may sign in**. Membership of `workspaceadmin` decides **what they may do**. |

## Create the `groups` scope mapping

**Authentik does not put group membership in the id_token by default.** Without this mapping, every
`adminGroup` check silently fails, and the shell cannot tell an administrator from anyone else.

1. **Customization → Property Mappings**.
2. **Create → Scope Mapping**.
3. **Name:** `groups`
4. **Scope name:** `groups`
5. **Expression:**

   ```python
   return {"groups": [g.name for g in request.user.ak_groups.all()]}
   ```

6. **Finish**.

Then add `groups` to **Selected Scopes** under *Advanced protocol settings* on every OIDC provider you
create.

## Create the provider and the application

### Provider

1. **Applications → Providers → Create → OAuth2/OpenID Provider → Next**.
2. **Name:** `workcenter`
3. **Authorization flow:** `default-provider-authorization-implicit-consent`. Use `…explicit-consent`
   if you want users to confirm each sign-in.
4. **Invalidation flow:** `default-provider-invalidation-flow`. Required on Authentik 2024.10 and
   newer.
5. **Protocol settings:**
   - **Client type:** `Confidential`
   - **Client ID:** `workcenter`, or accept the generated value and copy it
   - **Client Secret:** copy the generated value for the environment file
   - **Redirect URIs**, matching mode `Strict`, one per line:

     ```text
     https://example.com
     https://example.com/
     ```

6. **Advanced protocol settings:**
   - **Signing Key:** `authentik Self-signed Certificate`
   - **Encryption Key:** leave empty
   - **Selected Scopes:** `openid`, `profile`, `email`, `groups`
   - **Include claims in id_token:** on
   - Access token validity and refresh token validity as your policy requires
7. **Finish**.

### Application

1. **Applications → Applications → Create**.
2. **Name:** `Workcenter`
3. **Slug:** `workcenter`. The issuer becomes
   `https://auth.example.com/application/o/workcenter/`.
4. **Provider:** `workcenter`, then **Create**.
5. Re-open the provider and copy the **OpenID Configuration Issuer URL**.

### Restrict who can sign in

1. Open the `Workcenter` application → **Policy / Group / User Bindings**.
2. **Bind existing policy** → the **Group** tab → `workspaceusers` → **Enabled** → **Create**.

Anyone outside `workspaceusers` is then refused sign-in.

## Wire Workcenter to it

The shell reads this block from `user-data/conf.yml`. The client secret never goes in this file: the
server reads it from the environment. See [`OIDC.md` §6.1](../../OIDC.md).

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

| Key | Value |
| --- | --- |
| `auth.enableOidc` | `true`, to turn the mechanism on. |
| `oidc.clientId` | The provider's Client ID, exactly, including case. Quote it if it is numeric. |
| `oidc.endpoint` | The provider's **OpenID Configuration Issuer URL**, without `/.well-known/openid-configuration`. Workcenter appends the discovery path itself. |
| `oidc.adminGroup` | `workspaceadmin`. Members of this group get administrative access. |
| `oidc.scope` | Must include `groups`, or the id_token carries no group claim. |
| `oidc.enableSilentRenew` | Refresh the session in the background. Requires `offline_access` on the provider. |

```env
# .env
WORKCENTER_OIDC_CLIENT_ID=workcenter
WORKCENTER_OIDC_CLIENT_SECRET=<the secret from the provider>
WORKCENTER_USER_GROUP=workspaceusers
WORKCENTER_ADMIN_GROUP=workspaceadmin
```

**Two Authentik settings break the login when they are wrong.**

- **Encryption Key must be empty.** With one set, Authentik returns an encrypted JWE, and the shell
  refuses it with *"Workcenter needs signed JWT tokens, not encrypted JWE tokens"*.
- **Signing Key must be set.** With none, Authentik signs with HS256 and publishes no public key
  through JWKS, so the server cannot verify a token. Authentik's built-in
  `authentik Self-signed Certificate` is enough; it signs tokens and has nothing to do with the TLS
  certificate on the HTTPS endpoint.

Restart the server after changing a key under `auth.oidc`: the server reads that block at start-up.
If Authentik is reached through a proxy, `endpoint` must be reachable from inside the Workcenter
container, and the issuer it advertises must match `endpoint` exactly.

## Admin access from the group claim

There is no separate local administrator account for the workspace. Administrative access comes from
the token:

| Role | Groups | What they get |
| --- | --- | --- |
| Administrator | `workspaceusers` and `workspaceadmin` | The workspace, plus administrative access |
| User | `workspaceusers` | The workspace |

To promote someone, add them to `workspaceadmin` in Authentik. To check what the shell received,
decode the id_token and look for a `groups` array containing `workspaceadmin`. If it is missing, the
`groups` scope is not selected on the provider, or **Include claims in id_token** is off.

There is no logout control in the shell. A sign-out ends the session at Authentik: the stored session
is cleared and the browser is sent to the provider's end-session endpoint. Set
`oidc.postLogoutRedirectUri` if the provider should return the browser to the workspace afterwards,
and register that URL with the provider.

## Silent renewal

With `enableSilentRenew: true`, an expiring session is refreshed in the background instead of sending
the user back through Authentik:

```yaml
appConfig:
  auth:
    oidc:
      clientId: workcenter
      endpoint: https://auth.example.com/application/o/workcenter/
      adminGroup: workspaceadmin
      scope: openid profile email groups
      enableSilentRenew: true
```

Workcenter requests `offline_access` on its own, so the scope only has to be allowed on the provider:
open the provider, expand **Advanced protocol settings**, and add the built-in `offline_access` scope
to **Selected Scopes**. How often renewal runs follows the provider's access token and refresh token
validity. If a renewal fails, the client falls back to the interactive sign-in.

## Troubleshooting

Client-side problems are logged to the browser console, tagged `SSO` or `OIDC`. Token verification
failures appear in the Workcenter server log instead.

### Migrations still running on first boot

Authentik returns `502`, or the login page never loads, right after `docker compose up -d`. First
boot runs database migrations. Tail the logs with `docker compose logs -f server` and wait for the
startup line before opening the UI.

### A redirect loop between Workcenter and Authentik

`endpoint` in `conf.yml` includes `.well-known/openid-configuration`. Use the bare issuer.
If the issuer looks right, Authentik is advertising an `http://` issuer behind the proxy: set
`AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` and forward `X-Forwarded-Proto: https`.

### `invalid redirect URI`

The origin the shell is served from does not exactly match a registered redirect URI. Register both
the bare and trailing-slash forms, keep matching mode on `Strict`, and check the scheme.

### Signed in, but administrative access is missing

The id_token carries no `groups` claim. Add the `groups` scope mapping to the provider's **Selected
Scopes**, turn **Include claims in id_token** on, and confirm the user is in `workspaceadmin`.

### `unexpected "iss" claim value`

The browser reaches Authentik over HTTPS, but the token's issuer is HTTP. Same fix as the redirect
loop: trusted proxy ranges and a forwarded proto.

### `unexpected "aud" claim value`

`oidc.clientId` does not match the provider's **Client ID** exactly. If Authentik generated the
value, copy it character for character, and quote a numeric one.

### Self-signed certificate rejected

Fetching the discovery document or the JWKS fails, and the server logs a generic
`[auth-oidc] token verification failed: fetch failed`, with the TLS reason in the error cause. Use a
real certificate on Authentik's HTTPS endpoint, or mount your CA into the Workcenter container and
set `NODE_EXTRA_CA_CERTS`. The self-signed certificate that signs tokens is not the TLS certificate.

### `OIDC signinCallback returned no user`

The id_token came back without a usable username claim. Confirm `profile` and `email` are in the
provider's **Selected Scopes**, that **Include claims in id_token** is on, and that the user has an
email address or username in Authentik.

### `"exp" claim timestamp check failed` just after sign-in

Clock drift. Workcenter tolerates thirty seconds; sync both hosts over NTP. Container clocks follow
their host, so it is usually the host that has drifted.

### Silent renewal never refreshes the session

Authentik is not issuing a refresh token because `offline_access` is not granted. Add the built-in
`offline_access` scope to the provider's **Selected Scopes**. Workcenter requests the scope itself.

### The server cannot reach Authentik

Authenticated API calls return `401` and the server log shows fetch errors for
`.well-known/openid-configuration`. `endpoint` must be reachable from inside the Workcenter
container, not only from the browser. Test it from the container:

```bash
docker exec <workcenter-container> wget -qO- \
  "https://auth.example.com/application/o/workcenter/.well-known/openid-configuration" | head -c 200
```

### A change to `auth.oidc` is not picked up

The server reads the auth block only at start-up. Restart the Workcenter container after changing
`clientId`, `endpoint`, `adminGroup` or `scope`.

## How it works

1. The browser asks the server for the configuration. It has no session yet, so the server returns a
   bootstrap subset containing the auth block and a login page title, and nothing about the three
   applications.
2. The shell sees OIDC enabled and redirects to Authentik, using the authorization code flow with
   PKCE.
3. The user signs in — with MFA, if Authentik is configured for it — and Authentik returns a
   one-time code to the shell's origin.
4. The shell exchanges the code for a signed id_token, stores it, and attaches it as a bearer token
   to every request it makes to the server.
5. The server verifies the token against Authentik's published signing keys and checks the issuer,
   audience and expiry. A valid token is served the full configuration; a missing or invalid one
   gets the bootstrap subset, and the shell signs the user in again.
6. The `groups` claim travels inside the token. Membership of `workspaceadmin` is what grants
   administrative access.

The client side is
[`src/utils/auth/OidcAuth.js`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/utils/auth/OidcAuth.js);
server-side verification is in
[`services/utils/auth-oidc.js`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/services/utils/auth-oidc.js).

## Read next

- [`OIDC.md`](../../OIDC.md) — every provider, every application, and the `setup.sh` prompts
- [`oidc.md`](./oidc.md) — the OIDC client settings in full
- [`header-auth.md`](./header-auth.md) — forward auth, the pattern behind the Traefik dashboard
- [`security.md`](../security.md) — the trust boundaries of the deployed stack