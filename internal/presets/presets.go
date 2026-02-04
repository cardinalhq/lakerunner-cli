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
	"strings"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"
)

type Config struct {
	Presets map[string][]string `yaml:"presets"`
	Aliases map[string]string   `yaml:"aliases"`
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
		return &Config{Presets: make(map[string][]string), Aliases: make(map[string]string)}, nil
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return &Config{Presets: make(map[string][]string), Aliases: make(map[string]string)}, nil
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
	if cfg.Aliases == nil {
		cfg.Aliases = make(map[string]string)
	}

	return &cfg, nil
}

// ResolveFilters expands any aliased keys in the given filters.
// A filter "i:prod" with alias i->resource_installation becomes "resource_installation:prod".
func ResolveFilters(filters []string) ([]string, error) {
	cfg, err := Load()
	if err != nil {
		return nil, err
	}
	if len(cfg.Aliases) == 0 {
		return filters, nil
	}
	resolved := make([]string, len(filters))
	for i, f := range filters {
		parts := strings.SplitN(f, ":", 2)
		if len(parts) == 2 {
			if full, ok := cfg.Aliases[parts[0]]; ok {
				resolved[i] = full + ":" + parts[1]
				continue
			}
		}
		resolved[i] = f
	}
	return resolved, nil
}

// RegisterAliasFlags registers user-defined aliases as CLI flags on the given command.
// Single-char aliases become short flags (e.g., -i for resource_installation).
// Multi-char aliases become long flags (e.g., --svc for resource_service_name).
// Returns a map of fullKey -> value pointer for use with CollectAliasFilters.
func RegisterAliasFlags(cmd *cobra.Command) map[string]*string {
	cfg, err := Load()
	if err != nil || len(cfg.Aliases) == 0 {
		return nil
	}
	values := make(map[string]*string)
	for alias, fullKey := range cfg.Aliases {
		val := new(string)
		longName := strings.ReplaceAll(fullKey, "_", "-")
		desc := fmt.Sprintf("Filter by %s", fullKey)

		if len(alias) == 1 {
			// Single-char alias: register as short flag with full key as long name
			if cmd.Flags().ShorthandLookup(alias) != nil || cmd.Flags().Lookup(longName) != nil {
				continue
			}
			cmd.Flags().StringVarP(val, longName, alias, "", desc)
		} else {
			// Multi-char alias: register as long flag
			if cmd.Flags().Lookup(alias) != nil {
				continue
			}
			cmd.Flags().StringVar(val, alias, "", desc)
		}
		values[fullKey] = val
	}
	return values
}

// CollectAliasFilters returns filters from alias flags that were set by the user.
func CollectAliasFilters(values map[string]*string) []string {
	var filters []string
	for fullKey, val := range values {
		if val != nil && *val != "" {
			filters = append(filters, fullKey+":"+*val)
		}
	}
	return filters
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
