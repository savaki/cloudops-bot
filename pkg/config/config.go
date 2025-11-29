package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// Config holds application configuration loaded from environment variables
type Config struct {
	// AWS
	AWSRegion string

	// Slack
	SlackBotToken   string
	SlackSigningKey string

	// DynamoDB
	ConversationsTable       string
	ConversationHistoryTable string
	InactivityTimeoutMinutes int
	ConversationTTLDays      int

	// Bedrock
	BedrockModelID string

	// Step Functions
	StepFunctionArn string

	// Environment
	Environment string
}

// Load reads configuration from environment variables
func Load() (*Config, error) {
	cfg := &Config{
		AWSRegion:                getEnv("AWS_REGION", "us-east-1"),
		SlackBotToken:            getEnv("SLACK_BOT_TOKEN", ""),
		SlackSigningKey:          getEnv("SLACK_SIGNING_KEY", ""),
		ConversationsTable:       getEnv("CONVERSATIONS_TABLE", "cloudops-conversations"),
		ConversationHistoryTable: getEnv("CONVERSATION_HISTORY_TABLE", "cloudops-conversation-history"),
		InactivityTimeoutMinutes: getEnvInt("INACTIVITY_TIMEOUT_MINUTES", 30),
		ConversationTTLDays:      getEnvInt("CONVERSATION_TTL_DAYS", 7),
		BedrockModelID:           getEnv("BEDROCK_MODEL_ID", "anthropic.claude-3-5-sonnet-20241022-v2:0"),
		StepFunctionArn:          getEnv("STEP_FUNCTION_ARN", ""),
		Environment:              getEnv("ENVIRONMENT", "dev"),
	}

	// Validate required fields
	if err := cfg.Validate(); err != nil {
		return nil, err
	}

	return cfg, nil
}

// Validate checks that required configuration is present
func (c *Config) Validate() error {
	if c.SlackBotToken == "" {
		return fmt.Errorf("SLACK_BOT_TOKEN is required")
	}
	if c.SlackSigningKey == "" {
		return fmt.Errorf("SLACK_SIGNING_KEY is required")
	}
	if c.ConversationsTable == "" {
		return fmt.Errorf("CONVERSATIONS_TABLE is required")
	}
	if c.ConversationHistoryTable == "" {
		return fmt.Errorf("CONVERSATION_HISTORY_TABLE is required")
	}
	return nil
}

// ValidateLambda checks Lambda-specific configuration
func (c *Config) ValidateLambda() error {
	if err := c.Validate(); err != nil {
		return err
	}
	if c.StepFunctionArn == "" {
		return fmt.Errorf("STEP_FUNCTION_ARN is required for Lambda")
	}
	return nil
}

// GetInactivityTimeout returns the inactivity timeout as a duration
func (c *Config) GetInactivityTimeout() time.Duration {
	return time.Duration(c.InactivityTimeoutMinutes) * time.Minute
}

// GetConversationTTL returns the TTL duration for conversations
func (c *Config) GetConversationTTL() time.Duration {
	return time.Duration(c.ConversationTTLDays*24) * time.Hour
}

// Helper functions

func getEnv(key, defaultValue string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return defaultValue
}

func getEnvInt(key string, defaultValue int) int {
	if value, ok := os.LookupEnv(key); ok {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

func getEnvBool(key string, defaultValue bool) bool {
	if value, ok := os.LookupEnv(key); ok {
		switch value {
		case "true", "1", "yes", "on":
			return true
		case "false", "0", "no", "off":
			return false
		}
	}
	return defaultValue
}
