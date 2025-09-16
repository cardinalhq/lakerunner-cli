// Copyright 2025 CardinalHQ, Inc
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

package api

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestLogsResponse_UnmarshalJSON(t *testing.T) {
	tests := []struct {
		name     string
		jsonData string
		want     LogsResponse
		wantErr  bool
	}{
		{
			name: "timestamp as integer milliseconds",
			jsonData: `{
				"id": "test-1",
				"type": "event",
				"message": {
					"timestamp": 1704067200000,
					"tags": {
						"level": "INFO",
						"message": "test message"
					}
				}
			}`,
			want: LogsResponse{
				ID:   "test-1",
				Type: "event",
				Message: map[string]any{
					"timestamp": int64(1704067200000),
					"tags": map[string]any{
						"level":   "INFO",
						"message": "test message",
					},
				},
			},
		},
		{
			name: "tsns as integer nanoseconds",
			jsonData: `{
				"id": "test-2",
				"type": "event",
				"message": {
					"tsns": 1704067200123456789,
					"tags": {
						"level": "DEBUG"
					}
				}
			}`,
			want: LogsResponse{
				ID:   "test-2",
				Type: "event",
				Message: map[string]any{
					"tsns": int64(1704067200123456789),
					"tags": map[string]any{
						"level": "DEBUG",
					},
				},
			},
		},
		{
			name: "both timestamp and tsns present",
			jsonData: `{
				"id": "test-3",
				"type": "timeseries",
				"message": {
					"timestamp": 1704067200000,
					"tsns": 1704067200123456789,
					"value": 42.5
				}
			}`,
			want: LogsResponse{
				ID:   "test-3",
				Type: "timeseries",
				Message: map[string]any{
					"timestamp": int64(1704067200000),
					"tsns":      int64(1704067200123456789),
					"value":     42.5,
				},
			},
		},
		{
			name: "timestamp as float (JSON number)",
			jsonData: `{
				"id": "test-4",
				"type": "event",
				"message": {
					"timestamp": 1704067200000.0,
					"tags": {}
				}
			}`,
			want: LogsResponse{
				ID:   "test-4",
				Type: "event",
				Message: map[string]any{
					"timestamp": int64(1704067200000),
					"tags":      map[string]any{},
				},
			},
		},
		{
			name: "large timestamp preserving precision",
			jsonData: `{
				"id": "test-5",
				"type": "event",
				"message": {
					"timestamp": 9999999999999,
					"tsns": 9223372036854775807
				}
			}`,
			want: LogsResponse{
				ID:   "test-5",
				Type: "event",
				Message: map[string]any{
					"timestamp": int64(9999999999999),
					"tsns":      int64(9223372036854775807), // max int64
				},
			},
		},
		{
			name: "mixed field types",
			jsonData: `{
				"id": "test-6",
				"type": "data",
				"message": {
					"timestamp": 1704067200000,
					"string_field": "hello",
					"number_field": 123.45,
					"bool_field": true,
					"null_field": null,
					"array_field": [1, 2, 3],
					"object_field": {"nested": "value"}
				}
			}`,
			want: LogsResponse{
				ID:   "test-6",
				Type: "data",
				Message: map[string]any{
					"timestamp":    int64(1704067200000),
					"string_field": "hello",
					"number_field": 123.45,
					"bool_field":   true,
					"null_field":   nil,
					"array_field":  []any{float64(1), float64(2), float64(3)},
					"object_field": map[string]any{"nested": "value"},
				},
			},
		},
		{
			name: "empty message",
			jsonData: `{
				"id": "test-7",
				"type": "event",
				"message": {}
			}`,
			want: LogsResponse{
				ID:      "test-7",
				Type:    "event",
				Message: map[string]any{},
			},
		},
		{
			name: "no message field",
			jsonData: `{
				"id": "test-8",
				"type": "event"
			}`,
			want: LogsResponse{
				ID:      "test-8",
				Type:    "event",
				Message: nil,
			},
		},
		{
			name: "timestamp as string (fallback to standard unmarshaling)",
			jsonData: `{
				"id": "test-9",
				"type": "event",
				"message": {
					"timestamp": "not-a-number",
					"tsns": "also-not-a-number"
				}
			}`,
			want: LogsResponse{
				ID:   "test-9",
				Type: "event",
				Message: map[string]any{
					"timestamp": "not-a-number",
					"tsns":      "also-not-a-number",
				},
			},
		},
		{
			name: "negative timestamps",
			jsonData: `{
				"id": "test-10",
				"type": "event",
				"message": {
					"timestamp": -1704067200000,
					"tsns": -1704067200123456789
				}
			}`,
			want: LogsResponse{
				ID:   "test-10",
				Type: "event",
				Message: map[string]any{
					"timestamp": int64(-1704067200000),
					"tsns":      int64(-1704067200123456789),
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var got LogsResponse
			err := json.Unmarshal([]byte(tt.jsonData), &got)

			if (err != nil) != tt.wantErr {
				t.Errorf("UnmarshalJSON() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if !deepEqual(got, tt.want) {
				t.Errorf("UnmarshalJSON() = %+v, want %+v", got, tt.want)

				// Print detailed field comparison for debugging
				if !reflect.DeepEqual(got.ID, tt.want.ID) {
					t.Errorf("  ID: got %v, want %v", got.ID, tt.want.ID)
				}
				if !reflect.DeepEqual(got.Type, tt.want.Type) {
					t.Errorf("  Type: got %v, want %v", got.Type, tt.want.Type)
				}
				if !reflect.DeepEqual(got.Message, tt.want.Message) {
					t.Errorf("  Message: got %v, want %v", got.Message, tt.want.Message)

					// Check specific timestamp fields
					if got.Message != nil && tt.want.Message != nil {
						if gotTS, ok := got.Message["timestamp"]; ok {
							if wantTS, wok := tt.want.Message["timestamp"]; wok {
								t.Errorf("    timestamp: got %T(%v), want %T(%v)", gotTS, gotTS, wantTS, wantTS)
							}
						}
						if gotTS, ok := got.Message["tsns"]; ok {
							if wantTS, wok := tt.want.Message["tsns"]; wok {
								t.Errorf("    tsns: got %T(%v), want %T(%v)", gotTS, gotTS, wantTS, wantTS)
							}
						}
					}
				}
			}
		})
	}
}

func TestLogsResponse_TimestampPrecision(t *testing.T) {
	// Test that we can handle the maximum int64 values without loss of precision
	maxInt64 := int64(9223372036854775807)
	jsonData := `{
		"id": "max-test",
		"type": "event",
		"message": {
			"timestamp": 9223372036854775807,
			"tsns": 9223372036854775807
		}
	}`

	var got LogsResponse
	err := json.Unmarshal([]byte(jsonData), &got)
	if err != nil {
		t.Fatalf("Failed to unmarshal: %v", err)
	}

	if ts, ok := got.Message["timestamp"].(int64); !ok || ts != maxInt64 {
		t.Errorf("timestamp precision lost: got %v (%T), want %v", got.Message["timestamp"], got.Message["timestamp"], maxInt64)
	}

	if ts, ok := got.Message["tsns"].(int64); !ok || ts != maxInt64 {
		t.Errorf("tsns precision lost: got %v (%T), want %v", got.Message["tsns"], got.Message["tsns"], maxInt64)
	}
}

// deepEqual performs a deep comparison that handles the any/interface{} type properly
func deepEqual(a, b LogsResponse) bool {
	if a.ID != b.ID || a.Type != b.Type {
		return false
	}

	// Handle nil cases
	if a.Message == nil && b.Message == nil {
		return true
	}
	if a.Message == nil || b.Message == nil {
		return false
	}

	// Check map lengths
	if len(a.Message) != len(b.Message) {
		return false
	}

	// Compare each key-value pair
	for key, aVal := range a.Message {
		bVal, ok := b.Message[key]
		if !ok {
			return false
		}

		// Use reflect.DeepEqual for nested structures
		if !reflect.DeepEqual(aVal, bVal) {
			return false
		}
	}

	return true
}