# Docker

Docker is the recommended way of running Workcenter.
We have light-weight multi-arch (amd64 and arm64) images published to DockerHub ([`lissy93/dashy`](https://hub.docker.com/r/lissy93/dashy)) and GHCR ([`ghcr.io/lissy93/dashy`](https://github.com/lissy93/dashy/pkgs/container/dashy)) with full semver tags.

The container runs on port 8080 (can be overridden with PORT). Your config (`conf.yml`) and any other assets (icons, styles, themes, fonts, scripts, etc) will live in `/app/user-data` in the container.

**Container Info**: [
![Docker Supported Architecture](https://img.shields.io/badge/Architectures-amd64%20|%20arm64v8-6ba6e5)
![Docker Base Image](https://img.shields.io/badge/Base_Image-node%3A24--alpine-6ba6e5)
![Docker Hosted on](https://img.shields.io/badge/Hosted_on-DockerHub%20%26%20GHCR-6ba6e5)
](https://hub.docker.com/r/lissy93/dashy)<br>
**Status**:
![Build Status](https://img.shields.io/github/actions/workflow/status/Lissy93/dashy/docker.yml?label=Build&color=f4a966)
![Docker Pulls](https://img.shields.io/docker/pulls/lissy93/dashy?color=ecb2f7)
![Docker Stars](https://img.shields.io/docker/stars/lissy93/dashy?color=f7f754&label=Docker%20Stars)
![Docker Image Size](https://img.shields.io/docker/image-size/lissy93/dashy/latest?color=1eea76)
![Docker Latest Version](https://img.shields.io/docker/v/lissy93/dashy/latest?color=a8d8ea&label=Latest%20Version)

---

## Docker Run

You will need [Docker](https://docs.docker.com/get-docker/) installed on your system.

```bash
docker run -d \
  -p 8080:8080 \
  -v /path/to/your/user-data:/app/user-data \
  --name dashy \
  --restart=always \
  lissy93/dashy:latest
```

The `user-data` directory you mount must contain a `conf.yml` file. It can also contain any sub-config files, item icons, fonts, custom CSS, or other assets you want served from the web root. Anything you put in there is available at `/<filename>` in the browser.

Explanation of the above options:
- `-d` Detached mode (not running in the foreground of your terminal)
- `-p` The port that should be exposed, and the port it should be mapped to in your host system `[host-port]:[container-port]`, leave the container port as `8080`
- `-v` Mounts the host directory containing your `conf.yml` (and any other assets) into the container at `/app/user-data`
- `--name` Give your container a human-readable name
- `--restart=always` Spin up the container when the daemon starts, or after it has been stopped
- `lissy93/dashy:latest` The image to run. Replace `:latest` with a specific version from the [tags](https://hub.docker.com/r/lissy93/dashy/tags) if needed
- For all available options, and to learn more, see the [Docker Run Docs](https://docs.docker.com/reference/cli/docker/container/run/)

Notes:
- Workcenter is also available through GHCR: `docker pull ghcr.io/lissy93/dashy:latest`
- The image is multi-arch, so the same tag works on amd64 and arm64. Docker selects the right variant for your host automatically.
- Published tags: `latest`, exact versions (e.g. `4.3.9`), and rolling minor/major tags (`4.3`, `4.x`). See [available tags](https://hub.docker.com/r/lissy93/dashy/tags)
- The container runs as the `node` user (uid 1000). If your mounted `user-data` is owned by a different uid, you may hit permission errors. Fix this with `chown`, or run with `--user "$(id -u):$(id -g)"`

---

## Docker Compose

Using Docker Compose can be useful for saving your specific config in files, without having to type out a long run command each time. Save compose config as a YAML file, and then run `docker compose up -d` (optionally use the `-f` flag to specify file location, if it isn't located at `./docker-compose.yml`), `-d` is detached mode (not running in the foreground of your terminal). Compose is also useful if you are using clusters, as the format is very similar to stack files, used with Docker Swarm.

The following is a complete example of a [`docker-compose.yml`](https://github.com/Lissy93/dashy/blob/master/docker-compose.yml) for Workcenter. Run it as is, or uncomment the additional options you need.

```yaml
services:
  dashy:
    # The image to pull + version. Can use `ghcr.io/lissy93/dashy` instead
    image: lissy93/dashy:latest
    # Or, to build from source, replace `image:` with `build: .`
    # build: .
    # Optional container name
    container_name: dashy
    # Port to serve on (keep container port (second one) as 8080)
    ports:
      - 8080:8080
    # Mount a directory containing your conf.yml and any other assets
    volumes:
      - ./user-data:/app/user-data
    # Add any env vars for server here, if needed
    environment:
      - NODE_ENV=production
    # If you get permission errors on mounted files, set your own ids (`id -u` / `id -g`)
    # user: "1000:1000"
    # Auto-start the container on boot
    restart: unless-stopped
    # Optional healthcheck override (the image ships a built-in one, running every 5 minutes)
    healthcheck:
      test: ['CMD', 'node', '/app/services/healthcheck.js']
      interval: 1m30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

To pull from GHCR instead of Docker Hub, set `image: ghcr.io/lissy93/dashy:latest`.

---

## Podman

[Podman](https://podman.io/) is a drop-in replacement for Docker that runs containers without a daemon and doesn't require root. If you're on Fedora, RHEL, or just prefer daemonless containers, Podman works with the same images and mostly the same CLI.

```bash
podman run -d \
  -p 8080:8080 \
  -v /path/to/your/user-data:/app/user-data:Z \
  --name dashy \
  --restart=always \
  docker.io/lissy93/dashy:latest
```

The `:Z` suffix on the volume mount handles SELinux relabeling, which you'll need on Fedora/RHEL. If you're not using SELinux, you can leave it off.

Podman also supports `podman-compose` or `podman compose` (with the compose plugin) using the same `docker-compose.yml` file shown above.

---

## Read Next
If you're having issues, take a look at the [Troubleshooting Guide](/docs/troubleshooting.md).

For more detailed Docker setup and management guides, see the [Management Docs](/docs/management.md):
- [Updating](/docs/management.md#updating)
- [Backing Up](/docs/management.md#backing-up)
- [Healthchecks](/docs/management.md#healthchecks)
- [File Ownership and Permissions](/docs/management.md#file-ownership-and-permissions)
- [Passing in Environmental Variables](/docs/management.md#passing-in-environmental-variables)
- [Auto-Starting at System Boot](/docs/management.md#auto-starting-at-system-boot)
- [Verifying Releases](/docs/management.md#verifying-releases)
- [Container Security](/docs/management.md#container-security)
