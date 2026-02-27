// Copyright 2025-2026 CardinalHQ, Inc
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
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/cardinalhq/oteltools/pkg/dateutils"
	"github.com/lakerunner/cli/internal/api"
	"github.com/lakerunner/cli/internal/config"
	"github.com/lakerunner/cli/internal/presets"
	"github.com/spf13/cobra"
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
)

// getColorForLevel returns the appropriate color for a log level
func getColorForLevel(level string, noColor bool) string {
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

// normalizeTag replaces dots with underscores in keys/values
func normalizeTag(s string) string {
	return strings.ReplaceAll(s, ".", "_")
}

// getFieldValue extracts a field value from a log entry
func getFieldValue(message map[string]any, tags map[string]any, field string) string {
	switch strings.ToLower(field) {
	case "timestamp", "ts":
		// Prefer nanoseconds for highest precision
		if tsns, ok := message["timestamp_ns"].(int64); ok {
			return time.Unix(0, tsns).Format("2006-01-02 15:04:05.999999999")
		} else if ts, ok := message["timestamp"].(int64); ok {
			return time.UnixMilli(ts).Format("2006-01-02 15:04:05.000")
		} else if ts, ok := message["timestamp"].(float64); ok {
			return time.UnixMilli(int64(ts)).Format("2006-01-02 15:04:05.000")
		}
		return ""
	case "level":
		if tags != nil {
			if level, ok := tags["level"].(string); ok {
				return level
			}
		}
		return ""
	case "message":
		if tags != nil {
			if msg, ok := tags["message"].(string); ok {
				return msg
			}
		}
		return ""
	case "service", "svc":
		if tags != nil {
			if service, ok := tags["service_name"].(string); ok {
				return service
			}
		}
		return ""
	case "pod":
		if tags != nil {
			if pod, ok := tags["k8s_pod_name"].(string); ok {
				return pod
			}
		}
		return ""
	default:
		if tags != nil {
			colNorm := normalizeTag(field)
			if v, ok := tags[field]; ok {
				return fmt.Sprintf("%v", v)
			} else if v, ok := tags[colNorm]; ok {
				return fmt.Sprintf("%v", v)
			}
		}
		return ""
	}
}

// escapeCSV escapes a value for CSV/TSV output
func escapeCSV(val string, delimiter string) string {
	needsQuote := strings.ContainsAny(val, "\",\n\r"+delimiter)
	if needsQuote {
		return `"` + strings.ReplaceAll(val, `"`, `""`) + `"`
	}
	return val
}

// formatCSVRow formats a row for CSV/TSV output
func formatCSVRow(values []string, delimiter string) string {
	escaped := make([]string, len(values))
	for i, v := range values {
		escaped[i] = escapeCSV(v, delimiter)
	}
	return strings.Join(escaped, delimiter)
}

// buildAppCondition builds a LogQL condition for service name filtering
// Single app: service_name="app"
// Multiple apps: service_name=~"app1|app2|app3"
func buildAppCondition(appName string) string {
	apps := strings.Split(appName, ",")
	// Filter and normalize app names
	var normalized []string
	for _, a := range apps {
		trimmed := strings.TrimSpace(a)
		if trimmed != "" {
			normalized = append(normalized, normalizeTag(trimmed))
		}
	}
	if len(normalized) == 0 {
		return ""
	}
	if len(normalized) == 1 {
		return fmt.Sprintf(`service_name="%s"`, normalized[0])
	}
	// Multiple apps: use regex match
	return fmt.Sprintf(`service_name=~"%s"`, strings.Join(normalized, "|"))
}

// buildLogQLQuery constructs a LogQL query from filter parameters
func buildLogQLQuery(appName, logLevel string, filters []string, messageContains, messageNotContains, messageRegexMatch, messageRegexNot string) string {
	var conditions []string
	if appName != "" {
		if cond := buildAppCondition(appName); cond != "" {
			conditions = append(conditions, cond)
		}
	}
	if logLevel != "" {
		conditions = append(conditions, fmt.Sprintf(`level="%s"`, normalizeTag(logLevel)))
	}
	for _, f := range filters {
		parts := strings.SplitN(f, ":", 2)
		if len(parts) == 2 {
			key := normalizeTag(parts[0])
			val := normalizeTag(parts[1])
			conditions = append(conditions, fmt.Sprintf(`%s="%s"`, key, val))
		}
	}

	q := `{service_name=~".+"}`
	if len(conditions) > 0 {
		q = "{" + strings.Join(conditions, ", ") + "}"
	}

	if messageContains != "" {
		q += fmt.Sprintf(` |= "%s"`, normalizeTag(messageContains))
	}
	if messageNotContains != "" {
		q += fmt.Sprintf(` != "%s"`, normalizeTag(messageNotContains))
	}
	if messageRegexMatch != "" {
		q += fmt.Sprintf(` |~ "%s"`, normalizeTag(messageRegexMatch))
	}
	if messageRegexNot != "" {
		q += fmt.Sprintf(` !~ "%s"`, normalizeTag(messageRegexNot))
	}

	return q
}

// formatJSONEntry formats a log entry as JSON
func formatJSONEntry(message map[string]any, tags map[string]any, cols []string) string {
	output := make(map[string]any)
	for _, col := range cols {
		output[col] = getFieldValue(message, tags, col)
	}
	data, err := json.Marshal(output)
	if err != nil {
		fmt.Fprintf(os.Stderr, "failed to marshal log entry to JSON: %v\n", err)
		return "{}"
	}
	return string(data)
}

var (
	limit              int
	filters            []string
	preset             string
	startTime          string
	endTime            string
	appName            string
	logLevel           string
	columns            string
	messageContains    string
	messageNotContains string
	messageRegexMatch  string
	messageRegexNot    string
	getAliasValues     map[string]*string
	orderFlag          string
	rawQuery           string
	outputFormat       string
)

func init() {
	GetCmd.Flags().IntVar(&limit, "limit", 1000, "Limit the number of results returned")
	GetCmd.Flags().StringSliceVarP(&filters, "filter", "f", []string{}, "Filter in format 'key:value' (can be used multiple times)")
	GetCmd.Flags().StringVarP(&preset, "preset", "p", "", "Use a named filter preset from ~/.lakerunner/config.yaml")
	GetCmd.Flags().StringVarP(&startTime, "start", "s", "", "Start time (e.g., 'e-1h', '2024-01-01T00:00:00Z')")
	GetCmd.Flags().StringVarP(&endTime, "end", "e", "", "End time (e.g., 'now', '2024-01-01T23:59:59Z')")
	GetCmd.Flags().StringVarP(&appName, "app", "a", "", "Filter by service name (comma-separated for multiple)")
	GetCmd.Flags().StringVarP(&logLevel, "level", "l", "", "Filter logs by log level (e.g., ERROR, INFO, DEBUG, WARN)")
	GetCmd.Flags().StringVarP(&columns, "columns", "c", "", "Comma or space separated columns to display (e.g., 'timestamp,level,message')")
	GetCmd.Flags().StringVarP(&messageContains, "contains", "M", "", "Filter logs where message contains this string (|=)")
	GetCmd.Flags().StringVarP(&messageNotContains, "not-contains", "N", "", "Filter logs where message does not contain this string (!=)")
	GetCmd.Flags().StringVarP(&messageRegexMatch, "msg-regex", "R", "", "Filter logs where message matches this regex (|~)")
	GetCmd.Flags().StringVarP(&messageRegexNot, "msg-not-regex", "X", "", "Filter logs where message does not match this regex (!~)")
	GetCmd.Flags().StringVar(&orderFlag, "order", "newest", "Log ordering: newest or oldest")
	GetCmd.Flags().StringVar(&rawQuery, "query", "", "Raw LogQL query (bypasses filter flags)")
	GetCmd.Flags().StringVarP(&outputFormat, "output", "o", "text", "Output format: text, json, csv, tsv")
	getAliasValues = presets.RegisterAliasFlags(GetCmd)
}

var GetCmd = &cobra.Command{
	Use:   "get",
	Short: "Retrieve logs with filters",
	RunE:  runGetCmd,
}

func runGetCmd(cmdObj *cobra.Command, _ []string) error {
	noColor, _ := cmdObj.Flags().GetBool("no-color")

	// Validate output format
	outputFormat = strings.ToLower(outputFormat)
	switch outputFormat {
	case "text", "json", "csv", "tsv":
		// valid
	default:
		return fmt.Errorf("invalid output format %q: must be one of text, json, csv, tsv", outputFormat)
	}

	// Validate and convert order flag
	orderFlag = strings.ToLower(orderFlag)
	var reverseOrder bool
	switch orderFlag {
	case "newest":
		reverseOrder = true
	case "oldest":
		reverseOrder = false
	default:
		return fmt.Errorf("invalid order %q: must be newest or oldest", orderFlag)
	}

	var selectedColumns []string
	if columns != "" {
		parts := strings.Split(columns, ",")
		for _, part := range parts {
			for _, sp := range strings.Fields(strings.TrimSpace(part)) {
				if sp != "" {
					selectedColumns = append(selectedColumns, sp)
				}
			}
		}
	}

	var fields []string
	if len(selectedColumns) > 0 {
		for _, col := range selectedColumns {
			switch strings.ToLower(col) {
			case "timestamp", "ts", "level", "message", "service", "svc", "pod":
				// skip display-only
			default:
				fields = append(fields, col)
			}
		}
	}

	endpoint, _ := cmdObj.Flags().GetString("endpoint")
	apiKey, _ := cmdObj.Flags().GetString("api-key")
	cfg, err := config.LoadWithFlags(endpoint, apiKey)
	if err != nil {
		return fmt.Errorf("failed to load configuration: %w", err)
	}
	client := api.NewClient(cfg)

	// Parse start and end times
	startMs, endMs, err := dateutils.ToStartEnd(startTime, endTime)
	if err != nil {
		return fmt.Errorf("failed to parse time range: %w", err)
	}
	startTimeStr := fmt.Sprintf("%d", startMs)
	endTimeStr := fmt.Sprintf("%d", endMs)

	// Load preset filters if specified
	allFilters := filters
	if preset != "" {
		presetFilters, err := presets.GetFilters(preset)
		if err != nil {
			return err
		}
		allFilters = append(presetFilters, filters...)
	}

	// Resolve filter aliases in -f values
	allFilters, err = presets.ResolveFilters(allFilters)
	if err != nil {
		return err
	}

	// Collect filters from alias flags (e.g., -i prod)
	allFilters = append(allFilters, presets.CollectAliasFilters(getAliasValues)...)

	// Build LogQL query string
	var q string
	if rawQuery != "" {
		// Use raw query directly
		q = rawQuery
		// Warn if filter flags are also set
		hasFilterFlags := appName != "" || logLevel != "" || len(allFilters) > 0 ||
			messageContains != "" || messageNotContains != "" ||
			messageRegexMatch != "" || messageRegexNot != ""
		if hasFilterFlags {
			fmt.Fprintln(os.Stderr, "Warning: --query specified, filter flags will be ignored")
		}
	} else {
		q = buildLogQLQuery(appName, logLevel, allFilters, messageContains, messageNotContains, messageRegexMatch, messageRegexNot)
	}

	// Context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	responseChan, err := client.QueryLogs(ctx, q, startTimeStr, endTimeStr, limit, reverseOrder, fields)
	if err != nil {
		return fmt.Errorf("failed to query logs: %w", err)
	}

	quiet, _ := cmdObj.Flags().GetBool("quiet")

	// Structured output formats disable colors and progress indicators
	isStructuredOutput := outputFormat == "json" || outputFormat == "csv" || outputFormat == "tsv"
	if isStructuredOutput {
		noColor = true
		quiet = true
	}

	// Default columns for structured output
	outputColumns := selectedColumns
	if len(outputColumns) == 0 && isStructuredOutput {
		outputColumns = []string{"timestamp", "level", "service", "message"}
	}

	if !quiet {
		fmt.Printf("Querying logs from %s to %s...\n", startTimeStr, endTimeStr)
		fmt.Printf("LogQL: %s\n", q)
		fmt.Printf("Limit: %d results\n", limit)
		if len(selectedColumns) > 0 {
			fmt.Printf("Columns: %v\n", selectedColumns)
		}
		if len(fields) > 0 {
			fmt.Printf("Fields (API): %v\n", fields)
		}
		fmt.Println("---")
	}

	responseCount := 0
	started := time.Now()

	// Print CSV/TSV header before reading responses
	switch outputFormat {
	case "csv":
		fmt.Println(formatCSVRow(outputColumns, ","))
	case "tsv":
		fmt.Println(formatCSVRow(outputColumns, "\t"))
	}

	if !quiet {
		progressTicker := time.NewTicker(2 * time.Second)
		defer progressTicker.Stop()
		go func() {
			for range progressTicker.C {
				if responseCount == 0 {
					elapsed := time.Since(started)
					fmt.Fprintf(os.Stderr, "\rWaiting for logs... (%v elapsed)", elapsed.Round(time.Second))
				}
			}
		}()
	}

	for response := range responseChan {
		responseCount++
		if responseCount == 1 && !quiet {
			fmt.Fprintf(os.Stderr, "\r%s\r", strings.Repeat(" ", 50))
		}
		message := response.Data
		tags, _ := message["tags"].(map[string]any)

		// Handle structured output formats
		switch outputFormat {
		case "json":
			fmt.Println(formatJSONEntry(message, tags, outputColumns))
		case "csv":
			values := make([]string, len(outputColumns))
			for i, col := range outputColumns {
				values[i] = getFieldValue(message, tags, col)
			}
			fmt.Println(formatCSVRow(values, ","))
		case "tsv":
			values := make([]string, len(outputColumns))
			for i, col := range outputColumns {
				values[i] = getFieldValue(message, tags, col)
			}
			fmt.Println(formatCSVRow(values, "\t"))
		default: // text
			// Get timestamp with proper precision handling (prefer nanoseconds)
			timestamp := ""
			if tsns, ok := message["timestamp_ns"].(int64); ok {
				timestamp = time.Unix(0, tsns).Format("2006-01-02 15:04:05.999999999")
			} else if ts, ok := message["timestamp"].(int64); ok {
				timestamp = time.UnixMilli(ts).Format("2006-01-02 15:04:05.000")
			} else if ts, ok := message["timestamp"].(float64); ok {
				timestamp = time.UnixMilli(int64(ts)).Format("2006-01-02 15:04:05.000")
			}

			logMessage := ""
			serviceName := ""
			levelVal := ""
			podName := ""
			if tags != nil {
				if msg, ok := tags["message"].(string); ok {
					logMessage = msg
				}
				if service, ok := tags["service_name"].(string); ok {
					serviceName = service
				}
				if level, ok := tags["level"].(string); ok {
					levelVal = level
				}
				if pod, ok := tags["k8s_pod_name"].(string); ok {
					podName = pod
				}
			}

			if len(selectedColumns) > 0 {
				var parts []string
				for _, col := range selectedColumns {
					val := ""
					switch strings.ToLower(col) {
					case "timestamp", "ts":
						if noColor {
							val = timestamp
						} else {
							val = fmt.Sprintf("%s%s%s", colorBlue, timestamp, colorReset)
						}
					case "level":
						if noColor {
							val = levelVal
						} else {
							val = fmt.Sprintf("%s%s%s", getColorForLevel(levelVal, noColor), levelVal, colorReset)
						}
					case "message":
						val = logMessage
					case "service", "svc":
						if noColor {
							val = serviceName
						} else {
							val = fmt.Sprintf("%s%s%s", colorCyan, serviceName, colorReset)
						}
					case "pod":
						if noColor {
							val = podName
						} else {
							val = fmt.Sprintf("%s%s%s", colorPurple, podName, colorReset)
						}
					default:
						if tags != nil {
							colNorm := normalizeTag(col)
							if v, ok := tags[col]; ok {
								val = fmt.Sprintf("%v", v)
							} else if v, ok := tags[colNorm]; ok {
								val = fmt.Sprintf("%v", v)
							} else {
								val = "<undefined>"
							}
						} else {
							val = "<undefined>"
						}
					}
					parts = append(parts, val)
				}
				fmt.Println(strings.Join(parts, " "))
			} else {
				if noColor {
					fmt.Printf("[%s] %s %s: %s\n", timestamp, levelVal, serviceName, logMessage)
				} else {
					fmt.Printf("[%s%s%s] %s%s%s %s%s%s: %s\n",
						colorBlue, timestamp, colorReset,
						getColorForLevel(levelVal, noColor), levelVal, colorReset,
						colorCyan, serviceName, colorReset,
						logMessage)
				}
			}
		}

		if responseCount >= limit {
			cancel()
			break
		}
	}

	if responseCount == 0 && !quiet {
		fmt.Println("No responses received from the API")
	}
	return nil
}
