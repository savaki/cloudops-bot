package bedrock

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/bedrockruntime"
	"github.com/savaki/cloudops-bot/pkg/models"
)

const (
	// Default Bedrock model ID for Claude 3.5 Sonnet
	DefaultModelID = "anthropic.claude-3-5-sonnet-20241022-v2:0"
)

// Client is a client for AWS Bedrock Runtime (Claude models)
type Client struct {
	client  *bedrockruntime.Client
	modelID string
}

// NewClient creates a new Bedrock client
func NewClient(cfg aws.Config) *Client {
	return &Client{
		client:  bedrockruntime.NewFromConfig(cfg),
		modelID: DefaultModelID,
	}
}

// SetModel allows overriding the default model ID
func (c *Client) SetModel(modelID string) {
	c.modelID = modelID
}

// BedrockRequest represents a request to Bedrock (Claude Messages API format)
type BedrockRequest struct {
	AnthropicVersion string           `json:"anthropic_version"`
	MaxTokens        int              `json:"max_tokens"`
	Messages         []models.Message `json:"messages"`
	System           string           `json:"system,omitempty"`
}

// BedrockResponse represents a response from Bedrock
type BedrockResponse struct {
	ID      string `json:"id"`
	Type    string `json:"type"`
	Role    string `json:"role"`
	Content []struct {
		Type string `json:"type"`
		Text string `json:"text"`
	} `json:"content"`
	Model       string `json:"model"`
	StopReason  string `json:"stop_reason"`
	Usage       struct {
		InputTokens  int `json:"input_tokens"`
		OutputTokens int `json:"output_tokens"`
	} `json:"usage"`
}

// SendMessage sends a message to Claude via Bedrock with conversation history
func (c *Client) SendMessage(ctx context.Context, messages []models.Message, systemPrompt string) (string, error) {
	if len(messages) == 0 {
		return "", fmt.Errorf("messages cannot be empty")
	}

	// Build request in Claude Messages API format
	req := BedrockRequest{
		AnthropicVersion: "bedrock-2023-05-31",
		MaxTokens:        4096,
		Messages:         messages,
		System:           systemPrompt,
	}

	// Marshal request body
	body, err := json.Marshal(req)
	if err != nil {
		return "", fmt.Errorf("marshal request: %w", err)
	}

	// Invoke Bedrock model
	output, err := c.client.InvokeModel(ctx, &bedrockruntime.InvokeModelInput{
		ModelId:     aws.String(c.modelID),
		ContentType: aws.String("application/json"),
		Accept:      aws.String("application/json"),
		Body:        body,
	})
	if err != nil {
		return "", fmt.Errorf("invoke bedrock model: %w", err)
	}

	// Parse response
	var response BedrockResponse
	if err := json.Unmarshal(output.Body, &response); err != nil {
		return "", fmt.Errorf("unmarshal response: %w", err)
	}

	// Extract text from response
	if len(response.Content) == 0 {
		return "", fmt.Errorf("empty response from Bedrock")
	}

	return response.Content[0].Text, nil
}

// GetSystemPrompt returns the default system prompt for CloudOps assistant
func GetSystemPrompt() string {
	return `You are CloudOps Bot, an AWS cloud operations assistant. You help users troubleshoot and understand their AWS infrastructure.

Your capabilities:
- Answer questions about AWS services (EC2, ECS, RDS, Lambda, CloudWatch, etc.)
- Explain AWS concepts and best practices
- Help diagnose issues based on user descriptions
- Provide step-by-step guidance for common operations

Guidelines:
- Be concise but thorough in your responses
- Use technical terminology appropriately
- Suggest AWS CLI commands or console actions when relevant
- Always prioritize security and cost optimization
- If you're unsure, acknowledge limitations and suggest next steps

Current limitations:
- You cannot directly query AWS APIs (user must provide information)
- You cannot make changes to AWS resources
- You provide guidance, not automated fixes

Respond in a friendly, professional tone. Use markdown formatting for code blocks and commands.`
}
