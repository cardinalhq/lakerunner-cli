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
	"bytes"
	"context"
	"fmt"
	"log"
	"time"

	"github.com/minio/madmin-go/v3"
	minio "github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
	"github.com/minio/minio-go/v7/pkg/notification"
	"github.com/spf13/cobra"
)

var (
	minioEndpoint        string
	minioAccessKey       string
	minioSecretKey       string
	minioBucketName      string
	minioWebhookEndpoint string
)

var MinioSetupCmd = &cobra.Command{
	Use:   "minio-setup",
	Short: "Set up MinIO bucket and webhook configuration",
	RunE: func(cmd *cobra.Command, args []string) error {
		log.Println("Starting MinIO setup...")

		minioClient, err := minio.New(minioEndpoint, &minio.Options{
			Creds:  credentials.NewStaticV4(minioAccessKey, minioSecretKey, ""),
			Secure: false,
		})
		if err != nil {
			return fmt.Errorf("Failed to create MinIO client: %w", err)
		}

		adminClient, err := madmin.New(minioEndpoint, minioAccessKey, minioSecretKey, false)
		if err != nil {
			return fmt.Errorf("Failed to create MinIO admin client: %w", err)
		}

		log.Println("Creating bucket:", minioBucketName)
		err = minioClient.MakeBucket(context.Background(), minioBucketName, minio.MakeBucketOptions{})
		if err != nil {
			exists, err := minioClient.BucketExists(context.Background(), minioBucketName)
			if err != nil || !exists {
				return fmt.Errorf("Failed to create bucket: %w", err)
			}
			log.Println("Bucket already exists")
		}

		log.Println("Configuring webhook notification...")
		webhookConfig := fmt.Sprintf("notify_webhook:test endpoint=\"%s\"", minioWebhookEndpoint)
		err = adminClient.SetConfig(context.Background(), bytes.NewReader([]byte(webhookConfig)))
		if err != nil {
			return fmt.Errorf("Failed to set webhook config: %w", err)
		}

		log.Println("Restarting MinIO service...")
		err = adminClient.ServiceRestart(context.Background())
		if err != nil {
			log.Printf("Warning: Failed to restart service (this might be expected in some setups): %v", err)
		}

		time.Sleep(8 * time.Second)

		log.Println("Adding event notification...")
		arn := notification.NewArn("minio", "sqs", "", "test", "webhook")

		config := notification.Configuration{}
		// need to create 2 seperate configs for the different prefixes we want to support
		queueConfig1 := notification.NewConfig(arn)
		queueConfig1.AddEvents(notification.ObjectCreatedAll)
		queueConfig1.AddFilterPrefix("otel-raw/")
		queueConfig1.AddFilterSuffix("")
		config.AddQueue(queueConfig1)

		// One config for log-raw/
		queueConfig2 := notification.NewConfig(arn)
		queueConfig2.AddEvents(notification.ObjectCreatedAll)
		queueConfig2.AddFilterPrefix("log-raw/")
		queueConfig2.AddFilterSuffix("")
		config.AddQueue(queueConfig2)

		err = minioClient.SetBucketNotification(context.Background(), minioBucketName, config)
		if err != nil {
			return fmt.Errorf("Failed to set bucket notification: %w", err)
		}

		log.Println("MinIO setup completed successfully!")
		return nil
	},
}

func init() {
	MinioSetupCmd.Flags().StringVar(&minioEndpoint, "endpoint", "http://localhost:9000", "MinIO endpoint")
	MinioSetupCmd.Flags().StringVar(&minioAccessKey, "access-key", "", "MinIO access key")
	MinioSetupCmd.Flags().StringVar(&minioSecretKey, "secret-key", "", "MinIO secret key")
	MinioSetupCmd.Flags().StringVar(&minioBucketName, "bucket", "lakerunner", "Bucket name")
	MinioSetupCmd.Flags().StringVar(&minioWebhookEndpoint, "webhook-endpoint", "http://lakerunner-pubsub-http.lakerunner.svc.cluster.local:8080", "Webhook endpoint")
}
