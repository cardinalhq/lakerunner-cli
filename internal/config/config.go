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
