// Copyright 2025-2026 CardinalHQ, Inc
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package logs

import (
	"encoding/json"
	"strings"
	"testing"
)

// Mock log entries based on real API responses from OpenTelemetry demo app
var mockLogEntries = []struct {
	name    string
	message map[string]any
	tags    map[string]any
}{
	{
		name: "INFO log from cartservice",
		message: map[string]any{
			"timestamp":    int64(1771022549165),
			"timestamp_ns": int64(1771022549165115500),
			"tags": map[string]any{
				"log_level":             "INFO",
				"log_message":           "GetCartAsync called with userId={userId}",
				"resource_service_name": "cartservice",
				"resource_k8s_pod_name": "otel-demo-cartservice-744fc69cf7-bmm9z",
				"trace_id":              "fa80431d09e856c223bc3f691d0869e7",
			},
		},
		tags: map[string]any{
			"log_level":             "INFO",
			"log_message":           "GetCartAsync called with userId={userId}",
			"resource_service_name": "cartservice",
			"resource_k8s_pod_name": "otel-demo-cartservice-744fc69cf7-bmm9z",
			"trace_id":              "fa80431d09e856c223bc3f691d0869e7",
		},
	},
	{
		name: "ERROR log from loadgenerator",
		message: map[string]any{
			"timestamp":    int64(1771019896965),
			"timestamp_ns": int64(1771019896965957376),
			"tags": map[string]any{
				"log_level":             "ERROR",
				"log_message":           "Error ErrorCode.GENERAL while evaluating flag with key: 'loadgeneratorFloodHomepage'",
				"resource_service_name": "loadgenerator",
				"resource_k8s_pod_name": "otel-demo-loadgenerator-6b44d87f55-kng6x",
				"attr_exception_type":   "GeneralError",
			},
		},
		tags: map[string]any{
			"log_level":             "ERROR",
			"log_message":           "Error ErrorCode.GENERAL while evaluating flag with key: 'loadgeneratorFloodHomepage'",
			"resource_service_name": "loadgenerator",
			"resource_k8s_pod_name": "otel-demo-loadgenerator-6b44d87f55-kng6x",
			"attr_exception_type":   "GeneralError",
		},
	},
	{
		name: "WARN log from loadgenerator",
		message: map[string]any{
			"timestamp":    int64(1771022489921),
			"timestamp_ns": int64(1771022489921509376),
			"tags": map[string]any{
				"log_level":             "WARN",
				"log_message":           "Transient error StatusCode.UNAVAILABLE encountered while exporting metrics",
				"resource_service_name": "loadgenerator",
				"resource_k8s_pod_name": "otel-demo-loadgenerator-6b44d87f55-kng6x",
			},
		},
		tags: map[string]any{
			"log_level":             "WARN",
			"log_message":           "Transient error StatusCode.UNAVAILABLE encountered while exporting metrics",
			"resource_service_name": "loadgenerator",
			"resource_k8s_pod_name": "otel-demo-loadgenerator-6b44d87f55-kng6x",
		},
	},
}

