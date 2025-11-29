package dynamodb

import (
	"context"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
)

// NewClient creates a new DynamoDB client from AWS config
func NewClient(ctx context.Context) (*dynamodb.Client, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, err
	}

	return dynamodb.NewFromConfig(cfg), nil
}

// NewClientWithConfig creates a DynamoDB client from existing AWS config
func NewClientWithConfig(cfg aws.Config) *dynamodb.Client {
	return dynamodb.NewFromConfig(cfg)
}
