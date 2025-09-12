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

// LogsResponse represents a response from the logs endpoints
type LogsResponse struct {
	ID      string                 `json:"id"`
	Type    string                 `json:"type"`
	Message map[string]interface{} `json:"message"`
	Data    map[string]interface{} `json:"data"`
}

// NewClient creates a new API client with proper configuration
func NewClient(cfg *config.Config) *Client {
	return &Client{
		baseURL: cfg.LAKERUNNER_QUERY_URL,
		apiKey:  cfg.LAKERUNNER_API_KEY,
		client: &http.Client{
			Timeout: 60 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:       10,
				IdleConnTimeout:    60 * time.Second,
				DisableCompression: false,
			},
		},
	}
}

// setCommonHeaders sets the common headers for all requests
func (c *Client) setCommonHeaders(req *http.Request) {
	req.Header.Set("Accept", "text/event-stream")
	req.Header.Set("x-cardinalhq-api-key", c.apiKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Connection", "keep-alive")
	origin := strings.TrimSuffix(c.baseURL, "/")
	req.Header.Set("Origin", origin)
	req.Header.Set("User-Agent", "lakerunner-cli/1.0")
}

// QueryLogs makes a request to logs query and returns a channel of responses
func (c *Client) QueryLogs(ctx context.Context, q string, s string, e string, limit int, reverse bool) (<-chan LogsResponse, error) {
	url := c.baseURL + "/api/v1/logs/query"

	body := map[string]interface{}{
		"q":       q,
		"s":       s,
		"e":       e,
		"limit":   limit,
		"reverse": reverse,
	}
	jsonData, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	c.setCommonHeaders(httpReq)

	return c.streamResponses(ctx, httpReq)
}

// QueryLogTags makes a request to tags query and returns a json response
func (c *Client) QueryLogTags(ctx context.Context, s string, e string) (<-chan LogsResponse, error) {
	url := c.baseURL + "/api/v1/logs/tags"

	body := map[string]interface{}{
		"s": s,
		"e": e,
	}
	jsonData, _ := json.Marshal(body)
	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	c.setCommonHeaders(httpReq)

	resp, err := c.client.Do(httpReq)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("request failed with status %d: %s", resp.StatusCode, string(body))
	}
	var parsed struct {
		Tags []string `json:"tags"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return nil, fmt.Errorf("failed to decode tags: %w", err)
	}

	responseChan := make(chan LogsResponse, 1)
	go func() {
		defer close(responseChan)
		msg := map[string]interface{}{"tags": parsed.Tags}
		responseChan <- LogsResponse{Type: "data", Message: msg}
	}()
	return responseChan, nil
}

// QueryLogTagValues makes a request to tag values query and returns a channel of responses
func (c *Client) QueryLogTagValues(ctx context.Context, tagName, q, s, e string) (<-chan LogsResponse, error) {
	url := fmt.Sprintf("%s/api/v1/logs/tagvalues?tagName=%s", c.baseURL, tagName)

	body := map[string]interface{}{
		"s": s,
		"e": e,
	}
	if q != "" {
		body["q"] = q
	}

	jsonData, err := json.Marshal(body)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, "POST", url, bytes.NewBuffer(jsonData))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	c.setCommonHeaders(httpReq)

	return c.streamResponses(ctx, httpReq)
}

// SSE streaming logic
func (c *Client) streamResponses(ctx context.Context, httpReq *http.Request) (<-chan LogsResponse, error) {
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

		reader := bufio.NewReaderSize(resp.Body, 4096)
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
