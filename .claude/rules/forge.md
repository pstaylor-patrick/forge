# forge CLI: stable project rules

## API and auth (no secrets here)
- Base URL: `https://forge.laravel.com/api` (override with `FORGE_BASE_URL` only for testing).
- Only the org-scoped API is used: `/user`, `/orgs`, `/orgs/{org}/...`. The legacy `/api/v1` endpoints return 404 for these tokens; never add them.
- Auth: `Authorization: Bearer $FORGE_API_KEY`. The key comes from the repo `.env`, a gitignored symlink to the user's secrets store, loaded by `bin/forge` without overriding exported variables.
- Never print, log, echo, or commit `FORGE_API_KEY` or the Authorization header, including under `FORGE_DEBUG=1`. Never commit `.env`.
- No keychain flow and no auth-guard hook (jira's are legacy; do not copy them).

## Invocation
- `forge` on PATH is `~/.local/bin/forge`, a symlink to `bin/forge` created by `ruby install.rb`. `bin/forge` finds its repo through `File.realpath`, so it works from any directory.
- Use `bin/forge` (or `forge`) for every Forge call. No raw curl, no other Forge client, no generic `forge api` passthrough (rejected by design; do not add one, or a raw-body / `--field` escape hatch).

## Resolution
- Org: `--org SLUG`, else `FORGE_ORG`, else the token's only org; several orgs exit 1 listing slugs. Orgs are addressed by slug.
- Server: `-S/--server NAME|ID`, else `FORGE_SERVER`, else the org's only server; several exit 1 listing names. Servers and sites need numeric ids in paths, so names are resolved by listing.
- Site: name (its domain) or id. Without `-S`, list `/orgs/{org}/sites?include=server` and read `relationships.server.data.id`; fall back to per-server listings if absent.
- Children (domains, databases, db users, firewall rules, jobs) resolve by name or id; daemons by id only (no name attribute).
- Matching is exact, then case-insensitive exact. No partial matching. Zero matches exit 3 listing names; several exit 1 listing ids.

## JSON field paths (`-j` output, raw JSON:API data inside `{ok, command, data}`)
- Lists: `.data[]`, names at `.data[].attributes.name`, ids at `.data[].id` (strings).
- Site's server: `.data[].relationships.server.data.id`.
- Env: `.data.attributes.content` from the API; `forge -j env` emits `{site, revealed, entries[]}` and adds `content` only with `--reveal`.
- Deploy log: `.data.attributes.output`. Site and server logs: `.data.attributes.content`.
- Deployment commit: `.attributes.commit.{hash,author,message,branch}`.

## Pagination and rate limit
- Cursor pagination: `page[size]` (default 30) and `page[cursor]` from `meta.next_cursor`; `fetch_all` follows up to 50 pages, then warns.
- 60 requests per minute. A 429 waits once (when the reset is within 60 s) and retries; otherwise exit 4. Keep commands to one listing per resolution level.

## Write safety
- Every write goes through `CommandSupport.write!`: resolve -> build request -> dry-run exit -> guard -> send -> print -> return `Affected`. Every write supports `-d/--dry-run`; a dry run never prompts, never sends, never opens a browser.
- Guarded commands (every `*-delete`, `reboot`, `service ... stop`, `env-set`, `deploy-script-set`) need the resource name typed on a TTY, or `--yes`. Non-TTY without `--yes` exits 1 with nothing sent. There is no environment-variable bypass.
- Env values are masked by default (`KEY=********`); `--reveal` shows raw values. Never paste revealed values into commits, PRs, or chat.
- Database passwords come only from `--password-stdin` or a no-echo TTY prompt, and are redacted in dry-run output.
- A successful write opens the affected Forge page in the browser (`FORGE_NO_BROWSER=1` suppresses it).
- No real write against a live Forge server during development or tests. Verify writes with `-d`, `spec/write_commands_spec.rb`, and `spec/endpoints_openapi_spec.rb`. Never run a destructive command without `-d` to "test the guard".

## Code rules
- Ruby stdlib only. No Gemfile, gemspec, or Rakefile.
- One file per command in `lib/forge_cli/commands/`, listed in `COMMANDS` (and `WRITE_COMMANDS` for writes) in `bin/forge`, and in its usage heredoc and the README.
- Request builders live in `lib/forge_cli/endpoints.rb` and are checked against `docs/forge-openapi.json` by `spec/endpoints_openapi_spec.rb`. Refresh the snapshot with `curl -sS -o docs/forge-openapi.json https://forge.laravel.com/api/docs.openapi`.
- Specs are minitest with no network: `for f in spec/*_spec.rb; do ruby -Ilib "$f" || exit 1; done`.
- If a field is missing from human output, that is a formatter bug. Inspect with `-j`, then fix the formatter; do not work around it.

## Public repo
- This repository is public. Committed files (code, specs, docs, commit messages) use placeholder names only: `my-org`, `web-1`, `example.com`. Never commit a real org, server, or site name or id.
