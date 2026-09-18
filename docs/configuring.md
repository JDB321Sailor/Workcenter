# Configuring Workcenter

Workcenter reads one configuration file, `user-data/conf.yml`. It is YAML, and it is validated
against [`src/utils/config/ConfigSchema.json`](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/utils/config/ConfigSchema.json)
at start-up and by `yarn validate-config`.

Anything the file does not set falls back to a default, so a minimal file is two keys.

```yaml
pageInfo:
  title: Workcenter

appConfig:
  applications:
    files: { url: https://filebrowser.example.com }
    chat:  { url: https://chat.example.com }
    mail:  { url: https://mail.example.com/SOGo }
```

> **A key the schema does not know is rejected.** The schema sets
> `additionalProperties: false`, so a typo fails validation rather than being silently ignored.
> Run `yarn validate-config` after editing.

## Where the file lives

| Deployment | Location |
| --- | --- |
| Docker | mounted at `/app/user-data/conf.yml` |
| Docker Compose | `./user-data/conf.yml` in the repository |
| Bare metal, development | `./user-data/conf.yml` in the repository |

The directory is mounted, not copied, so an edit takes effect on the next page load. There is no
restart needed for a change that only affects the client.

## `pageInfo`

Metadata for the document. Every key is optional.

| Key | Type | Description |
| --- | --- | --- |
| `title` | `string` | The page title, shown in the browser tab and in the document title. |
| `description` | `string` | The document description. |
| `navLinks` | `array` | Links shown in the shell header. Each entry takes `title` and `path`. |
| `favicon` | `string` | A favicon URL or path, validated before use. |
| `color` | `string` | A theme colour, validated against the browser's CSS parser. |

```yaml
pageInfo:
  title: Workcenter
  description: Files, chat and mail in one place
  navLinks:
    - title: Documentation
      path: https://github.com/JDB321Sailor/Workcenter/blob/Dev/Readme.md
```

## `appConfig`

Shell settings.

### `appConfig.applications` — the three panes

This is the block that matters most. Each application the shell embeds has one address here. A
pane with no address is shown as **unavailable** rather than as a blank frame.

| Application | Key | What to point it at |
| --- | --- | --- |
| Files | `files.url` | FileBrowser Quantum, for example `https://filebrowser.example.com` |
| Chat | `chat.url` | Zulip, for example `https://chat.example.com` |
| Mail | `mail.url` | SOGo, for example `https://mail.example.com/SOGo` |

```yaml
appConfig:
  applications:
    files:
      url: https://filebrowser.example.com
    chat:
      url: https://chat.example.com
    mail:
      url: https://mail.example.com/SOGo
```

| Ref | Rule |
| --- | --- |
| C-1 | A value must be `http` or `https`. Anything else is rejected and the pane reports unavailable. |
| C-2 | The address is the one the **browser** reaches, not an internal Docker hostname. The pane is an iframe in the user's browser. |
| C-3 | The host must permit Workcenter as a frame ancestor. Zulip sends `X-Frame-Options: DENY` by default, which is why `integration.md` deploys a derived image for it. |
| C-4 | `setup.sh` writes this block from the base domain you give it. Hand-edit it only if you deploy the applications elsewhere. |

### Appearance — set directly on `appConfig`

These keys sit on `appConfig` itself. There is no `appConfig.appearance` object: the schema sets
`additionalProperties: false`, so nesting them under one is rejected. Write `appConfig.theme`, not
`appConfig.appearance.theme`.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `theme` | `string` | `default` | The theme name. See [`theming.md`](./theming.md) for the built-in list. |
| `dayTheme` | `string` | — | A theme to use when the operating system prefers light. Overrides `theme` during the day. |
| `nightTheme` | `string` | — | A theme to use when the operating system prefers dark. Overrides `theme` at night. |
| `customColors` | `object` | — | Overrides individual colour variables, for example `primary: '#4c9be8'`. |
| `customCss` | `string` | — | A stylesheet path or URL, applied to the shell. It cannot reach inside an embedded application. |
| `cssThemes` | `array` | — | Additional theme names, each mapping to a stylesheet. The shell has no theme switcher, so select one with `theme`. |
| `externalStyleSheet` | `string` | — | A stylesheet URL loaded alongside the theme. |
| `contentMaxWidth` | `string` | — | A maximum width for the shell content, for example `1400px`. |
| `hideComponents` | `object` | — | Hide parts of the shell header. The keys are `hideHeading`, `hideNav`, `hideSearch` and `hideSettings`, each a boolean. |

#### Accepted but not read

These keys validate, because the schema still declares them, but **nothing in the shell reads
them**. They are inherited from Dashy, where they drove a tile grid, a favicon resolver and a
default link target. Setting one has no visible effect:

| Key | What it did in Dashy |
| --- | --- |
| `backgroundImg` | Set a dashboard background image. |
| `defaultOpeningMethod` | Chose where a link opened: `newtab`, `sametab`, `top` or `newwindow`. |
| `workspaceLandingUrl` | Opened a URL on load. |
| `iconSize` | Sized icons in the tile grid and page title. |
| `defaultIcon` | Applied a fallback icon to items that had none. |
| `faviconApi` | Resolved a favicon for a link through a third-party service. |

