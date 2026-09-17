# Credits

## Built from Dashy

Workcenter began as [Dashy](https://github.com/lissy93/dashy), by
[Alicia Sykes](https://aliciasykes.com), which is MIT licensed. Workcenter keeps Dashy's
Workspace view — the sidebar plus the embedded content surface — and its theming,
authentication and documentation conventions. The Default dashboard, the Minimal view,
the widget engine, status monitoring, the tile grid and the in-app configuration editor
are not part of Workcenter.

The upstream copyright notice is retained in [`LICENSE`](../LICENSE) and in the header of
every file that carries one. Workcenter is an independent project and is not a fork.

## Dependencies

Workcenter is built on the following projects. Full credit to their authors.

### Core

| Project | Role |
| --- | --- |
| [Vue.js](https://github.com/vuejs/core) | The UI framework |
| [Vuex](https://vuex.vuejs.org/) | State management |
| [Vue Router](https://github.com/vuejs/router) | Routing between the workspace and the three panes |
| [Vite](https://github.com/vitejs/vite) | Build tooling and dev server |
| [SCSS](https://github.com/sass/sass) | Styling |
| [TypeScript](https://github.com/microsoft/TypeScript) | Types, checked with `vue-tsc` |
| [ESLint](https://github.com/eslint/eslint) | Linting |
| [Vitest](https://github.com/vitest-dev/vitest) | Unit and server tests |
| [Express](https://github.com/expressjs/express) | The Node server: static assets, the config API and `/healthz` |
| [YAML](https://github.com/yaml/yaml) | The configuration format |
| [js-yaml](https://github.com/nodeca/js-yaml) | Configuration parsing |
| [Docker](https://www.docker.com/) | Container deployment |

### Application

| Project | Role |
| --- | --- |
| [oidc-client-ts](https://github.com/authts/oidc-client-ts) | The OIDC client, used for Authentik sign-in |
| [jose](https://github.com/panva/jose) | Server-side token verification |
| [vue-i18n](https://github.com/intlify/vue-i18n) | The 33 locales |
| [DOMPurify](https://github.com/cure53/DOMPurify) | Sanitising untrusted HTML |
| [crypto-js](https://github.com/brix/crypto-js) | Password hashing for the local auth fallback |
| [ajv](https://github.com/ajv-validator/ajv) | Validating `user-data/conf.yml` against the schema |
| [rsup-progress](https://github.com/Inndy/rsup-progress) | The route-change progress bar |
| [simple-icons](https://github.com/simple-icons/simple-icons) | Brand icons |
| [vue-select](https://github.com/sagalbot/vue-select) | The select component |

### The integrated stack

Workcenter deploys and integrates, but does not vendor, these projects. Their licences
apply to their own code.

| Project | Licence | Role |
| --- | --- | --- |
| [FileBrowser Quantum](https://github.com/gtsteffaniak/filebrowser) | Apache-2.0 | Files, and the standard for version control and contribution process |
| [ONLYOFFICE Docs](https://github.com/ONLYOFFICE/DocumentServer) | AGPL-3.0 | Document editing inside the Files pane |
| [Zulip](https://github.com/zulip/zulip) | Apache-2.0 | Team chat |
| [Mailcow Dockerized](https://github.com/mailcow/mailcow-dockerized) | GPL-3.0 | The mail server stack |
| [SOGo](https://github.com/Alinto/sogo) | LGPL-2.1 | Webmail, calendar and contacts |
| [Authentik](https://github.com/goauthentik/authentik) | MIT / GPL-3.0 | The identity provider |
| [Traefik](https://github.com/traefik/traefik) | MIT | The reverse proxy |

## Contributing

See [`contributions.md`](../contributions.md) for how to contribute, and
[`credits`](credits.md) for the licence of each dependency.
