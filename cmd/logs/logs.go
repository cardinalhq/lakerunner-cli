package logs

import (
	"github.com/spf13/cobra"
)

var LogsCmd = &cobra.Command{
	Use:   "logs",
	Short: "Commands for querying logs",
}

func init() {
	LogsCmd.AddCommand(GetCmd)
}
