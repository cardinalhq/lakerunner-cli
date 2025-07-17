package github

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	gh "github.com/google/go-github/v57/github"
)

type Client struct {
	client *gh.Client
}

func NewClient() *Client {
	return &Client{
		client: gh.NewClient(nil),
	}
}

// DownloadFiles recursively downloads all files and folders from the given path in the repo
func (c *Client) DownloadFiles(ctx context.Context, repoURL, path, localDir string) error {
	owner, repo, err := parseRepoURL(repoURL)
	if err != nil {
		return fmt.Errorf("failed to parse repository URL: %w", err)
	}

	return c.downloadRecursive(ctx, owner, repo, path, localDir)
}

func (c *Client) downloadRecursive(ctx context.Context, owner, repo, path, localDir string) error {
	_, contents, _, err := c.client.Repositories.GetContents(ctx, owner, repo, path, nil)
	if err != nil {
		return fmt.Errorf("failed to get repository contents for %s: %w", path, err)
	}

	for _, content := range contents {
		if content.GetType() == "dir" {
			subDir := filepath.Join(localDir, content.GetName())
			if err := os.MkdirAll(subDir, 0755); err != nil {
				return fmt.Errorf("failed to create local directory: %w", err)
			}
			if err := c.downloadRecursive(ctx, owner, repo, content.GetPath(), subDir); err != nil {
				return err
			}
		} else if content.GetType() == "file" {
			if err := c.downloadFile(ctx, owner, repo, content, localDir); err != nil {
				return err
			}
		}
	}
	return nil
}

func (c *Client) downloadFile(ctx context.Context, owner, repo string, content *gh.RepositoryContent, localDir string) error {
	fileContent, _, err := c.client.Repositories.DownloadContents(ctx, owner, repo, content.GetPath(), nil)
	if err != nil {
		return fmt.Errorf("failed to download file content: %w", err)
	}
	defer fileContent.Close()

	localPath := filepath.Join(localDir, content.GetName())
	file, err := os.Create(localPath)
	if err != nil {
		return fmt.Errorf("failed to create local file: %w", err)
	}
	defer file.Close()

	_, err = io.Copy(file, fileContent)
	if err != nil {
		return fmt.Errorf("failed to write file content: %w", err)
	}

	fmt.Printf("Downloaded: %s\n", localPath)
	return nil
}

func parseRepoURL(url string) (string, string, error) {
	url = strings.TrimPrefix(url, "https://github.com/")
	url = strings.TrimPrefix(url, "http://github.com/")
	parts := strings.Split(strings.TrimSuffix(url, ".git"), "/")
	if len(parts) < 2 {
		return "", "", fmt.Errorf("invalid GitHub URL format")
	}
	return parts[0], parts[1], nil
}
