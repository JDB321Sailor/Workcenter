# Deployment

Workcenter is a self-hosted application: a Node server that serves the built shell, the
configuration and the API. It is deployed as a container, or run directly on a host.

The supported production deployment is the **full stack** described in
[`production.md`](../production.md): Workcenter plus Traefik, Authentik, FileBrowser Quantum,
ONLYOFFICE, Zulip and Mailcow/SOGo, brought up together. That is what makes the three panes and
the cross-application file movement work. Running the shell alone is useful for development.

## Quick start

Build and run the shell:

```bash
git clone https://github.com/JDB321Sailor/Workcenter.git
cd Workcenter
git checkout Dev
docker build -t workcenter:dev .
docker run -d -p 4000:8080 -v "$PWD/user-data:/app/user-data" --name workcenter workcenter:dev
```

Then open `http://localhost:4000`.

**No image is published to Docker Hub or GHCR yet** — Workcenter has not cut a release. Build
locally, as above.

## Deployment methods

| Method | Guide | When to use it |
| --- | --- | --- |
| **The full stack** | [`production.md`](../production.md) | Production. Every integrated application, TLS and identity. |
| **Docker** | [`deployment/docker.md`](./deployment/docker.md) | The shell alone, in a container |
| **Bare metal** | [`deployment/bare-metal.md`](./deployment/bare-metal.md) | A host that already runs Node.js, or development |
| **Local development** | [`developing.md`](./developing.md) | `yarn dev`, with hot reloading |

## Requirements

### Host

| Resource | Minimum | Recommended |
| --- | --- | --- |
| CPU | 4 vCPU for the full stack; 1 core for the shell alone | 8 vCPU |
| RAM | 8 GB for the full stack; 256 MB for the shell alone | 16 GB |
| Disk | 100 GB for the full stack; 250 MB for the shell alone | 250 GB SSD |

The full stack needs the larger figures because Zulip wants about 2 GB, ONLYOFFICE about 2 GB,
and Mailcow runs roughly eighteen containers. The shell on its own is small: the Node server
idles around 80–120 MB.

### Software

| Tool | Version |
| --- | --- |
| Docker Engine | 24+ |
| Docker Compose | v2.20+ (the root composition uses `include:`) |
| Git | any recent |
| Node.js | 24.x, only for bare metal or development |
| Yarn | 1.22, only for bare metal or development |

### Network

Ports 80 and 443 must reach the host for Traefik to obtain certificates, plus Mailcow's mail
ports. Six DNS records are needed — see [`production.md` §3](../production.md).

### Browser support

JavaScript is required. Workcenter targets browsers with more than 1% global usage and the last
two versions of each, via [browserslist](https://browsersl.ist/).

| Browser | Minimum | Status |
| --- | --- | --- |
| Chrome / Chromium | 90+ | Supported |
| Firefox | 90+ | Supported |
| Edge | 90+ | Supported |
| Safari | 14+ | Supported |
| Opera | 76+ | Supported |
| Samsung Internet | 15+ | Supported |
| Internet Explorer | — | Not supported |

## Where to go next

- [`quick-start.md`](./quick-start.md) — the shortest path to a running instance
- [`configuring.md`](./configuring.md) — the options in `user-data/conf.yml`
- [`OIDC.md`](../OIDC.md) — the Authentik setup, which every pane depends on
- [`management.md`](./management.md) — day-2 operations
