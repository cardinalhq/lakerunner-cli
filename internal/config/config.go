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

package config

import (
	"fmt"
	"os"
)

type Config struct {
	LAKERUNNER_QUERY_URL string
	LAKERUNNER_API_KEY   string
}

func Load() *Config {
	return &Config{
		LAKERUNNER_QUERY_URL: getEnv("LAKERUNNER_QUERY_URL", ""),
		LAKERUNNER_API_KEY:   getEnv("LAKERUNNER_API_KEY", ""),
	}
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func (c *Config) Validate() error {
	if c.LAKERUNNER_QUERY_URL == "" {
		return fmt.Errorf("LAKERUNNER_QUERY_URL environment variable is required")
	}
	if c.LAKERUNNER_API_KEY == "" {
		return fmt.Errorf("LAKERUNNER_API_KEY environment variable is required")
	}
	return nil
}
