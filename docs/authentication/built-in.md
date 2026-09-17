# Built-In Auth

Workcenter can hold its own list of users, in `appConfig.auth.users`, and show a login page when
nobody is signed in. The list lives in `user-data/conf.yml`, so there is no separate service to run
and no identity provider to deploy.

**Built-in auth authenticates the shell and nothing else.** It decides who may load the workspace. It
does not sign anyone in to FileBrowser Quantum, Zulip or Mailcow/SOGo — those are separate services
on their own origins and keep their own sessions. For one identity across the whole workspace, use
[Authentik over OIDC](./authentik.md).

## What it covers

| Surface | Covered |
| --- | --- |
| The workspace and its route guard | Yes — an unauthenticated visitor is sent to `/login` |
| The configuration served to the browser | Yes, as a stripped bootstrap subset, when server-side enforcement is on |
| `/config-manager/save`, `/system-info`, `/cors-proxy`, `/get-user` | Yes, when `ENABLE_HTTP_AUTH=true` |
| The `.yml` files in `user-data/` | Yes, when `ENABLE_HTTP_AUTH=true` |
| The three embedded applications | No — each application authenticates its own users |
| The broker and the REST API | No — the broker verifies Authentik tokens, and the API has its own gate |

## Defining users

`appConfig.auth.users` is a list. Each entry needs a username and exactly one credential.

```yaml
appConfig:
  auth:
    users:
      - user: alicia
        hash: 5994471ABB01112AFCC18159F6CC74B4F511B99806DA59B3CAF5A9C173CACFC5
        type: admin
      - user: guestuser
        hash: EF797C8118F02DFB649607DD5D3F8C7623048C9C063D532CC95C5ED7A898A64F
        type: normal
```

| Key | Type | Description |
| --- | --- | --- |
| `user` | `string` | The username. Matched case-insensitively at sign-in. Required. |
| `hash` | `string` | A SHA-256 hash of the password, 64 hexadecimal characters. |
| `password` | `string` | The name of a `VITE_APP_*` environment variable holding the plaintext password. |
| `type` | `string` | `admin` or `normal`. Defaults to `normal`. |

Each entry needs `user` plus one of `hash` or `password`, not both. The schema rejects any other key
inside an entry.

### Generating a password hash

The hash is a plain SHA-256 of the password, in hex. Either case is accepted, because the comparison
is case-insensitive.

```bash
echo -n "my-super-secure-password" | sha256sum
```

Use `echo -n`, or `printf '%s' 'my-super-secure-password' | sha256sum`. A tool that appends a
newline produces a hash of the password plus a newline, which never matches.

### Naming a password environment variable

Instead of an inline hash, an entry can name an environment variable:

```yaml
appConfig:
  auth:
    users:
      - user: alicia
        password: VITE_APP_ALICIA_PASSWORD
        type: admin
```

The name is resolved from the built bundle, not from the running process. A `VITE_APP_*` value is
compiled in by Vite when the client is built, so changing it means rebuilding the client. The name
must start with `VITE_APP_`; anything else is rejected and the entry cannot sign in.

To use this, build the client from the repository with the variable set:

```bash
VITE_APP_ALICIA_PASSWORD=my-super-secure-password yarn build
```

## Protection modes

There are two ways to protect the shell, and they are independent of each other.

| Mode | What you set | Login page | Server enforces |
| --- | --- | --- | --- |
| Client-side | `appConfig.auth.users` | Yes | No |
| Server-enforced | `appConfig.auth.users` and `ENABLE_HTTP_AUTH=true` | Yes | Yes |

**Server-enforced is the mode to use for anything beyond a private network.** With the client-side
mode alone, the login page is a route guard: the configuration and the server routes are still
reachable by anyone who can reach the host.

### Client-side

The workspace is only rendered to a signed-in user. Signing in sets a cookie derived from the
username and the password hash, and the route guard reads that cookie back on every navigation.

The login form also asks how long the session should last — **Never**, 4 hours, 1 day, 1 week or 52
weeks — and the cookie's expiry follows that choice. **Never** means a session cookie, which ends
when the browser closes.

### Server-enforced

```env
ENABLE_HTTP_AUTH=true
```

The flag has no effect unless `appConfig.auth.users` is also set. When both are present, the Express
server protects `/config-manager/save`, `/system-info`, `/cors-proxy`, `/get-user`, the `.yml` files
in `user-data/`, and the REST API routes with the same user list. A request with no valid credential
is refused with `401` and a basic-auth challenge.

The credential the browser sends is the value it holds from sign-in: the username, and the token
derived from that username and the matching password hash. The server derives the same token for each
entry in `auth.users` and accepts the request on a match. There is no signature and no server-side
expiry — the token is valid as long as the entry is.

## Guest access

```yaml
appConfig:
  auth:
    enableGuestAccess: true
    users:
      - user: alicia
        hash: 5994471ABB01112AFCC18159F6CC74B4F511B99806DA59B3CAF5A9C173CACFC5
        type: admin
```

A visitor without a session is shown the workspace read-only instead of being sent to the login
page. The login page offers a **Continue as Guest** button. Guest access requires `auth.users` to be
set; with no users, authentication is off entirely and the workspace is open to everyone.

With guest access on, an unauthenticated request for `conf.yml` receives the full file rather than
the bootstrap subset. Guests can therefore read the addresses of the three applications. Do not put a
secret in `conf.yml`; secrets belong in the environment. See [`configuring.md`](../configuring.md).

## Roles

`type` has two values, `admin` and `normal`, and defaults to `normal`. An unauthenticated visitor is
a guest when guest access is on.

| Identity | Load the workspace | Send authenticated requests to the server |
| --- | --- | --- |
| `admin` | Yes | Yes |
| `normal` | Yes | Yes |
| Guest | Yes, when guest access is on | No |

A signed-in user of either type gets the same workspace: there is no configuration interface to be
admin of, and nothing in the shell is admin-only. Administrative privilege is decided server-side,
from the token's claims when OIDC or Keycloak is the mechanism, or by the REST API's `API_TOKEN`
bearer. See [`api.md`](../api.md).

## Ending a session

There is no logout control in the shell. A built-in session ends in one of three ways:

- Clear the cookies and site data for the Workcenter origin. The session cookie and the stored
  username go with it.
- Set `appConfig.auth.logoutRedirectUrl` so that a sign-out sends the browser to a URL of your
  choosing.
- Visit `/login`. While signed in, the page shows a **Log out** button next to the existing session,
  which clears the session and returns to the login form.

```yaml
appConfig:
  auth:
    logoutRedirectUrl: https://sso.example.com/logout
```

## Security notes

- **The hash is plain SHA-256.** It is fast, which makes it weak against offline cracking. A leaked
  `conf.yml` exposes every password that is not long and random.
- **The client-side mode is bypassable.** Without `ENABLE_HTTP_AUTH=true`, a script on the page is
  the only thing standing between a visitor and the workspace. It suits a trusted network, not an
  internet-facing deployment.
- **There is no password reset, no lockout and no rate limiting.** Put a proxy that rate limits in
  front of the shell if that matters to you.
- **Built-in auth is not part of the workspace's identity model.** The three applications do not
  read this list, so it cannot give anyone single sign-on. Use it to keep a private instance private,
  or use OIDC to run a workspace.

## Read next

- [`header-auth.md`](./header-auth.md) — trust an upstream proxy instead of a password
- [`oidc.md`](./oidc.md) — the identity mechanism that covers the whole workspace
- [`authentik.md`](./authentik.md) — OIDC against Authentik, end to end
- [`configuring.md`](../configuring.md) — the configuration file and the schema
