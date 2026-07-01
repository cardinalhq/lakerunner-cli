---
name: lakerunner-cli
description: Query S3 logs through the Lakerunner CLI. Use when the user wants to search, filter, or export logs; discover available attributes; or answer questions about log volume, error rates, or specific services from data stored via Lakerunner.
---

# Lakerunner CLI skill

You have access to `lakerunner-cli` on this machine. Use it to answer log-related questions instead of guessing.

Full reference: https://docs.cardinalhq.io/lakerunner/cli

## Before you run anything

1. Confirm the binary is on `PATH`: `command -v lakerunner-cli`. If missing, tell the user to install it from https://github.com/cardinalhq/lakerunner-cli/releases and stop.
2. Confirm credentials are set: `LAKERUNNER_QUERY_URL` and `LAKERUNNER_API_KEY` must be in the environment. If either is missing, ask the user before proceeding — don't invent an endpoint.
3. Default to `--quiet` in scripted/agentic use so the banner doesn't pollute output you'll parse.
4. Default to `--output json` when you're going to parse or reason about the data. Reserve `text` for cases where the user asked to see the logs directly.

## Commands you'll actually use

### `lakerunner-cli logs get` — the primary query

Returns log rows. Defaults: last 1 hour, 1000 rows, newest first.

Flags worth knowing:

- `-s / --start`, `-e / --end` — time bounds. Accepts relative (`e-1h`, `e-30m`, `now`) or ISO 8601 (`2024-01-01T00:00:00Z`). Relative bounds anchor to `end`, not to wall-clock now — so if you change `--end`, `e-1h` moves with it.
- `-a / --app` — filter by service name. Comma-separated for multiple: `-a "api,auth"`.
- `-l / --level` — `ERROR`, `WARN`, `INFO`, `DEBUG`, `TRACE`.
- `-f / --filter` — repeatable `key:value` filters (`-f "environment:prod" -f "region:us-east-1"`).
- `-p / --preset` — named filter set from `~/.lakerunner/config.yaml`.
- `-M / --contains`, `-N / --not-contains` — plain substring match on the message.
- `-R / --msg-regex`, `-X / --msg-not-regex` — regex match on the message.
- `-c / --columns` — comma-separated columns. Shortcuts: `timestamp`/`ts`, `level`, `service`/`svc`, `pod`, `message`. Any raw attribute name also works.
- `-o / --output` — `text` | `json` | `csv` | `tsv`.
- `--order` — `newest` (default) or `oldest`.
- `--limit` — cap on rows (default 1000). Raise deliberately; don't request millions.
- `--query` — a raw LogQL query. Bypasses the structured flags. Only use when the user hands you one or when the structured flags can't express what they want.

Preset filters are applied first, then `--filter` values are appended.

### `lakerunner-cli logs get-attr` — discover fields

Lists attribute names available for a given time range. With no filters this is a fast metadata lookup; with any filter flag the returned list is scoped to attributes actually attached to matching rows. Same time/filter flags as `logs get`.

Use this when the user asks "what can I filter by?" or before crafting a complex filter on unfamiliar data.

### `lakerunner-cli logs get-values <attr>` — enumerate values

Returns the observed values for a single attribute. Same time/filter flags as `logs get-attr`. Use this to answer "what services do we have?", "which environments?", etc.

### `lakerunner-cli presets list` and `lakerunner-cli aliases list`

Show what's configured in `~/.lakerunner/config.yaml`. Check these before writing a long `-f` chain — the user may already have a preset.

## Patterns

**Answering "any errors in the last hour?"**

```bash
lakerunner-cli --quiet logs get -l ERROR -s e-1h -o json --limit 200
```
Then summarize by service and message shape.

**Answering "why is service X failing?"**

1. `lakerunner-cli --quiet logs get -a X -l ERROR -o json --limit 500`
2. Group by message pattern, pick the top offenders, report counts + a sample line.

**Exploring unfamiliar data:**

1. `lakerunner-cli --quiet logs get-attr -s e-24h` — see what fields exist.
2. `lakerunner-cli --quiet logs get-values service -s e-24h` — see the service catalog.
3. Then narrow.

**Exporting for the user:**

Use `-o csv` or `-o json` and either redirect to a file the user names or print a short preview and ask where to save it. Don't dump 10k rows into chat.

## Guardrails

- **Never fabricate log lines.** If a query returns nothing, say so.
- **Don't guess time ranges.** If the user says "recently" and there's ambiguity, ask, or default to `e-1h` and state your assumption.
- **Don't invent attribute names.** Run `logs get-attr` first if you aren't sure a field exists.
- **Don't run unbounded exports.** Ask before raising `--limit` above ~10k or pulling multi-day ranges.
- **Redact obvious secrets** (tokens, keys, passwords) from any log content you paste back into chat.
- If the CLI errors, show the exact error to the user rather than retrying blindly.

## Quick smoke test

If you're not sure the setup works, run:

```bash
lakerunner-cli --quiet logs get -s e-5m --limit 5 -o json
```

A JSON array (possibly empty) means you're wired up.