`sections`, at the top level, is in the same position — see below. Each of these may be implemented
later; until then, treat them as reserved names rather than as settings.

### `appConfig.language`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `language` | `string` | auto-detected | An ISO 639-1 code, for example `en` or `en-GB`. Must be one of the bundled locales. It sets the shell's starting language; a user changes it afterwards from the user menu's language control, see [`design.md` §8](../design.md#8-i18n). |

### `appConfig.auth` — signing in

Authentik is the identity provider. The full setup is in [`OIDC.md`](../OIDC.md).

| Key | Type | Description |
| --- | --- | --- |
| `auth.enableOidc` | `boolean` | Use OIDC. Set by `setup.sh`. |
| `auth.oidc.clientId` | `string` | The Client ID from the Authentik provider. |
| `auth.oidc.endpoint` | `string` | The provider's issuer URL. Use the **bare** issuer, without `/.well-known/openid-configuration`. |
| `auth.oidc.adminGroup` | `string` | The Authentik group that grants administrative access. `workspaceadmin`. |
| `auth.oidc.scope` | `string` | Must include `groups` when `adminGroup` is set, or the claim never arrives. |
| `auth.oidc.enableSilentRenew` | `boolean` | Refresh the session in the background. Requires the `offline_access` scope on the provider. |

```yaml
appConfig:
  auth:
    enableOidc: true
    oidc:
      clientId: workcenter
      endpoint: https://auth.example.com/application/o/workcenter/
      adminGroup: workspaceadmin
      scope: openid profile email groups
      enableSilentRenew: true
```

### `appConfig.behaviour`

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `defaultOpeningMethod` | `string` | `newtab` | Where a link opens: `newtab`, `sametab`, `top` or `newwindow`. |
| `workspaceLandingUrl` | `string` | — | A URL to open on load. If it matches a pane, that application is selected. |
| `enableServiceWorker` | `boolean` | `false` | Register the service worker, which caches the shell for faster loads. |
| `enableAuthProxyCompat` | `boolean` | `false` | Drop the cached service worker when an authenticating proxy redirects, so the proxy can re-authenticate the user. |
| `enableErrorReporting` | `boolean` | `false` | Send anonymous crash reports. Off by default, and nothing is sent without this set. |
| `sentryDsn` | `string` | — | The DSN used when `enableErrorReporting` is on. |
| `enableFontAwesome` | `boolean` | auto | Inject the Font Awesome kit. Leave unset to inject it only when an `fa-` icon is used. |
| `enableMaterialDesignIcons` | `boolean` | auto | Inject the Material Design Icons stylesheet, on the same basis. |
| `fontAwesomeKey` | `string` | bundled | Your own Font Awesome kit ID. |

## `sections` — accepted but ignored

Earlier versions of Workcenter, and Dashy before them, listed sidebar entries in a `sections`
array. **Workcenter does not read it.** The sidebar now follows the active application, and the
applications come from `appConfig.applications`.

The key is still accepted so that an existing configuration validates rather than failing with a
schema error, and it is ignored entirely. Removing it is safe.

```yaml
# Accepted for compatibility, and ignored. The shell does not read this.
sections: []
```

## Validating

```bash
yarn validate-config
```

The validator prints every problem it finds with the path to the offending key:

```
1.  /appConfig/applications must NOT have additional properties (filebrowser)
```

That message means the key is spelled `files`, not `filebrowser`.

## Environment variables

Two namespaces exist, and they do different things.

| Prefix | Read by | Use it for |
| --- | --- | --- |
| `VITE_APP_*` | The client, at build time | Values compiled into the bundle. Changing one needs a rebuild. |
| `WORKCENTER_*` | The client, at build time | The project's own namespace, for the same purpose. |

An operator-facing setting belongs in `conf.yml`, not in an environment variable: an environment
variable is baked in when the bundle is built, so it cannot be changed without rebuilding.

Secrets never go in `conf.yml`. The OIDC client secret is read from the environment by the
server. See [`OIDC.md`](../OIDC.md).

## A complete example

```yaml
pageInfo:
  title: Workcenter
  description: Files, chat and mail in one place

appConfig:
  theme: default
  nightTheme: one-dark
  language: en

  applications:
    files:
      url: https://filebrowser.example.com
    chat:
      url: https://chat.example.com
    mail:
      url: https://mail.example.com/SOGo

  auth:
    enableOidc: true
    oidc:
      clientId: workcenter
      endpoint: https://auth.example.com/application/o/workcenter/
      adminGroup: workspaceadmin
      scope: openid profile email groups

  enableServiceWorker: true
  defaultOpeningMethod: newtab
```

## Read next

- [`theming.md`](./theming.md) — themes, colour variables and custom styles
- [`authentication.md`](./authentication.md) — how sign-in works
- [`OIDC.md`](../OIDC.md) — the Authentik setup
- [`deployment.md`](./deployment.md) — deploying Workcenter
- [`production.md`](../production.md) — the full stack and `setup.sh`
