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
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/lakerunner/cli/internal/api"
	"github.com/lakerunner/cli/internal/config"
	"github.com/spf13/cobra"
	"golang.org/x/term"
)

// Color constants
const (
	colorReset  = "\033[0m"
	colorRed    = "\033[31m"
	colorGreen  = "\033[32m"
	colorYellow = "\033[33m"
	colorBlue   = "\033[34m"
	colorPurple = "\033[35m"
	colorCyan   = "\033[36m"
	colorWhite  = "\033[37m"
	colorBold   = "\033[1m"
)

// getColorForLevel returns the appropriate color for a log level
func getColorForLevel(level string) string {
	if noColor {
		return ""
	}
	switch strings.ToUpper(level) {
	case "ERROR":
		return colorRed
	case "WARN", "WARNING":
		return colorYellow
	case "INFO":
		return colorGreen
	case "DEBUG":
		return colorCyan
	case "TRACE":
		return colorPurple
	default:
		return colorWhite
	}
}

var (
	messageRegex string
	limit        int
	filters      []string
	regexFilters []string
	startTime    string
	endTime      string
	noColor      bool
	appName      string
)

func init() {
	GetCmd.Flags().StringVarP(&messageRegex, "message-regex", "m", "", "Filter logs by message regex pattern")
	GetCmd.Flags().IntVarP(&limit, "limit", "l", 1000, "Limit the number of results returned")
	GetCmd.Flags().StringSliceVarP(&filters, "filter", "f", []string{}, "Filter in format 'key:value' (can be used multiple times)")
	GetCmd.Flags().StringSliceVarP(&regexFilters, "regex", "r", []string{}, "Regex filter in format 'key:value' (can be used multiple times)")
	GetCmd.Flags().StringVarP(&startTime, "start", "s", "", "Start time (e.g., 'e-1h', '2024-01-01T00:00:00Z')")
	GetCmd.Flags().StringVarP(&endTime, "end", "e", "", "End time (e.g., 'now', '2024-01-01T23:59:59Z')")
	GetCmd.Flags().BoolVar(&noColor, "no-color", false, "Disable colored output")
	GetCmd.Flags().StringVarP(&appName, "app", "a", "", "Filter logs by application/service name")
}

var GetCmd = &cobra.Command{
	Use:   "get",
	Short: "Retrieve logs with filters",
	RunE:  runGetCmd,
}

