# Fix Flatten PR Review Issues

## Goal

Address the issues identified during the PR review of #16 (flatten-cli-attribute-names). The review found a stale comment referencing old prefixed attribute names, missing test coverage for `attributes.go` condition building, and spec documentation gaps.

This fix spec is intentionally narrow: close review findings without expanding behavior beyond what PR #16 already changed.

## Requirements

### 1. Fix stale comment in presets.go

**File:** `internal/presets/presets.go`, lines 94-95

The `RegisterAliasFlags` doc comment still references the old prefixed names:

```go
// Single-char aliases become short flags (e.g., -i for resource_installation).
// Multi-char aliases become long flags (e.g., --svc for resource_service_name).
```

Update the examples to use flat attribute names (e.g., `installation`, `service_name`).

### 2. Add test coverage for attributes.go condition building

**File:** `cmd/logs/attributes.go`, lines 175-188

The `runTagValuesCmd` function builds LogQL conditions inline (service name filtering with `service_name`, level filtering with `level`, and custom filters). This code has zero test coverage. The condition-building logic should be extracted into a testable function and tested with cases covering:

- App name only (`service_name="app"`)
- Log level only (`level="ERROR"`)
- App name + log level combined
- Custom filters (`key="value"`)
- All combined
- No conditions (empty result)
- Dot normalization in filter keys/values

Implementation guidance:

- Extract only condition construction (not network calls, sorting, output rendering, or command wiring).
- Keep behavior identical to current PR branch behavior; this is a refactor-for-testability, not a feature change.
- Prefer a pure helper with explicit inputs and deterministic output (stable ordering of generated predicates).
- Keep the helper in `cmd/logs/attributes.go`; tests should target it directly from `cmd/logs/attributes_test.go`.

### 3. Update the flatten spec document

**File:** `docs/specs/flatten-cli-attribute-names.md`

Address documentation gaps identified in the review:

- Add `attr_` to the Background section's list of prefix patterns (e.g., `attr_exception_type`)
- Clarify in requirement 4 that the "no LogQL predicate rewrite" statement applies only to `get-attr`, not `get-values` (which is covered by requirement 5)
- Add a note about the breaking change: users with existing presets referencing prefixed names must update them manually

When updating wording, keep terminology consistent with command names (`logs get-attr` and `logs get-values`) to avoid ambiguity.

## Scope

### In Scope

- `internal/presets/presets.go`: Fix stale comment (lines 94-95)
- `cmd/logs/attributes.go`: Extract condition-building into a testable function
- `cmd/logs/attributes_test.go`: New test file for the extracted function
- `docs/specs/flatten-cli-attribute-names.md`: Documentation improvements

### Out of Scope

- Version-mismatch detection (valuable but a separate feature, not a fix for this PR)
- Pre-existing error handling issues identified in the review (SSE JSON parse failures, filter validation, LogQL injection) — these predate this PR and should be tracked separately
- Changes to `cmd/logs/get.go` or its tests — no issues were found in those files

## Acceptance Criteria

1. The comment in `presets.go` uses flat attribute name examples
2. A `buildTagValuesQuery` (or similar) function is extracted from `runTagValuesCmd` and is testable
3. Table-driven tests cover app name, log level, filters, combined conditions, empty/no-condition cases, and dot normalization
4. The flatten spec document includes the `attr_` prefix pattern, clarifies get-attr vs get-values, and notes the breaking change for presets
5. Existing command behavior is unchanged apart from comment/spec text updates and testability refactor
6. `make check` passes
