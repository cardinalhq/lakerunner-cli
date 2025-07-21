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

	"github.com/cardinalhq/oteltools/pkg/dateutils"
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
	logLevel     string
	columns      string
)

func init() {
	GetCmd.Flags().StringVarP(&messageRegex, "message-regex", "m", "", "Filter logs by message regex pattern")
	GetCmd.Flags().IntVar(&limit, "limit", 1000, "Limit the number of results returned")
	GetCmd.Flags().StringSliceVarP(&filters, "filter", "f", []string{}, "Filter in format 'key:value' (can be used multiple times)")
	GetCmd.Flags().StringSliceVarP(&regexFilters, "regex", "r", []string{}, "Regex filter in format 'key:value' (can be used multiple times)")
	GetCmd.Flags().StringVarP(&startTime, "start", "s", "", "Start time (e.g., 'e-1h', '2024-01-01T00:00:00Z')")
	GetCmd.Flags().StringVarP(&endTime, "end", "e", "", "End time (e.g., 'now', '2024-01-01T23:59:59Z')")
	GetCmd.Flags().BoolVar(&noColor, "no-color", false, "Disable colored output")
	GetCmd.Flags().StringVarP(&appName, "app", "a", "", "Filter logs by application/service name")
	GetCmd.Flags().StringVarP(&logLevel, "level", "l", "", "Filter logs by log level (e.g., ERROR, INFO, DEBUG, WARN)")
	GetCmd.Flags().StringVarP(&columns, "columns", "c", "", "Comma or space separated columns to display (e.g., 'timestamp,level,message' or 'timestamp level message')")
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

	var selectedColumns []string
	if columns != "" {
		parts := strings.Split(columns, ",")
		for _, part := range parts {
			part = strings.TrimSpace(part)
			if part != "" {
				spaceParts := strings.Fields(part)
				for _, spacePart := range spaceParts {
					spacePart = strings.TrimSpace(spacePart)
					if spacePart != "" {
						selectedColumns = append(selectedColumns, spacePart)
					}
				}
			}
		}
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}
	client := api.NewClient(cfg)

	// Parse start and end times using dateutils
	startMs, endMs, err := dateutils.ToStartEnd(startTime, endTime)
	if err != nil {
		return fmt.Errorf("failed to parse time range: %w", err)
	}

	// Convert milliseconds to ISO8601 format for API
	startTimeStr := time.UnixMilli(startMs).UTC().Format(time.RFC3339)
	endTimeStr := time.UnixMilli(endMs).UTC().Format(time.RFC3339)

	// Start with default filter for resource.service.name
	var filterObj *api.Filter

	// If app flag is provided, use it to filter by resource.service.name
	if appName != "" {
		filterObj = api.CreateFilter("resource.service.name", "eq", "string", []string{appName})
	} else {
		filterObj = api.CreateFilter("resource.service.name", "has", "string", []string{""})
	}

	if logLevel != "" {
		levelFilter := api.CreateFilter("_cardinalhq.level", "eq", "string", []string{logLevel})

		if appName != "" {
			filterObj = api.CreateNestedFilter(filterObj, levelFilter)
		} else {
			filterObj = levelFilter
		}
	}

	// Add message regex filter if provided
	if messageRegex != "" {
		messageFilter := api.CreateFilter("_cardinalhq.message", "regex", "string", []string{messageRegex})

		if filterObj != nil {
			filterObj = api.CreateNestedFilter(filterObj, messageFilter)
		} else {
			filterObj = messageFilter
		}
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
	params := api.CreateQueryParams(startTimeStr, endTimeStr, "", "")

	// Create context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second) // Increased timeout for streaming
	defer cancel()

	responseChan, err := client.QueryGraph(ctx, req, params)
	if err != nil {
		return fmt.Errorf("failed to query logs: %w", err)
	}

	// Display results
	fmt.Printf("Querying logs from %s to %s...\n", startTimeStr, endTimeStr)
	if appName != "" {
		fmt.Printf("App Filter: resource.service.name = %s\n", appName)
	}
	if logLevel != "" {
		fmt.Printf("Level Filter: level = %s\n", logLevel)
	}
	if messageRegex != "" {
		fmt.Printf("Message Regex Filter: _cardinalhq.message = %s\n", messageRegex)
	}
	if len(filters) > 0 || len(regexFilters) > 0 {
		for _, f := range filters {
			fmt.Printf("Filter: %s\n", f)
		}
		for _, f := range regexFilters {
			fmt.Printf("Regex Filter: %s\n", f)
		}
	}
	fmt.Printf("Limit: %d results\n", limit)
	if len(selectedColumns) > 0 {
		fmt.Printf("Columns: %v\n", selectedColumns)
	}
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

			// If columns are specified, show only those columns
			if len(selectedColumns) > 0 {
				var outputParts []string

				for _, col := range selectedColumns {
					var value string
					var color string

					switch strings.ToLower(col) {
					case "timestamp":
						value = timestamp
						color = colorBlue
					case "level":
						value = logLevel
						color = getColorForLevel(logLevel)
					case "message":
						value = logMessage
						color = colorReset
					case "service":
						value = serviceName
						color = colorCyan
					case "pod":
						value = podName
						color = colorPurple
					default:
						// Try to find the value in tags, with _cardinalhq prefix mapping
						if tags, ok := message["tags"].(map[string]interface{}); ok {
							// First try the exact column name
							if val, ok := tags[col].(string); ok {
								value = val
								color = colorCyan
							} else if val, ok := tags[col].(float64); ok {
								value = fmt.Sprintf("%v", val)
								color = colorCyan
							} else if val, ok := tags[col].(bool); ok {
								value = fmt.Sprintf("%v", val)
								color = colorCyan
							} else {
								// Try with _cardinalhq prefix
								cardinalhqKey := "_cardinalhq." + col
								if val, ok := tags[cardinalhqKey].(string); ok {
									value = val
									color = colorCyan
								} else if val, ok := tags[cardinalhqKey].(float64); ok {
									value = fmt.Sprintf("%v", val)
									color = colorCyan
								} else if val, ok := tags[cardinalhqKey].(bool); ok {
									value = fmt.Sprintf("%v", val)
									color = colorCyan
								}
							}
						}
					}

					if noColor {
						outputParts = append(outputParts, value)
					} else {
						outputParts = append(outputParts, fmt.Sprintf("%s%s%s", color, value, colorReset))
					}
				}

				fmt.Println(strings.Join(outputParts, " "))
			} else {
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
