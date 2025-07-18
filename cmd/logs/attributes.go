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

// Shared variables with get.go
var (
	attributesFilters      []string
	attributesRegexFilters []string
	attributesStartTime    string
	attributesEndTime      string
	attributesNoColor      bool
	attributesAppName      string
	attributesLogLevel     string
)

var AttributesCmd = &cobra.Command{
	Use:   "get-attr",
	Short: "Retrieve log attributes",
	Long:  `Retrieve unique log attributes with optional filters.`,
	RunE:  runAttributesCmd,
	Args:  cobra.NoArgs,
}

var TagValuesCmd = &cobra.Command{
	Use:   "get-values",
	Short: "Retrieve values for a specific tag",
	Long:  `Retrieve possible values for a specific tag with optional filters.`,
	RunE:  runTagValuesCmd,
	Args:  cobra.ExactArgs(1),
}

func init() {
	AttributesCmd.Flags().StringSliceVarP(&attributesFilters, "filter", "f", []string{}, "Filter in format 'key:value' (can be used multiple times)")
	AttributesCmd.Flags().StringSliceVarP(&attributesRegexFilters, "regex", "r", []string{}, "Regex filter in format 'key:value' (can be used multiple times)")
	AttributesCmd.Flags().StringVarP(&attributesStartTime, "start", "s", "", "Start time (e.g., 'e-1h', '2024-01-01T00:00:00Z')")
	AttributesCmd.Flags().StringVarP(&attributesEndTime, "end", "e", "", "End time (e.g., 'now', '2024-01-01T23:59:59Z')")
	AttributesCmd.Flags().BoolVar(&attributesNoColor, "no-color", false, "Disable colored output")
	AttributesCmd.Flags().StringVarP(&attributesAppName, "app", "a", "", "Filter by application/service name")
	AttributesCmd.Flags().StringVarP(&attributesLogLevel, "level", "l", "", "Filter by log level (e.g., ERROR, INFO, DEBUG, WARN)")

	TagValuesCmd.Flags().StringSliceVarP(&attributesFilters, "filter", "f", []string{}, "Filter in format 'key:value' (can be used multiple times)")
	TagValuesCmd.Flags().StringVarP(&attributesStartTime, "start", "s", "", "Start time (e.g., 'e-1h', '2024-01-01T00:00:00Z')")
	TagValuesCmd.Flags().StringVarP(&attributesEndTime, "end", "e", "", "End time (e.g., 'now', '2024-01-01T23:59:59Z')")
	TagValuesCmd.Flags().BoolVar(&attributesNoColor, "no-color", false, "Disable colored output")
	TagValuesCmd.Flags().StringVarP(&attributesAppName, "app", "a", "", "Filter by application/service name")
	TagValuesCmd.Flags().StringVarP(&attributesLogLevel, "level", "l", "", "Filter by log level (e.g., ERROR, INFO, DEBUG, WARN)")
}

