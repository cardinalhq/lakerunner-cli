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

import "testing"

func TestBuildTagValuesQuery(t *testing.T) {
	tests := []struct {
		name     string
		appName  string
		logLevel string
		filters  []string
		expected string
	}{
		{
			name:     "app name only",
			appName:  "myapp",
			expected: `{service_name="myapp"}`,
		},
		{
			name:     "log level only",
			logLevel: "ERROR",
			expected: `{level="ERROR"}`,
		},
		{
			name:     "app and level",
			appName:  "myapp",
			logLevel: "WARN",
			expected: `{service_name="myapp", level="WARN"}`,
		},
		{
			name:     "single filter",
			filters:  []string{"env:prod"},
			expected: `{env="prod"}`,
		},
		{
			name:     "all combined",
			appName:  "myapp",
			logLevel: "ERROR",
			filters:  []string{"env:prod", "region:us-west-2"},
			expected: `{service_name="myapp", level="ERROR", env="prod", region="us-west-2"}`,
		},
		{
			name:     "no conditions",
			expected: "",
		},
		{
			name:     "dot normalization in app name",
			appName:  "my.app",
			expected: `{service_name="my_app"}`,
		},
		{
			name:     "dot normalization in filter key and value",
			filters:  []string{"k8s.namespace:my.namespace"},
			expected: `{k8s_namespace="my_namespace"}`,
		},
		{
			name:     "malformed filter ignored",
			filters:  []string{"invalid"},
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := buildTagValuesQuery(tt.appName, tt.logLevel, tt.filters)
			if result != tt.expected {
				t.Errorf("buildTagValuesQuery() = %q, want %q", result, tt.expected)
			}
		})
	}
}
