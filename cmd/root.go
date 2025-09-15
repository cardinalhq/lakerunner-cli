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
	"os"
	"runtime"

	"github.com/lakerunner/cli/cmd/demo"
	"github.com/lakerunner/cli/cmd/logs"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)


var rootCmd = &cobra.Command{
	Use:   "lakerunner",
	Short: "CLI tool to query Lakerunner",
	Long:  `A CLI tool to interact with deployed lakerunner. It currently supports querying logs.`,
	PersistentPreRun: func(cmd *cobra.Command, args []string) {
		// Automatically disable colors on Windows or when not in a terminal
		noColor, _ := cmd.Flags().GetBool("no-color")
		if !noColor {
			if runtime.GOOS == "windows" || !term.IsTerminal(int(os.Stdout.Fd())) {
				cmd.Flags().Set("no-color", "true")
			}
		}
	},
}

func Execute() error {
	return rootCmd.Execute()
}


func init() {
	rootCmd.PersistentFlags().BoolP("verbose", "v", false, "verbose output")
	rootCmd.PersistentFlags().BoolP("quiet", "q", false, "suppress informational output")
	rootCmd.PersistentFlags().Bool("no-color", false, "disable colored output")
	rootCmd.PersistentFlags().String("endpoint", "", "API endpoint URL (overrides LAKERUNNER_QUERY_URL)")
	rootCmd.PersistentFlags().String("api-key", "", "API key (overrides LAKERUNNER_API_KEY)")

	rootCmd.AddCommand(logs.LogsCmd)
	rootCmd.AddCommand(demo.DemoCmd)
}
