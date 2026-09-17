# Management

Day-2 operation of a self-hosted instance: where state lives, how to update it, how to back it up,
and how it is exposed on the network. The full stack's own runbook — Traefik, Authentik, FileBrowser
Quantum, ONLYOFFICE, Zulip and Mailcow — is [`production.md`](../production.md).

## Contents

- [Where state lives](#where-state-lives)
- [File ownership and permissions](#file-ownership-and-permissions)
- [Environment variables](#environment-variables)
- [Healthchecks](#healthchecks)
- [Logs](#logs)
- [Updating](#updating)
- [Backing up and restoring](#backing-up-and-restoring)
- [Running behind Traefik](#running-behind-traefik)
- [TLS](#tls)
- [Scheduling backups](#scheduling-backups)
- [Network exposure](#network-exposure)

---

## Where state lives

Workcenter has no database. Its state is one directory, `user-data/`, mounted into the container at
`/app/user-data`.

| Path | Contents |
| --- | --- |
| `user-data/conf.yml` | The configuration: `pageInfo` and `appConfig`, including the address of each embedded application. |
| `user-data/config-backups/` | Timestamped copies written before each configuration write. |
| `user-data/broker/` | The broker's token store and audit log in a full-stack deployment. See [`privacy.md`](./privacy.md). |

| Deployment | Host directory | Container path |
| --- | --- | --- |
| Docker | whatever you mount | `/app/user-data` |
| Docker Compose, shell only | `./user-data` in the repository | `/app/user-data` |
| Bare metal | `./user-data` in the repository | — |

The directory is mounted, not copied. An edit to `conf.yml` takes effect on the next page load; a
restart is needed only for a change the server reads at start-up, such as `appConfig.auth`.

**The directory is served from the web root**, so a file placed in it is reachable at `/<filename>`.
Do not put secrets in it.

`USER_DATA_DIR` moves the directory. See [Environment variables](#environment-variables).

## File ownership and permissions

The image runs as the `node` user, uid and gid **1000**. The container must be able to write
`conf.yml` and the backup directory. When it cannot, a configuration write fails with a permission
error.

Fix the ownership on the host:

```bash
sudo chown -R 1000:1000 /srv/workcenter/user-data
```

Or run the container as your own user, which leaves host ownership alone:

```bash
docker run -d -p 4000:8080 \
  --user "$(id -u):$(id -g)" \
  -v "$PWD/user-data:/app/user-data" \
  --name workcenter \
  workcenter:dev
```

```yaml
services:
  workcenter:
    user: "1000:1000"   # whatever `id -u` and `id -g` print on the host
```

| Ref | Rule |
| --- | --- |
| M-1 | The container creates `config-backups/` if it is missing, so the directory that contains it must be writable when it does not exist yet. |
| M-2 | If the pre-write backup cannot be written, the whole save is refused with `Unable to backup conf.yml`. Point `BACKUP_DIR` at a writable path, or set `DISABLE_CONFIG_BACKUPS=true`. |
| M-3 | A read-only mount (`-v …:/app/user-data:ro`) still serves the configuration; every write fails. |
| M-4 | On bare metal the process runs as the user that starts it, and that user must own `user-data/`. The systemd unit in [`deployment/bare-metal.md`](./deployment/bare-metal.md) does this. |

## Environment variables

Every one of these is optional. The defaults below are the values in the container image.

| Variable | Default | Effect |
| --- | --- | --- |
| `USER_DATA_DIR` | `user-data` under the app root (`/app/user-data` in the image) | The directory holding `conf.yml` and the configuration backups. |
| `BACKUP_DIR` | `<USER_DATA_DIR>/config-backups` | Where the pre-write backup copy is written. |
| `DISABLE_CONFIG_BACKUPS` | unset | `true` skips the pre-write backup step. |
| `ENABLE_API` | unset | `true` enables the REST API under `/api`. Unless it is `true`, every `/api` route returns `404`. |
| `API_TOKEN` | unset | A bearer token the API accepts as an administrator. Setting it secures the API even when no other auth is configured. |
| `ENABLE_HTTP_AUTH` | unset | Enforces the `appConfig.auth.users` list on the server: the server routes, the `.yml` files in `user-data/`, and the REST API. It has no effect unless that list is present. |
| `BASIC_AUTH_USERNAME` | unset | A static credential pair, used when no OIDC client and no server-enforced user list are configured. Set both halves. |
| `BASIC_AUTH_PASSWORD` | unset | The password for `BASIC_AUTH_USERNAME`. |
| `PORT` | `8080` in the image, `4000` otherwise | The HTTP listen port. |
| `HOST` | `0.0.0.0` | The listen address. |
| `IS_DOCKER` | `true` in the image | Selects the `8080` and `443` port defaults. |
| `SSL_PRIV_KEY_PATH` | `/etc/ssl/certs/workcenter-priv.key` | The private key. HTTPS starts only when it and the certificate both exist. |
| `SSL_PUB_KEY_PATH` | `/etc/ssl/certs/workcenter-pub.pem` | The certificate. |
| `SSL_PORT` | `443` in the image, `4001` otherwise | The HTTPS listen port. |
| `REDIRECT_HTTPS` | `true` | `false` stops HTTP being redirected to HTTPS when the server is serving TLS. |
| `DISABLE_PROXY_ENDPOINTS` | unset | `true` makes `/cors-proxy` answer `403` and never make an outbound request. |

**OIDC is configured in `conf.yml`, not in an environment variable.** The client ID, issuer, scopes
and administrative group live under `appConfig.auth.oidc`; see [`configuring.md`](./configuring.md)
and [`OIDC.md`](../OIDC.md). The OIDC client secrets belong to the stack's gitignored `.env` files,
listed in [`OIDC.md` §9](../OIDC.md#9-environment-variable-reference).

`VITE_APP_*` and `WORKCENTER_*` are read by the client at build time, so changing one needs a
rebuild. An operator-facing setting belongs in `conf.yml`.

```yaml
services:
  workcenter:
    environment:
      - BACKUP_DIR=/app/user-data/config-backups
      - ENABLE_API=true
      - API_TOKEN=${WORKCENTER_API_TOKEN}
```

## Healthchecks

The image ships a Docker healthcheck that runs `services/healthcheck.js`. The script sends
`GET /healthz` and exits `0` on a `200`. The `Dockerfile` sets a five-minute interval; the shell-only
`docker-compose.yml` shortens it to 90 seconds. Both use a 10-second timeout and three retries.

`/healthz` is unauthenticated and answers with a small JSON body:

```json
{ "status": "ok", "uptime": 1234, "version": "0.1.0" }
```

```bash
# Current health, as Docker sees it
docker inspect --format '{{.State.Health.Status}}' workcenter

# Ask the endpoint directly
curl -fsS http://localhost:8080/healthz
```

`yarn health-check` from a checkout runs the same script against the configured port.

### Application health

The shell polls `GET /api/broker/health` for the status indicator beside each application button. It
polls every 30 seconds while a state changes, and backs off to five minutes while none does. Each
application is reported as `healthy`, `degraded`, `unhealthy` or `unknown`.

**A failed poll leaves every application `unknown`.** That is a state, not an error: it means the
check did not run. The per-application checks the broker composes in the full stack are listed in
[`integration.md` §10](../integration.md#10-health-model).

## Logs

The server writes to standard output and standard error, and Docker captures both. There is no
application log file to rotate.

```bash
docker logs -f workcenter
docker compose logs -f workcenter
docker compose logs -f --tail=100 workcenter
```

Docker's default `json-file` driver keeps logs unbounded unless a limit is set. Set one on the
service:

```yaml
services:
  workcenter:
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

The log carries the start-up banner, the configuration validation result, the TLS status line, and a
warning for each rejected token.

The broker's audit log — who moved which file — is a file rather than a stream, at
`user-data/broker/audit.log`; see [`privacy.md`](./privacy.md).

`docker stats workcenter` reports CPU, memory and network use per container.

## Updating

**No image is published to Docker Hub or GHCR**: Workcenter has not cut a release. Update by
rebuilding the image from the repository.

```bash
git pull
docker compose up -d --build workcenter
```

With `docker run`, rebuild and recreate the container:

```bash
git pull
docker build -t workcenter:dev .
docker stop workcenter && docker rm workcenter
docker run -d -p 4000:8080 \
  -v "$PWD/user-data:/app/user-data" \
  --restart unless-stopped \
  --name workcenter \
  workcenter:dev
```

**The configuration survives**, because `user-data/` is a mount: recreating the container does not
touch it. Read [`CHANGELOG.md`](../CHANGELOG.md) before updating, then check the result:

```bash
docker compose ps
docker compose exec workcenter node services/utils/config-validator
```

In the full stack, upgrade Workcenter last and follow the order in
[`production.md` §10](../production.md#10-upgrading). To roll back, check out the previous commit and
rebuild the image.

## Backing up and restoring

`user-data/` is the whole of Workcenter's own state. With that directory and the repository, a
deployment can be rebuilt.

### Automatic backups

Before each configuration write, the previous file is copied to `BACKUP_DIR`, by default
`user-data/config-backups/`:

```
user-data/config-backups/conf-1757600000000.backup.yml
```

The number is milliseconds since the epoch, so the files sort in write order. Set
`DISABLE_CONFIG_BACKUPS=true` to turn the copies off.

**These are per-write copies, not a schedule.** They protect against a bad edit, not against losing
the host. Schedule a copy of the directory as well; see [Scheduling backups](#scheduling-backups).

### Backing up

```bash
# One archive of the configuration and its backups
tar -czf "workcenter-user-data-$(date +%F).tar.gz" -C /srv/workcenter user-data

# Or an incremental copy, preserving ownership, links and extended attributes
rsync -aHAX /srv/workcenter/user-data/ /backup/workcenter/user-data/
```

In the full stack, `user-data/` is one row of a larger backup. Databases, secrets and certificates
are covered in [`production.md` §11](../production.md#11-backup-and-restore).

### Restoring

```bash
docker compose stop workcenter
tar -xzf workcenter-user-data-2025-01-01.tar.gz -C /srv/workcenter
docker compose start workcenter
```

To recover from a bad edit instead, copy one of the automatic backups over the live file:

```bash
cp user-data/config-backups/conf-1757600000000.backup.yml user-data/conf.yml
docker compose exec workcenter node services/utils/config-validator
```

Restore onto a disposable host at least once. A backup that has never been restored is not a backup.

## Running behind Traefik

Traefik is the reverse proxy for the stack. It terminates TLS, routes each hostname, and is the only
service that faces the internet. Workcenter is reached over the `proxy` Docker network, so it is
`expose`d rather than published.

**Set both `traefik.docker.network` on the service and `providers.docker.network` in Traefik's
static configuration.** With either missing, Traefik can pick the wrong network and return `502`.

A router for the shell:

```yaml
labels:
  traefik.enable: "true"
  traefik.docker.network: "proxy"
  traefik.http.routers.workcenter.rule: "Host(`example.com`)"
  traefik.http.routers.workcenter.entrypoints: "websecure"
  traefik.http.routers.workcenter.tls: "true"
  traefik.http.routers.workcenter.tls.certresolver: "le"
  traefik.http.routers.workcenter.middlewares: "security-headers@file"
  traefik.http.services.workcenter.loadbalancer.server.port: "8080"
```

Point the proxy's health check for the service at `/healthz`; it answers without a session and
without touching the configuration.

### Forward authentication and OIDC

Workcenter, FileBrowser Quantum, Zulip and Mailcow are **OIDC clients**: each redirects the browser
to Authentik itself. The one forward-auth surface is the Traefik dashboard, exposed at
`traefik.<base>` behind the `authentik@file` middleware and restricted to `workspaceadmin`. It needs
**two routers** — one for `/outpost.goauthentik.io/` at a higher priority than the application's —
plus `maxResponseBodySize: 4194304` on the middleware. Forward-auth chains and TLS options cannot be
expressed as Docker labels, so they belong in Traefik's dynamic file provider (`Traefik/dynamic/`).

Authentik must trust the proxy: Traefik has to send `X-Forwarded-Proto: https`, and Authentik's
`AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS` must include Traefik's network. Without that, Authentik
advertises an `http://` issuer and every client rejects the token.

### Headers and framing

Every application is embedded in a pane, so every application has a framing policy. It is set **per
application, never globally**.

| Application | Requirement |
| --- | --- |
| Workcenter | The `security-headers` middleware: HSTS, `X-Content-Type-Options`, `Referrer-Policy` and a `frame-ancestors` allow-list naming the Workcenter origin. |
| FileBrowser Quantum | The `security-headers` middleware. `http.trustProxyHeaders: true`, with `X-Forwarded-Proto` and `X-Forwarded-Host` passed through and the client `Host` preserved. |
| Zulip | As shipped, its nginx sends `X-Frame-Options: DENY` and Zulip exposes no setting to change it. The Chat pane is framed by a derived image that replaces the header with a `frame-ancestors` allow-list naming the Workcenter origin — never `*`. The long-poll routes need response buffering off and read and idle timeouts beyond 60 seconds. |
| ONLYOFFICE | The `no-frame-block` middleware and `accesscontrolalloworiginlist=*`. It must not share FileBrowser's router middleware. |
| Mailcow and SOGo | The `security-headers` middleware. The Mailcow UI is an OIDC client, so do not put `mail.<base>` behind forward-auth. |
| Traefik dashboard | `authentik@file` forward-auth, restricted to `workspaceadmin`. |

OnlyOffice's callbacks (`/health`, `/public/*`, `/api/office/callback`, `/api/resources/view`,
`/api/resources/download`) are authorised by a JWT in the query string: exclude them from any
forward-auth middleware.

The middleware contracts and the per-application traps are in
[`integration.md` §8.4](../integration.md#84-middleware-contracts) and
[`production.md` §7.2](../production.md#72-traefik-roles).

## TLS

Terminate TLS at the reverse proxy. Traefik obtains certificates from Let's Encrypt through the `le`
resolver with the HTTP-01 challenge, stores them in `Traefik/acme.json` (mode `600`), and renews them
automatically without a restart. Mailcow's own ACME is disabled because Traefik owns every
certificate, and exactly one Traefik instance may run.

Workcenter serves plain HTTP on `8080` behind the proxy. The server can also serve HTTPS directly
when a private key and certificate are mounted at the paths in the
[environment table](#environment-variables), which suits a deployment without a proxy. Service-to-
service TLS inside the stack is opt-in with `ENABLE_INTERNAL_TLS=true`.

See [`production.md` §7.3](../production.md#73-tls) and
[§12](../production.md#12-internal-tls-between-backend-services). **Never disable certificate
verification to work around a failing certificate**; see [`security.md`](./security.md).

## Scheduling backups

The automatic configuration backups happen when the file is written, not on a timer. Schedule a copy
of `user-data/` yourself.

A script that keeps thirty days of archives:

```bash
#!/bin/sh
# /usr/local/bin/workcenter-backup
set -eu
backup_dir=/var/backups/workcenter
mkdir -p "$backup_dir"
tar -czf "$backup_dir/user-data-$(date +%F).tar.gz" -C /srv/workcenter user-data
find "$backup_dir" -name 'user-data-*.tar.gz' -mtime +30 -delete
```

```bash
chmod +x /usr/local/bin/workcenter-backup
```

Run it from cron — as `/etc/cron.d/workcenter-backup`:

```cron
0 3 * * * root /usr/local/bin/workcenter-backup
```

Or from a systemd timer:

```ini
# /etc/systemd/system/workcenter-backup.service
[Unit]
Description=Back up Workcenter user-data

[Service]
Type=oneshot
ExecStart=/usr/local/bin/workcenter-backup
```

```ini
# /etc/systemd/system/workcenter-backup.timer
[Unit]
Description=Daily Workcenter backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
systemctl daemon-reload
systemctl enable --now workcenter-backup.timer
```

Keep at least three generations, one of them off the host. In the full stack, the same timer can run
the database dumps and the `rsync` from
[`production.md` §11](../production.md#11-backup-and-restore).

## Network exposure

In the full stack, only Traefik and Mailcow's mail ports are published. Every other service,
Workcenter included, is on the Docker `proxy` network and reached by the proxy.

| Port | Service | Notes |
| --- | --- | --- |
| `80` | Traefik | Redirects to `443`, and serves the Let's Encrypt HTTP-01 challenge. |
| `443` | Traefik | Every HTTPS hostname: the shell, the embedded applications and the dashboard. |
| `8080` | Traefik | The dashboard and API entrypoint, reached through the authenticated router at `traefik.<base>`. |
| `8080` | Workcenter | The container's HTTP port. The shell-only compose publishes it as `4000:8080`; the full stack reaches it over the `proxy` network instead. |
| `443` | Workcenter | HTTPS, only when a key and certificate are mounted. `SSL_PORT` moves it. |
| `25`, `465`, `587`, `143`, `993`, `110`, `995`, `4190` | Mailcow | SMTP, IMAP, POP3 and SIEVE — the only non-HTTP ports that face the internet. |

`proxy`, `internal` and `mailcow-network` are Docker networks, not host ports.

**Do not publish `8080` to an untrusted network.** If the shell has to be reachable directly, put
authentication in front of it first. The surfaces that answer without a session are:

| Surface | Behaviour |
| --- | --- |
| `/healthz` | Unauthenticated by design; it reports status, uptime and version. |
| `/conf.yml` | With auth configured, an anonymous request receives a bootstrap subset unless `appConfig.auth.enableGuestAccess` is set; the full file requires a valid session. |
| `/api/*` | `404` unless `ENABLE_API=true`. With it enabled, set `API_TOKEN` or configure auth, and serve it over HTTPS only. |
| `/cors-proxy` | Makes outbound requests on the caller's behalf. It requires a session when auth is configured, and `DISABLE_PROXY_ENDPOINTS=true` turns it off completely. |

The Workcenter container does not need the Docker socket, and must not be given it.

## Read next

- [`production.md`](../production.md) — the full stack, TLS and upgrades
- [`security.md`](./security.md) — the threat model and hardening
- [`privacy.md`](./privacy.md) — what is stored and what is sent
- [`api.md`](./api.md) — the REST API
