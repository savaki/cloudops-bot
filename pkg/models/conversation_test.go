package models

import (
	"strings"
	"testing"
	"time"
)

func TestNewConversation(t *testing.T) {
	channelID := "C123456"
	userID := "U789ABC"
	initialCommand := "check ec2 status"

	conv := NewConversation(channelID, userID, initialCommand)

	if conv.ChannelID != channelID {
		t.Errorf("ChannelID = %s, want %s", conv.ChannelID, channelID)
	}

	if conv.UserID != userID {
		t.Errorf("UserID = %s, want %s", conv.UserID, userID)
	}

	if conv.InitialCommand != initialCommand {
		t.Errorf("InitialCommand = %s, want %s", conv.InitialCommand, initialCommand)
	}

	if conv.Status != StatusPending {
		t.Errorf("Status = %s, want %s", conv.Status, StatusPending)
	}

	if conv.ConversationID == "" {
		t.Error("ConversationID should not be empty")
	}

	if !strings.HasPrefix(conv.ConversationID, "conv-") {
		t.Errorf("ConversationID should start with 'conv-', got %s", conv.ConversationID)
	}

	if conv.CreatedAt.IsZero() {
		t.Error("CreatedAt should be set")
	}

	if conv.LastHeartbeat.IsZero() {
		t.Error("LastHeartbeat should be set")
	}
}

func TestConversationUpdateStatus(t *testing.T) {
	conv := NewConversation("C123", "U456", "test")
	originalCreatedAt := conv.CreatedAt

	tests := []struct {
		name   string
		status string
		check  func(conv *Conversation) error
	}{
		{
			name:   "update to active",
			status: StatusActive,
			check: func(conv *Conversation) error {
				if conv.Status != StatusActive {
					t.Errorf("Status = %s, want %s", conv.Status, StatusActive)
				}
				return nil
			},
		},
		{
			name:   "update to completed",
			status: StatusCompleted,
			check: func(conv *Conversation) error {
				if conv.Status != StatusCompleted {
					t.Errorf("Status = %s, want %s", conv.Status, StatusCompleted)
				}
				if conv.CompletedAt == nil {
					t.Error("CompletedAt should be set when status is Completed")
				}
				return nil
			},
		},
		{
			name:   "update to failed",
			status: StatusFailed,
			check: func(conv *Conversation) error {
				if conv.Status != StatusFailed {
					t.Errorf("Status = %s, want %s", conv.Status, StatusFailed)
				}
				if conv.CompletedAt == nil {
					t.Error("CompletedAt should be set when status is Failed")
				}
				return nil
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			conv.UpdateStatus(tt.status)
			tt.check(conv)
			// CreatedAt should not change
			if conv.CreatedAt != originalCreatedAt {
				t.Error("CreatedAt should not change when updating status")
			}
		})
	}
}

func TestConversationUpdateHeartbeat(t *testing.T) {
	conv := NewConversation("C123", "U456", "test")
	originalHeartbeat := conv.LastHeartbeat

	// Wait a tiny bit to ensure time difference
	time.Sleep(10 * time.Millisecond)

	conv.UpdateHeartbeat()

	if conv.LastHeartbeat == originalHeartbeat {
		t.Error("LastHeartbeat should be updated")
	}

	if !conv.LastHeartbeat.After(originalHeartbeat) {
		t.Error("LastHeartbeat should be after original timestamp")
	}
}

func TestConversationStatusConstants(t *testing.T) {
	tests := []struct {
		status string
		want   string
	}{
		{StatusPending, "pending"},
		{StatusActive, "active"},
		{StatusCompleted, "completed"},
		{StatusFailed, "failed"},
		{StatusTimeout, "timeout"},
	}

	for _, tt := range tests {
		if tt.status != tt.want {
			t.Errorf("Status constant = %s, want %s", tt.status, tt.want)
		}
	}
}

func TestConversationRoleConstants(t *testing.T) {
	tests := []struct {
		role string
		want string
	}{
		{RoleUser, "user"},
		{RoleAssistant, "assistant"},
	}

	for _, tt := range tests {
		if tt.role != tt.want {
			t.Errorf("Role constant = %s, want %s", tt.role, tt.want)
		}
	}
}

func TestConversationUniqueIDs(t *testing.T) {
	conv1 := NewConversation("C123", "U456", "test1")
	conv2 := NewConversation("C123", "U456", "test2")

	if conv1.ConversationID == conv2.ConversationID {
		t.Error("ConversationIDs should be unique")
	}

	if conv1.CreatedAt.Equal(conv2.CreatedAt) {
		t.Error("CreatedAt times should be different (or at least very likely to be)")
	}
}

func TestConversationWithExecutionData(t *testing.T) {
	conv := NewConversation("C123", "U456", "test")

	taskArn := "arn:aws:ecs:us-east-1:123456789012:task/cloudops/abc123"
	executionArn := "arn:aws:states:us-east-1:123456789012:execution:cloudops:conv-123"

	conv.TaskArn = taskArn
	conv.ExecutionArn = executionArn

	if conv.TaskArn != taskArn {
		t.Errorf("TaskArn = %s, want %s", conv.TaskArn, taskArn)
	}

	if conv.ExecutionArn != executionArn {
		t.Errorf("ExecutionArn = %s, want %s", conv.ExecutionArn, executionArn)
	}
}

func TestConversationWithError(t *testing.T) {
	conv := NewConversation("C123", "U456", "test")

	errorMsg := "Failed to execute command"
	conv.Error = errorMsg

	if conv.Error != errorMsg {
		t.Errorf("Error = %s, want %s", conv.Error, errorMsg)
	}
}

func TestConversationTTLGeneration(t *testing.T) {
	conv := NewConversation("C123", "U456", "test")

	if conv.TTL == 0 {
		t.Error("TTL should be set")
	}

	// TTL should be approximately 7 days from now
	expectedTTL := time.Now().Add(7 * 24 * time.Hour).Unix()
	ttlDiff := conv.TTL - expectedTTL

	if ttlDiff < -10 || ttlDiff > 10 { // Allow 10 second variance
		t.Errorf("TTL = %d, expected approximately %d", conv.TTL, expectedTTL)
	}
}

func TestMessageStructure(t *testing.T) {
	tests := []struct {
		name    string
		role    string
		content string
	}{
		{"user message", RoleUser, "What's the EC2 status?"},
		{"assistant message", RoleAssistant, "EC2 instance is running normally"},
		{"empty content", RoleUser, ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			msg := &Message{
				Role:    tt.role,
				Content: tt.content,
			}

			if msg.Role != tt.role {
				t.Errorf("Role = %s, want %s", msg.Role, tt.role)
			}

			if msg.Content != tt.content {
				t.Errorf("Content = %s, want %s", msg.Content, tt.content)
			}
		})
	}
}

func TestStepFunctionInput(t *testing.T) {
	sfInput := &StepFunctionInput{
		ConversationID: "conv-123",
		ChannelID:      "C123",
		UserID:         "U456",
		InitialCommand: "test command",
		CreatedAt:      "2024-01-01T00:00:00Z",
	}

	if sfInput.ConversationID != "conv-123" {
		t.Errorf("ConversationID = %s, want conv-123", sfInput.ConversationID)
	}

	if sfInput.ChannelID != "C123" {
		t.Errorf("ChannelID = %s, want C123", sfInput.ChannelID)
	}

	if sfInput.UserID != "U456" {
		t.Errorf("UserID = %s, want U456", sfInput.UserID)
	}
}
