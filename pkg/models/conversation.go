package models

import (
	"crypto/rand"
	"time"

	"github.com/oklog/ulid/v2"
)

// Conversation represents a user's troubleshooting session with the CloudOps bot
type Conversation struct {
	ConversationID string     `dynamodbav:"conversation_id"`
	ChannelID      string     `dynamodbav:"channel_id"`
	UserID         string     `dynamodbav:"user_id"`
	Status         string     `dynamodbav:"status"` // pending, active, completed, failed, timeout
	InitialCommand string     `dynamodbav:"initial_command"`
	CreatedAt      time.Time  `dynamodbav:"created_at"`
	LastHeartbeat  time.Time  `dynamodbav:"last_heartbeat"`
	CompletedAt    *time.Time `dynamodbav:"completed_at,omitempty"`
	TaskArn        string     `dynamodbav:"task_arn,omitempty"`
	ExecutionArn   string     `dynamodbav:"execution_arn"`
	Error          string     `dynamodbav:"error,omitempty"`
	TTL            int64      `dynamodbav:"ttl"` // Unix timestamp (7 days)
}

// Message represents a single message in the conversation history
type Message struct {
	Role    string // "user" or "assistant"
	Content string
}

// StepFunctionInput is the input payload sent to Step Functions when starting a conversation
type StepFunctionInput struct {
	ConversationID string `json:"conversationId"`
	ChannelID      string `json:"channelId"`
	UserID         string `json:"userId"`
	InitialCommand string `json:"initialCommand"`
	CreatedAt      string `json:"createdAt"`
}

// ConversationStatus constants
const (
	StatusPending   = "pending"
	StatusActive    = "active"
	StatusCompleted = "completed"
	StatusFailed    = "failed"
	StatusTimeout   = "timeout"
)

// MessageRole constants
const (
	RoleUser      = "user"
	RoleAssistant = "assistant"
)

// NewConversation creates a new conversation with generated ID and initial state
func NewConversation(channelID, userID, initialCommand string) *Conversation {
	now := time.Now()
	ttl := now.AddDate(0, 0, 7).Unix() // 7 days from now

	return &Conversation{
		ConversationID: generateConversationID(),
		ChannelID:      channelID,
		UserID:         userID,
		Status:         StatusPending,
		InitialCommand: initialCommand,
		CreatedAt:      now,
		LastHeartbeat:  now,
		TTL:            ttl,
	}
}

// UpdateStatus changes the conversation status
func (c *Conversation) UpdateStatus(status string) {
	c.Status = status
	if status == StatusCompleted || status == StatusFailed || status == StatusTimeout {
		now := time.Now()
		c.CompletedAt = &now
	}
}

// UpdateHeartbeat records the last activity timestamp
func (c *Conversation) UpdateHeartbeat() {
	c.LastHeartbeat = time.Now()
}

// generateConversationID creates a unique conversation identifier
func generateConversationID() string {
	return "conv-" + generateULID()
}

// generateULID generates a ULID string for unique identifiers
func generateULID() string {
	id, _ := ulid.New(ulid.Timestamp(time.Now()), rand.Reader)
	return id.String()
}
