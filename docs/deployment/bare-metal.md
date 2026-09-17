# Bare Metal

## Build from Source

Workcenter can be compiled and run directly on your machine.<br>
For this, you will need both [git](https://git-scm.com/downloads) and [Node.js](https://nodejs.org/) (v20 or newer) installed.

1. Get Code: `git clone https://github.com/Lissy93/dashy.git` and `cd dashy`
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
git clone https://github.com/Lissy93/dashy.git
cd dashy

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

## Pre-Built Release

We publish GitHub releases for every major and minor (not patch) version of Workcenter.<br>
Each release includes the pre-compiled app as `dashy-[version].tar.gz` (plus a SHA256 checksum and SLSA build-provenance attestation).

This is useful if you want to run Workcenter on bare metal, without the need to compile from source.

You'll need [Node.js](https://nodejs.org/) (v20 or newer), `curl`, `tar`, and `yarn` enabled through Corepack.

1. Pick a release from [GitHub Releases](https://github.com/Lissy93/dashy/releases)
2. Download `dashy-[version].tar.gz`
3. Extract it somewhere permanent, such as `/opt/dashy`
4. Run `yarn install --production --frozen-lockfile`
5. Edit `user-data/conf.yml`
6. Start it with `node server`

For example (replace 4.3.0 with whichever version you want):

```bash
curl -LO https://github.com/Lissy93/dashy/releases/download/4.3.0/dashy-4.3.0.tar.gz
mkdir -p dashy
tar -xzf dashy-4.3.0.tar.gz -C dashy
cd dashy
corepack enable
yarn install --production --frozen-lockfile
node server
```

Workcenter will run on `http://localhost:4000` by default. Change this with the `PORT` env var.

You can now start configuring by editing `user-data/conf.yml` and put any assets you want within user-data.

---

## Systemd Service

If you're running Workcenter on a Linux server, you can use systemd to start it at boot and restart it if it crashes.

This example assumes Workcenter is installed in `/opt/dashy`, and runs it as a dedicated `dashy` user, so adjust it for your usecase.

Run these commands as root:

```bash
useradd --system --home /opt/dashy --shell /usr/sbin/nologin dashy
chown -R dashy:dashy /opt/dashy
```

Create `/etc/systemd/system/dashy.service`:

```ini
[Unit]
Description=Workcenter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=dashy
WorkingDirectory=/opt/dashy
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
systemctl enable --now dashy
systemctl status dashy
```

If you installed Workcenter somewhere else, update `WorkingDirectory`.

---

## Checksum Verification

Each pre-built release includes a SHA256 checksum. This is optional, but it is a quick way to check the file downloaded correctly.

```bash
curl -LO https://github.com/Lissy93/dashy/releases/download/4.3.0/dashy-4.3.0.tar.gz
curl -LO https://github.com/Lissy93/dashy/releases/download/4.3.0/dashy-4.3.0.tar.gz.sha256
sha256sum -c dashy-4.3.0.tar.gz.sha256
```

You should see `dashy-4.3.0.tar.gz: OK`.

---

## Provenance Attestation

GitHub releases also include a SLSA build-provenance attestation. This lets you verify that the release asset was built by Workcenter's GitHub Actions release workflow.

Install a recent [GitHub CLI](https://cli.github.com/), then run:

```bash
gh attestation verify dashy-4.3.0.tar.gz --repo Lissy93/dashy
```

---

## Install Script

The following is an example script to install or update the latest pre-built release on a Linux server with systemd.
It creates a `dashy` user, installs into `/opt/dashy`, verifies the SHA256 checksum, installs production dependencies, and starts Workcenter as a service.

<details>

<summary>install-dashy.sh</summary>

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="Lissy93/dashy"
INSTALL_DIR="${INSTALL_DIR:-/opt/dashy}"
RUN_USER="${RUN_USER:-dashy}"
PORT="${PORT:-4000}"
VERSION="${DASHY_VERSION:-latest}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run this script as root"
  exit 1
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1"
    exit 1
  }
}

install_packages() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl ca-certificates tar gzip coreutils
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates tar gzip coreutils nodejs
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl ca-certificates tar gzip coreutils nodejs
  else
    echo "Please install curl, tar, sha256sum and Node.js v20 or newer, then re-run this script."
    exit 1
  fi
}

