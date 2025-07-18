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

package cmd

import (
	"fmt"

	"github.com/lakerunner/cli/cmd/demo"
	"github.com/lakerunner/cli/cmd/logs"
	"github.com/lakerunner/cli/internal/config"
	"github.com/spf13/cobra"
)

var (
	verbose bool
)

var rootCmd = &cobra.Command{
	Use:   "lakerunner",
	Short: "CLI tool to query Lakerunner",
	Long:  `A CLI tool to interact with deployed lakerunner. It currently supports querying logs.`,
	PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
		if cmd.Name() == "help" || cmd.Name() == "demo" {
			return nil
		}

		if cmd.Parent() != nil && cmd.Parent().Name() == "demo" {
			return nil
		}

		cfg := config.Load()
		if err := cfg.Validate(); err != nil {
			return fmt.Errorf("configuration error: %w", err)
		}
		return nil
	},
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "verbose output")

	rootCmd.AddCommand(logs.LogsCmd)
	rootCmd.AddCommand(demo.DemoCmd)
}
