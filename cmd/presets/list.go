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
	"sort"

	internalPresets "github.com/lakerunner/cli/internal/presets"
	"github.com/spf13/cobra"
)

var ListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all configured presets",
	RunE:  runListCmd,
	Args:  cobra.NoArgs,
}

func runListCmd(_ *cobra.Command, _ []string) error {
	cfg, err := internalPresets.Load()
	if err != nil {
		return err
	}

	if len(cfg.Presets) == 0 {
		fmt.Println("No presets configured. Add presets to ~/.lakerunner/config.yaml")
		return nil
	}

	names := make([]string, 0, len(cfg.Presets))
	for name := range cfg.Presets {
		names = append(names, name)
	}
	sort.Strings(names)

	for i, name := range names {
		fmt.Println(name)
		for _, filter := range cfg.Presets[name] {
			fmt.Printf("  - %s\n", filter)
		}
		if i < len(names)-1 {
			fmt.Println()
		}
	}

	return nil
}