func runGetCmd(_ *cobra.Command, _ []string) error {
	if !term.IsTerminal(int(os.Stdout.Fd())) {
		noColor = true
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}
	client := api.NewClient(cfg)

	// Set default time range if not provided
	if startTime == "" {
		startTime = "e-4h" // Changed from e-1h to e-4h to get more logs
	}
	if endTime == "" {
		endTime = "now"
	}

	// Start with default filter for resource.service.name
	var filterObj *api.Filter

	// If app flag is provided, use it to filter by resource.service.name
	if appName != "" {
		filterObj = api.CreateFilter("resource.service.name", "eq", "string", []string{appName})
	} else {
		filterObj = api.CreateFilter("resource.service.name", "has", "string", []string{""})
	}

	// Collect all filters
	allFilters := []*api.Filter{}

	// Add multiple filters if provided
	for _, f := range filters {
		parts := strings.SplitN(f, ":", 2)
		if len(parts) != 2 {
			return fmt.Errorf("filter must be in format 'key:value'")
		}

		// Determine if this is a regex pattern
		operation := "eq"
		if strings.Contains(parts[1], "\\") || strings.Contains(parts[1], ".*") || strings.Contains(parts[1], "^") || strings.Contains(parts[1], "$") {
			operation = "regex"
		}

		allFilters = append(allFilters, api.CreateFilter(parts[0], operation, "string", []string{parts[1]}))
	}

	// Add regex filters if provided
	for _, f := range regexFilters {
		parts := strings.SplitN(f, ":", 2)
		if len(parts) != 2 {
			return fmt.Errorf("regex filter must be in format 'key:value'")
		}

		allFilters = append(allFilters, api.CreateFilter(parts[0], "regex", "string", []string{parts[1]}))
	}

	// If we have custom filters, create nested filter
	if len(allFilters) > 0 {
		// Check if any filter is for resource.service.name and replace default
		for i, f := range allFilters {
			if f.K == "resource.service.name" {
				filterObj = f
				allFilters = append(allFilters[:i], allFilters[i+1:]...)
				break
			}
		}

		// Add remaining filters as nested conditions
		if len(allFilters) > 0 {
			allFilters = append([]*api.Filter{filterObj}, allFilters...)
			filterObj = api.CreateNestedFilter(allFilters...)
		}
	}

	expression := api.CreateExpression("logs", limit, filterObj, nil)
	expressions := map[string]api.Expression{
		"a": expression,
	}

	req := api.CreateGraphRequest(expressions)
	params := api.CreateQueryParams(startTime, endTime, "", "")

	// Create context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second) // Increased timeout for streaming
	defer cancel()

	responseChan, err := client.QueryGraph(ctx, req, params)
	if err != nil {
		return fmt.Errorf("failed to query logs: %w", err)
	}

	// Display results
	fmt.Printf("Querying logs from %s to %s...\n", startTime, endTime)
	if appName != "" {
		fmt.Printf("App Filter: resource.service.name = %s\n", appName)
	}
	if len(filters) > 0 || len(regexFilters) > 0 {
		for _, f := range filters {
			fmt.Printf("Filter: %s\n", f)
		}
		for _, f := range regexFilters {
			fmt.Printf("Regex Filter: %s\n", f)
		}
	} else if appName == "" {
		fmt.Printf("Filter: resource.service.name has *\n")
	}
	fmt.Printf("Limit: %d results\n", limit)
	fmt.Println("---")

	responseCount := 0
	startTime := time.Now()

	// Start a goroutine to show progress
	progressTicker := time.NewTicker(2 * time.Second)
	defer progressTicker.Stop()

	go func() {
		for range progressTicker.C {
			if responseCount == 0 {
				elapsed := time.Since(startTime)
				fmt.Fprintf(os.Stderr, "\rWaiting for logs... (%v elapsed)", elapsed.Round(time.Second))
			}
		}
	}()

	for response := range responseChan {
		responseCount++

		// Clear progress line when we get first response
		if responseCount == 1 {
			fmt.Fprintf(os.Stderr, "\r%s\r", strings.Repeat(" ", 50))
		}

		if response.Type == "timeseries" || response.Type == "event" || response.Type == "data" {
			// Extract key log information
			message := response.Message

			// Get timestamp
			timestamp := ""
			if ts, ok := message["timestamp"].(float64); ok {
				timestamp = time.Unix(int64(ts)/1000, 0).Format("2006-01-02 15:04:05")
			}

			// Get log message
			logMessage := ""
			if tags, ok := message["tags"].(map[string]interface{}); ok {
				if msg, ok := tags["_cardinalhq.message"].(string); ok {
					logMessage = msg
				}
			}

			// Get service name
			serviceName := ""
			if tags, ok := message["tags"].(map[string]interface{}); ok {
				if service, ok := tags["resource.service.name"].(string); ok {
					serviceName = service
				}
			}

			// Get log level
			logLevel := ""
			if tags, ok := message["tags"].(map[string]interface{}); ok {
				if level, ok := tags["_cardinalhq.level"].(string); ok {
					logLevel = level
				}
			}

			// Get pod name
			podName := ""
			if tags, ok := message["tags"].(map[string]interface{}); ok {
				if pod, ok := tags["resource.k8s.pod.name"].(string); ok {
					podName = pod
				}
			}

			// Format the output with colors
			levelColor := getColorForLevel(logLevel)
			timestampColor := colorBlue
			serviceColor := colorCyan
			podColor := colorPurple

			if noColor {
				fmt.Printf("[%s] %s %s %s: %s\n",
					timestamp, logLevel, serviceName, podName, logMessage)
			} else {
				fmt.Printf("[%s%s%s] %s%s%s %s%s%s %s%s%s: %s\n",
					timestampColor, timestamp, colorReset,
					levelColor, logLevel, colorReset,
					serviceColor, serviceName, colorReset,
					podColor, podName, colorReset,
					logMessage)
			}

			// Early termination if we've reached the limit
			if responseCount >= limit {
				break
			}
		}
	}

	if responseCount == 0 {
		fmt.Println("No responses received from the API")
	}

	return nil
}
