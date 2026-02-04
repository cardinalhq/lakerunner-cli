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

Create `~/.lakerunner/config.yaml` and add your presets:

```yaml
presets:
  prod-errors:
    - "environment:prod"
    - "log_level:ERROR"
  staging-debug:
    - "environment:staging"
    - "log_level:DEBUG"
```

Each preset is a named list of filters in `key:value` format.

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

You can combine a preset with additional inline filters. Inline filters are appended to the preset filters:

```bash
lakerunner logs get --preset prod-errors --filter "region:us-west-2"
```
