# AGENTS.md

This file provides guidance to AI agents and bags of mostly water alike.

## Project Overview

Lakerunner CLI is a Go-based command-line tool for querying S3 logs through the Lakerunner service. It provides fast, flexible log analysis capabilities without requiring a web UI.

## Commands

### Build and Development

```bash
# Build locally for development
make local

# Run tests
make test

# Run tests only (without generate)
make test-only

# Generate code
make generate

# Build for all platforms
make binaries

# Build multi-architecture Docker images
make images
```

### Code Quality

```bash
# Run all checks (test, license-check, lint)
make check

# Run linter
make lint

# Run license header check
make license-check
```

### Clean

```bash
# Clean binaries
make clean

# Deep clean
make really-clean
```

## Configuration

The CLI requires two environment variables:

- `LAKERUNNER_QUERY_URL`: API endpoint URL
- `LAKERUNNER_API_KEY`: API authentication key

These can be overridden with command-line flags `--endpoint` and `--api-key`.

## Code Architecture

### Directory Structure

- `main.go`: Entry point that delegates to cmd package
- `cmd/`: Cobra command definitions
  - `root.go`: Root command with global flags and color/terminal handling
  - `logs/`: Log querying commands (get, attributes, tag-values)
  - `demo/`: Demo-related commands
- `internal/`: Internal packages
  - `config/`: Configuration management with environment variable loading
  - `api/`: API client functionality
  - `github/`: GitHub integration

### Key Patterns

- Uses Cobra for CLI structure with nested subcommands
- Configuration precedence: CLI flags > environment variables > .env file
- Automatic color disabling on Windows and non-terminal environments
- Standard Go project layout with internal packages

### Dependencies

- `github.com/spf13/cobra`: CLI framework
- `github.com/joho/godotenv`: Environment file loading
- `golang.org/x/term`: Terminal detection
- Go 1.24.0+ required

## Testing

Run `go test -race ./...` to execute all tests with race detection.
