# REST API

Workcenter includes an optional REST API, for reading and writing your config programmatically — from the command line, scripts or third-party applications. It covers whole config files, as well as individual sections and items.

> [!NOTE]
> The API is served by Workcenter's Node server, so it's available with Docker and bare-metal deployments, but not on static hosting providers (Netlify, Vercel, EdgeOne, CDN).

## Enabling the API

The API is disabled by default. To enable it, set the `ENABLE_API` environmental variable to `true`. For example, with Docker Compose:

```yaml
environment:
  - ENABLE_API=true
```

Or with `docker run`, pass `-e ENABLE_API=true`. While disabled, all `/api/*` requests return a 404.

## Authentication

By default, the API uses Workcenter's existing [server-side authentication](/docs/authentication.md). Read endpoints require any authenticated user, and write endpoints require an admin. If no auth is configured, the API is open — the same as Workcenter's other endpoints.

```bash
# With HTTP Basic Auth (ENABLE_HTTP_AUTH or BASIC_AUTH_USERNAME / BASIC_AUTH_PASSWORD)
curl -u alice:hunter2 http://localhost:8080/api/config

# With OIDC / Keycloak, pass your ID token
curl -H 'Authorization: Bearer <id-token>' http://localhost:8080/api/config
```

### API token

If you have no auth configured, or would prefer a dedicated credential for the API, set the `API_TOKEN` environmental variable and send it as a bearer token. A valid token grants full (admin) access, and works alongside any other configured auth method.

```yaml
environment:
  - ENABLE_API=true
  - API_TOKEN=your-long-random-secret
```

```bash
curl -H 'Authorization: Bearer your-long-random-secret' http://localhost:8080/api/config
```

> [!NOTE]
> Setting `API_TOKEN` also secures the API on deployments that have no other auth — anonymous requests are then rejected. Use a long, random value (e.g. `openssl rand -hex 32`) and only send it over HTTPS. The token applies to the API only, not Workcenter's other endpoints.

## Endpoints

`:filename` is any YAML config file in your user-data directory (e.g. `conf.yml`, or a sub-page like `home-lab.yml`). `:key` is one of the top-level config keys: `pageInfo`, `appConfig`, `sections` or `pages`.

**Method** | **Path** | **Description**
--- | --- | ---
`GET` | `/api/config` | List config files
`GET` | `/api/config/:filename` | Get a full config file, as JSON
`PUT` | `/api/config/:filename` | Replace a full config file
`GET` | `/api/config/:filename/:key` | Get a top-level key
`PUT` | `/api/config/:filename/:key` | Replace a top-level key
`POST` | `/api/config/:filename/sections` | Add a section (`name` required)
`GET` | `/api/config/:filename/sections/:sid` | Get a section
`PATCH` | `/api/config/:filename/sections/:sid` | Update fields on a section
`DELETE` | `/api/config/:filename/sections/:sid` | Delete a section
`GET` | `/api/config/:filename/sections/:sid/items` | List a section's items
`POST` | `/api/config/:filename/sections/:sid/items` | Add an item (`title` required)
`GET` | `/api/config/:filename/sections/:sid/items/:iid` | Get an item
`PATCH` | `/api/config/:filename/sections/:sid/items/:iid` | Update fields on an item
`DELETE` | `/api/config/:filename/sections/:sid/items/:iid` | Delete an item

All bodies are JSON. Errors return `{ "success": false, "message": "..." }` with an appropriate status code (400 bad input, 401/403 auth, 404 not found).

### Addressing Sections and Items

`:sid` and `:iid` can be either a zero-based index (`0`, `1`, ...) or an exact match on the section's `name` / item's `title` (URL-encoded). If multiple entries share a name, the first match wins. A section literally named `2` can only be addressed by index.

### Updating

`PATCH` does a shallow merge: only the fields you send are changed, but nested values (like a section's `items` array) are replaced wholesale if included. `PUT` replaces the target entirely.

## Examples

```bash
# List config files
curl http://localhost:8080/api/config

# Get your main config as JSON
curl http://localhost:8080/api/config/conf.yml

# Add an item to the first section
curl -X POST -H 'Content-Type: application/json' \
  -d '{"title": "Grafana", "url": "https://grafana.local", "icon": "hl-grafana"}' \
  http://localhost:8080/api/config/conf.yml/sections/0/items

# Rename a section
curl -X PATCH -H 'Content-Type: application/json' \
  -d '{"name": "Monitoring"}' \
  'http://localhost:8080/api/config/conf.yml/sections/Old%20Name'

# Update the theme
curl -X PUT -H 'Content-Type: application/json' \
  -d '{"theme": "nord-frost"}' \
  http://localhost:8080/api/config/conf.yml/appConfig
```

After modifying your config, refresh the page to see changes.

## Limitations & Notes

- Writes re-serialize the YAML file, so comments, anchors and custom formatting are discarded (the same applies to saving via the UI). A timestamped backup is saved to `user-data/config-backups/` before every write, unless `DISABLE_CONFIG_BACKUPS=true`
- Writes to `conf.yml` are validated against [the schema](https://github.com/JDB321Sailor/Workcenter/blob/Dev/src/utils/config/ConfigSchema.json) and rejected if invalid. Sub-page files are not schema-validated, since they may contain only a subset of fields
- Config files are capped at 256 KB
- Concurrent writes are last-write-wins; there is no locking or optimistic concurrency
