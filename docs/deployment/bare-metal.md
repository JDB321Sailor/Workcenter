# Bare metal

Running Workcenter directly on a host, without Docker. Most deployments should use Docker
instead — see [`deployment.md`](../deployment.md) — but this is useful for development and for
a host that already runs Node.js.

## Build from Source

Workcenter can be compiled and run directly on your machine.<br>
For this, you will need both [git](https://git-scm.com/downloads) and [Node.js](https://nodejs.org/) (v20 or newer) installed.

1. Get Code: `git clone https://github.com/JDB321Sailor/Workcenter.git` and `cd workcenter`
2. Configuration: Fill in your settings in `./user-data/conf.yml`
3. Install dependencies: `yarn`
4. Build: `yarn build`
5. Run: `yarn start`

For example, the following steps can be used for Ubuntu/Debian based distros:

```bash
# Install prerequisites
sudo apt update
sudo apt install -y curl git

# Install Node.js (v24 LTS) from NodeSource, and enable yarn
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt install -y nodejs
sudo corepack enable

# Get the code
git clone https://github.com/JDB321Sailor/Workcenter.git
cd workcenter

# Install dependencies and build
yarn
yarn build

# Run it (serves on http://localhost:4000 by default, change with PORT env var)
yarn start

# Put all your assets (icons, styles, scripts, fonts, pages, etc) and configs in ./user-data
# Then, get started with editing the main config
nano user-data/conf.yml
```

Notes:
- If you're making changes to Workcenter's codebase, you can run `yarn dev` to start the dev server with hot reloading. See the [Developing](/docs/developing.md) docs for more info.
- To keep Workcenter running in the background, either use `yarn pm2-start` (instead of yarn start). Or, with systemd, see the [systemd service](#systemd-service) example below

---

---

## Systemd Service

If you're running Workcenter on a Linux server, you can use systemd to start it at boot and restart it if it crashes.

This example assumes Workcenter is installed in `/opt/workcenter`, and runs it as a dedicated `workcenter` user, so adjust it for your usecase.

Run these commands as root:

```bash
useradd --system --home /opt/workcenter --shell /usr/sbin/nologin workcenter
chown -R workcenter:workcenter /opt/workcenter
```

Create `/etc/systemd/system/workcenter.service`:

```ini
[Unit]
Description=Workcenter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=workcenter
WorkingDirectory=/opt/workcenter
Environment=NODE_ENV=production
Environment=PORT=4000
ExecStart=/usr/bin/env node server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Then enable and start it:

```bash
systemctl daemon-reload
systemctl enable --now workcenter
systemctl status workcenter
```

If you installed Workcenter somewhere else, update `WorkingDirectory`.

---

---

## Notes

- The server is a single Node process. It serves the built bundle from `dist/`, the
  configuration from `user-data/`, and the API endpoints including `/healthz`.
- `yarn build` must run before `yarn start`; there is no build step at start-up.
- Workcenter has not cut a release yet. There is no published tarball, no Docker image and no
  GHCR package: build from source, or use the release process in
  [`docs/release-workflow.md`](../release-workflow.md) once `Dev` is promoted through `Beta`
  into `Stable`.
- For production, the supported deployment is the Docker stack described in
  [`production.md`](../../production.md), which brings up Traefik, Authentik, FileBrowser
  Quantum, ONLYOFFICE, Zulip and Mailcow alongside Workcenter.
