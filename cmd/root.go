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