func runAttributesCmd(_ *cobra.Command, targets []string) error {
	if !term.IsTerminal(int(os.Stdout.Fd())) {
		attributesNoColor = true
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}
	client := api.NewClient(cfg)

	// Parse start and end times using dateutils
	startMs, endMs, err := dateutils.ToStartEnd(attributesStartTime, attributesEndTime)
	if err != nil {
		return fmt.Errorf("failed to parse time range: %w", err)
	}

	// Convert milliseconds to ISO8601 format for API
	startTimeStr := time.UnixMilli(startMs).UTC().Format(time.RFC3339)
	endTimeStr := time.UnixMilli(endMs).UTC().Format(time.RFC3339)

	// Create query parameters
	params := api.CreateQueryParams(startTimeStr, endTimeStr, "", "")

	// Create context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Create filter based on whether filters are provided
	var filterObj *api.Filter

	// Check if we have any filters (including shorthand flags)
	hasFilters := len(attributesFilters) > 0 || len(attributesRegexFilters) > 0 || attributesAppName != "" || attributesLogLevel != ""

	if !hasFilters {
		// No filters provided - use the default filter for all tags (like frontend)
		filterObj = api.CreateFilter("log.telemetry_type", "has", "string", []string{""})
	} else {
		// Handle shorthand flags by adding them to the filters list
		if attributesAppName != "" {
			attributesFilters = append(attributesFilters, fmt.Sprintf("resource.service.name:%s", attributesAppName))
		}
		if attributesLogLevel != "" {
			attributesFilters = append(attributesFilters, fmt.Sprintf("_cardinalhq.level:%s", attributesLogLevel))
		}
		// Filters provided - create nested filter structure like frontend
		if len(attributesFilters) > 0 {
			// Use the first filter as the main filter
			parts := strings.SplitN(attributesFilters[0], ":", 2)
			if len(parts) != 2 {
				return fmt.Errorf("filter must be in format 'key:value'")
			}

			// Determine if this is a regex pattern
			operation := "eq"
			if strings.Contains(parts[1], "\\") || strings.Contains(parts[1], ".*") || strings.Contains(parts[1], "^") || strings.Contains(parts[1], "$") {
				operation = "regex"
			}

			filterObj = api.CreateFilter(parts[0], operation, "string", []string{parts[1]})

			// If we have additional filters, create nested filter
			if len(attributesFilters) > 1 || len(attributesRegexFilters) > 0 {
				allFilters := []*api.Filter{filterObj}

				// Add remaining filters
				for i := 1; i < len(attributesFilters); i++ {
					parts := strings.SplitN(attributesFilters[i], ":", 2)
					if len(parts) != 2 {
						return fmt.Errorf("filter must be in format 'key:value'")
					}

					operation := "eq"
					if strings.Contains(parts[1], "\\") || strings.Contains(parts[1], ".*") || strings.Contains(parts[1], "^") || strings.Contains(parts[1], "$") {
						operation = "regex"
					}

					allFilters = append(allFilters, api.CreateFilter(parts[0], operation, "string", []string{parts[1]}))
				}

				// Add regex filters
				for _, f := range attributesRegexFilters {
					parts := strings.SplitN(f, ":", 2)
					if len(parts) != 2 {
						return fmt.Errorf("regex filter must be in format 'key:value'")
					}

					allFilters = append(allFilters, api.CreateFilter(parts[0], "regex", "string", []string{parts[1]}))
				}

				if len(allFilters) > 1 {
					filterObj = api.CreateNestedFilter(allFilters...)
				}
			}
		} else {
			// Only regex filters
			parts := strings.SplitN(attributesRegexFilters[0], ":", 2)
			if len(parts) != 2 {
				return fmt.Errorf("regex filter must be in format 'key:value'")
			}

			filterObj = api.CreateFilter(parts[0], "regex", "string", []string{parts[1]})

			// If we have additional regex filters, create nested filter
			if len(attributesRegexFilters) > 1 {
				allFilters := []*api.Filter{filterObj}

				for i := 1; i < len(attributesRegexFilters); i++ {
					parts := strings.SplitN(attributesRegexFilters[i], ":", 2)
					if len(parts) != 2 {
						return fmt.Errorf("regex filter must be in format 'key:value'")
					}

					allFilters = append(allFilters, api.CreateFilter(parts[0], "regex", "string", []string{parts[1]}))
				}

				if len(allFilters) > 1 {
					filterObj = api.CreateNestedFilter(allFilters...)
				}
			}
		}
	}

	// Create expression for tags endpoint (send single expression like frontend)
	expression := api.CreateExpression("logs", 1000, filterObj, nil)

	// Send the expression directly, not wrapped in GraphRequest
	req := &expression

	// Call the tags endpoint
	responseChan, err := client.QueryTags(ctx, req, params)
	if err != nil {
		return fmt.Errorf("failed to query tags: %w", err)
	}

	// Display results
	fmt.Printf("Querying tags from %s to %s...\n", startTimeStr, endTimeStr)
	if attributesAppName != "" {
		fmt.Printf("App Filter: resource.service.name = %s\n", attributesAppName)
	}
	if attributesLogLevel != "" {
		fmt.Printf("Level Filter: _cardinalhq.level = %s\n", attributesLogLevel)
	}
	if len(attributesFilters) > 0 || len(attributesRegexFilters) > 0 {
		for _, f := range attributesFilters {
			fmt.Printf("Filter: %s\n", f)
		}
		for _, f := range attributesRegexFilters {
			fmt.Printf("Regex Filter: %s\n", f)
		}
	}
	fmt.Println("---")

	// Process responses like frontend - extract all tag names
	responseCount := 0
	tagsSet := make(map[string]bool)

	for response := range responseChan {
		responseCount++

		if response.Type == "data" {
			// Extract all tag names from the message (like frontend)
			message := response.Message

			// Process all keys in the message as potential tags
			for tagName := range message {
				// Skip _cardinalhq tags completely
				if strings.HasPrefix(tagName, "_cardinalhq") {
					continue
				}

				if tagName != "" && !tagsSet[tagName] {
					tagsSet[tagName] = true

					if attributesNoColor {
						fmt.Printf("%s\n", tagName)
					} else {
						fmt.Printf("\033[36m%s\033[0m\n", tagName)
					}
				}
			}
		}
	}

	if responseCount == 0 {
		fmt.Println("No tags found for the specified criteria")
	} else if len(tagsSet) == 0 {
		fmt.Println("No tags found in the response")
	}

	return nil
}

