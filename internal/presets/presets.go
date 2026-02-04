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

package presets

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Presets map[string][]string `yaml:"presets"`
}

func configPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".lakerunner", "config.yaml")
}

func Load() (*Config, error) {
	path := configPath()
	if path == "" {
		return &Config{Presets: make(map[string][]string)}, nil
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return &Config{Presets: make(map[string][]string)}, nil
		}
		return nil, fmt.Errorf("failed to read config file: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config file: %w", err)
	}

	if cfg.Presets == nil {
		cfg.Presets = make(map[string][]string)
	}

	return &cfg, nil
}

func GetFilters(presetName string) ([]string, error) {
	cfg, err := Load()
	if err != nil {
		return nil, err
	}

	filters, ok := cfg.Presets[presetName]
	if !ok {
		return nil, fmt.Errorf("preset '%s' not found in %s", presetName, configPath())
	}

	return filters, nil
}
