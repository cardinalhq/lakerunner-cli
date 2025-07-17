package demo

import (
	"github.com/spf13/cobra"
)

var DemoCmd = &cobra.Command{
	Use:   "demo",
	Short: "Demo commands for setting up test environments",
}

func init() {
	DemoCmd.AddCommand(SetupCmd)
}