install_packages
need_cmd curl
need_cmd tar
need_cmd sha256sum
need_cmd runuser

install_node_apt() {
  curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
  apt-get install -y nodejs
}

if ! command -v node >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    install_node_apt
  else
    echo "Please install Node.js v20 or newer, then re-run this script."
    exit 1
  fi
fi

NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
if [ "$NODE_MAJOR" -lt 20 ]; then
  if command -v apt-get >/dev/null 2>&1; then
    install_node_apt
    NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
  fi

  if [ "$NODE_MAJOR" -lt 20 ]; then
    echo "Node.js v20 or newer is required. Found: $(node -v)"
    exit 1
  fi
fi

corepack enable
need_cmd yarn

case "$INSTALL_DIR" in
  /*) ;;
  *) echo "INSTALL_DIR must be an absolute path"; exit 1 ;;
esac

if [ "$INSTALL_DIR" = "/" ]; then
  echo "INSTALL_DIR cannot be /"
  exit 1
fi

if [ "$VERSION" = "latest" ]; then
  RELEASE_URL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
  VERSION="${RELEASE_URL##*/}"
fi
VERSION="${VERSION#v}"

ASSET="dashy-${VERSION}.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading Workcenter ${VERSION}..."
curl -fL "${BASE_URL}/${ASSET}" -o "${TMP_DIR}/${ASSET}"
curl -fL "${BASE_URL}/${ASSET}.sha256" -o "${TMP_DIR}/${ASSET}.sha256"

(
  cd "$TMP_DIR"
  sha256sum -c "${ASSET}.sha256"
)

if ! id "$RUN_USER" >/dev/null 2>&1; then
  useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$RUN_USER"
fi

if [ -d "$INSTALL_DIR/user-data" ]; then
  BACKUP_DIR="${INSTALL_DIR}.user-data.$(date +%Y%m%d%H%M%S)"
  cp -a "$INSTALL_DIR/user-data" "$BACKUP_DIR"
  echo "Backed up user-data to ${BACKUP_DIR}"
fi

NEW_DIR="${INSTALL_DIR}.new"
OLD_DIR="${INSTALL_DIR}.old"

rm -rf "$NEW_DIR" "$OLD_DIR"
mkdir -p "$NEW_DIR"
tar -xzf "${TMP_DIR}/${ASSET}" -C "$NEW_DIR"

if [ -d "$INSTALL_DIR/user-data" ]; then
  rm -rf "${NEW_DIR}/user-data"
  cp -a "$INSTALL_DIR/user-data" "${NEW_DIR}/user-data"
fi

chown -R "$RUN_USER:$RUN_USER" "$NEW_DIR"

runuser -u "$RUN_USER" -- bash -lc "cd '$NEW_DIR' && yarn install --production --frozen-lockfile"

if [ -d "$INSTALL_DIR" ]; then
  mv "$INSTALL_DIR" "$OLD_DIR"
fi

mv "$NEW_DIR" "$INSTALL_DIR"
rm -rf "$OLD_DIR"

cat >/etc/systemd/system/dashy.service <<EOF
[Unit]
Description=Workcenter
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
WorkingDirectory=${INSTALL_DIR}
Environment=NODE_ENV=production
Environment=PORT=${PORT}
ExecStart=/usr/bin/env node server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dashy
systemctl restart dashy

echo "Workcenter ${VERSION} is running on http://localhost:${PORT}"
echo "Edit your config at ${INSTALL_DIR}/user-data/conf.yml"
```

To install a specific version, run it with `DASHY_VERSION=4.3.0`. To use a different port, set `PORT=8080`.

</details>
