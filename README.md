<p align="center">
  <img src="assets/lakerunner-chip.png" alt="Lakerunner Logo" width="50" />
</p>

<h1 align="center">Lakerunner CLI</h1>

<p align="center">
  <em>The intuitive CLI to query your S3 logs</em>
</p>

<p align="center">
  <img src="assets/lrcli.gif" alt="Demo of LakeRunner in action" width="800" />
</p>

---

### Why Lakerunner CLI?

- Query your S3 logs on your terms. Fast, flexible, and free.
- Filter and extract what you need without a web UI getting in the way.
- Pipe output to grep, jq, awk, or whatever else you want.

---

## Getting Started

Grab a release from the releases page, or install via brew:

```
brew tap cardinalhq/lakerunner-cli
brew install lakerunner-cli
```

Set your endpoint and API key ([Lakerunner setup guide](https://docs.cardinalhq.io/lakerunner)):

```
export LAKERUNNER_QUERY_URL=http://localhost:7101
export LAKERUNNER_API_KEY=your-api-key
```

---

## Querying Logs

### Basic usage

```bash
lakerunner logs get
```

By default this returns the last hour of logs, newest first, limited to 1000 results.

### Time ranges

Use `-s` (start) and `-e` (end) to specify a time range:

```bash
# Last 30 minutes
lakerunner logs get -s e-30m

# Last 24 hours
lakerunner logs get -s e-24h

# Specific time range
lakerunner logs get -s 2024-01-15T00:00:00Z -e 2024-01-15T12:00:00Z
```

The `e-` prefix means "end minus", so `e-1h` is one hour before the end time.

### Filtering by service and level

```bash
# Logs from a specific service
lakerunner logs get -a cartservice

# Logs from multiple services
lakerunner logs get -a cartservice,checkoutservice,frontend

# Only errors
lakerunner logs get -l ERROR

# Errors from a specific service
lakerunner logs get -a cartservice -l ERROR
```

### Filtering by message content

```bash
# Messages containing "timeout"
lakerunner logs get -M timeout

# Messages NOT containing "health"
lakerunner logs get -N health

# Regex match
lakerunner logs get -R "user_id=\d+"

# Regex exclude
lakerunner logs get -X "DEBUG|TRACE"
```

### Generic filters

Use `-f` for any tag:

```bash
lakerunner logs get -f "environment:prod" -f "region:us-west-2"
```

### Limit and ordering

```bash
# Get more results
lakerunner logs get --limit 5000

# Oldest first instead of newest first
lakerunner logs get --order=oldest
```

---

## Output Formats

### Text (default)

```bash
lakerunner logs get
```

Output:
```
[2024-01-15 10:23:45.123] INFO cartservice: GetCartAsync called
[2024-01-15 10:23:44.891] ERROR authservice: Connection refused
```

### JSON

One JSON object per line (JSON Lines format), works well with jq:

```bash
lakerunner logs get -o json

# Filter with jq
lakerunner logs get -o json | jq 'select(.level == "ERROR")'
```

### CSV and TSV

Includes a header row:

```bash
lakerunner logs get -o csv > logs.csv
lakerunner logs get -o tsv > logs.tsv
```

### Selecting columns

By default, structured output includes timestamp, level, service, and message. Use `-c` to pick different columns:

```bash
lakerunner logs get -o csv -c "timestamp,level,service,message,trace_id"
lakerunner logs get -o json -c "timestamp,level,message"
```

Column selection also works with text output:

```bash
lakerunner logs get -c "timestamp,level,message"
```

---

## Raw LogQL Queries

If you know LogQL, you can pass a query directly:

```bash
lakerunner logs get --query '{resource_service_name="cartservice"} |= "error"'
```

When using `--query`, filter flags like `-a`, `-l`, and `-f` are ignored.

---

## Exploring Available Data

### List all available tags

```bash
lakerunner logs get-attr
```

### List values for a specific tag

```bash
lakerunner logs get-values resource_service_name
lakerunner logs get-values log_level
```

---

## Presets and Aliases

Presets let you save common filter combinations. Aliases give you shorthand flags.

### Configuration

Create `~/.lakerunner/config.yaml`:

```yaml
presets:
  prod-errors:
    - "environment:prod"
    - "log_level:ERROR"
  staging-debug:
    - "environment:staging"
    - "log_level:DEBUG"

aliases:
  i: resource_installation
  svc: resource_service_name
  env: environment
```

### Using presets

```bash
lakerunner logs get --preset prod-errors

# Combine with other filters
lakerunner logs get --preset prod-errors -a cartservice
```

### Using aliases

Aliases become flags automatically:

```bash
# -i expands to resource_installation
lakerunner logs get -i prod

# --svc expands to resource_service_name
lakerunner logs get --svc myapp

# Also works in -f values
lakerunner logs get -f "i:prod"
```

### Listing what's configured

```bash
lakerunner presets list
lakerunner aliases list
```

---

## Putting it together

A few real-world examples:

```bash
# Errors from prod in the last hour, as JSON
lakerunner logs get -l ERROR -f "environment:prod" -o json

# Debug what happened around a specific time
lakerunner logs get -s 2024-01-15T14:30:00Z -e 2024-01-15T14:35:00Z --order=oldest

# Export a day of logs to CSV for analysis
lakerunner logs get -s e-24h --limit 50000 -o csv > yesterday.csv

# Find slow requests
lakerunner logs get -M "duration_ms" -R "duration_ms=[0-9]{4,}" -o json | jq '.message'

# Tail-like behavior (oldest first, watch for new logs)
lakerunner logs get -s e-5m --order=oldest
```
