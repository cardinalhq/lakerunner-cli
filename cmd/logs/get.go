package logs

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/lakerunner/cli/internal/api"
	"github.com/lakerunner/cli/internal/config"
	"github.com/spf13/cobra"
)

var (
	messageRegex string
	limit        int
	filter       string
	startTime    string
	endTime      string
)

var GetCmd = &cobra.Command{
	Use:   "get",
	Short: "Retrieve logs with filters",
	RunE: func(cmd *cobra.Command, args []string) error {
		cfg := config.Load()
		client := api.NewClient(cfg)

		// Parse filter if provided
		var filterObj *api.Filter
		if filter != "" {
			parts := strings.SplitN(filter, ":", 2)
			if len(parts) != 2 {
				return fmt.Errorf("filter must be in format 'key:value'")
			}
			filterObj = api.CreateFilter(parts[0], "has", "string", []string{parts[1]})
		}

		// Set default time range if not provided
		if startTime == "" {
			startTime = "e-1h"
		}
		if endTime == "" {
			endTime = "now"
		}

		req := api.CreateLogsRequest("logs", limit, filterObj)
		params := api.CreateQueryParams(startTime, endTime, "", "")

		// Create context with timeout
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()

		responseChan, err := client.QueryLogs(ctx, req, params)
		if err != nil {
			return fmt.Errorf("failed to query logs: %w", err)
		}

		// Display results
		fmt.Printf("Querying logs from %s to %s...\n", startTime, endTime)
		if filterObj != nil {
			fmt.Printf("Filter: %s:%s\n", filterObj.K, filterObj.V[0])
		}
		fmt.Println("---")

		for response := range responseChan {
			if response.Type == "data" {
				// Pretty print the message
				messageJSON, err := json.MarshalIndent(response.Message, "", "  ")
				if err != nil {
					fmt.Printf("Error formatting response: %v\n", err)
					continue
				}
				fmt.Printf("%s\n", string(messageJSON))
			}
		}

		return nil
	},
}

func init() {
	GetCmd.Flags().StringVar(&messageRegex, "message-regex", "", "Filter logs by message regex pattern")
	GetCmd.Flags().IntVar(&limit, "limit", 1000, "Limit the number of results returned")
	GetCmd.Flags().StringVar(&filter, "filter", "", "Filter in format 'key:value' (e.g., 'log.telemetry_type:logs')")
	GetCmd.Flags().StringVar(&startTime, "start", "", "Start time (e.g., 'e-1h', '2024-01-01T00:00:00Z')")
	GetCmd.Flags().StringVar(&endTime, "end", "", "End time (e.g., 'now', '2024-01-01T23:59:59Z')")
}
