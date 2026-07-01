# Lakerunner CLI

![Lakerunner Logo](assets/lakerunner-chip-small.png)

The intuitive CLI to query your S3 logs.

![Demo of LakeRunner in action](assets/lrcli.gif)

---

## Why Lakerunner CLI?

- Query your S3 logs on your terms. Fast, flexible, and free.
- Filter and extract what you need without a web UI getting in the way.
- Pipe output to grep, jq, awk, or whatever else you want.

---

## Getting Started

Grab a release from the [releases page](https://github.com/cardinalhq/lakerunner-cli/releases).

For full documentation, see the [CLI reference](https://docs.cardinalhq.io/lakerunner/cli).

### Quick setup

Set your endpoint and API key ([Lakerunner setup guide](https://docs.cardinalhq.io/lakerunner)):

```sh
export LAKERUNNER_QUERY_URL=http://localhost:7101
export LAKERUNNER_API_KEY=your-api-key
```

### Quick examples

```bash
# Get recent logs
lakerunner logs get

# Filter by service and level
lakerunner logs get -a cartservice -l ERROR

# Last 30 minutes, as JSON
lakerunner logs get -s e-30m -o json

# Export to CSV
lakerunner logs get -s e-24h --limit 50000 -o csv > yesterday.csv
```

See the [full CLI reference](https://docs.cardinalhq.io/lakerunner/cli) for all flags, output formats, presets, aliases, and more.

## Building from source

Requires Go 1.24+.

```sh
git clone https://github.com/cardinalhq/lakerunner-cli.git
cd lakerunner-cli
make local        # produces ./bin/lakerunner-cli
make check        # go test -race + license-check + golangci-lint
```
