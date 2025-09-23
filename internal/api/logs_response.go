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

import "encoding/json"

// LogsResponse represents a response from the logs endpoint
type LogsResponse struct {
	ID      string         `json:"id"`
	Type    string         `json:"type"`
	Message map[string]any `json:"message"`
}

// UnmarshalJSON implements custom JSON unmarshaling to preserve timestamp precision
func (lr *LogsResponse) UnmarshalJSON(data []byte) error {
	// Use a temporary struct for standard fields
	type Alias LogsResponse
	aux := &struct {
		*Alias
		Message json.RawMessage `json:"message"`
	}{
		Alias: (*Alias)(lr),
	}

	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}

	// Now handle the message field specially
	if len(aux.Message) > 0 {
		// First unmarshal into a temporary map to check for timestamp fields
		var tempMsg map[string]json.RawMessage
		if err := json.Unmarshal(aux.Message, &tempMsg); err != nil {
			return err
		}

		// Initialize the final message map
		lr.Message = make(map[string]any)

		// Process each field
		for key, rawValue := range tempMsg {
			if key == "timestamp" || key == "tsns" {
				// Try to unmarshal as int64 first
				var intVal int64
				if err := json.Unmarshal(rawValue, &intVal); err == nil {
					lr.Message[key] = intVal
				} else {
					// Fall back to float64 if it's not an integer
					var floatVal float64
					if err := json.Unmarshal(rawValue, &floatVal); err == nil {
						lr.Message[key] = int64(floatVal)
					} else {
						// If neither works, unmarshal as generic interface{}
						var val any
						if err := json.Unmarshal(rawValue, &val); err != nil {
							return err
						}
						lr.Message[key] = val
					}
				}
			} else {
				// For all other fields, use standard unmarshaling
				var val any
				if err := json.Unmarshal(rawValue, &val); err != nil {
					return err
				}
				lr.Message[key] = val
			}
		}
	}

	return nil
}