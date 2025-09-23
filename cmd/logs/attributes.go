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
)

var (
	attributesFilters      []string
	attributesRegexFilters []string
	attributesStartTime    string
	attributesEndTime      string
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
	AttributesCmd.Flags().StringVarP(&attributesStartTime, "start", "s", "", "Start time (e.g., 'e-1h', '2024-01-01T00:00:00Z')")
	AttributesCmd.Flags().StringVarP(&attributesEndTime, "end", "e", "", "End time (e.g., 'now', '2024-01-01T23:59:59Z')")
	AttributesCmd.Flags().StringVarP(&attributesAppName, "app", "a", "", "Filter by application/service name")
	AttributesCmd.Flags().StringVarP(&attributesLogLevel, "level", "l", "", "Filter by log level (e.g., ERROR, INFO, DEBUG, WARN)")

	TagValuesCmd.Flags().StringSliceVarP(&attributesFilters, "filter", "f", []string{}, "Filter in format 'key:value' (can be used multiple times)")
	TagValuesCmd.Flags().StringVarP(&attributesStartTime, "start", "s", "", "Start time (e.g., 'e-1h', '2024-01-01T00:00:00Z')")
	TagValuesCmd.Flags().StringVarP(&attributesEndTime, "end", "e", "", "End time (e.g., 'now', '2024-01-01T23:59:59Z')")
	TagValuesCmd.Flags().StringVarP(&attributesAppName, "app", "a", "", "Filter by application/service name")
	TagValuesCmd.Flags().StringVarP(&attributesLogLevel, "level", "l", "", "Filter by log level (e.g., ERROR, INFO, DEBUG, WARN)")

}

func runAttributesCmd(cmdObj *cobra.Command, _ []string) error {
	noColor, _ := cmdObj.Flags().GetBool("no-color")

	endpoint, _ := cmdObj.Flags().GetString("endpoint")
	apiKey, _ := cmdObj.Flags().GetString("api-key")
	cfg, err := config.LoadWithFlags(endpoint, apiKey)
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}
	client := api.NewClient(cfg)

	// Parse time range
	startMs, endMs, err := dateutils.ToStartEnd(attributesStartTime, attributesEndTime)
	if err != nil {
		return fmt.Errorf("failed to parse time range: %w", err)
	}
	startTimeStr := fmt.Sprintf("%d", startMs)
	endTimeStr := fmt.Sprintf("%d", endMs)

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Call /logs/tags
	responseChan, err := client.QueryLogTags(ctx, startTimeStr, endTimeStr)
	if err != nil {
		return fmt.Errorf("failed to query tags: %w", err)
	}

	fmt.Printf("Querying tags from %s to %s...\n", startTimeStr, endTimeStr)
	fmt.Println("---")

	tagsSet := make(map[string]bool)
	for response := range responseChan {
		if response.Type == "data" {
			if tagsArr, ok := response.Message["tags"].([]string); ok {
				for _, tagName := range tagsArr {
					if strings.HasPrefix(tagName, "_cardinalhq") {
						continue
					}
					if !tagsSet[tagName] {
						tagsSet[tagName] = true
						if noColor {
							fmt.Println(tagName)
						} else {
							fmt.Printf("\033[36m%s\033[0m\n", tagName)
						}
					}
				}
			} else {
				fmt.Fprintf(os.Stderr, "DEBUG: unexpected tags format: %#v\n", response.Message["tags"])
			}
		}
	}

	if len(tagsSet) == 0 {
		fmt.Println("No tags found for the specified criteria")
	}
	return nil
}

func runTagValuesCmd(cmdObj *cobra.Command, args []string) error {
	noColor, _ := cmdObj.Flags().GetBool("no-color")

	endpoint, _ := cmdObj.Flags().GetString("endpoint")
	apiKey, _ := cmdObj.Flags().GetString("api-key")
	cfg, err := config.LoadWithFlags(endpoint, apiKey)
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}
	client := api.NewClient(cfg)

	tagName := args[0]

	startMs, endMs, err := dateutils.ToStartEnd(attributesStartTime, attributesEndTime)
	if err != nil {
		return fmt.Errorf("failed to parse time range: %w", err)
	}
	startTimeStr := fmt.Sprintf("%d", startMs)
	endTimeStr := fmt.Sprintf("%d", endMs)

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	// Build LogQL query string (only if filters are provided)
	var conditions []string
	if attributesAppName != "" {
		conditions = append(conditions, fmt.Sprintf(`resource_service_name="%s"`, attributesAppName))
	}
	if attributesLogLevel != "" {
		conditions = append(conditions, fmt.Sprintf(`_cardinalhq_level="%s"`, attributesLogLevel))
	}
	for _, f := range attributesFilters {
		if parts := strings.SplitN(f, ":", 2); len(parts) == 2 {
			key := normalizeTag(parts[0])
			conditions = append(conditions, fmt.Sprintf(`%s="%s"`, key, parts[1]))
		}
	}

	var q string
	if len(conditions) > 0 {
		q = "{" + strings.Join(conditions, ", ") + "}"
	} else {
		q = "" // omit q entirely if no filters
	}

	// Call /logs/tagvalues
	responseChan, err := client.QueryLogTagValues(ctx, tagName, q, startTimeStr, endTimeStr)
	if err != nil {
		return fmt.Errorf("failed to query tag values: %w", err)
	}

	fmt.Printf("Querying values for tag '%s' from %s to %s", tagName, startTimeStr, endTimeStr)
	if q != "" {
		fmt.Printf(" with query %s", q)
	}
	fmt.Println("...")
	fmt.Println("---")

	valuesSet := make(map[string]bool)
	for response := range responseChan {
		if response.Type == "result" {
			if tagValue, ok := response.Data["value"].(string); ok {
				if tagValue != "" && !valuesSet[tagValue] {
					valuesSet[tagValue] = true
					if noColor {
						fmt.Println(tagValue)
					} else {
						fmt.Printf("\033[36m%s\033[0m\n", tagValue)
					}
				}
			}
		}
	}

	if len(valuesSet) == 0 {
		fmt.Println("No values found for this tag")
	}
	return nil
}
