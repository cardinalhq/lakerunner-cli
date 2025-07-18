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

package logs

import (
	"fmt"
	"log/slog"
	"os"

	"github.com/lakerunner/cli/internal/api"
	"github.com/lakerunner/cli/internal/config"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)

var AttributesCmd = &cobra.Command{
	Use:   "get-attr",
	Short: "Retrieve log attributes",
	Long:  `Retrieve unique log attributes with optional filters.`,
	RunE:  runAttributesCmd,
	Args:  cobra.ExactArgs(1),
}

func init() {
	AttributesCmd.Flags().StringSliceVarP(&filters, "filter", "f", []string{}, "Filter in format 'key:value' (can be used multiple times)")
	AttributesCmd.Flags().StringSliceVarP(&regexFilters, "regex", "r", []string{}, "Regex filter in format 'key:value' (can be used multiple times)")
}

func runAttributesCmd(_ *cobra.Command, targets []string) error {
	if !term.IsTerminal(int(os.Stdout.Fd())) {
		noColor = true
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}
	client := api.NewClient(cfg)

	//  POST /api/v1/tags/logs?s=e-1h&e=now

	//  POST /api/v1/tags/logs?s=e-1h&e=now&tagName=resource.service.name&dataType=string

	// POST /api/v1/tags/logs?s=e-1h&e=now
	// {
	//     "dataset": "logs",
	//     "limit": 1000,
	//     "order": "DESC",
	//     "returnResults": true,
	//     "filter": {
	//         "k": "resource.service.name",
	//         "v": [
	//             "query-api"
	//         ],
	//         "op": "eq",
	//         "dataType": "string",
	//         "extracted": false,
	//         "computed": false
	//     }
	// }

	for _, target := range targets {

		slog.Info("Retrieving attributes for target", slog.String("target", target))
	}

	return nil
}