func runTagValuesCmd(_ *cobra.Command, args []string) error {
	if !term.IsTerminal(int(os.Stdout.Fd())) {
		attributesNoColor = true
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}
	client := api.NewClient(cfg)

	// Get the tag name from arguments
	tagName := args[0]

	// Parse start and end times using dateutils
	startMs, endMs, err := dateutils.ToStartEnd(attributesStartTime, attributesEndTime)
	if err != nil {
		return fmt.Errorf("failed to parse time range: %w", err)
	}

	// Convert milliseconds to ISO8601 format for API
	startTimeStr := time.UnixMilli(startMs).UTC().Format(time.RFC3339)
	endTimeStr := time.UnixMilli(endMs).UTC().Format(time.RFC3339)

	// Create query parameters with tagName and dataType (like frontend)
	params := api.CreateQueryParams(startTimeStr, endTimeStr, tagName, "string")

	// Create context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Create filter based on whether filters are provided
	var filterObj *api.Filter

	// Check if we have any filters (including shorthand flags)
	hasFilters := len(attributesFilters) > 0 || attributesAppName != "" || attributesLogLevel != ""

	if !hasFilters {
		// No filters provided - use the default filter for the specific tag
		filterObj = api.CreateFilter(tagName, "exists", "string", []string{""})
	} else {
		// Handle shorthand flags by adding them to the filters list
		if attributesAppName != "" {
			attributesFilters = append(attributesFilters, fmt.Sprintf("resource.service.name:%s", attributesAppName))
		}
		if attributesLogLevel != "" {
			attributesFilters = append(attributesFilters, fmt.Sprintf("_cardinalhq.level:%s", attributesLogLevel))
		}
		// Filters provided - create nested filter structure like frontend
		if len(attributesFilters) > 0 {
			// Use the first filter as the main filter
			parts := strings.SplitN(attributesFilters[0], ":", 2)
			if len(parts) != 2 {
				return fmt.Errorf("filter must be in format 'key:value'")
			}

			filterObj = api.CreateFilter(parts[0], "eq", "string", []string{parts[1]})

			// If we have additional filters, create nested filter
			if len(attributesFilters) > 1 {
				allFilters := []*api.Filter{filterObj}

				// Add remaining filters
				for i := 1; i < len(attributesFilters); i++ {
					parts := strings.SplitN(attributesFilters[i], ":", 2)
					if len(parts) != 2 {
						return fmt.Errorf("filter must be in format 'key:value'")
					}

					allFilters = append(allFilters, api.CreateFilter(parts[0], "eq", "string", []string{parts[1]}))
				}

				if len(allFilters) > 1 {
					filterObj = api.CreateNestedFilter(allFilters...)
				}
			}
		}
	}

	// Create expression for tag values endpoint (like frontend)
	expression := api.CreateExpression("logs", 1000, filterObj, nil)
	req := &expression

	// Call the tags endpoint with query parameters
	responseChan, err := client.QueryTags(ctx, req, params)
	if err != nil {
		return fmt.Errorf("failed to query tag values: %w", err)
	}

	// Display results
	fmt.Printf("Querying values for tag '%s' from %s to %s...\n", tagName, startTimeStr, endTimeStr)
	if attributesAppName != "" {
		fmt.Printf("App Filter: resource.service.name = %s\n", attributesAppName)
	}
	if attributesLogLevel != "" {
		fmt.Printf("Level Filter: _cardinalhq.level = %s\n", attributesLogLevel)
	}
	if len(attributesFilters) > 0 {
		for _, f := range attributesFilters {
			fmt.Printf("Filter: %s\n", f)
		}
	}
	fmt.Println("---")

	// Process responses like frontend - extract tag values
	responseCount := 0
	valuesSet := make(map[string]bool)

	for response := range responseChan {
		responseCount++

		if response.Type == "data" {
			// Extract tag value from the message (like frontend)
			message := response.Message

			// Get the specific tag value
			if tagValue, ok := message[tagName].(string); ok {
				if tagValue != "" && !valuesSet[tagValue] {
					valuesSet[tagValue] = true

					if attributesNoColor {
						fmt.Printf("%s\n", tagValue)
					} else {
						fmt.Printf("\033[36m%s\033[0m\n", tagValue)
					}
				}
			}
		}
	}

	if responseCount == 0 {
		fmt.Println("No tag values found for the specified criteria")
	} else if len(valuesSet) == 0 {
		fmt.Println("No values found for this tag")
	}

	return nil
}