func TestGetFieldValue(t *testing.T) {
	tests := []struct {
		name      string
		message   map[string]any
		tags      map[string]any
		field     string
		expected  string
		checkFunc func(string) bool // optional custom check function
	}{
		{
			name:    "get timestamp from timestamp_ns",
			message: map[string]any{"timestamp_ns": int64(1771022549165115500)},
			tags:    nil,
			field:   "timestamp",
			// Timestamp formatting is timezone-dependent, so just check format
			checkFunc: func(s string) bool {
				return strings.Contains(s, "2026-02-") && strings.Contains(s, ":42:29")
			},
		},
		{
			name:    "get timestamp from timestamp milliseconds",
			message: map[string]any{"timestamp": int64(1771022549165)},
			tags:    nil,
			field:   "timestamp",
			// Timestamp formatting is timezone-dependent, so just check format
			checkFunc: func(s string) bool {
				return strings.Contains(s, "2026-02-") && strings.Contains(s, ":42:29.165")
			},
		},
		{
			name:     "get level from tags",
			message:  map[string]any{},
			tags:     map[string]any{"log_level": "INFO"},
			field:    "level",
			expected: "INFO",
		},
		{
			name:     "get message from tags",
			message:  map[string]any{},
			tags:     map[string]any{"log_message": "test message"},
			field:    "message",
			expected: "test message",
		},
		{
			name:     "get service from tags",
			message:  map[string]any{},
			tags:     map[string]any{"resource_service_name": "cartservice"},
			field:    "service",
			expected: "cartservice",
		},
		{
			name:     "get svc alias for service",
			message:  map[string]any{},
			tags:     map[string]any{"resource_service_name": "myservice"},
			field:    "svc",
			expected: "myservice",
		},
		{
			name:     "get pod from tags",
			message:  map[string]any{},
			tags:     map[string]any{"resource_k8s_pod_name": "my-pod-abc123"},
			field:    "pod",
			expected: "my-pod-abc123",
		},
		{
			name:     "get custom field from tags",
			message:  map[string]any{},
			tags:     map[string]any{"trace_id": "abc123def456"},
			field:    "trace_id",
			expected: "abc123def456",
		},
		{
			name:     "get custom field with dot normalization",
			message:  map[string]any{},
			tags:     map[string]any{"resource_k8s_cluster_name": "my-cluster"},
			field:    "resource.k8s.cluster.name",
			expected: "my-cluster",
		},
		{
			name:     "missing field returns empty",
			message:  map[string]any{},
			tags:     map[string]any{},
			field:    "nonexistent",
			expected: "",
		},
		{
			name:     "nil tags returns empty for custom field",
			message:  map[string]any{},
			tags:     nil,
			field:    "custom_field",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := getFieldValue(tt.message, tt.tags, tt.field)
			if tt.checkFunc != nil {
				if !tt.checkFunc(result) {
					t.Errorf("getFieldValue() = %q, custom check failed", result)
				}
			} else if result != tt.expected {
				t.Errorf("getFieldValue() = %q, want %q", result, tt.expected)
			}
		})
	}
}

func TestEscapeCSV(t *testing.T) {
	tests := []struct {
		name      string
		value     string
		delimiter string
		expected  string
	}{
		{
			name:      "simple value no escaping",
			value:     "hello",
			delimiter: ",",
			expected:  "hello",
		},
		{
			name:      "value with comma needs quotes",
			value:     "hello, world",
			delimiter: ",",
			expected:  `"hello, world"`,
		},
		{
			name:      "value with quotes needs escaping",
			value:     `say "hello"`,
			delimiter: ",",
			expected:  `"say ""hello"""`,
		},
		{
			name:      "value with newline needs quotes",
			value:     "line1\nline2",
			delimiter: ",",
			expected:  "\"line1\nline2\"",
		},
		{
			name:      "value with tab for TSV",
			value:     "hello\tworld",
			delimiter: "\t",
			expected:  "\"hello\tworld\"",
		},
		{
			name:      "TSV value with comma still gets quoted (conservative)",
			value:     "hello, world",
			delimiter: "\t",
			expected:  `"hello, world"`,
		},
		{
			name:      "empty value",
			value:     "",
			delimiter: ",",
			expected:  "",
		},
		{
			name:      "complex message with quotes and commas",
			value:     `Error: "failed to connect", retrying...`,
			delimiter: ",",
			expected:  `"Error: ""failed to connect"", retrying..."`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := escapeCSV(tt.value, tt.delimiter)
			if result != tt.expected {
				t.Errorf("escapeCSV() = %q, want %q", result, tt.expected)
			}
		})
	}
}

func TestFormatCSVRow(t *testing.T) {
	tests := []struct {
		name      string
		values    []string
		delimiter string
		expected  string
	}{
		{
			name:      "simple CSV row",
			values:    []string{"a", "b", "c"},
			delimiter: ",",
			expected:  "a,b,c",
		},
		{
			name:      "CSV row with escaping needed",
			values:    []string{"hello", "world, test", "done"},
			delimiter: ",",
			expected:  `hello,"world, test",done`,
		},
		{
			name:      "TSV row",
			values:    []string{"a", "b", "c"},
			delimiter: "\t",
			expected:  "a\tb\tc",
		},
		{
			name:      "single value",
			values:    []string{"only"},
			delimiter: ",",
			expected:  "only",
		},
		{
			name:      "empty values",
			values:    []string{"", "", ""},
			delimiter: ",",
			expected:  ",,",
		},
		{
			name:      "real log data",
			values:    []string{"2026-02-13 21:42:29.165", "INFO", "cartservice", "GetCartAsync called"},
			delimiter: ",",
			expected:  "2026-02-13 21:42:29.165,INFO,cartservice,GetCartAsync called",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := formatCSVRow(tt.values, tt.delimiter)
			if result != tt.expected {
				t.Errorf("formatCSVRow() = %q, want %q", result, tt.expected)
			}
		})
	}
}

