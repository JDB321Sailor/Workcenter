# OIDC

OIDC is the mechanism that covers the whole workspace: the shell signs the user in against an OpenID
Connect provider, and the server verifies every token the browser sends. For the full stack, read
[`OIDC.md`](../../OIDC.md); for Authentik specifically, [`authentik.md`](./authentik.md).

## Configuration

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

| Key | Type | Required | Description |
| --- | --- | --- | --- |
| `enableOidc` | `boolean` | Yes | Turns the mechanism on. Without it the `oidc` block is ignored. |
| `oidc.clientId` | `string` | Yes | The client ID from the provider, matched exactly, including case. |
| `oidc.endpoint` | `string` | Yes | The provider's bare issuer URL. The discovery path is appended by the client, so do not include `/.well-known/openid-configuration`. |
| `oidc.scope` | `string` | No | Scopes to request. Defaults to `openid profile email roles groups`. |
| `oidc.adminGroup` | `string` | No | A group that grants administrative access. |
| `oidc.adminRole` | `string` | No | A role that grants administrative access. |
| `oidc.enableSilentRenew` | `boolean` | No | Refresh the session in the background, adding the `offline_access` scope. |
| `oidc.showLoginPage` | `boolean` | No | Show Workcenter's login page instead of redirecting straight to the provider. |
| `oidc.postLogoutRedirectUri` | `string` | No | Where the provider sends the browser once it has ended the session. |
| `oidc.allowedIssuers` | `array` | No | Issuers to accept in place of the discovery document's, for a multi-tenant provider. |
| `oidc.disableServerSideCheck` | `boolean` | No | Skip server-side token verification. See [Server-side enforcement](#server-side-enforcement). |

**Quote a numeric `clientId`**, or YAML parses it as a number and loses precision past roughly
fifteen digits.

**Use `allowedIssuers` for a multi-tenant provider.** One whose token issuer differs from the
configured endpoint — Microsoft Entra's `organizations` endpoint, for example — fails issuer
verification. List the issuers to accept instead, as
`allowedIssuers: ['https://…/<tenant-id>/v2.0']`. Signature, audience and expiry are still verified.

## The provider side

Register the shell as a client using the **authorization code flow with PKCE**. Workcenter sends
`response_type=code`, and the redirect URI is the origin the shell is served from.

| Requirement | Why |
| --- | --- |
| `groups` in the requested scopes, when `adminGroup` is set | Without it the id_token carries no group claim, and the admin check silently fails. |
| Claims included in the id_token | The client reads the claims from the token, not from userinfo. |
| A signing key, and no encryption key | Only signed JWTs are accepted. An encrypted token is rejected as a JWE. |
| The exact redirect URI registered | Matching is strict, including a trailing slash. |
| `offline_access` allowed, when silent renewal is on | That is what makes the provider issue a refresh token. |

## Admin access

Workcenter decides administrative access from the token's claims. `adminGroup` is matched against
the `groups` claim, and against `groups_direct` for providers that put group membership there;
`adminRole` is matched against `roles`. With neither set, nobody is an admin.

**The claim must be in the id_token.** A claim that appears only in the access token is not read, so
decode the id_token and check what arrived. A user with no admin claim can still use the workspace —
they simply have no administrative privilege.

## Silent renewal

By default, an expired token sends the browser back through the provider for a new one. Set
`enableSilentRenew: true` to refresh in the background instead. Workcenter then requests the
`offline_access` scope, which the provider must allow.

Renewal is scheduled against the token's lifetime. If it fails — no refresh token, a revoked one, or
no fresh id_token — the client falls back to the interactive sign-in. Two guards prevent loops: one
sign-in redirect per five seconds, and one silent renewal per thirty seconds.

Leave the flag off against a provider that rejects `offline_access`, since the rejected scope would
break interactive sign-in too.

## Server-side enforcement

The Express server reads `appConfig.auth` when it starts. With OIDC enabled it fetches the
provider's discovery document and published signing keys, then verifies the bearer token the browser
attaches to each request: signature, issuer, audience and expiry. The audience is `clientId`, so a
mismatch there rejects every call. A five-part encrypted token is refused before any network call.

| Request | Response |
| --- | --- |
| A valid bearer token | The route runs, and `req.auth` carries the username and the admin decision. |
| A token that fails verification | `401`, `Unauthorized - Invalid or expired token`. No configuration is served. |
| No token, guest access off | A bootstrap subset of `conf.yml`: the `auth` block, `enableServiceWorker`, `enableAuthProxyCompat` and a login page title. The three applications' addresses are not sent. |
| No token, guest access on | The full configuration, read-only. |

Guest access is `appConfig.auth.enableGuestAccess`: with it on, an unauthenticated visitor sees the
workspace read-only instead of the sign-in flow. Authenticated configuration responses carry
`Cache-Control: private, no-store` and `Vary: Authorization`, so a shared cache cannot hand one user
another user's configuration. The server reads `appConfig.auth` at start-up, so restart it after
changing a key under `auth.oidc`; the client reads the same block on each page load. The
implementation is
[`services/utils/auth-oidc.js`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/services/utils/auth-oidc.js).

Setting `oidc.disableServerSideCheck: true` makes OIDC a client-side login only: the server stops
verifying tokens and stops stripping the configuration. **Do not set it on a deployment reachable
from outside your network.** It exists for a provider that cannot be verified server-side, or for a
disposable test host.

## Ending a session

There is no logout control in the shell, and the session is ended at the provider. A sign-out clears
the browser's stored session — the username, the admin flag and the token — and sends the browser to
the provider's end-session endpoint. Visiting `/login` while signed in offers a button that does the
same.

Set `oidc.postLogoutRedirectUri` to bring the browser back after the provider ends the session. The
value is sent as `post_logout_redirect_uri`, so it must be registered with the provider as a valid
post-logout redirect URI. An unregistered value is refused by many providers instead of ending the
session.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| A redirect loop with the provider | `endpoint` includes `/.well-known/openid-configuration` | Use the bare issuer. |
| `invalid redirect URI` | The served origin differs by scheme, host or trailing slash | Register the exact URL, including the trailing-slash form. |
| `unexpected "iss" claim value` | The provider advertises an issuer the token does not carry — commonly `http` behind a proxy | Make the provider trust the proxy, and forward the HTTPS scheme. |
| `unexpected "aud" claim value` | `clientId` does not match the provider's client ID | Copy the exact value, and quote a numeric one. |
| `"exp" claim timestamp check failed` just after sign-in | Clock drift | Sync both hosts over NTP. Workcenter tolerates thirty seconds. |
| No admin access | The token carries no `groups` claim | Add the `groups` scope, and include claims in the id_token. |
| Silent renewal never fires | `offline_access` is not granted | Add it to the provider's allowed scopes. |

See [`authentik.md`](./authentik.md) for the provider walkthrough, and [`OIDC.md`](../../OIDC.md) for the whole stack.
