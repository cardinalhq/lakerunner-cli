package config

import (
	"fmt"
	"os"
)

type Config struct {
	APIURL string
	APIKey string
}

func Load() *Config {
	return &Config{
		APIURL: getEnv("API_URL", ""),
		APIKey: getEnv("API_KEY", ""),
	}
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func (c *Config) Validate() error {
	if c.APIURL == "" {
		return fmt.Errorf("API_URL environment variable is required")
	}
	if c.APIKey == "" {
		return fmt.Errorf("API_KEY environment variable is required")
	}
	return nil
}
