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

package aliases

import (
	"fmt"
	"sort"

	"github.com/lakerunner/cli/internal/presets"
	"github.com/spf13/cobra"
)

var ListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all configured filter aliases",
	RunE:  runListCmd,
	Args:  cobra.NoArgs,
}

func runListCmd(_ *cobra.Command, _ []string) error {
	cfg, err := presets.Load()
	if err != nil {
		return err
	}

	if len(cfg.Aliases) == 0 {
		fmt.Println("No aliases configured. Add aliases to ~/.lakerunner/config.yaml")
		return nil
	}

	keys := make([]string, 0, len(cfg.Aliases))
	for k := range cfg.Aliases {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	for _, k := range keys {
		fmt.Printf("%s -> %s\n", k, cfg.Aliases[k])
	}

	return nil
}
