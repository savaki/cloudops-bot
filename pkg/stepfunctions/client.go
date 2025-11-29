package stepfunctions

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sfn"
	"github.com/savaki/cloudops-bot/pkg/models"
)

// Client is a wrapper around AWS Step Functions SDK
type Client struct {
	client *sfn.Client
}

// NewClient creates a new Step Functions client
func NewClient(cfg aws.Config) *Client {
	return &Client{
		client: sfn.NewFromConfig(cfg),
	}
}

// StartConversation starts a Step Functions execution for a conversation
// This will spawn an ECS Fargate task to handle the conversation
func (c *Client) StartConversation(ctx context.Context, stateMachineArn string, conversation *models.Conversation) (string, error) {
	// Prepare input for Step Functions
	input := map[string]string{
		"conversationId": conversation.ConversationID,
		"channelId":      conversation.ChannelID,
		"userId":         conversation.UserID,
	}

	inputJSON, err := json.Marshal(input)
	if err != nil {
		return "", fmt.Errorf("marshal input: %w", err)
	}

	// Start execution
	result, err := c.client.StartExecution(ctx, &sfn.StartExecutionInput{
		StateMachineArn: &stateMachineArn,
		Input:           aws.String(string(inputJSON)),
		Name:            aws.String(fmt.Sprintf("conv-%s", conversation.ConversationID)),
	})
	if err != nil {
		return "", fmt.Errorf("start execution: %w", err)
	}

	return *result.ExecutionArn, nil
}
