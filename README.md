# forge

A small command-line client for the [Laravel Forge](https://forge.laravel.com) organization-scoped API. Ruby standard library only: no Gemfile, no gems at runtime.

Current commands are read-only: the account, orgs, and servers.

## Setup

1. Clone the repo.
2. Create a Forge API token in your Forge account settings.
3. Put it in a dotenv file that lives outside the repo (your own secrets store), as `FORGE_API_KEY=...`.
4. Symlink that file into the repo root as `.env`:

   ```bash
   ln -s /path/to/your/secrets/.env.forge .env
   ```

   `.env` is gitignored. `bin/forge` loads it on every run without overriding anything you already exported.

5. Run `bin/forge me` to check the token.

Requires Ruby 4.0 or newer.

## Usage

```
forge [-j|--json] [--org SLUG] <command> [args] [options]
```

Global flags:

| Flag | Meaning |
|------|---------|
| `-j`, `--json` | JSON envelope output: `{"ok": true, "command": "...", "data": ...}` with the raw API data |
| `--org SLUG` | Organization slug (default: `FORGE_ORG`, else the token's only org) |
| `--version` | Print the version |
| `-h`, `--help` | Print help |

### Commands

| Command | What it does |
|---------|--------------|
| `me` | The user that owns `FORGE_API_KEY` |
| `orgs` | Organizations the token can see |
| `servers` | Every server in the org |
| `server [SERVER]` | One server's details. `SERVER` is a name or numeric id; `-S/--server` also works |

`SERVER` defaults to `FORGE_SERVER`, else the org's only server. If the org has several servers and none is selected, the command fails and lists their names.

### Examples

```bash
bin/forge servers
bin/forge server web-1
bin/forge --org my-org -j servers | jq '.data[].attributes.name'
```

### Environment

| Variable | Meaning |
|----------|---------|
| `FORGE_API_KEY` | API token (required) |
| `FORGE_ORG` | Default organization slug |
| `FORGE_SERVER` | Default server name or id |
| `FORGE_DEBUG` | `1` prints a short backtrace on errors (never the token) |
| `NO_COLOR` | Disables color in human output |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage error, ambiguous name, network failure, or other error |
| 2 | Auth: `FORGE_API_KEY` missing, rejected (401), or lacking permission (403) |
| 3 | Not found: HTTP 404 or a name that matches nothing |
| 4 | API error: any other non-2xx response, including 422 validation and 429 after one retry |

## API notes

- Base URL `https://forge.laravel.com/api`. Only the org-scoped API (`/orgs/...`, `/user`) is used; the legacy `/api/v1` endpoints are not.
- Orgs are addressed by slug, servers and sites by numeric id. The CLI resolves names to ids by listing first.
- Lists use cursor pagination (`page[size]`, `page[cursor]` from `meta.next_cursor`); the CLI follows every page, up to 50.
- The API allows 60 requests per minute. On a 429 the CLI waits once (when the reset is within 60 seconds) and retries.
- `docs/forge-openapi.json` is a snapshot of the API spec. Refresh it with:

  ```bash
  curl -sS -o docs/forge-openapi.json https://forge.laravel.com/api/docs.openapi
  ```

## Specs

Minitest, no network:

```bash
for f in spec/*_spec.rb; do ruby -Ilib "$f" || exit 1; done
```
