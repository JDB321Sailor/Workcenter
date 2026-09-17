# REST API

Workcenter ships an HTTP API for reading and replacing its configuration files. It is off unless it
is explicitly enabled, and writes require an administrative identity.

## Enabling the API

```bash
ENABLE_API=true
```

While the variable is unset or set to anything else, every route under `/api` answers `404`:

```json
{ "success": false, "message": "API not enabled. Set ENABLE_API=true to use the REST API." }
```

The gate is deliberate: the API can replace the whole configuration file, so it is opt-in.

## Authentication

| Environment | Identity accepted |
| --- | --- |
| `API_TOKEN` set | `Authorization: Bearer <token>`, treated as an administrator. |
| Workcenter auth configured (`ENABLE_HTTP_AUTH`, or an OIDC/proxy identity) | The caller's normal session, with administrative rights required for writes. |
| Neither configured | The API is open to anyone who can reach the port. Do not run it that way on a reachable network. |

A token is compared in constant time and must match exactly. With Workcenter auth in place and no
token, an unauthenticated request receives `401`:

```json
{ "success": false, "message": "Unauthorized" }
```

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/api/config` | List the configuration files. |
| `GET` | `/api/config/:filename` | Read one configuration file as JSON. |
| `PUT` | `/api/config/:filename` | Replace a configuration file. Admin. |
| `GET` | `/api/config/:filename/:key` | Read one top-level key of a file. |
| `PUT` | `/api/config/:filename/:key` | Replace one top-level key of a file. Admin. |

`:filename` is a bare name ending in `.yml` or `.yaml`. A path separator, a control character or a
`..` segment is rejected with `400`, so the API cannot reach outside the user-data directory.

`:key` is one of `pageInfo`, `appConfig` or `sections`. Anything else is rejected with
`400`.

Responses:

- `GET /api/config` → `{ "success": true, "files": ["conf.yml"] }`, sorted.
- `GET /api/config/:filename` → the file itself, as a JSON object with no wrapper.
- `GET /api/config/:filename/:key` → the value of that key, with no wrapper.
- `PUT` → `{ "success": true, "message": "Config saved successfully in ..." }`.

Errors take the shape `{ "success": false, "message": "..." }` with the status that goes with them:
`400` for a bad request or a schema failure, `401` for a missing or rejected identity, `404` for a
missing file or key, and `500` for a file that cannot be parsed or written.

## Rules

| Ref | Rule |
| --- | --- |
| A-1 | `conf.yml` is validated against the config schema before it is written, and a failure is reported as `400` with the offending paths. Other files are written as given. |
| A-2 | A request body is limited to 1 MB by the JSON parser, and a configuration may be at most 256 KB. |
| A-3 | Every write backs up the previous file into `user-data/config-backups/`, unless `DISABLE_CONFIG_BACKUPS=true`. Move it with `BACKUP_DIR`. |
| A-4 | `PUT` replaces its target. It does not merge, so a partial body writes a partial configuration: read the file, change it, send the whole object back. |
| A-5 | A `$schema` modeline already in the file is preserved. |

## Examples

```bash
# List the configuration files
curl -s http://localhost:4000/api/config \
  -H "Authorization: Bearer $API_TOKEN"

# Read the main configuration
curl -s http://localhost:4000/api/config/conf.yml \
  -H "Authorization: Bearer $API_TOKEN"

# Read a single top-level key
curl -s http://localhost:4000/api/config/conf.yml/appConfig \
  -H "Authorization: Bearer $API_TOKEN"

# Replace one key
curl -s -X PUT http://localhost:4000/api/config/conf.yml/appConfig \
  -H "Authorization: Bearer $API_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"language":"en","applications":{"files":{"url":"https://filebrowser.example.com"}}}'

# Replace a whole file, from a file on disk
curl -s -X PUT http://localhost:4000/api/config/conf.yml \
  -H "Authorization: Bearer $API_TOKEN" \
  -H 'Content-Type: application/json' \
  --data-binary @new-conf.json
```

With HTTP Basic Auth instead of a token, replace the header with `-u alice:hunter2`.

Wait for `"success": true` before assuming a write landed. A rejected write leaves the previous file
untouched, and the message names the reason.

## Read next

- [`configuring.md`](./configuring.md) — what each configuration key means
- [`security.md`](./security.md) — how the API is protected, and what to do before exposing it
- [`management.md`](./management.md) — backups, and the environment variables the server reads
