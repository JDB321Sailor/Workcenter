# Docker

Workcenter deploys as a container. This page covers running the shell on its own.

For the full stack — Traefik, Authentik, FileBrowser Quantum, ONLYOFFICE, Zulip and
Mailcow/SOGo — use the root `compose.yaml`, or `setup.sh` once Phase 3 and Phase 4 land. See
[`production.md`](../../production.md).

## There is no published image yet

Workcenter has not cut a release, so **no image is published to Docker Hub or GHCR**. Build
the image locally:

```bash
git clone https://github.com/JDB321Sailor/Workcenter.git
cd Workcenter
git checkout Dev
docker build -t workcenter:dev .
```

When the first release is cut from `Stable`, the image will be published with an SBOM and build
provenance. Until then, `workcenter:dev` is what you build.

## Run

```bash
docker run -d \
  -p 4000:8080 \
  -v "$PWD/user-data:/app/user-data" \
  --name workcenter \
  --restart unless-stopped \
  workcenter:dev
```

The container listens on **8080**; the mapping above serves it on 4000. Override the container
port with `PORT`.

| Flag | Meaning |
| --- | --- |
| `-p 4000:8080` | Host port 4000 to container port 8080. Keep the container port at 8080. |
| `-v "$PWD/user-data:/app/user-data"` | Mounts the directory holding `conf.yml` and any assets you want served from the web root. |
| `--name workcenter` | A readable container name. |
| `--restart unless-stopped` | Start on boot, and after a crash. |

The container runs as the `node` user, uid 1000. If your mounted `user-data` is owned by a
different uid you will hit permission errors; `chown` it, or run with
`--user "$(id -u):$(id -g)"`.

## Docker Compose

`docker-compose.yml` in the repository root builds and runs the shell:

```bash
docker compose up -d
docker compose ps
docker compose logs -f workcenter
```

```yaml
services:
  workcenter:
    container_name: workcenter
    build: .
    ports:
      - 4000:8080
    volumes:
      - ./user-data:/app/user-data
    environment:
      - NODE_ENV=production
    restart: unless-stopped
    healthcheck:
      test: ['CMD', 'node', '/app/services/healthcheck.js']
      interval: 1m30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

## Health

The image ships a healthcheck that calls `services/healthcheck.js`, which probes `/healthz`.
The endpoint returns status, uptime and version:

```bash
docker inspect --format '{{.State.Health.Status}}' workcenter
```

## Compose deployment helper

`scripts/publish-to-github.sh` creates the GitHub repository, pushes `Stable`, `Beta` and `Dev`,
and opens the pull request that carries the current branch into `Dev`. It is not needed to build
or run the image.

## Read next

- [`deployment.md`](../deployment.md) — the deployment options
- [`deployment/bare-metal.md`](./bare-metal.md) — running on a host without Docker
- [`production.md`](../../production.md) — the full stack, `setup.sh`, TLS and upgrades
- [`management.md`](../management.md) — day-2 operations