func TestFormatJSONEntry(t *testing.T) {
	tests := []struct {
		name    string
		message map[string]any
		tags    map[string]any
		cols    []string
	}{
		{
			name: "default columns",
			message: map[string]any{
				"timestamp_ns": int64(1771022549165115500),
			},
			tags: map[string]any{
				"log_level":             "INFO",
				"log_message":           "test message",
				"resource_service_name": "testservice",
			},
			cols: []string{"timestamp", "level", "service", "message"},
		},
		{
			name: "custom columns",
			message: map[string]any{
				"timestamp_ns": int64(1771022549165115500),
			},
			tags: map[string]any{
				"log_level":             "ERROR",
				"log_message":           "error occurred",
				"resource_service_name": "errorservice",
				"trace_id":              "abc123",
			},
			cols: []string{"level", "message", "trace_id"},
		},
		{
			name:    "empty tags",
			message: map[string]any{"timestamp": int64(1771022549165)},
			tags:    map[string]any{},
			cols:    []string{"timestamp", "level"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := formatJSONEntry(tt.message, tt.tags, tt.cols)

			// Verify it's valid JSON
			var parsed map[string]any
			if err := json.Unmarshal([]byte(result), &parsed); err != nil {
				t.Errorf("formatJSONEntry() returned invalid JSON: %v", err)
				return
			}

			// Verify all requested columns are present
			for _, col := range tt.cols {
				if _, ok := parsed[col]; !ok {
					t.Errorf("formatJSONEntry() missing column %q in output", col)
				}
			}

			// Verify no extra columns
			if len(parsed) != len(tt.cols) {
				t.Errorf("formatJSONEntry() has %d columns, want %d", len(parsed), len(tt.cols))
			}
		})
	}
}

func TestFormatJSONEntryValues(t *testing.T) {
	message := map[string]any{
		"timestamp_ns": int64(1771022549165115500),
	}
	tags := map[string]any{
		"log_level":             "INFO",
		"log_message":           "GetCartAsync called",
		"resource_service_name": "cartservice",
	}

	result := formatJSONEntry(message, tags, []string{"level", "service", "message"})

	var parsed map[string]any
	if err := json.Unmarshal([]byte(result), &parsed); err != nil {
		t.Fatalf("Failed to parse JSON: %v", err)
	}

	if parsed["level"] != "INFO" {
		t.Errorf("level = %v, want INFO", parsed["level"])
	}
	if parsed["service"] != "cartservice" {
		t.Errorf("service = %v, want cartservice", parsed["service"])
	}
	if parsed["message"] != "GetCartAsync called" {
		t.Errorf("message = %v, want 'GetCartAsync called'", parsed["message"])
	}
}

func TestNormalizeTag(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"resource.service.name", "resource_service_name"},
		{"log.level", "log_level"},
		{"no_dots_here", "no_dots_here"},
		{"a.b.c.d", "a_b_c_d"},
		{"", ""},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			result := normalizeTag(tt.input)
			if result != tt.expected {
				t.Errorf("normalizeTag(%q) = %q, want %q", tt.input, result, tt.expected)
			}
		})
	}
}

