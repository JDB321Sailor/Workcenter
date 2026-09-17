# Authentication

Workcenter renders one page: the workspace, which embeds three applications as panes. Authentication
means two things at once. The shell must know who is using it, and the integrated applications —
FileBrowser Quantum, Zulip and Mailcow/SOGo — must authenticate the same person against the same
identity provider. One identity for the whole workspace, not one login per pane.

Authentik over OIDC is the supported path for that integrated workspace: it is the only mechanism in
this set that the shell and all three applications can share. The other mechanisms exist, and are
documented, but each of them stops at the shell. See [What the mechanisms cover](#what-the-mechanisms-cover).

## Options

| Option | Enabled by | Guide |
| --- | --- | --- |
| OIDC | `appConfig.auth.enableOidc` with an `appConfig.auth.oidc` block | [`oidc.md`](./authentication/oidc.md) |
| Authentik over OIDC | The OIDC mechanism, configured against Authentik | [`authentik.md`](./authentication/authentik.md) |
| Header auth | `appConfig.auth.enableHeaderAuth` — the mechanism behind a forward-auth proxy such as Traefik with Authentik | [`header-auth.md`](./authentication/header-auth.md) |
| Built-in user list | `appConfig.auth.users` | [`built-in.md`](./authentication/built-in.md) |
| Keycloak | `appConfig.auth.enableKeycloak` with an `appConfig.auth.keycloak` block | [`other-auth-methods.md`](./authentication/other-auth-methods.md) |
| Nothing in front of it | A proxy, VPN or network that authenticates before the request arrives | [`other-auth-methods.md`](./authentication/other-auth-methods.md) |

**Authentik over OIDC is the recommended configuration.** Deploying it once gives the shell, Files,
Chat and Mail the same sign-in and the same group membership. Read [`OIDC.md`](../OIDC.md) for the
full stack, and [`authentik.md`](./authentication/authentik.md) for the walkthrough.

## The configuration an OIDC session needs

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

`clientId` and `endpoint` are required. `endpoint` is the provider's bare issuer URL, without
`/.well-known/openid-configuration`. `scope` must include `groups` when `adminGroup` is set, or the
claim that decides admin access never arrives. The full key list is in
[`oidc.md`](./authentication/oidc.md) and in [`configuring.md`](./configuring.md).

## What a session is

| Mechanism | What the browser holds | What the server checks |
| --- | --- | --- |
| OIDC | The id_token the provider issued, and the username and admin flag derived from its claims | The bearer token on every protected route, against the provider's published signing keys |
| Header auth | A token derived from the username and the matching `appConfig.auth.users` entry | That the request came from an address in `proxyWhitelist`, and that it carries the user header |
| Built-in user list | A cookie derived from the username and password hash | The same derived token, but only when `ENABLE_HTTP_AUTH=true` |

With OIDC the token is the credential: when it expires, the API calls that carry it fail until the
session is renewed or the user signs in again. With `enableSilentRenew: true` the client refreshes
the session in the background using a refresh token, which requires the `offline_access` scope on
the provider.

## What the mechanisms cover

| Mechanism | Authenticates the shell | Authenticates the embedded applications | Administrative access |
| --- | --- | --- | --- |
| OIDC | Yes, and the server verifies every token | Yes, when each application is registered as its own OIDC client | The `adminGroup` or `adminRole` claim |
| Header auth | Yes, from a header an upstream proxy sets | Yes, through the proxy's own policy | The matched user's `type` in `appConfig.auth.users` |
| Built-in user list | Yes, client-side, and server-side with `ENABLE_HTTP_AUTH=true` | No — the applications never see it | The matched user's `type` in `appConfig.auth.users` |
| Keycloak | Yes, through Keycloak's JavaScript adapter | Yes, when each application is registered as its own Keycloak client | The `adminGroup` or `adminRole` claim |
| Nothing in front of it | No | The application's own login | Not applicable |

## Rules

- **The shell cannot authenticate an embedded application.** A pane is an iframe on the
  application's own origin, so the shell cannot set a cookie or a header inside it. Signing in to the
  shell and signing in to an application are separate events; a shared identity provider is what
  makes them feel like one.
- **Prefer OIDC for anything reachable from outside your network.** Built-in auth puts a login page
  in front of the shell; it does not protect the applications, and it cannot replace an identity
  provider.
- **Bind access to a group as well as authenticating.** Being able to sign in is not the same as
  being authorised. See [`security.md`](./security.md).
- **OIDC and Keycloak need an identity provider; header auth needs a proxy.** Only the built-in user
  list works on its own.

## Ending a session

There is no logout control in the shell. Where a session actually ends depends on the mechanism.

| Mechanism | How the session ends |
| --- | --- |
| OIDC | Clear the browser's storage for the Workcenter origin, then use the identity provider's own end-session page |
| Header auth | End the session at the proxy. Set `appConfig.auth.logoutRedirectUrl` so the shell sends the browser to the proxy's sign-out endpoint |
| Built-in user list | Clear the cookie and the stored values for the Workcenter origin, or visit `/login` while signed in and use the logout button there |
| Anything in front of Workcenter | End the session at the proxy, VPN or provider that authenticated the request |

## In this folder

- [`authentik.md`](./authentication/authentik.md) — Authentik as the identity provider for the whole workspace
- [`oidc.md`](./authentication/oidc.md) — the OIDC client settings, the admin group claim and server-side verification
- [`header-auth.md`](./authentication/header-auth.md) — trusting a username header from an upstream proxy
- [`built-in.md`](./authentication/built-in.md) — the user list in `conf.yml`, and what it does and does not cover
- [`other-auth-methods.md`](./authentication/other-auth-methods.md) — what Workcenter does not implement, and what an operator can put in front of it

## Read next

- [`OIDC.md`](../OIDC.md) — the identity provider setup for the full stack
- [`configuring.md`](./configuring.md) — the configuration file and the `appConfig.auth` keys
- [`security.md`](./security.md) — trust boundaries and known limitations
