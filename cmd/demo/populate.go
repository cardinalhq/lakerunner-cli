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

package demo

import (
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/go-github/v57/github"
	minio "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/spf13/cobra"
)

var (
	populateEndpoint   string
	populateAccessKey  string
	populateSecretKey  string
	populateBucketName string
	populateRepoOwner  string
	populateRepoName   string
	populateRepoPath   string
)

var PopulateCmd = &cobra.Command{
	Use:   "populate",
	Short: "Download files from GitHub and upload them to MinIO",
	RunE: func(cmd *cobra.Command, args []string) error {
		log.Println("Starting file population...")

		minioClient, err := minio.New(populateEndpoint, &minio.Options{
			Creds:  credentials.NewStaticV4(populateAccessKey, populateSecretKey, ""),
			Secure: false,
		})
		if err != nil {
			return fmt.Errorf("failed to create MinIO client: %w", err)
		}

		// Download files from GitHub repo
		log.Println("Downloading files from GitHub repo...")
		tempDir, err := os.MkdirTemp("", "github-download")
		if err != nil {
			return fmt.Errorf("failed to create temp directory: %w", err)
		}
		defer func() {
			if err := os.RemoveAll(tempDir); err != nil {
				log.Printf("Warning: Failed to remove temp directory %s: %v", tempDir, err)
			}
		}()

		client := github.NewClient(nil)
		// Recursively download the entire directory structure, skipping .git and hidden files
		err = downloadDirectoryRecursivelyPopulate(client, populateRepoOwner, populateRepoName, populateRepoPath, tempDir)
		if err != nil {
			return fmt.Errorf("failed to download repo contents: %w", err)
		}

		// Upload files to MinIO recursively
		log.Println("Uploading files to MinIO...")
		err = uploadDirectoryToMinIOPopulate(minioClient, populateBucketName, tempDir, populateRepoPath)
		if err != nil {
			return fmt.Errorf("failed to upload files: %w", err)
		}

		log.Println("File population completed successfully!")
		return nil
	},
}

func init() {
	PopulateCmd.Flags().StringVar(&populateEndpoint, "endpoint", "localhost:9000", "MinIO endpoint")
	PopulateCmd.Flags().StringVar(&populateAccessKey, "access-key", "muhfw6BmPZQxyzTZfBnO", "MinIO access key")
	PopulateCmd.Flags().StringVar(&populateSecretKey, "secret-key", "tyLdAHxvvjXMTx8sQM8znvgh2itpfNYwmPClPw5", "MinIO secret key")
	PopulateCmd.Flags().StringVar(&populateBucketName, "bucket", "lakerunner", "Bucket name")
	PopulateCmd.Flags().StringVar(&populateRepoOwner, "repo-owner", "aditya-prajapati", "GitHub repo owner")
	PopulateCmd.Flags().StringVar(&populateRepoName, "repo-name", "otel-pq", "GitHub repo name")
	PopulateCmd.Flags().StringVar(&populateRepoPath, "repo-path", "otel-raw", "Path within the repo to download")
}

func uploadDirectoryToMinIOPopulate(client *minio.Client, bucketName, localPath, remotePath string) error {
	entries, err := os.ReadDir(localPath)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		localFilePath := filepath.Join(localPath, entry.Name())
		remoteFilePath := filepath.Join(remotePath, entry.Name())
		if entry.IsDir() {
			err = uploadDirectoryToMinIOPopulate(client, bucketName, localFilePath, remoteFilePath)
			if err != nil {
				log.Printf("Warning: Failed to upload directory %s: %v", localFilePath, err)
			}
		} else {
			file, err := os.Open(localFilePath)
			if err != nil {
				log.Printf("Warning: Failed to open file %s: %v", localFilePath, err)
				continue
			}
			defer func() {
				if err := file.Close(); err != nil {
					log.Printf("Warning: Failed to close file: %v", err)
				}
			}()
			fileInfo, err := file.Stat()
			if err != nil {
				log.Printf("Warning: Failed to get file info for %s: %v", localFilePath, err)
				continue
			}
			_, err = client.PutObject(context.Background(), bucketName, remoteFilePath, file, fileInfo.Size(), minio.PutObjectOptions{})
			if err != nil {
				log.Printf("Warning: Failed to upload file %s: %v", localFilePath, err)
			} else {
				log.Printf("Uploaded: %s -> %s", localFilePath, remoteFilePath)
			}
		}
	}
	return nil
}

// Recursively downloads a directory from GitHub, skipping .git and hidden files
func downloadDirectoryRecursivelyPopulate(client *github.Client, owner, repo, path, localBase string) error {
	_, contents, _, err := client.Repositories.GetContents(context.Background(), owner, repo, path, nil)
	if err != nil {
		return err
	}
	for _, content := range contents {
		name := content.GetName()
		if strings.HasPrefix(name, ".") || name == ".git" {
			continue // skip hidden files and .git
		}
		if content.GetType() == "dir" {
			// Recursively download subdirectory
			subPath := filepath.Join(path, name)
			subLocal := filepath.Join(localBase, name)
			if err := os.MkdirAll(subLocal, 0755); err != nil {
				log.Printf("Warning: Failed to create directory %s: %v", subLocal, err)
				continue
			}
			err := downloadDirectoryRecursivelyPopulate(client, owner, repo, subPath, subLocal)
			if err != nil {
				log.Printf("Warning: Failed to download directory %s: %v", subPath, err)
			}
		} else if content.GetType() == "file" {
			log.Printf("Downloading: %s", content.GetPath())
			fileContent, _, err := client.Repositories.DownloadContents(context.Background(), owner, repo, content.GetPath(), nil)
			if err != nil {
				log.Printf("Warning: Failed to download %s: %v", content.GetPath(), err)
				continue
			}
			defer func() {
				if err := fileContent.Close(); err != nil {
					log.Printf("Warning: Failed to close file content: %v", err)
				}
			}()
			localPath := filepath.Join(localBase, name)
			file, err := os.Create(localPath)
			if err != nil {
				log.Printf("Warning: Failed to create file %s: %v", localPath, err)
				continue
			}
			defer func() {
				if err := file.Close(); err != nil {
					log.Printf("Warning: Failed to close file: %v", err)
				}
			}()
			_, err = io.Copy(file, fileContent)
			if err != nil {
				log.Printf("Warning: Failed to write file %s: %v", localPath, err)
				continue
			}
		}
	}
	return nil
}
