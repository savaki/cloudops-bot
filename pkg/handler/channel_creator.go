package handler

import (
	"context"
	"fmt"
	"log"
	"math/rand"
	"time"
)

// SlackClientInterface defines the interface for Slack operations
type SlackClientInterface interface {
	CreateConversation(ctx context.Context, channelName string) (string, error)
	InviteUsersToConversation(ctx context.Context, channelID string, userIDs ...string) error
	ArchiveConversation(ctx context.Context, channelID string) error
}

// ChannelCreator handles creation of private Slack channels for conversations
type ChannelCreator struct {
	slackClient SlackClientInterface
}

// NewChannelCreator creates a new channel creator
func NewChannelCreator(slackClient SlackClientInterface) *ChannelCreator {
	return &ChannelCreator{
		slackClient: slackClient,
	}
}

// CreateConversationChannel creates a private channel for a conversation
// Returns the channel ID or error
func (cc *ChannelCreator) CreateConversationChannel(ctx context.Context, userID string) (string, error) {
	// Generate channel name
	channelName := generateChannelName()
	log.Printf("Creating private channel: %s", channelName)

	// Create the channel
	channelID, err := cc.slackClient.CreateConversation(ctx, channelName)
	if err != nil {
		return "", fmt.Errorf("create channel: %w", err)
	}

	log.Printf("Channel created: %s (ID: %s)", channelName, channelID)

	// Invite the user
	if err := cc.slackClient.InviteUsersToConversation(ctx, channelID, userID); err != nil {
		// Log but don't fail - user might already be there
		log.Printf("Warning: failed to invite user to channel: %v", err)
	}

	return channelID, nil
}

// generateChannelName creates a unique channel name
// Format: incident-YYYYMMDD-HHMMSS-XXXX
func generateChannelName() string {
	now := time.Now()
	timestamp := now.Format("20060102-150405")
	// Add random suffix for uniqueness when multiple channels created in same second
	randomSuffix := rand.Intn(10000)
	return fmt.Sprintf("incident-%s-%04d", timestamp, randomSuffix)
}

// ArchiveConversationChannel archives a conversation channel (optional cleanup)
func (cc *ChannelCreator) ArchiveConversationChannel(ctx context.Context, channelID string) error {
	log.Printf("Archiving channel: %s", channelID)
	if err := cc.slackClient.ArchiveConversation(ctx, channelID); err != nil {
		log.Printf("Warning: failed to archive channel: %v", err)
		// Don't fail - archiving is optional
	}
	return nil
}
