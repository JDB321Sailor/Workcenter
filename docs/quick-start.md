# Quick start

The shortest path from nothing to a running Workcenter: build the image, edit one file, start it.

Workcenter is the shell. It embeds three applications that are deployed separately, so until their
addresses are configured and those applications are reachable, the panes report themselves as
unavailable. Deploying the whole stack is covered by [`production.md`](../production.md) and
[`integration.md`](../integration.md).

## Prerequisites

| Deployment | Needs |
| --- | --- |
| Docker (recommended) | Docker Engine with the Compose plugin |
| Bare metal | Node.js 24 and Yarn 1.22 |

## 1. Get the code

```bash
git clone https://github.com/JDB321Sailor/Workcenter.git
cd Workcenter
```

Workcenter has not cut a release, so there is no image or package to pull: the image is built from
the repository.

## 2. Configure it

The repository ships `user-data/conf.yml`, the only configuration the shell reads. The minimum
useful file names the three applications:

```yaml
pageInfo:
  title: Workcenter

appConfig:
  applications:
    files:
      url: https://filebrowser.example.com
    chat:
      url: https://chat.example.com
    mail:
      url: https://mail.example.com/SOGo
```

Each address is the one the **browser** reaches, because each pane is an iframe in the user's
browser. An internal container hostname will not resolve.

Check the file before starting:

```bash
yarn validate-config
```

Every key is documented in [`configuring.md`](./configuring.md). A key the schema does not know is
rejected rather than ignored, so a typo is reported instead of silently doing nothing.

## 3. Start it

### Docker

```bash
docker build -t workcenter:dev .
docker run -d --name workcenter \
  -p 4000:8080 \
  -v "$PWD/user-data:/app/user-data" \
  --restart unless-stopped \
  workcenter:dev
```

Workcenter is then at `http://localhost:4000`. The container listens on 8080; the mapping above
publishes it on 4000. The configuration directory is mounted rather than copied, so an edit to
`user-data/conf.yml` takes effect on the next page load.

### Bare metal

```bash
yarn
yarn build
yarn start
```

The build has to run before the start: the server serves the compiled bundle from `dist/` and does
not build at start-up. It listens on port 4000 by default, which `PORT` overrides. The full
walkthrough, including a systemd unit, is in
[`deployment/bare-metal.md`](./deployment/bare-metal.md).

## 4. What you should see

The header shows `pageInfo.title`, and the rail beneath it carries one button per application, each
with a status indicator:

| Indicator | Meaning |
| --- | --- |
| Healthy | The application answered its health check. |
| Degraded | The application answered, but something it depends on did not. |
| Unhealthy | The application answered and reported a failure. |
| Unknown | There is no recent answer. An unconfigured or unreachable application reports this. |

Selecting a button loads that application into the pane and deep-links to `/files`, `/chat` or
`/mail`, so a pane can be bookmarked or shared.

If a pane reports an error instead of showing the application, the usual causes are an address the
browser cannot reach and an application that refuses to be embedded in a frame. Both are covered in
[`troubleshooting.md`](./troubleshooting.md).

## 5. Sign in

Workcenter authenticates against Authentik over OIDC, and the same identity provider serves the
applications it embeds: `workspaceusers` for general access and `workspaceadmin` for
administration. The contract is in [`OIDC.md`](../OIDC.md), and
[`authentication/authentik.md`](./authentication/authentik.md) walks through the provider setup.

The shell renders no sign-out control. End the session at the identity provider, or set
`appConfig.auth.logoutRedirectUrl` so that signing out lands on the provider's end-session
endpoint.

## Read next

- [`deployment.md`](./deployment.md) — the deployment options
- [`configuring.md`](./configuring.md) — every option in `user-data/conf.yml`
- [`management.md`](./management.md) — updating, backing up and monitoring an instance
- [`production.md`](../production.md) — the full stack and `setup.sh`
