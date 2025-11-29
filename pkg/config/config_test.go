package config

import (
	"os"
	"testing"
	"time"
)

func TestLoadConfig(t *testing.T) {
	// Save original env vars
	originalEnv := saveEnvironment()
	defer restoreEnvironment(originalEnv)

	// Set required environment variables
	os.Setenv("AWS_REGION", "us-east-1")
	os.Setenv("SLACK_BOT_TOKEN", "xoxb-test-token")
	os.Setenv("SLACK_SIGNING_KEY", "test-signing-key")
	os.Setenv("CONVERSATIONS_TABLE", "test-conversations")
	os.Setenv("CONVERSATION_HISTORY_TABLE", "test-history")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.AWSRegion != "us-east-1" {
		t.Errorf("AWSRegion = %s, want us-east-1", cfg.AWSRegion)
	}

	if cfg.SlackBotToken != "xoxb-test-token" {
		t.Errorf("SlackBotToken = %s, want xoxb-test-token", cfg.SlackBotToken)
	}

	if cfg.SlackSigningKey != "test-signing-key" {
		t.Errorf("SlackSigningKey = %s, want test-signing-key", cfg.SlackSigningKey)
	}

	if cfg.ConversationsTable != "test-conversations" {
		t.Errorf("ConversationsTable = %s, want test-conversations", cfg.ConversationsTable)
	}
}

func TestLoadConfigMissingRequired(t *testing.T) {
	// Save original env vars
	originalEnv := saveEnvironment()
	defer restoreEnvironment(originalEnv)

	os.Clearenv()

	_, err := Load()
	if err == nil {
		t.Error("Load() should return error when required env vars are missing")
	}
}

func TestConfigDefaultValues(t *testing.T) {
	// Save original env vars
	originalEnv := saveEnvironment()
	defer restoreEnvironment(originalEnv)

	os.Clearenv()
	os.Setenv("AWS_REGION", "us-east-1")
	os.Setenv("SLACK_BOT_TOKEN", "xoxb-test")
	os.Setenv("SLACK_SIGNING_KEY", "key")
	os.Setenv("CONVERSATION_HISTORY_TABLE", "cloudops-conversation-history")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	// Check default values
	if cfg.ConversationsTable != "cloudops-conversations" {
		t.Errorf("Default ConversationsTable = %s, want cloudops-conversations", cfg.ConversationsTable)
	}

	if cfg.ConversationHistoryTable != "cloudops-conversation-history" {
		t.Errorf("Default ConversationHistoryTable = %s, want cloudops-conversation-history", cfg.ConversationHistoryTable)
	}

	if cfg.InactivityTimeoutMinutes != 30 {
		t.Errorf("Default InactivityTimeoutMinutes = %d, want 30", cfg.InactivityTimeoutMinutes)
	}
}

func TestGetInactivityTimeout(t *testing.T) {
	tests := []struct {
		name             string
		timeoutMinutes   int
		expectedDuration time.Duration
	}{
		{
			name:             "default timeout",
			timeoutMinutes:   30,
			expectedDuration: 30 * time.Minute,
		},
		{
			name:             "custom 5 minutes",
			timeoutMinutes:   5,
			expectedDuration: 5 * time.Minute,
		},
		{
			name:             "custom 60 minutes",
			timeoutMinutes:   60,
			expectedDuration: 60 * time.Minute,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := &Config{
				InactivityTimeoutMinutes: tt.timeoutMinutes,
			}

			timeout := cfg.GetInactivityTimeout()
			if timeout != tt.expectedDuration {
				t.Errorf("GetInactivityTimeout() = %v, want %v", timeout, tt.expectedDuration)
			}
		})
	}
}

func TestValidateLambda(t *testing.T) {
	cfg := &Config{
		AWSRegion:                "us-east-1",
		SlackBotToken:            "xoxb-token",
		SlackSigningKey:          "signing-key",
		ConversationsTable:       "table",
		ConversationHistoryTable: "history-table",
		StepFunctionArn:          "arn:aws:states:us-east-1:123456789012:stateMachine:test",
	}

	err := cfg.ValidateLambda()
	if err != nil {
		t.Errorf("ValidateLambda() error = %v, want nil", err)
	}
}

func TestValidateLambdaMissingConversationsTable(t *testing.T) {
	cfg := &Config{
		AWSRegion:       "us-east-1",
		SlackBotToken:   "xoxb-token",
		SlackSigningKey: "signing-key",
	}

	err := cfg.ValidateLambda()
	if err == nil {
		t.Error("ValidateLambda() should error when ConversationsTable is missing")
	}
}

// Helper function to save environment variables
func saveEnvironment() map[string]string {
	env := make(map[string]string)
	for _, pair := range os.Environ() {
		var key, val string
		for i, c := range pair {
			if c == '=' {
				key = pair[:i]
				val = pair[i+1:]
				break
			}
		}
		env[key] = val
	}
	return env
}

// Helper function to restore environment variables
func restoreEnvironment(env map[string]string) {
	os.Clearenv()
	for key, val := range env {
		os.Setenv(key, val)
	}
}
