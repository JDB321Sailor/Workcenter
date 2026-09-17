# Deployment

Welcome to Workcenter, so glad you're here :) Deployment is super easy, and there are several methods available depending on what type of system you're using. If you're self-hosting, then deploying with Docker (or similar container engine) is the recommended approach.

## Quick Start

If you want to skip the fuss, and [get straight down to it](/docs/quick-start.md), then you can spin up a new instance of Workcenter by running:

```bash
docker run -p 8080:8080 lissy93/dashy
```

See [Management Docs](/docs/management.md) for info about securing, monitoring, updating, health checks, auto starting, web server configuration, etc

Once you've got Workcenter up and running, you'll want to configure it with your own content, for this you can reference the [configuring docs](/docs/configuring.md).

## Deployment Methods

- [Docker](/docs/deployment/docker.md)
  - [Docker Run](/docs/deployment/docker.md#docker-run)
  - [Docker Compose](/docs/deployment/docker.md#docker-compose)
  - [Podman](/docs/deployment/docker.md#podman)
- [Bare Metal](/docs/deployment/bare-metal.md)
  - [Build from Source](/docs/deployment/bare-metal.md#build-from-source)
  - [Pre-Built Release](/docs/deployment/bare-metal.md#pre-built-release)
- [Self-Hosted Operating Systems](/docs/deployment/self-hosted-os.md)
  - [TrueNAS SCALE](/docs/deployment/self-hosted-os.md#truenas-scale)
  - [Proxmox VE](/docs/deployment/self-hosted-os.md#proxmox-ve)
  - [Unraid](/docs/deployment/self-hosted-os.md#unraid)
  - [Synology NAS](/docs/deployment/self-hosted-os.md#synology-nas)
  - [NixOS](/docs/deployment/self-hosted-os.md#nixos)
  - [Kubernetes](/docs/deployment/self-hosted-os.md#kubernetes)
- [Self-Hosted Platforms](/docs/deployment/self-hosted-platforms.md)
  - [Portainer](/docs/deployment/self-hosted-platforms.md#portainer)
  - [Coolify](/docs/deployment/self-hosted-platforms.md#coolify)
  - [1Panel](/docs/deployment/self-hosted-platforms.md#1panel)
  - [Runtipi](/docs/deployment/self-hosted-platforms.md#runtipi)
  - [Cosmos Cloud](/docs/deployment/self-hosted-platforms.md#cosmos-cloud)
  - [CasaOS](/docs/deployment/self-hosted-platforms.md#casaos)
  - [Umbrel](/docs/deployment/self-hosted-platforms.md#umbrel)
  - [EasyPanel](/docs/deployment/self-hosted-platforms.md#easypanel)
  - [Saltbox](/docs/deployment/self-hosted-platforms.md#saltbox)
- [Cloud Services](/docs/deployment/cloud.md)
  - [Static Hosting Providers](/docs/deployment/cloud.md#static-hosting-providers)
    - [Netlify](/docs/deployment/cloud.md#netlify)
    - [Vercel](/docs/deployment/cloud.md#vercel)
    - [EdgeOne Pages](/docs/deployment/cloud.md#edgeone-pages)
    - [Cloudflare Pages](/docs/deployment/cloud.md#cloudflare-pages)
    - [Firebase Hosting](/docs/deployment/cloud.md#firebase-hosting)
    - [Azure Static Web Apps](/docs/deployment/cloud.md#azure-static-web-apps)
  - [Container Runtimes](/docs/deployment/cloud.md#container-runtimes)
    - [Render](/docs/deployment/cloud.md#render)
    - [Railway](/docs/deployment/cloud.md#railway)
    - [Fly.io](/docs/deployment/cloud.md#flyio)
    - [Koyeb](/docs/deployment/cloud.md#koyeb)
    - [Northflank](/docs/deployment/cloud.md#northflank)
    - [DigitalOcean App Platform](/docs/deployment/cloud.md#digitalocean-app-platform)
    - [Azure Container Apps](/docs/deployment/cloud.md#azure-container-apps)
    - [Google Cloud Run](/docs/deployment/cloud.md#google-cloud-run)
  - [Managed Hosting](/docs/deployment/cloud.md#managed-hosting)
  - [Hosting with any CDN](/docs/deployment/cloud.md#hosting-with-any-cdn)
  - [Other VPS](/docs/deployment/cloud.md#other-vps)

---

## Requirements

### Architecture
The pre-built Docker image runs on `amd64` and `arm64` (32-bit `armv7` and `armv6` are not supported). If you need armv7, pin an older release such as `lissy93/dashy:4.4.10`.

### System Resources
- CPU: any single core, x86-64 or ARM
- RAM: Node server idles around ~80-120 MB; 256 MB is comfortable, works in less
- Disk: ~250 MB for the image + whatever your config/icons need
- Runs fine on a Pi 3 and up

### Bare Metal
Requires [Node.js](https://nodejs.org/) (20+) and [Yarn](https://yarnpkg.com/)

### CDN / Cloud Deploy
No specific requirements. The built app (without the Node server) is very lightweight and can be served by any static host or CDN. If you're using custom icons or other assets, additional disk space will be needed.

### Browser Support
JavaScript is required. Workcenter targets browsers with >1% global usage and the last 2 versions of each (via [browserslist](https://browsersl.ist/)). In practice, any modern browser works fine. Internet Explorer is not supported.

| Browser | Minimum Version | Status |
|---------|----------------|--------|
| Chrome / Chromium | 90+ | Fully supported |
| Firefox | 90+ | Fully supported |
| Edge | 90+ | Fully supported |
| Safari | 14+ | Mostly Supported |
| Opera | 76+ | Supported |
| Samsung Internet | 15+ | Supported |
| Firefox ESR | Latest | Supported |
| Internet Explorer | - | Not supported |
