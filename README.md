# forge

A small command-line client for the [Laravel Forge](https://forge.laravel.com) organization-scoped API. Ruby standard library only: no Gemfile, no gems at runtime.

Commands cover reads (the account, orgs, servers, sites, deployments, env, logs, and server resources) and writes: deploying, editing a site's `.env`, replacing its deploy script, firewall rules, service actions, server reboots, background processes (daemons), and scheduled jobs. Every write can be previewed with `-d`.

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

#### Sites

`SITE` is a site name (its domain, e.g. `example.com`) or numeric id. Site commands find the site's server themselves; `-S SERVER` only narrows the lookup.

| Command | What it prints |
|---------|----------------|
| `sites [-S SERVER]` | Every site in the org (or on one server): id, name, server_id, php_version, deployment_status, repository |
| `site SITE` | One site's details, including server_id and repository (url and branch) |
| `deploys SITE [-n N]` | Recent deployments, newest first: id, status, commit (short hash and first message line), created_at, ended_at. Default 10, max 100 |
| `deploy-log SITE [DEPLOYMENT_ID]` | A deployment's output. Default: the latest deployment |
| `deploy-status SITE` | The running deployment's status and start time, or `idle` |
| `deploy-script SITE` | The deploy script on stdout; `auto_source: true\|false` on stderr, so `forge deploy-script SITE > file` captures the script alone |
| `env SITE [--reveal]` | The site's `.env` with values masked (see below); `--reveal` prints the raw file |
| `domains SITE` | id, name, type, status, www_redirect_type, allow_wildcard_subdomains |
| `certs SITE` | SSL certificates: id, type, status, active, request_status, key_type, created_at |
| `logs SITE [--type T] [--tail N]` | The last N lines of a site log. `T` is `application` (default), `nginx-access`, or `nginx-error`; N defaults to 200, `0` prints everything |

#### Server resources

All take `-S SERVER`.

| Command | What it prints |
|---------|----------------|
| `dbs` | Database schemas: id, name, status, created_at |
| `db-users` | Database users: id, name, status, created_at |
| `daemons` | Background processes: id, command, user, directory, processes, status |
| `daemon-log DAEMON_ID` | A background process's log (daemons have no name, so the id is required) |
| `jobs [--site SITE]` | Scheduled jobs on the server, or on one site: id, name, command, user, frequency, cron, next_run_time, status |
| `job-output JOB [--site SITE]` | A scheduled job's latest output. `JOB` is a job name or id |
| `firewall` | Firewall rules: id, name, port, type, ip_address, status |
| `events [-n N]` | Recent events, newest first: id, description, ran_as, created_at. Org-wide unless `-S` is given. Default 20, max 100 |
| `event-output EVENT_ID` | An event's output |
| `server-log KEY [--tail N]` | The last N lines of a server log (default 200, `0` = all). See the keys below |

#### Writes

Every write takes `-d/--dry-run`, which prints the method, path, and body and sends nothing (exit 0). Run a write with `-d` first.

| Command | What it does | Guarded |
|---------|--------------|---------|
| `deploy SITE [-w\|--wait] [--timeout SEC]` | Queues a deployment. `--wait` polls every 5 seconds, printing each status change to stderr, until it finishes; a `failed`, `failed-build`, or `cancelled` deployment, or the timeout (default 900 seconds), exits 1 with the `forge deploy-log SITE ID` command to run | no |
| `env-set SITE MODE [--cache] [--queues] [--reveal]` | Replaces the site's `.env`. `MODE` is exactly one of `--file PATH`, `--stdin`, or one or more `--set KEY=VALUE` / `--unset KEY` (applied in order to the current file). Prints the added, removed, and changed key names to stderr, never values. The dry-run body shows the file masked unless `--reveal` | yes |
| `deploy-script-set SITE (--file PATH \| --stdin) [--[no-]auto-source]` | Replaces the deploy script. Prints `N lines -> M lines` to stderr | yes |
| `firewall-create --name NAME [--port PORT] [--ip ADDR] [--type allow\|deny]` | Adds a firewall rule (type default `allow`; name at most 50 characters). Without `--ip` the rule applies to any address | no |
| `firewall-delete RULE` | Removes a firewall rule by name or id | yes (rule name) |
| `service SERVICE ACTION [--php-version phpNN]` | Runs a service action, checked against the table below before anything is sent. For `php`, the version defaults to the server's `php_version` | `stop` only (server name) |
| `reboot [--power-cycle]` | Reboots the server, or power-cycles it at the provider | yes (server name) |
| `daemon-create --name NAME --command CMD [--user forge\|root] [--directory DIR] [--processes N] [--site SITE] [--startsecs N] [--stopwaitsecs N] [--stopsignal SIG]` | Adds a background process (user default `forge`, 1 process). `--site` associates it with a site | no |
| `daemon-delete DAEMON_ID` | Removes a background process | yes (its id) |
| `daemon-restart DAEMON_ID` | Restarts a background process | no |
| `job-create --command CMD --frequency F [--cron EXPR] [--name NAME] [--user USER] [--heartbeat] [--site SITE]` | Schedules a job on the server, or on a site with `--site`. `F` is `minutely`, `hourly`, `nightly`, `weekly`, `monthly`, `reboot`, or `custom`; `--cron` is required with `custom` and rejected otherwise. User default `forge` | no |
| `job-delete JOB [--site SITE]` | Removes a scheduled job by name or id | yes (job name, else its id) |

The server writes take `-S SERVER`. Service actions:

| Service | Actions |
|---------|---------|
| `nginx`, `mysql`, `postgres` | `restart`, `reboot`, `stop` |
| `redis`, `supervisor` | `restart`, `reboot` |
| `php` | `restart`, `reboot`, `reload` |

`restart` is an alias sent as `reboot`, which is what the API calls a restart.

A write that would change nothing (same content, ignoring trailing newlines) prints `no change`, sends nothing, and exits 0. So `forge deploy-script SITE > script.sh`, an edit, then `forge deploy-script-set SITE --file script.sh -d` previews exactly that edit.

Guarded writes destroy or overwrite something Forge cannot give back, or take a server or service down without bringing it back. On a terminal they say what will happen and ask you to type the resource's name (shown in the table above); anything else aborts (exit 1) with nothing sent. Without a terminal (scripts, agents) they refuse (exit 1) unless you pass `-y/--yes`. `--stdin` consumes stdin, so it always needs `--yes` (or `-d`). No environment variable skips the guard.

After a successful write, the CLI opens the affected site's (or, for server writes, the server's) Forge page in your browser, so no change is silent. Set `FORGE_NO_BROWSER=1` to turn that off. Dry runs and no-ops never open anything.

