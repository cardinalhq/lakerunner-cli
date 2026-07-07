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

package config

import (
	"fmt"
	"os"
	"strconv"

	"github.com/joho/godotenv"
)

type Config struct {
	LAKERUNNER_QUERY_URL string
	LAKERUNNER_API_KEY   string
	// Insecure skips TLS certificate verification. Use only for endpoints
	// with a self-signed certificate (e.g. a CloudFormation install whose
	// ALB has no real cert). Equivalent to curl -k.
	Insecure bool
}

func Load() (*Config, error) {
	// Try to load .env file, but don't fail if it doesn't exist
	_ = godotenv.Load()

	cfg := &Config{
		LAKERUNNER_QUERY_URL: getEnv("LAKERUNNER_QUERY_URL", ""),
		LAKERUNNER_API_KEY:   getEnv("LAKERUNNER_API_KEY", ""),
		Insecure:             getEnvBool("LAKERUNNER_INSECURE"),
	}
	return cfg, cfg.Validate()
}

// LoadWithFlags loads configuration with optional flag overrides
func LoadWithFlags(endpointFlag, apiKeyFlag string, insecureFlag bool) (*Config, error) {
	// Try to load .env file, but don't fail if it doesn't exist
	_ = godotenv.Load()

	cfg := &Config{
		LAKERUNNER_QUERY_URL: getEnvOrFlag("LAKERUNNER_QUERY_URL", endpointFlag),
		LAKERUNNER_API_KEY:   getEnvOrFlag("LAKERUNNER_API_KEY", apiKeyFlag),
		Insecure:             insecureFlag || getEnvBool("LAKERUNNER_INSECURE"),
	}
	return cfg, cfg.Validate()
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

// getEnvOrFlag returns flag value if provided, otherwise falls back to environment variable
func getEnvOrFlag(envKey, flagValue string) string {
	if flagValue != "" {
		return flagValue
	}
	return getEnv(envKey, "")
}

// getEnvBool parses a boolean environment variable (e.g. "1", "true"); unset or
// unparseable is false.
func getEnvBool(key string) bool {
	v, err := strconv.ParseBool(os.Getenv(key))
	return err == nil && v
}

func (c *Config) Validate() error {
	if c.LAKERUNNER_QUERY_URL == "" {
		return fmt.Errorf("API endpoint is required: set LAKERUNNER_QUERY_URL environment variable or use --endpoint flag")
	}
	if c.LAKERUNNER_API_KEY == "" {
		return fmt.Errorf("API key is required: set LAKERUNNER_API_KEY environment variable or use --api-key flag")
	}
	return nil
}
