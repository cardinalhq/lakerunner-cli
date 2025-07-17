package demo

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/go-github/v57/github"
	"github.com/minio/madmin-go/v3"
	minio "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/minio/minio-go/v7/pkg/notification"
	"github.com/spf13/cobra"
)

var (
	endpoint        string
	accessKey       string
	secretKey       string
	bucketName      string
	webhookEndpoint string
	repoOwner       string
	repoName        string
	repoPath        string
)

var SetupCmd = &cobra.Command{
	Use:   "setup",
	Short: "Automate MinIO bucket, webhook, and upload Parquet files from GitHub",
	RunE: func(cmd *cobra.Command, args []string) error {
		log.Println("Starting MinIO setup script...")

		// 1. Set up MinIO client
		minioClient, err := minio.New(endpoint, &minio.Options{
			Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
			Secure: false,
		})
		if err != nil {
			return fmt.Errorf("Failed to create MinIO client: %w", err)
		}

		// Set up MinIO admin client
		adminClient, err := madmin.New(endpoint, accessKey, secretKey, false)
		if err != nil {
			return fmt.Errorf("Failed to create MinIO admin client: %w", err)
		}

		// 2. Create bucket
		log.Println("Creating bucket:", bucketName)
		err = minioClient.MakeBucket(context.Background(), bucketName, minio.MakeBucketOptions{})
		if err != nil {
			// Check if bucket already exists
			exists, err := minioClient.BucketExists(context.Background(), bucketName)
			if err != nil || !exists {
				return fmt.Errorf("Failed to create bucket: %w", err)
			}
			log.Println("Bucket already exists")
		}

		// 3. Configure webhook notification
		log.Println("Configuring webhook notification...")
		webhookConfig := fmt.Sprintf("notify_webhook:test endpoint=\"%s\"", webhookEndpoint)
		err = adminClient.SetConfig(context.Background(), bytes.NewReader([]byte(webhookConfig)))
		if err != nil {
			return fmt.Errorf("Failed to set webhook config: %w", err)
		}

		// 4. Restart MinIO service
		log.Println("Restarting MinIO service...")
		err = adminClient.ServiceRestart(context.Background())
		if err != nil {
			log.Printf("Warning: Failed to restart service (this might be expected in some setups): %v", err)
		}

		time.Sleep(8 * time.Second)

		// 5. Add event notification
		log.Println("Adding event notification...")
		arn := notification.NewArn("minio", "sqs", "", "test", "webhook")
		queueConfig := notification.NewConfig(arn)
		queueConfig.AddEvents(notification.ObjectCreatedAll)
		queueConfig.AddFilterPrefix("")
		queueConfig.AddFilterSuffix("")
		config := notification.Configuration{}
		config.AddQueue(queueConfig)
		err = minioClient.SetBucketNotification(context.Background(), bucketName, config)
		if err != nil {
			return fmt.Errorf("Failed to set bucket notification: %w", err)
		}

		// 6. Download files from GitHub repo
		log.Println("Downloading files from GitHub repo...")
		tempDir, err := os.MkdirTemp("", "github-download")
		if err != nil {
			return fmt.Errorf("Failed to create temp directory: %w", err)
		}
		defer os.RemoveAll(tempDir)

		client := github.NewClient(nil)
		// Recursively download the entire otel-raw directory structure, skipping .git and hidden files
		err = downloadDirectoryRecursively(client, repoOwner, repoName, repoPath, tempDir)
		if err != nil {
			return fmt.Errorf("Failed to download repo contents: %w", err)
		}

		// 7. Upload files to MinIO recursively
		log.Println("Uploading files to MinIO...")
		err = uploadDirectoryToMinIO(minioClient, bucketName, tempDir, "otel-raw")
		if err != nil {
			return fmt.Errorf("Failed to upload files: %w", err)
		}

		log.Println("Setup completed successfully!")
		return nil
	},
}

func init() {
	SetupCmd.Flags().StringVar(&endpoint, "endpoint", "localhost:9000", "MinIO endpoint")
	SetupCmd.Flags().StringVar(&accessKey, "access-key", "muhfw6BmPZQxyzTZfBnO", "MinIO access key")
	SetupCmd.Flags().StringVar(&secretKey, "secret-key", "tyLdAHxvvjXMTx8sQM8znvgh2itpfNYwmPClPw5", "MinIO secret key")
	SetupCmd.Flags().StringVar(&bucketName, "bucket", "lakerunner", "Bucket name")
	SetupCmd.Flags().StringVar(&webhookEndpoint, "webhook-endpoint", "http://lakerunner-pubsub-http.lakerunner.svc.cluster.local:8080", "Webhook endpoint")
	SetupCmd.Flags().StringVar(&repoOwner, "repo-owner", "aditya-prajapati", "GitHub repo owner")
	SetupCmd.Flags().StringVar(&repoName, "repo-name", "otel-pq", "GitHub repo name")
	SetupCmd.Flags().StringVar(&repoPath, "repo-path", "otel-raw", "Path within the repo to download")
}

func uploadDirectoryToMinIO(client *minio.Client, bucketName, localPath, remotePath string) error {
	entries, err := os.ReadDir(localPath)
	if err != nil {
		return err
	}
	for _, entry := range entries {
		localFilePath := filepath.Join(localPath, entry.Name())
		remoteFilePath := filepath.Join(remotePath, entry.Name())
		if entry.IsDir() {
			err = uploadDirectoryToMinIO(client, bucketName, localFilePath, remoteFilePath)
			if err != nil {
				log.Printf("Warning: Failed to upload directory %s: %v", localFilePath, err)
			}
		} else {
			file, err := os.Open(localFilePath)
			if err != nil {
				log.Printf("Warning: Failed to open file %s: %v", localFilePath, err)
				continue
			}
			defer file.Close()
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
func downloadDirectoryRecursively(client *github.Client, owner, repo, path, localBase string) error {
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
			err := downloadDirectoryRecursively(client, owner, repo, subPath, subLocal)
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
			defer fileContent.Close()
			localPath := filepath.Join(localBase, name)
			file, err := os.Create(localPath)
			if err != nil {
				log.Printf("Warning: Failed to create file %s: %v", localPath, err)
				continue
			}
			defer file.Close()
			_, err = io.Copy(file, fileContent)
			if err != nil {
				log.Printf("Warning: Failed to write file %s: %v", localPath, err)
				continue
			}
		}
	}
	return nil
}
