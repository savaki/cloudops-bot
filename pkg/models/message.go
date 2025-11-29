package models

import "time"

// ConversationHistoryItem represents a single message in conversation history
type ConversationHistoryItem struct {
	ConversationID string    `dynamodbav:"conversation_id"`
	MessageIndex   int       `dynamodbav:"message_index"`
	Role           string    `dynamodbav:"role"` // "user" or "assistant"
	Content        string    `dynamodbav:"content"`
	CreatedAt      time.Time `dynamodbav:"created_at"`
	TTL            int64     `dynamodbav:"ttl"`
}

// SlackMessage represents a message from Slack
type SlackMessage struct {
	UserID    string
	Text      string
	Channel   string
	Timestamp string
}

// SlackEvent represents various Slack event types
type SlackEvent struct {
	Type      string
	Challenge string // For URL verification
	Event     SlackEventBody
}

// SlackEventBody represents the actual event details
type SlackEventBody struct {
	Type    string `json:"type"`
	User    string `json:"user"`
	Text    string `json:"text"`
	Channel string `json:"channel"`
	BotID   string `json:"bot_id,omitempty"`
	SubType string `json:"subtype,omitempty"`
}

// SlackURLVerification is for Slack URL verification
type SlackURLVerification struct {
	Type      string `json:"type"`
	Challenge string `json:"challenge"`
}

// SlackEventCallback is the main event structure
type SlackEventCallback struct {
	Type             string         `json:"type"`
	Event            SlackEventBody `json:"event"`
	Challenge        string         `json:"challenge"`
	RequestTimestamp string         `json:"request_timestamp"`
}
