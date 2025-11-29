package slack

import (
	"context"
	"fmt"
	"log"

	"github.com/slack-go/slack"
)

// Client wraps the Slack SDK client for use throughout the application
type Client struct {
	client *slack.Client
}

// NewClient creates a new Slack client with bot token
func NewClient(botToken string) *Client {
	return &Client{
		client: slack.New(botToken),
	}
}

// NewClientWithAppToken creates a new Slack client with bot token and app token for Socket Mode
func NewClientWithAppToken(botToken, appToken string) *Client {
	return &Client{
		client: slack.New(botToken, slack.OptionAppLevelToken(appToken)),
	}
}

// GetRawClient returns the underlying slack.Client for advanced operations like Socket Mode
func (c *Client) GetRawClient() *slack.Client {
	return c.client
}

// PostMessage posts a message to a Slack channel
func (c *Client) PostMessage(ctx context.Context, channelID string, opts ...slack.MsgOption) (string, error) {
	_, timestamp, err := c.client.PostMessageContext(ctx, channelID, opts...)
	if err != nil {
		return "", fmt.Errorf("post message: %w", err)
	}

	return timestamp, nil
}

// CreateConversation creates a private Slack channel
func (c *Client) CreateConversation(ctx context.Context, channelName string) (string, error) {
	params := slack.CreateConversationParams{
		ChannelName: channelName,
		IsPrivate:   true,
	}
	resp, err := c.client.CreateConversationContext(ctx, params)
	if err != nil {
		return "", fmt.Errorf("create conversation: %w", err)
	}

	return resp.ID, nil
}

// InviteUsersToConversation invites users to a channel
func (c *Client) InviteUsersToConversation(ctx context.Context, channelID string, userIDs ...string) error {
	_, err := c.client.InviteUsersToConversationContext(ctx, channelID, userIDs...)
	if err != nil {
		return fmt.Errorf("invite users: %w", err)
	}

	return nil
}

// GetUserInfo gets information about a user
func (c *Client) GetUserInfo(ctx context.Context, userID string) (*slack.User, error) {
	user, err := c.client.GetUserInfoContext(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("get user info: %w", err)
	}

	return user, nil
}

// GetChannelInfo gets information about a channel
func (c *Client) GetChannelInfo(ctx context.Context, channelID string) (*slack.Channel, error) {
	input := &slack.GetConversationInfoInput{
		ChannelID:     channelID,
		IncludeLocale: true,
	}
	channel, err := c.client.GetConversationInfoContext(ctx, input)
	if err != nil {
		return nil, fmt.Errorf("get channel info: %w", err)
	}

	return channel, nil
}

// AuthTest verifies the bot token is valid
func (c *Client) AuthTest(ctx context.Context) (*slack.AuthTestResponse, error) {
	resp, err := c.client.AuthTestContext(ctx)
	if err != nil {
		return nil, fmt.Errorf("auth test: %w", err)
	}

	return resp, nil
}

// GetBotUserID gets the bot's user ID for filtering messages
func (c *Client) GetBotUserID(ctx context.Context) (string, error) {
	resp, err := c.client.AuthTestContext(ctx)
	if err != nil {
		return "", fmt.Errorf("get bot user id: %w", err)
	}

	return resp.UserID, nil
}

// ArchiveConversation archives a channel
func (c *Client) ArchiveConversation(ctx context.Context, channelID string) error {
	err := c.client.ArchiveConversationContext(ctx, channelID)
	if err != nil {
		log.Printf("Warning: failed to archive conversation %s: %v", channelID, err)
		// Don't return error - archiving is nice-to-have
	}

	return nil
}
