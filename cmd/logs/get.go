package logs

import (
	"github.com/spf13/cobra"
)

var (
	messageRegex string
	limit        int
)

var GetCmd = &cobra.Command{
	Use:   "get",
	Short: "Retrieve logs with filters",
	Run: func(cmd *cobra.Command, args []string) {
		cmd.Println("logs get command ")
	},
}

func init() {
	GetCmd.Flags().StringVar(&messageRegex, "message-regex", "", "Filter logs by message regex pattern")
	GetCmd.Flags().IntVar(&limit, "limit", 1000, "Limit the number of results returned")
}
