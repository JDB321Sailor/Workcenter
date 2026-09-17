# Troubleshooting

Something is broken. Find the heading that matches the symptom, read the cause, apply the fix.

Two facts shape everything below. The shell reads one configuration file, `user-data/conf.yml`, and it
reads it on page load. And there is no configuration UI: the file is written by you or by the REST API,
never by the shell. See [`configuring.md`](./configuring.md).

| Where to look | What it tells you |
| --- | --- |
| The **Configuration Load Error** panel | Why the shell could not read `conf.yml` |
| The **browser console** | Client errors, tagged `OIDC`, `SSO` or `Service Worker Status` |
| The **server log** | Config validation at boot, and `[auth-oidc]` token verification |
| `GET /healthz` | Whether the Node server is serving, and its version |

## Contents

- [Configuration does not load](#configuration-does-not-load)
- [Writing the configuration back](#writing-the-configuration-back)
- [Sign-in and OIDC](#sign-in-and-oidc)
- [Panes](#panes)
- [Routing and 404s](#routing-and-404s)
- [Build and memory](#build-and-memory)
- [Docker and volumes](#docker-and-volumes)
- [Styles and assets after a deploy](#styles-and-assets-after-a-deploy)
- [Gathering information for a bug report](#gathering-information-for-a-bug-report)

---

## Configuration does not load

The server resolves the file as `USER_DATA_DIR/conf.yml`: `/app/user-data/conf.yml` in Docker,
`./user-data/conf.yml` in a checkout. The shell requests it from `/conf.yml` at the origin root, and the
server answers from disk every load.

### The panel says `Server responded with status 404`

**Cause.** No readable `conf.yml` at that path. Usually `user-data/` is mounted over an empty host
directory, the file is named something else, or it cannot be read by uid 1000.

**Fix.** Check what the server is reading. The name is `conf.yml`, exactly; if it is missing, copy yours
into `./user-data/` on the host and run the container with that directory mounted:

```bash
docker exec workcenter head -n 9 /app/user-data/conf.yml
docker run -d -p 4000:8080 -v "$PWD/user-data:/app/user-data" --name workcenter workcenter:dev
```

If the panes come up pointed at `example.com` addresses instead, no directory is mounted over
`/app/user-data` at all, and the container is reading the `conf.yml` that ships inside the image.

### The panel says `No response from server`

**Cause.** The request never reached the Node server: the container is stopped, the port mapping is
wrong, or a proxy returned a connection error rather than a response.

**Fix.** Call the server directly. A JSON body with `status`, `uptime` and `version` means the server is
fine and the proxy is not; nothing at all means the container or the port.

```bash
curl -s http://localhost:4000/healthz
```

### The panel says `Failed to parse YAML: ...`, or `yarn validate-config` reports problems

A parse failure means the file is not valid YAML: a tab where an indent belongs, an unquoted colon in a
value, or a duplicate key. Run the validator, which reports the line and column, after every edit:

```bash
yarn validate-config
```

A line such as `1. /appConfig/applications must NOT have additional properties (filebrowser)` means the
key is spelled `files`. A YAML syntax error is reported with the line, the column and a snippet instead.
The server prints the same report at boot, then runs with the file as written.

**A key the schema does not know is rejected.** The schema sets `additionalProperties: false`, and
`PUT /api/config/conf.yml` applies the same check, so a typo fails rather than being ignored. The top-level
keys are `pageInfo`, `appConfig` and `sections`; `sections` validates and the shell does not read it.
`backgroundImg`, `defaultOpeningMethod`, `workspaceLandingUrl`, `iconSize`, `defaultIcon` and
`faviconApi` are accepted and ignored — nothing in the shell reads them. An address belongs in
`appConfig.applications`.

### Edits on the host never reach the container

**Cause.** `conf.yml` is bind-mounted as a single file, and an editor that saves by writing a new file and
renaming it over the old one leaves the mount pointing at the old file. **Fix.** Mount the directory,
`./user-data:/app/user-data`, not the file.

### Nothing loads when Workcenter is served under a sub-path

**Cause.** The configuration is requested from `/conf.yml` at the origin root, which a proxy that forwards
only `/workcenter/*` never sees. **Fix.** Give Workcenter its own hostname, or build the client with
`VITE_APP_CONFIG_PATH` set to the full path or URL of the configuration.

### The tab title reads `Login | ...` and nothing else renders

**Cause.** Expected. With authentication configured and no session, the server answers `/conf.yml` with a
bootstrap subset: the `auth` block and the title `Login | <your title>`. **Fix.** Sign in. If you are
signed in and still see it, your token is not reaching the server.

---

## Writing the configuration back

Change the file directly, or use the REST API, which is off until `ENABLE_API=true` is set on the server.
Reads need any authenticated user, writes need an admin. See [`api.md`](./api.md).

| Method | Path |
| --- | --- |
| `GET` | `/api/config`, `/api/config/:filename`, `/api/config/:filename/:key` |
| `PUT` | `/api/config/:filename`, `/api/config/:filename/:key` |

`:key` is one of `pageInfo`, `appConfig`, `sections` or `pages`. Errors come back as
`{"success": false, "message": "..."}` with a 400, 401, 403 or 404.

| Message | Cause | Fix |
| --- | --- | --- |
| `API not enabled. Set ENABLE_API=true to use the REST API.` | The API is disabled | Set `ENABLE_API=true` on the container and restart |
| 401 `Unauthorized` | No usable identity on the request | Send your `id_token` as a bearer token, or set `API_TOKEN` and send that |
| 403 `Forbidden - Admin access required` | Authenticated, not an admin | See [the 403 below](#a-write-returns-403-forbidden---admin-access-required) |
| `Config does not conform to schema: ...` | `PUT` validates `conf.yml` before writing | Correct the keys and send the whole file again |
| `Invalid filename: must be a basename ending in .yml or .yaml` | A path separator, or another extension | Send a plain basename |
| `conf.yml not found` | Nothing to read or back up | See [Configuration does not load](#configuration-does-not-load) |
| `Config exceeds maximum size of 256 KB` | The file is over the limit | Split it, or trim it |
| `Unable to backup conf.yml` | The copy into `user-data/config-backups/` failed, so the write was abandoned | Point `BACKUP_DIR` at a writable path, or set `DISABLE_CONFIG_BACKUPS=true` |

The API validates `conf.yml`; `POST /config-manager/save`, which the API calls to write, checks only the
filename and the size.

### `Unable to write to conf.yml: EACCES` or `EROFS`

**Cause.** The container cannot write the file. Almost always an ownership mismatch: the mounted
directory belongs to a different uid than the one Workcenter runs as. **Fix.** The container runs as the
`node` user, uid 1000:

```bash
docker exec workcenter ls -la /app/user-data
sudo chown -R 1000:1000 ./user-data
```

To keep host ownership instead, run the container as your own user with `--user "$(id -u):$(id -g)"`, or
set `user: "1001:1001"` (your host uid and gid) on the Compose service. `EROFS` means the mount itself is
read-only: a `:ro` flag, or a Kubernetes ConfigMap volume, which is read-only by design.

---

## Sign-in and OIDC

Client-side problems are logged to the browser console tagged `OIDC` or `SSO`; token verification failures
are logged by the server as `[auth-oidc] token verification failed: <reason>`. The identity setup is in
[`OIDC.md`](../OIDC.md) and [`authentication/authentik.md`](./authentication/authentik.md).

**The server reads `appConfig.auth` once, at boot.** Restart the container after changing anything under
`auth`, including `oidc.clientId`, `oidc.endpoint`, `adminGroup` and `scope`.

### You bounce between Workcenter and the provider, or see `invalid_redirect_uri`

| Symptom | Cause | Fix |
| --- | --- | --- |
| A redirect loop, and the console reports `OIDC sign-in redirect loop detected. Check provider redirect URIs and that id_token claims include a username.` | `oidc.endpoint` includes `.well-known/openid-configuration`, but the endpoint is the bare issuer; the discovery document is appended to it | Drop everything from `.well-known` onwards, so the value looks like `https://auth.example.com/application/o/workcenter/`, then restart |
| The provider rejects the sign-in with `invalid_redirect_uri` | The URL the shell is served from does not exactly match what the provider registered. The shell sends its bare origin as the redirect URI | Register the origin itself, same scheme, no path: `https://workcenter.example.com` |

### Login completes, then every request is 401

**Cause.** The server could not verify the `id_token`. The server log gives the reason:

| Log reason | Cause | Fix |
| --- | --- | --- |
| `unexpected "iss" claim value` | The issuer in the token is not the configured one; behind a proxy the discovery document may advertise `http://` while you configured `https://` | Forward `X-Forwarded-Proto: https`, and set `AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` to include the proxy |
| `unexpected "aud" claim value` | `oidc.clientId` is not the provider's Client ID | Copy the exact value from the provider, including case |
| `fetch failed` | The server cannot reach the issuer, or its certificate is untrusted | Fetch the discovery document from inside the container with `wget -qO-`, and use a trusted certificate on the issuer's hostname |
| `"exp" claim timestamp check failed` | A clock more than 30 seconds out | Sync both hosts with NTP |

`disableServerSideCheck: true` skips server-side verification and leaves the server's routes
unprotected. Use it only as a stop-gap in a trusted environment.

### A write returns 403 `Forbidden - Admin access required`

**Cause.** Verification succeeded, but the token carries no matching group or role claim. Groups are read
from `groups` (and GitLab's `groups_direct`), roles from `roles`. **Fix.** Decode the `id_token` from
`localStorage` (key `idToken`) and look for the claim. If it is missing, `scope` must include `groups`,
and the user must be in `adminGroup` — `workspaceadmin` for the integrated workspace.

### Other sign-in failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| Signed out after a while | The token expired | Set `oidc.enableSilentRenew: true`, and grant the `offline_access` scope on the provider |
| Logout leaves you at the provider | The invalidation flow asks for confirmation | Use a flow without a consent stage, or set `oidc.postLogoutRedirectUri` and register it |
| `SSO token is encrypted` | The provider encrypted the token as well as signing it | Clear the provider's encryption key and keep only its signing key |
| A numeric `clientId` is rejected as an unknown client | YAML parsed an unquoted number, and a value past JavaScript's safe-integer range loses precision | Quote it: `clientId: "918756876419824312"` |
| `Invalid user object` on startup | An all-digit `hash` was parsed by YAML as a number, so the entry looks incomplete | Quote the hash; see [`authentication/built-in.md`](./authentication/built-in.md) |
| Basic auth fails and `auth.users` is also set | `ENABLE_HTTP_AUTH=true` validates against `auth.users`, while `BASIC_AUTH_USERNAME` and `BASIC_AUTH_PASSWORD` are a separate method; the server warns at boot that they do not work together | Keep one method |
| `Unauthorized - not from trusted proxy` or `Unauthorized - missing user header` | Header auth: the proxy's address is not in `auth.headerAuth.proxyWhitelist`, or the configured `userHeader` is not on the request. In Docker that address is the bridge address | Add the address, check the proxy's forward-auth configuration, and restart; see [`authentication/header-auth.md`](./authentication/header-auth.md) |

---

## Panes

Each application is an iframe. The shell cannot read inside a pane, so it reports only what it can see:
whether the frame loaded, and what the health check says.

### A pane says `<App> is not responding`, or `<App> did not finish loading`

**Cause.** No address is configured for the application, the configured value is not an `http` or `https`
URL, the frame failed to load, or it did not fire a load event within 30 seconds. Clicking the application
in the switcher shows `Set its address in appConfig.applications` in the first case.

**Fix.** The address must be the one the **browser** reaches, not an internal Docker hostname, and it must
include the scheme — for example `url: https://filebrowser.example.com` under
`appConfig.applications.files`. Otherwise **Retry**, or **Open in new tab** to see the application's own
error.

### A pane is blank, or shows `refused to connect`

**Cause.** The application refuses to be embedded. A frame is displayed only if the embedded page permits
its parent, and a refused frame may still fire its load event, so the shell can show a blank frame with
no error card. The browser console names the offending header.

| Cause | Fix |
| --- | --- |
| `X-Frame-Options` is `DENY`, or `SAMEORIGIN` and Workcenter is on another host. Zulip sends `DENY` by default, which is why [`integration.md`](../integration.md) deploys a derived image for it | Allow Workcenter as a frame ancestor there, then reload: `Content-Security-Policy: frame-ancestors 'self' https://workcenter.example.com` |
| An untrusted certificate on the application's hostname, which the browser will not render inside a frame | Open the host in a new tab, and use a trusted certificate |
| An expired session in the application itself | The pane shows that application's login page; the shell cannot tell it apart from a working session |

**Open in new tab** always reaches the application, even when the frame is refused.

### A status indicator stays grey

**Cause.** The indicators come from `GET /api/broker/health`, which the shell polls while the workspace is
open: every 30 seconds, backing off to five minutes while nothing changes. Each application is `healthy`,
`degraded`, `unhealthy` or `unknown`, and `unknown` is what a failed poll produces. A grey dot means the
check did not run, not that the application is down.

**Fix.** Read that request's status in the Network tab. A 401 means it arrived without a usable session; a
404 means this deployment's server does not serve the route. Either way every application reports
`unknown`. Hover an indicator to see the state and the check behind it.

---

## Routing and 404s

The router has five routes: `/`, `/files`, `/chat` and `/mail` render the single workspace view, and
`/login` renders the login page. Every other path falls through to the workspace.

| Symptom | Cause | Fix |
| --- | --- | --- |
| An unknown path shows the workspace, not a 404 page | The catch-all route, working as intended; the unmatched route selects the first application, so Files is shown | None |
| A deep link 404s behind a reverse proxy | The proxy forwards only some prefixes; the server answers any GET that is not a static asset with the shell | Forward every path for the hostname to Workcenter's port, leaving `/api/*`, `/conf.yml`, `/config-manager/*` and `/healthz` untouched |
| A missing asset returns JSON, not a page | A path ending in a 2–5 character extension is treated as an asset and answered with `{"success":false,"message":"Not Found"}` | Correct the reference; the session is fine |
| A reload of `https://host/files` shows the login page | Expected: each route is guarded, and an unauthenticated request goes to `/login` | Sign in, or set `appConfig.auth.enableGuestAccess: true` |

---

## Build and memory

`yarn build` writes `dist/`; `yarn typecheck` and `yarn lint` catch most failures before it runs. The error
`The engine "node" is incompatible with this module` means your Node version is below the range in
`package.json`: use `^22.18.0 || >=24.11.0`, which `node --version` reports and `nvm install 24` provides.

### `yarn build` fails inside a running container

**Cause.** The runtime image carries the built client, the server, `services/` and production dependencies
only. There is no `src/`, no `vite` and no build toolchain in it. **Fix.** Build where the source is, then
rebuild the image so it picks up the new `dist/`:

```bash
yarn install --frozen-lockfile && yarn build
```

A configuration change needs none of this: the server reads `user-data/conf.yml` on every request.

### The build is killed

**Cause.** Out of memory. The signature is `FATAL ERROR: Reached heap limit Allocation failed - JavaScript
heap out of memory`, or a bare `Killed` with exit code 137. The image build runs the Vite build in its
first stage. **Fix.** Give it more heap, or build on the host and copy `dist/` into your own image:

```bash
NODE_OPTIONS=--max-old-space-size=4096 yarn build
```

A `Cannot find module ...` error after switching branches means `node_modules` and `yarn.lock` disagree;
run `yarn cache clean && rm -rf node_modules && yarn install --frozen-lockfile`.

---

## Docker and volumes

The container listens on **8080**; the Compose file and [`deployment/docker.md`](./deployment/docker.md)
publish it as 4000. The image runs as the `node` user, uid 1000. For status and logs, use
`docker compose ps` and `docker compose logs -f workcenter`.

### The container says `unhealthy`

**Cause.** The healthcheck could not reach `/healthz` on its own port. It probes HTTPS when certificate
files exist at the paths the server uses. **Fix.** Read the field, then run the check:

```bash
docker inspect --format '{{.State.Health.Status}}' workcenter
docker exec workcenter node services/healthcheck.js
```

The default start period is 20 seconds, so a failure counted just after a restart is expected. A failure
that persists means the server is not serving: usually an unreadable `conf.yml` or a missing `user-data`
mount. If you set `PORT`, `SSL_PRIV_KEY_PATH` or `SSL_PUB_KEY_PATH`, set it in the container's
environment, not only in the port mapping.

### The container starts, but nothing answers

**Cause.** The server failed to bind its port. It logs `Unable to start Workcenter's Node server` and
stays up without a listener, so `docker ps` still reports the container as running. **Fix.** Free the
port, or change both sides of the mapping together:

```bash
docker run -d -p 4000:3000 -e PORT=3000 -v "$PWD/user-data:/app/user-data" workcenter:dev
```

A host-side `Bind for 0.0.0.0:4000 failed: port is already allocated` is a different error: another
process holds the published port.

### Every request redirects to HTTPS that is not published

**Cause.** Certificate files exist at the paths the server reads (`/etc/ssl/certs/workcenter-pub.pem` and
`workcenter-priv.key`, or the files named by `SSL_PUB_KEY_PATH` and `SSL_PRIV_KEY_PATH`). The server then
also listens on `SSL_PORT` — 443 in the container — and redirects HTTP to it, so an unpublished 443
refuses the connection. **Fix.** Publish 443, remove the certificates, or set `REDIRECT_HTTPS=false`.
`/healthz` is exempt from the redirect.

### `Are you trying to mount a directory onto a file (or vice-versa)?`

**Cause.** The host side and the container side of the mount disagree about which one is a file. **Fix.**
Mount a host directory with `conf.yml` in it onto `/app/user-data`, as in
[`deployment/docker.md`](./deployment/docker.md). A single-file mount needs that file to exist already,
or Docker creates a directory in its place — and see
[Edits on the host never reach the container](#edits-on-the-host-never-reach-the-container).

---

## Styles and assets after a deploy

The symptom is a page that looks half-updated, or a hard refresh that changes nothing. Asset filenames are
content-hashed, so a page mixing builds is a stale document, not stale assets. Check in this order.

1. **The service worker.** With `appConfig.enableServiceWorker: true`, the shell is cached and an update
   applies only when you accept it. A toast reads `A new version of Workcenter is available.` with a
   **Refresh** action. Without the toast, unregister it in DevTools → **Application** →
   **Service Workers**, then reload; setting `enableServiceWorker: false` also unregisters it.
2. **The browser cache.** Hard-refresh: <kbd>Ctrl</kbd> + <kbd>F5</kbd>, or
   <kbd>Cmd</kbd> + <kbd>Shift</kbd> + <kbd>R</kbd>.
3. **A cache in front of the server.** Purge the hostname at the CDN or caching proxy.
4. **The image was not rebuilt.** Compose reuses an existing image, so `docker compose up -d` alone keeps
   the previous build; rebuild with `docker compose up -d --build`.

The service worker also caches `conf.yml` for up to 24 hours, refetching it with a three-second timeout,
which is why an edited configuration can survive a reload while it is registered. If you enable the
service worker and authenticate through a proxy, set `appConfig.enableAuthProxyCompat: true` as well: the
shell then spots an expired session on load, drops the worker and reloads.

---

## Gathering information for a bug report

Open issues at
[github.com/JDB321Sailor/Workcenter/issues](https://github.com/JDB321Sailor/Workcenter/issues/new/choose).
A security issue goes through the private advisory process instead — see
[`security.md`](./security.md). **Redact session tokens, password hashes, API tokens and addresses.**

**Console.** <kbd>F12</kbd> opens DevTools; messages tagged `OIDC`, `SSO` or `Service Worker Status` carry
the client-side detail, and the **Configuration Load Error** panel quotes the load failure verbatim.
Right-click the console and choose **Save as**. Windows / Linux:
<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>J</kbd>. macOS: <kbd>Cmd</kbd> + <kbd>Option</kbd> + <kbd>J</kbd>.

**Configuration.** Paste the whole report from `yarn validate-config`, including the paths it names.

**Network tab.** Filter by `Fetch/XHR`, reload, and record the status and body of these:

| Request | Worth reporting |
| --- | --- |
| `GET /conf.yml` | The status, and whether the body is your configuration or a bootstrap subset |
| `GET /api/broker/health` | The status and any body. A failure here makes every indicator `unknown` |
| `POST /config-manager/save`, or `/api/config/...` | The status and the `message` field |
| The three application hosts | Whether the frame request was blocked, and by which header |

**Server.** `/healthz` bypasses authentication and the HTTPS redirect, so it answers even when the rest of
the shell does not. Add the server log from the same window, since `[auth-oidc]` and config-validation
messages are written there and nowhere else. `curl -s http://localhost:4000/healthz` for the endpoint,
`docker logs workcenter` for the log.

## Read next

- [`configuring.md`](./configuring.md) — every key in `user-data/conf.yml`
- [`api.md`](./api.md) — the REST API for reading and writing the configuration
- [`deployment/docker.md`](./deployment/docker.md) — running the shell in a container
- [`authentication/authentik.md`](./authentication/authentik.md) — the supported identity setup
- [`security.md`](./security.md) — the threat model, and how to report a security issue
