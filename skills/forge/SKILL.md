---
name: forge
description: Use the local forge CLI for Laravel Forge - servers, sites, deploys, env, logs, daemons, scheduled jobs, databases, firewall rules, domains, and certificates. Use whenever the user asks to read or change anything on Laravel Forge.
---

# /forge skill

Use `forge` (on PATH through `~/.local/bin/forge`) for every Laravel Forge
operation. Never call the Forge API with raw curl, never use another Forge
client (including Laravel's official forge CLI or a Forge MCP), and never parse
the API yourself. If a field you need is missing from human output, run the
same command with `-j` and read the JSON; a missing field is a CLI bug worth
reporting.

The CLI reads `FORGE_API_KEY` from the `.env` symlink in its own repo. Never
print, echo, or pass the token on the command line.

## Invocation

```
forge [-j|--json] [--org SLUG] <command> [args] [options]
forge --help        # full command list with every flag
```

- `-j` wraps output as `{"ok": true, "command": ..., "data": ...}` with the raw
  JSON:API data (`.data[].attributes.name`, `.data.attributes.content`).
- `--org` defaults to `FORGE_ORG`, else the token's only org.
- `-S/--server NAME|ID` selects the server for server-scoped commands
  (default `FORGE_SERVER`, else the org's only server).
- `SITE` is a site name (its domain) or numeric id; site commands find the
  server themselves.

## Commands

Reads (always safe):

```
me | orgs | servers | server [SERVER]
sites [-S] | site SITE
deploys SITE [-n N] | deploy-log SITE [ID] | deploy-status SITE | deploy-script SITE
env SITE [--reveal] | domains SITE | certs SITE
logs SITE [--type application|nginx-access|nginx-error] [--tail N]
dbs | db-users | daemons | daemon-log ID | jobs [--site SITE] | job-output JOB [--site SITE]
firewall | events [-n N] | event-output ID | server-log KEY [--tail N]
```

Writes (every one takes `-d/--dry-run`; G = guarded, needs a typed name or `--yes`):

```
deploy SITE [--wait] [--timeout SEC]
env-set SITE (--file PATH | --stdin | --set K=V ... | --unset K ...)      G
deploy-script-set SITE (--file PATH | --stdin)                           G
firewall-create --name N [--port P] [--ip ADDR] [--type allow|deny]
firewall-delete RULE                                                     G
service SERVICE ACTION [--php-version phpNN]                             G for stop
reboot [--power-cycle]                                                   G
daemon-create --name N --command CMD [...] | daemon-restart ID
daemon-delete ID                                                         G
job-create --command CMD --frequency F [--cron EXPR] [--site SITE]
job-delete JOB [--site SITE]                                             G
db-create NAME [--user U] [--password-stdin]
db-delete DB                                                             G
db-user-create NAME [--databases a,b] [--read-only] [--password-stdin]
db-user-update USER [--databases a,b] [--password-stdin]   (--databases replaces grants)
db-user-delete USER                                                      G
site-create DOMAIN [...] | site-update SITE [...]
site-delete SITE                                                         G
domain-create SITE DOMAIN [--www ...] [--wildcard]
domain-delete SITE DOMAIN                                                G
cert-issue SITE DOMAIN [--verification ...] [--key-type ...]
cert-delete SITE DOMAIN CERT_ID                                          G
```

There is no generic API passthrough. If the user needs an endpoint the CLI does
not cover, say so instead of reaching for curl.

## Write rules

1. Always run a write with `-d` first and show the user the dry run (method,
   path, body). Run it for real only after the user agrees.
2. Guarded (destructive) commands prompt for the resource name on a terminal.
   As an agent you have no terminal, so the command refuses (exit 1) unless
   you pass `--yes`. Pass `--yes` only after the user has explicitly said to go
   ahead with that exact destructive change. `--stdin` modes always need
   `--yes` (or `-d`).
3. Database passwords go through `--password-stdin`, never as arguments.
4. A successful write opens the affected Forge page in the browser. Set
   `FORGE_NO_BROWSER=1` only for bulk or headless runs.
5. `env-set` and `deploy-script-set` print `no change` and send nothing when
   the content is identical.

## Secrets

- `forge env SITE` masks every value (`KEY=********`). Never pass `--reveal`
  unless the user asked for raw values, and never echo revealed values back
  into chat, commits, PRs, or files.
- `env-set` prints changed key names only; its dry run masks the body unless
  `--reveal` is given.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, including dry runs and no-op writes |
| 1 | Usage error, ambiguous name, guard refused or confirmation mismatch, failed or timed-out `deploy --wait`, network error |
| 2 | Auth: `FORGE_API_KEY` missing, rejected (401), or lacking permission (403) |
| 3 | Not found: HTTP 404 or a name that matches nothing (the message lists what exists) |
| 4 | API error: other non-2xx, including 422 validation and 429 after one retry |

The API allows 60 requests per minute; a site-scoped command makes 2 to 3
requests, one of them the org lookup that setting `FORGE_ORG` skips. Prefer one listing with `-j` over many
single-item reads.
