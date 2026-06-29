# Flatten CLI Attribute Names

## Goal

Update lakerunner-cli to work with the new flat attribute naming format from Lakerunner's query API. With the upstream "Flatten Attribute Namespaces" change enabled (`features.scoped_attributes=false`, the new default), query results return flat attribute names (`service_name`, `level`, `message`) instead of prefixed ones (`resource_service_name`, `log_level`, `log_message`). The CLI must generate correct LogQL queries and correctly extract fields from the flat response format.

## Background

The upstream Lakerunner spec (`flatten-attribute-namespaces.md`) removes namespace prefixes from Parquet column names at ingest time. This means the query API now returns results with flat names. The CLI currently hardcodes prefixed attribute names in several places:

- LogQL query construction: `resource_service_name="app"`, `log_level="ERROR"`
- Field extraction from response tags: `log_level`, `log_message`, `resource_service_name`, `resource_k8s_pod_name`
- Default selector fallback in LogQL: `{resource_service_name=~".+"}`
- Tag value queries: `_cardinalhq_level` for level filtering, `resource_service_name` for service filtering
- Custom attribute tags: `attr_exception_type` for `exception_type`

All of these must be updated to use flat names.

## Requirements

### Functional

1. **LogQL query construction**: Update `buildAppCondition()` and `buildLogQLQuery()` to use flat attribute names:
   - `resource_service_name` → `service_name`
   - `log_level` → `level`
   - Default fallback selector when no conditions are provided: `{service_name=~".+"}` (was `{resource_service_name=~".+"}`)
   - Filter key normalization: do not prepend any namespace prefix; just normalize dots to underscores

2. **Field extraction**: Update `getFieldValue()` shorthand mappings:
   - `level` → look for `level` in tags (was `log_level`)
   - `message` → look for `message` in tags (was `log_message`)
   - `service` / `svc` → look for `service_name` in tags (was `resource_service_name`)
   - `pod` → look for `k8s_pod_name` in tags (was `resource_k8s_pod_name`)
   - No new field aliases are introduced as part of this change.

3. **Default text output**: Update the default (no-columns) text output format to extract `level`, `message`, and `service_name` from tags instead of their prefixed equivalents.

4. **Attributes command (`logs get-attr`)**: Keep current behavior of listing tags and excluding `_cardinalhq*` internal tags. No LogQL predicate rewrite is required in the `get-attr` command itself (the `logs get-values` command in the same file is updated separately in requirement 5).

5. **Tag values command**: Update `logs get-values` to use flat names:
   - Level filtering: use `level` instead of `_cardinalhq_level`
   - Service filtering: use `service_name` instead of `resource_service_name`

6. **Tests**: Update all test fixtures and assertions to use flat attribute names in mock response data and expected queries.

### Non-Functional

- No new dependencies.
- No behavioral changes to output formatting logic — only the attribute names used to look up values change.
- Backward compatibility with prefixed names is NOT required — the CLI assumes flat mode is enabled on the server.
- Automatic migration of user presets/aliases from prefixed keys to flat keys is NOT required.
- Users with existing presets or aliases referencing prefixed attribute names (e.g., `resource_service_name`) must manually update them to flat names (e.g., `service_name`). No automatic migration or warning is provided.

## Scope

### In Scope

- `cmd/logs/get.go`: LogQL query building, field extraction, default output rendering
- `cmd/logs/get_test.go`: Update test fixtures and assertions
- `cmd/logs/attributes.go`: Tag values query construction (`logs get-values`)
- Any preset/alias resolution that references prefixed names

### Out of Scope

- API client (`internal/api/client.go`) — no changes needed, it just passes queries through
- Response parsing (`internal/api/logs_response.go`) — the structure is the same, only tag key names change
- Config loading (`internal/config/config.go`) — no feature flag needed in the CLI
- Preset file format and alias schema — presets/aliases use user-supplied filter keys; users are responsible for updating prefixed keys to flat keys

## Acceptance Criteria

1. `lakerunner logs get -a myapp` generates a LogQL query containing `service_name="myapp"` (not `resource_service_name`).
2. `lakerunner logs get -l ERROR` generates a LogQL query containing `level="ERROR"` (not `log_level`).
3. `lakerunner logs get -f k8s.namespace.name:default` generates `k8s_namespace_name="default"` (not `attr_k8s_namespace_name`).
4. Default text output correctly extracts `level`, `message`, and `service_name` from flat-named tags.
5. `lakerunner logs get -c level,service_name,message` works with flat column names.
6. `lakerunner logs get` with no filters generates `{service_name=~".+"}`.
7. `lakerunner logs get-values level -l ERROR -a myapp` uses query predicates `level="ERROR"` and `service_name="myapp"` (not `_cardinalhq_level` / `resource_service_name`).
8. All existing tests pass after updating fixtures to use flat attribute names.
9. `make check` passes.

## Open Questions

None — the upstream spec is clear that flat mode is the new default and the CLI should assume it.
