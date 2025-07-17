package api

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/lakerunner/cli/internal/config"
)

// Client represents the API client
type Client struct {
	baseURL string
	apiKey  string
	client  *http.Client
}

// LogsRequest represents a request to the logs endpoint
type LogsRequest struct {
	Dataset       string  `json:"dataset"`
	Limit         int     `json:"limit"`
	Order         string  `json:"order"`
	ReturnResults bool    `json:"returnResults"`
	Filter        *Filter `json:"filter,omitempty"`
}

// Filter represents a filter for log queries
type Filter struct {
	K         string   `json:"k"`
	V         []string `json:"v"`
	Op        string   `json:"op"`
	DataType  string   `json:"dataType"`
	Extracted bool     `json:"extracted"`
	Computed  bool     `json:"computed"`
}

// LogsResponse represents a response from the logs endpoint
type LogsResponse struct {
	ID      string                 `json:"id"`
	Type    string                 `json:"type"`
	Message map[string]interface{} `json:"message"`
}

// QueryParams represents URL query parameters
type QueryParams struct {
	StartTime string `json:"s"`
	EndTime   string `json:"e"`
	TagName   string `json:"tagName,omitempty"`
	DataType  string `json:"dataType,omitempty"`
}

// NewClient creates a new API client with proper configuration
func NewClient(cfg *config.Config) *Client {
	return &Client{
		baseURL: cfg.LAKERUNNER_QUERY_URL,
		apiKey:  cfg.LAKERUNNER_API_KEY,
		client: &http.Client{
			Timeout: 30 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:       10,
				IdleConnTimeout:    30 * time.Second,
				DisableCompression: false,
			},
		},
	}
}

// buildURL constructs the URL with query parameters
func (c *Client) buildURL(endpoint string, params QueryParams) string {
	url := fmt.Sprintf("%s%s", c.baseURL, endpoint)

	var queryParts []string
	if params.StartTime != "" {
		queryParts = append(queryParts, fmt.Sprintf("s=%s", params.StartTime))
	}
	if params.EndTime != "" {
		queryParts = append(queryParts, fmt.Sprintf("e=%s", params.EndTime))
	}
	if params.TagName != "" {
		queryParts = append(queryParts, fmt.Sprintf("tagName=%s", params.TagName))
	}
	if params.DataType != "" {
		queryParts = append(queryParts, fmt.Sprintf("dataType=%s", params.DataType))
	}

	if len(queryParts) > 0 {
		url += "?" + strings.Join(queryParts, "&")
	}

	return url
}

// QueryLogs makes a request to the logs endpoint and returns a channel of responses
func (c *Client) QueryLogs(ctx context.Context, req *LogsRequest, params QueryParams) (<-chan LogsResponse, error) {
	url := c.buildURL("/api/v1/tags/logs", params)

	jsonData, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Set headers according to the API specification
	httpReq.Header.Set("Accept", "text/event-stream")
	httpReq.Header.Set("api-key", c.apiKey)
	httpReq.Header.Set("Content-Type", "text/plain;charset=UTF-8")
	httpReq.Header.Set("Connection", "keep-alive")

	resp, err := c.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		return nil, fmt.Errorf("request failed with status %d: %s", resp.StatusCode, string(body))
	}

	responseChan := make(chan LogsResponse)

	go func() {
		defer resp.Body.Close()
		defer close(responseChan)

		reader := bufio.NewReader(resp.Body)
		for {
			select {
			case <-ctx.Done():
				return
			default:
				line, err := reader.ReadString('\n')
				if err != nil {
					if err == io.EOF {
						return
					}
					return
				}

				line = strings.TrimSpace(line)
				if line == "" {
					continue
				}

				if strings.HasPrefix(line, "data: ") {
					data := strings.TrimPrefix(line, "data: ")
					if data == `{"type":"done"}` {
						return
					}

					var response LogsResponse
					if err := json.Unmarshal([]byte(data), &response); err != nil {
						continue // Skip malformed responses
					}

					select {
					case responseChan <- response:
					case <-ctx.Done():
						return
					}
				}
			}
		}
	}()

	return responseChan, nil
}

// Helper functions for creating common request types

// CreateLogsRequest creates a basic logs request
func CreateLogsRequest(dataset string, limit int, filter *Filter) *LogsRequest {
	return &LogsRequest{
		Dataset:       dataset,
		Limit:         limit,
		Order:         "DESC",
		ReturnResults: true,
		Filter:        filter,
	}
}

// CreateFilter creates a filter with the specified parameters
func CreateFilter(key, operation, dataType string, values []string) *Filter {
	return &Filter{
		K:         key,
		V:         values,
		Op:        operation,
		DataType:  dataType,
		Extracted: false,
		Computed:  false,
	}
}

// CreateQueryParams creates query parameters
func CreateQueryParams(startTime, endTime, tagName, dataType string) QueryParams {
	return QueryParams{
		StartTime: startTime,
		EndTime:   endTime,
		TagName:   tagName,
		DataType:  dataType,
	}
}