`SERVER` defaults to `FORGE_SERVER`, else the org's only server. If the org has several servers and none is selected, the command fails and lists their names.

Names resolve exactly (then case-insensitively); there is no partial matching. A name that matches nothing exits 3 and lists what exists; a name that matches several things exits 1 and lists their ids.

#### Env masking

`forge env SITE` never prints a secret unless asked:

- every non-empty value becomes `KEY=********` (fixed width, so length is not revealed);
- `KEY=` with an empty value stays `KEY=`;
- a multi-line quoted value collapses to one masked line;
- comments and blank lines stay, but a commented-out assignment (`# OLD_KEY=value`) is masked too;
- a line that does not parse is shown as `# (unparsed line hidden)`.

`-j env SITE` returns `{site, revealed: false, entries: [{key, value: "********"}]}` with no raw content. `--reveal` prints the file as stored (and in JSON adds `content` and the real values). Do not paste revealed output anywhere it could be logged.

#### Server log keys

The API types the server log `KEY` as a free string with no list. These keys were observed to work on a Forge server; the php and database keys follow the installed versions:

| Key | Log |
|-----|-----|
| `nginx-access` | nginx access log |
| `nginx-error` | nginx error log |
| `php-8.4` | PHP-FPM log for PHP 8.4 (use the server's PHP version: `php-8.3`, and so on) |
| `redis-server` | Redis log |
| `database-mysql` | MySQL log |

Keys such as `nginx`, `php84`, `mysql`, `auth`, and `syslog` return 404.

### Examples

```bash
bin/forge servers
bin/forge server web-1
bin/forge --org my-org -j servers | jq '.data[].attributes.name'
bin/forge sites
bin/forge deploys example.com -n 5
bin/forge deploy-log example.com | tail -20
bin/forge env example.com
bin/forge logs example.com --type nginx-error --tail 50
bin/forge jobs --site example.com
bin/forge server-log nginx-access -S web-1 --tail 100
bin/forge -j events -n 5 | jq '.data[].attributes.description'
bin/forge deploy example.com -d
bin/forge deploy example.com --wait
bin/forge env-set example.com --set APP_DEBUG=false --unset OLD_FLAG -d
bin/forge deploy-script example.com > script.sh   # edit script.sh, then:
bin/forge deploy-script-set example.com --file script.sh -d
bin/forge firewall-create --name office --port 22 --ip 203.0.113.7 -d
bin/forge service php restart -d
bin/forge daemon-create --name queue --command 'php artisan queue:work' --site example.com -d
bin/forge job-create --command 'php artisan schedule:run' --frequency minutely --site example.com -d
bin/forge job-delete scheduler -d
```

### Environment

| Variable | Meaning |
|----------|---------|
| `FORGE_API_KEY` | API token (required) |
| `FORGE_ORG` | Default organization slug |
| `FORGE_SERVER` | Default server name or id |
| `FORGE_DEBUG` | `1` prints a short backtrace on errors (never the token) |
| `FORGE_NO_BROWSER` | `1` stops successful writes from opening the Forge page in a browser |
| `NO_COLOR` | Disables color in human output |

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success, including dry runs and writes that change nothing |
| 1 | Usage error, ambiguous name, guard refused or confirmation mismatch, `deploy --wait` ending in failure or timing out, network failure, or other error |
| 2 | Auth: `FORGE_API_KEY` missing, rejected (401), or lacking permission (403) |
| 3 | Not found: HTTP 404 or a name that matches nothing |
| 4 | API error: any other non-2xx response, including 422 validation and 429 after one retry |

## API notes

- Base URL `https://forge.laravel.com/api`. Only the org-scoped API (`/orgs/...`, `/user`) is used; the legacy `/api/v1` endpoints are not.
- Orgs are addressed by slug, servers and sites by numeric id. The CLI resolves names to ids by listing first.
- The org-wide site listing (`/orgs/{org}/sites`) only carries `relationships.server` when asked with `include=server`, which the CLI always sends. Without it, the CLI falls back to listing each server's sites.
- Deployments come back oldest first unless sorted; the CLI sends `sort=-created_at`. Deployment logs are JSON with the text in `data.attributes.output`.
- Each command costs a few requests: the org lookup (skip it by setting `FORGE_ORG`), one listing per name to resolve, then the read itself.
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
