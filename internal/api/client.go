package api

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/lakerunner/cli/internal/config"
)

// Client represents the API client
type Client struct {
	config *config.Config
	client *http.Client
}

// NewClient creates a new API client
func NewClient(cfg *config.Config) *Client {
	return &Client{
		config: cfg,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// GetLogs retrieves logs with the given filters
func (c *Client) GetLogs(filters map[string]interface{}) ([]byte, error) {
	// TODO: Implement actual API call
	return []byte(`{"message": "GetLogs not implemented yet"}`), nil
}

// GetLogKeys retrieves available log keys
func (c *Client) GetLogKeys(duration string) ([]byte, error) {
	// TODO: Implement actual API call
	return []byte(`{"message": "GetLogKeys not implemented yet"}`), nil
}

// GetLogKeyValues retrieves key-value pairs for specific keys
func (c *Client) GetLogKeyValues(keys []string, filters []string) ([]byte, error) {
	// TODO: Implement actual API call
	return []byte(`{"message": "GetLogKeyValues not implemented yet"}`), nil
}

// makeRequest is a helper method for making HTTP requests
func (c *Client) makeRequest(method, endpoint string, body interface{}) ([]byte, error) {
	var reqBody []byte
	var err error

	if body != nil {
		reqBody, err = json.Marshal(body)
		if err != nil {
			return nil, fmt.Errorf("failed to marshal request body: %w", err)
		}
	}

	req, err := http.NewRequest(method, c.config.APIURL+endpoint, bytes.NewBuffer(reqBody))
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.config.APIKey)

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to make request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("API request failed with status: %d", resp.StatusCode)
	}

	var responseBody []byte
	_, err = resp.Body.Read(responseBody)
	if err != nil {
		return nil, fmt.Errorf("failed to read response body: %w", err)
	}

	return responseBody, nil
}
