# Header Authentication

Header authentication lets Workcenter take a username from a request header, set by a reverse proxy
that has already authenticated the user. The shell has no login form of its own in this mode: the
proxy decides who gets in, and Workcenter maps the forwarded username to a user in `conf.yml`.

This is the mechanism behind a forward-auth setup — Traefik with Authentik, nginx with
`auth_request`, Caddy with `forward_auth`, or oauth2-proxy — where the proxy holds the session and
the upstream application only receives an identity.
## Configure Workcenter

```yaml
appConfig:
  auth:
    enableHeaderAuth: true
    logoutRedirectUrl: https://workcenter.example.com/oauth2/sign_out
    users:
      - user: alicia
        hash: 5994471ABB01112AFCC18159F6CC74B4F511B99806DA59B3CAF5A9C173CACFC5
        type: admin
      - user: bob
        hash: EF797C8118F02DFB649607DD5D3F8C7623048C9C063D532CC95C5ED7A898A64F
        type: normal
    headerAuth:
      userHeader: Remote-User
      proxyWhitelist:
        - 172.18.0.2
```

| Key | Type | Description |
| --- | --- | --- |
| `enableHeaderAuth` | `boolean` | Turns the mode on. Required. |
| `headerAuth.userHeader` | `string` | The header carrying the username. Defaults to `Remote-User`. Header names are matched case-insensitively. |
| `headerAuth.proxyWhitelist` | `array` | The addresses the header is accepted from. Required by the schema. |
| `auth.users` | `array` | The identities allowed in, each with `user` and a `hash`. |
| `logoutRedirectUrl` | `string` | Where to send the browser so the proxy can end its own session. Optional. |

The whitelist is compared against the address of the connection that reaches Workcenter, not the
address of the original client. Behind Docker that is the proxy container's address on the shared
network. Find it with `docker inspect` on the proxy container.

A forwarded username must match a `user` in `auth.users`, case-insensitively. The match supplies the
`type`, and its `hash` — any 64-character SHA-256 hex value — is the input from which the shell
derives its session token. Nobody types that password; it exists so that the session has a value to
derive. Generate one as described in [`built-in.md`](./built-in.md#generating-a-password-hash).

## Configure the proxy

The proxy has two jobs:

1. Authenticate the user, and forward the username on every request to Workcenter, for example
   `Remote-User: alicia`.
2. Connect from an address that is listed in `proxyWhitelist`.

**Workcenter must not be reachable except through the proxy.** The whitelist is the only thing
separating a genuine header from a forged one, and a client that can reach Workcenter directly from
a whitelisted address can claim any username. Bind the shell to an internal network, or restrict it
at the firewall.

## Forward auth with Traefik and Authentik

Traefik terminates TLS, Authentik's proxy outpost answers the forward-auth check, and the
authenticated username reaches the upstream service as a header. [`OIDC.md`](../../OIDC.md) creates the
proxy provider, the `Traefik` application and the group binding for the Traefik dashboard.

Point the Workcenter router at the forward-auth middleware, set `userHeader` to the header the
outpost forwards, and list Traefik's address on the shared Docker network in `proxyWhitelist`. The
proxy and `userHeader` must agree on the header name; read it from the outpost's configuration
rather than assuming a default.

Leave `logoutRedirectUrl` unset unless the proxy exposes a sign-out endpoint you want a sign-out to
reach.

## Ending a session

There is no logout control in the shell, and header authentication has no session of its own — the
session lives at the proxy. Clearing anything in the browser signs the user straight back in on the
next request, because the proxy still holds a session and still sends the header.

Set `logoutRedirectUrl` to the proxy's sign-out endpoint:

```yaml
appConfig:
  auth:
    logoutRedirectUrl: https://workcenter.example.com/oauth2/sign_out
```

A sign-out then sends the browser to that URL. For oauth2-proxy the endpoint is usually
`/oauth2/sign_out`, and an `rd` query parameter chains the identity provider's own logout:

```text
https://workcenter.example.com/oauth2/sign_out?rd=https://auth.example.com/application/o/workcenter/end-session/
```

The `rd` target must be listed in oauth2-proxy's `whitelist_domains`, or the redirect is dropped.
The parameter name is oauth2-proxy's; another proxy will use its own.

## Troubleshooting

### `401 Unauthorized - not from trusted proxy`

The request reached Workcenter from an address that is not in `proxyWhitelist`. The check is on the
direct connection address, so behind Docker it is the proxy container's address, not the host's and
not the client's. Read the address from the rejected request in Workcenter's logs, or from
`docker inspect` on the proxy container, and add it.

### `401 Unauthorized - missing user header`

The request came from a trusted address but carried no value in the configured header. Either the
proxy is not forwarding it, or `userHeader` names a header the proxy does not send.

### `User '...' from upstream proxy was not found in conf.yml`

The proxy authenticated someone who has no entry in `appConfig.auth.users`. Add an entry whose
`user` matches the forwarded name. Removing an entry blocks that person even while the proxy still
lets them through, which is the intended place to revoke access.

### The workspace keeps reloading or shows an authentication failure

The user entry matched, but the session token could not be derived. Confirm the entry carries a
`hash` of exactly 64 hexadecimal characters, and that the forwarded username and the `user` value
are the same name.

### Signed out, then signed straight back in

The proxy's session is still alive. Set `logoutRedirectUrl` to the proxy's sign-out endpoint, as
described above.

## How it works

1. The browser loads the shell through the proxy. The proxy authenticates the request and adds the
   username header.
2. The shell asks the server for the current user. The server checks the request's address against
   `proxyWhitelist`, reads the header if the address is trusted, and returns the username.
3. The shell matches that username against `appConfig.auth.users` and stores a session derived from
   the matched user.
4. On every later request the proxy re-authenticates, and the server enforces the same whitelist on
   the routes it protects.

The client side is
[`src/utils/auth/HeaderAuth.js`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/utils/auth/HeaderAuth.js).
The server side is
[`services/endpoints/get-user.js`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/services/endpoints/get-user.js),
with the whitelist middleware in
[`services/app.js`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/services/app.js).

## Read next

- [`authentik.md`](./authentik.md) — the identity provider and the forward-auth outpost
- [`oidc.md`](./oidc.md) — signing the shell in directly, instead of through a proxy
- [`security.md`](../security.md) — trust boundaries and the intended deployment