func TestGetColorForLevel(t *testing.T) {
	tests := []struct {
		level   string
		noColor bool
		isEmpty bool
	}{
		{"ERROR", false, false},
		{"WARN", false, false},
		{"WARNING", false, false},
		{"INFO", false, false},
		{"DEBUG", false, false},
		{"TRACE", false, false},
		{"UNKNOWN", false, false},
		{"ERROR", true, true},
		{"INFO", true, true},
	}

	for _, tt := range tests {
		t.Run(tt.level, func(t *testing.T) {
			result := getColorForLevel(tt.level, tt.noColor)
			if tt.isEmpty && result != "" {
				t.Errorf("getColorForLevel(%q, %v) = %q, want empty", tt.level, tt.noColor, result)
			}
			if !tt.isEmpty && result == "" {
				t.Errorf("getColorForLevel(%q, %v) returned empty, want color code", tt.level, tt.noColor)
			}
		})
	}
}

// Test that different log levels get different colors
func TestGetColorForLevelDifferentiation(t *testing.T) {
	colors := make(map[string]string)
	levels := []string{"ERROR", "WARN", "INFO", "DEBUG", "TRACE"}

	for _, level := range levels {
		color := getColorForLevel(level, false)
		colors[level] = color
	}

	// ERROR should be red
	if colors["ERROR"] != colorRed {
		t.Errorf("ERROR should be red, got %q", colors["ERROR"])
	}

	// WARN should be yellow
	if colors["WARN"] != colorYellow {
		t.Errorf("WARN should be yellow, got %q", colors["WARN"])
	}

	// INFO should be green
	if colors["INFO"] != colorGreen {
		t.Errorf("INFO should be green, got %q", colors["INFO"])
	}

	// DEBUG should be cyan
	if colors["DEBUG"] != colorCyan {
		t.Errorf("DEBUG should be cyan, got %q", colors["DEBUG"])
	}

	// TRACE should be purple
	if colors["TRACE"] != colorPurple {
		t.Errorf("TRACE should be purple, got %q", colors["TRACE"])
	}
}

// Integration-style tests using real API response structures
func TestFormatRealLogEntries(t *testing.T) {
	for _, entry := range mockLogEntries {
		t.Run(entry.name, func(t *testing.T) {
			// Test JSON formatting
			jsonOut := formatJSONEntry(entry.message, entry.tags, []string{"timestamp", "level", "service", "message"})
			var parsed map[string]any
			if err := json.Unmarshal([]byte(jsonOut), &parsed); err != nil {
				t.Errorf("JSON output is invalid: %v", err)
			}

			// Test CSV formatting
			values := []string{
				getFieldValue(entry.message, entry.tags, "timestamp"),
				getFieldValue(entry.message, entry.tags, "level"),
				getFieldValue(entry.message, entry.tags, "service"),
				getFieldValue(entry.message, entry.tags, "message"),
			}
			csvOut := formatCSVRow(values, ",")
			if csvOut == "" {
				t.Error("CSV output is empty")
			}

			// Verify field extraction works
			level := getFieldValue(entry.message, entry.tags, "level")
			if level == "" {
				t.Error("Failed to extract level from entry")
			}

			service := getFieldValue(entry.message, entry.tags, "service")
			if service == "" {
				t.Error("Failed to extract service from entry")
			}
		})
	}
}

// Test that messages with special characters are properly escaped in CSV
func TestCSVEscapingWithRealMessages(t *testing.T) {
	messagesWithSpecialChars := []string{
		`Error ErrorCode.GENERAL while evaluating flag with key: 'loadgeneratorFloodHomepage'`,
		`Transient error StatusCode.UNAVAILABLE encountered while exporting metrics to otel-demo-otelcol:4317, retrying in 2s.`,
		`GetCartAsync called with userId={userId}`,
		`Connection failed: "timeout exceeded", retrying...`,
		"Multi\nline\nmessage",
	}

	for i, msg := range messagesWithSpecialChars {
		// Sanitize test name by replacing newlines with spaces
		testName := strings.ReplaceAll(msg[:min(20, len(msg))], "\n", " ")
		t.Run(testName, func(t *testing.T) {
			_ = i // use index to silence linter if needed
			escaped := escapeCSV(msg, ",")
			// If the original had special chars, it should be quoted
			if strings.ContainsAny(msg, ",\"\n\r") {
				if !strings.HasPrefix(escaped, `"`) || !strings.HasSuffix(escaped, `"`) {
					t.Errorf("Message with special chars should be quoted: %q", escaped)
				}
			}
		})
	}
}

