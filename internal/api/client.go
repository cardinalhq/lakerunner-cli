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

// GraphRequest represents a request to the graph endpoint
type GraphRequest struct {
	BaseExpressions map[string]Expression `json:"baseExpressions"`
}

// Expression represents an expression in a graph request
type Expression struct {
	Dataset       string                 `json:"dataset"`
	Limit         int                    `json:"limit"`
	Order         string                 `json:"order"`
	ReturnResults bool                   `json:"returnResults"`
	Filter        *Filter                `json:"filter,omitempty"`
	Chart         map[string]interface{} `json:"chart,omitempty"`
}

// Filter represents a filter for log queries
type Filter struct {
	K         string   `json:"k,omitempty"`
	V         []string `json:"v,omitempty"`
	Op        string   `json:"op,omitempty"`
	DataType  string   `json:"dataType,omitempty"`
	Extracted bool     `json:"extracted,omitempty"`
	Computed  bool     `json:"computed,omitempty"`
	// For nested filters - use map for dynamic keys
	Filters map[string]*Filter `json:"-"`
	// MarshalJSON will handle the dynamic filter keys
}

// MarshalJSON implements custom JSON marshaling for Filter
func (f *Filter) MarshalJSON() ([]byte, error) {
	// Create a map to hold all fields
	result := make(map[string]interface{})

	// Add the base fields
	if f.K != "" {
		result["k"] = f.K
	}
	if len(f.V) > 0 {
		result["v"] = f.V
	}
	if f.Op != "" {
		result["op"] = f.Op
	}
	if f.DataType != "" {
		result["dataType"] = f.DataType
	}
	if f.Extracted {
		result["extracted"] = f.Extracted
	}
	if f.Computed {
		result["computed"] = f.Computed
	}

	// Add dynamic filters
	if f.Filters != nil {
		for key, filter := range f.Filters {
			result[key] = filter
		}
	}

	return json.Marshal(result)
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
			Timeout: 60 * time.Second, // Increased timeout for streaming
			Transport: &http.Transport{
				MaxIdleConns:       10,
				IdleConnTimeout:    60 * time.Second, // Increased idle timeout
				DisableCompression: false,
			},
		},
	}
}

// buildURL constructs the URL with query parameters
func (c *Client) buildURL(endpoint string, params QueryParams) string {
	// Ensure baseURL doesn't end with slash and endpoint starts with slash
	baseURL := strings.TrimSuffix(c.baseURL, "/")
	if !strings.HasPrefix(endpoint, "/") {
		endpoint = "/" + endpoint
	}

	url := baseURL + endpoint

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

// setCommonHeaders sets the common headers for all requests
func (c *Client) setCommonHeaders(req *http.Request) {
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("api-key", c.apiKey)
	req.Header.Set("Content-Type", "text/plain;charset=UTF-8")
	req.Header.Set("Connection", "keep-alive")
	// Fix the Origin header to not have trailing slash
	origin := strings.TrimSuffix(c.baseURL, "/")
	req.Header.Set("Origin", origin)
	req.Header.Set("User-Agent", "lakerunner-cli/1.0")
}

// QueryGraph makes a request to the graph endpoint and returns a channel of responses
func (c *Client) QueryGraph(ctx context.Context, req *GraphRequest, params QueryParams) (<-chan LogsResponse, error) {
	url := c.buildURL("/api/v1/graph", params)

	jsonData, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	c.setCommonHeaders(httpReq)

	resp, err := c.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		return nil, fmt.Errorf("request failed with status %d: %s", resp.StatusCode, string(body))
	}

	responseChan := make(chan LogsResponse)

	go func() {
		defer func() { _ = resp.Body.Close() }()
		defer close(responseChan)

		reader := bufio.NewReaderSize(resp.Body, 4096) // Larger buffer for efficiency
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
						continue
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

// QueryTags makes a request to the tags endpoint and returns a channel of responses
func (c *Client) QueryTags(ctx context.Context, req *Expression, params QueryParams) (<-chan LogsResponse, error) {
	url := c.buildURL("/api/v1/tags/logs", params)

	jsonData, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	c.setCommonHeaders(httpReq)

	resp, err := c.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		return nil, fmt.Errorf("request failed with status %d: %s", resp.StatusCode, string(body))
	}

	responseChan := make(chan LogsResponse)

	go func() {
		defer func() { _ = resp.Body.Close() }()
		defer close(responseChan)

		reader := bufio.NewReaderSize(resp.Body, 4096) // Larger buffer for efficiency
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
						continue
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

// CreateGraphRequest creates a graph request with expressions
func CreateGraphRequest(expressions map[string]Expression) *GraphRequest {
	return &GraphRequest{
		BaseExpressions: expressions,
	}
}

// CreateExpression creates an expression for graph queries
func CreateExpression(dataset string, limit int, filter *Filter, chart map[string]interface{}) Expression {
	return Expression{
		Dataset:       dataset,
		Limit:         limit,
		Order:         "DESC",
		ReturnResults: true,
		Filter:        filter,
		Chart:         chart,
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

// CreateNestedFilter creates a filter with multiple conditions using AND logic
func CreateNestedFilter(filters ...*Filter) *Filter {
	if len(filters) == 0 {
		return nil
	}
	if len(filters) == 1 {
		return filters[0]
	}

	// Create nested filter structure
	result := &Filter{
		Op:      "and",
		Filters: make(map[string]*Filter),
	}

	// Add filters dynamically with q1, q2, q3, etc.
	for i, filter := range filters {
		key := fmt.Sprintf("q%d", i+1)
		result.Filters[key] = filter
	}

	return result
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
