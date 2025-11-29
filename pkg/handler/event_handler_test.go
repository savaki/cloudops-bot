package handler

import (
	"context"
	"testing"
)

func TestNewEventHandler(t *testing.T) {
	handler := NewEventHandler()

	if handler == nil {
		t.Error("NewEventHandler() returned nil")
	}
}

func TestHandleAppMention(t *testing.T) {
	handler := NewEventHandler()
	ctx := context.Background()

	tests := []struct {
		name      string
		userID    string
		channelID string
		command   string
		wantErr   bool
	}{
		{
			name:      "valid app mention",
			userID:    "U123456",
			channelID: "C987654",
			command:   "check ec2 status",
			wantErr:   false,
		},
		{
			name:      "app mention with empty command",
			userID:    "U123456",
			channelID: "C987654",
			command:   "",
			wantErr:   false,
		},
		{
			name:      "app mention with long command",
			userID:    "U123456",
			channelID: "C987654",
			command:   "check the status of all ec2 instances in us-east-1 region and list their ip addresses",
			wantErr:   false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := handler.HandleAppMention(ctx, tt.userID, tt.channelID, tt.command)
			if (err != nil) != tt.wantErr {
				t.Errorf("HandleAppMention() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestHandleChannelMessage(t *testing.T) {
	handler := NewEventHandler()
	ctx := context.Background()

	tests := []struct {
		name           string
		conversationID string
		userID         string
		text           string
		wantErr        bool
	}{
		{
			name:           "valid channel message",
			conversationID: "conv-abc123",
			userID:         "U123456",
			text:           "What's the status?",
			wantErr:        false,
		},
		{
			name:           "channel message with empty text",
			conversationID: "conv-abc123",
			userID:         "U123456",
			text:           "",
			wantErr:        false,
		},
		{
			name:           "channel message with special characters",
			conversationID: "conv-abc123",
			userID:         "U123456",
			text:           "Check status: !@#$%^&*()",
			wantErr:        false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := handler.HandleChannelMessage(ctx, tt.conversationID, tt.userID, tt.text)
			if (err != nil) != tt.wantErr {
				t.Errorf("HandleChannelMessage() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestHandleAppMentionWithContextCancellation(t *testing.T) {
	handler := NewEventHandler()

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately

	err := handler.HandleAppMention(ctx, "U123", "C456", "test command")
	// Should not error even with cancelled context (stub implementation)
	if err != nil {
		t.Errorf("HandleAppMention() with cancelled context error = %v", err)
	}
}

func TestHandleChannelMessageWithContextCancellation(t *testing.T) {
	handler := NewEventHandler()

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately

	err := handler.HandleChannelMessage(ctx, "conv-123", "U456", "test message")
	// Should not error even with cancelled context (stub implementation)
	if err != nil {
		t.Errorf("HandleChannelMessage() with cancelled context error = %v", err)
	}
}
