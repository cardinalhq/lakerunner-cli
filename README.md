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

- ⚡ Query your S3 logs on your terms. Fast, Flexible and Free.
- 🛠️ Filter out and extract whatever you need - no forced web UI formats
- 🧰 Use the entire *nix arsenal to filter, transform and analyze logs

---

<p align="center">
  <a href="#getting-started"><strong>Get Started →</strong></a>
</p>

---

## Getting Started

<!-- To-do: Add instructions and link to lakerunner repo here -->
Grab a release from the releases page, or get it via brew

```
brew tap cardinalhq/lakerunner-cli
brew install lakerunner-cli
```

Once you have the CLI installed, you need to set 2 environment variables to Lakerunner. ([Setup guide for Lakerunner](https://docs.cardinalhq.io/lakerunner))

```
export LAKERUNNER_QUERY_URL=http://localhost:7101
export LAKERUNNER_API_KEY=test-key
```

and you should be good to go!

---

## Presets

Presets let you save and reuse sets of filters so you don't have to retype them every time. Define them once in `~/.lakerunner/config.yaml` and reference them by name.

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

**Presets** are named lists of filters in `key:value` format. **Aliases** map short names to full filter key names — they become real CLI flags on every log command and also work as shorthand in `-f` values.

### Usage

Use the `--preset` (or `-p`) flag on any log query command:

```bash
# Query logs using a preset
lakerunner logs get --preset prod-errors

# Get available attributes using a preset
lakerunner logs get-attr --preset prod-errors

# Get tag values using a preset
lakerunner logs get-values resource_service_name --preset prod-errors
```

You can combine a preset with additional inline filters:

```bash
lakerunner logs get --preset prod-errors --filter "region:us-west-2"
```

### Aliases

Aliases are registered as flags automatically. Single-character aliases become short flags, multi-character aliases become long flags:

```bash
# Single-char alias "i: resource_installation" becomes -i
lakerunner logs get -i prod

# Multi-char alias "svc: resource_service_name" becomes --svc
lakerunner logs get --svc myapp

# Aliases also work as shorthand in -f values
lakerunner logs get -f "i:prod"
```

Alias flags show up in `--help` so you can see what's available.

Presets, aliases, and inline filters can all be used together:

```bash
lakerunner logs get --preset prod-errors -i us-west --svc myapp
```

### Listing presets and aliases

```bash
lakerunner presets list
lakerunner aliases list
```
