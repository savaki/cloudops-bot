package handler

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

// MockSlackClient mocks the SlackClientInterface for testing
type MockSlackClient struct {
	CreateConversationFunc        func(ctx context.Context, channelName string) (string, error)
	InviteUsersToConversationFunc func(ctx context.Context, channelID string, userIDs ...string) error
	ArchiveConversationFunc       func(ctx context.Context, channelID string) error
}

// Verify MockSlackClient implements SlackClientInterface
var _ SlackClientInterface = (*MockSlackClient)(nil)

func (m *MockSlackClient) CreateConversation(ctx context.Context, channelName string) (string, error) {
	if m.CreateConversationFunc != nil {
		return m.CreateConversationFunc(ctx, channelName)
	}
	return "C123456", nil
}

func (m *MockSlackClient) InviteUsersToConversation(ctx context.Context, channelID string, userIDs ...string) error {
	if m.InviteUsersToConversationFunc != nil {
		return m.InviteUsersToConversationFunc(ctx, channelID, userIDs...)
	}
	return nil
}

func (m *MockSlackClient) ArchiveConversation(ctx context.Context, channelID string) error {
	if m.ArchiveConversationFunc != nil {
		return m.ArchiveConversationFunc(ctx, channelID)
	}
	return nil
}

func TestNewChannelCreator(t *testing.T) {
	mockClient := &MockSlackClient{}
	creator := NewChannelCreator(mockClient)

	if creator == nil {
		t.Error("NewChannelCreator() returned nil")
	}

	if creator.slackClient == nil {
		t.Error("slackClient not properly initialized")
	}
}

func TestCreateConversationChannel(t *testing.T) {
	tests := []struct {
		name       string
		userID     string
		mockFunc   func(ctx context.Context, channelName string) (string, error)
		inviteFunc func(ctx context.Context, channelID string, userIDs ...string) error
		wantErr    bool
		validateID func(string) bool
	}{
		{
			name:   "successful channel creation",
			userID: "U123456",
			mockFunc: func(ctx context.Context, channelName string) (string, error) {
				return "C987654", nil
			},
			inviteFunc: func(ctx context.Context, channelID string, userIDs ...string) error {
				return nil
			},
			wantErr: false,
			validateID: func(id string) bool {
				return id == "C987654"
			},
		},
		{
			name:   "channel creation fails",
			userID: "U123456",
			mockFunc: func(ctx context.Context, channelName string) (string, error) {
				return "", errors.New("slack api error")
			},
			wantErr: true,
		},
		{
			name:   "invite fails but returns channel id",
			userID: "U123456",
			mockFunc: func(ctx context.Context, channelName string) (string, error) {
				return "C987654", nil
			},
			inviteFunc: func(ctx context.Context, channelID string, userIDs ...string) error {
				return errors.New("invite failed")
			},
			wantErr: false, // Invite failure is non-fatal
			validateID: func(id string) bool {
				return id == "C987654"
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockClient := &MockSlackClient{
				CreateConversationFunc:        tt.mockFunc,
				InviteUsersToConversationFunc: tt.inviteFunc,
			}
			creator := NewChannelCreator(mockClient)
			ctx := context.Background()

			id, err := creator.CreateConversationChannel(ctx, tt.userID)

			if (err != nil) != tt.wantErr {
				t.Errorf("CreateConversationChannel() error = %v, wantErr %v", err, tt.wantErr)
			}

			if !tt.wantErr && tt.validateID != nil {
				if !tt.validateID(id) {
					t.Errorf("CreateConversationChannel() returned id = %s", id)
				}
			}
		})
	}
}

func TestCreateConversationChannelWithContext(t *testing.T) {
	mockClient := &MockSlackClient{
		CreateConversationFunc: func(ctx context.Context, channelName string) (string, error) {
			return "C123456", nil
		},
	}
	creator := NewChannelCreator(mockClient)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	id, err := creator.CreateConversationChannel(ctx, "U123456")
	if err != nil {
		t.Errorf("CreateConversationChannel() error = %v", err)
	}

	if id != "C123456" {
		t.Errorf("CreateConversationChannel() returned = %s, want C123456", id)
	}
}

func TestGenerateChannelName(t *testing.T) {
	tests := []struct {
		name     string
		validate func(string) bool
	}{
		{
			name: "channel name starts with incident-",
			validate: func(name string) bool {
				return strings.HasPrefix(name, "incident-")
			},
		},
		{
			name: "channel name contains date format",
			validate: func(name string) bool {
				// Format should be: incident-YYYYMMDD-HHMMSS
				return len(name) >= len("incident-20060102-150405")
			},
		},
		{
			name: "channel name is not empty",
			validate: func(name string) bool {
				return name != ""
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			name := generateChannelName()
			if !tt.validate(name) {
				t.Errorf("generateChannelName() = %s failed validation", name)
			}
		})
	}
}

func TestGenerateChannelNameUniqueness(t *testing.T) {
	names := make(map[string]bool)

	// Generate multiple names quickly
	for i := 0; i < 10; i++ {
		name := generateChannelName()
		if names[name] {
			t.Errorf("generateChannelName() produced duplicate: %s", name)
		}
		names[name] = true
		time.Sleep(100 * time.Millisecond) // Small delay between generations
	}

	if len(names) != 10 {
		t.Errorf("generateChannelName() produced only %d unique names, expected 10", len(names))
	}
}

func TestGenerateChannelNameFormat(t *testing.T) {
	name := generateChannelName()

	// Verify format: incident-YYYYMMDD-HHMMSS-XXXX
	if !strings.HasPrefix(name, "incident-") {
		t.Errorf("generateChannelName() doesn't start with 'incident-': %s", name)
	}

	// Extract the parts
	parts := strings.Split(name, "-")
	if len(parts) != 4 {
		t.Errorf("generateChannelName() should have 4 parts, got %d: %s", len(parts), name)
	}

	// Verify date part is 8 digits
	if len(parts[1]) != 8 {
		t.Errorf("generateChannelName() date part not 8 digits: %s", parts[1])
	}

	// Verify time part is 6 digits
	if len(parts[2]) != 6 {
		t.Errorf("generateChannelName() time part not 6 digits: %s", parts[2])
	}

	// Verify random suffix is 4 digits
	if len(parts[3]) != 4 {
		t.Errorf("generateChannelName() random suffix not 4 digits: %s", parts[3])
	}
}

func TestArchiveConversationChannel(t *testing.T) {
	tests := []struct {
		name        string
		channelID   string
		archiveFunc func(ctx context.Context, channelID string) error
		wantErr     bool
	}{
		{
			name:      "successful archive",
			channelID: "C123456",
			archiveFunc: func(ctx context.Context, channelID string) error {
				return nil
			},
			wantErr: false,
		},
		{
			name:      "archive failure is non-fatal",
			channelID: "C123456",
			archiveFunc: func(ctx context.Context, channelID string) error {
				return errors.New("archive failed")
			},
			wantErr: false, // Archive failure should not error
		},
		{
			name:      "archive with empty channel id",
			channelID: "",
			archiveFunc: func(ctx context.Context, channelID string) error {
				return nil
			},
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockClient := &MockSlackClient{
				ArchiveConversationFunc: tt.archiveFunc,
			}
			creator := NewChannelCreator(mockClient)
			ctx := context.Background()

			err := creator.ArchiveConversationChannel(ctx, tt.channelID)
			if (err != nil) != tt.wantErr {
				t.Errorf("ArchiveConversationChannel() error = %v, wantErr %v", err, tt.wantErr)
			}
		})
	}
}

func TestCreateConversationChannelMultipleCalls(t *testing.T) {
	callCount := 0
	mockClient := &MockSlackClient{
		CreateConversationFunc: func(ctx context.Context, channelName string) (string, error) {
			callCount++
			return "C" + string(rune(callCount)), nil
		},
	}
	creator := NewChannelCreator(mockClient)
	ctx := context.Background()

	for i := 0; i < 5; i++ {
		_, err := creator.CreateConversationChannel(ctx, "U123456")
		if err != nil {
			t.Errorf("CreateConversationChannel() iteration %d error = %v", i, err)
		}
	}

	if callCount != 5 {
		t.Errorf("CreateConversationChannel() called %d times, expected 5", callCount)
	}
}

func TestCreateConversationChannelWithMultipleUsers(t *testing.T) {
	invitedUsers := []string{}
	mockClient := &MockSlackClient{
		CreateConversationFunc: func(ctx context.Context, channelName string) (string, error) {
			return "C123456", nil
		},
		InviteUsersToConversationFunc: func(ctx context.Context, channelID string, userIDs ...string) error {
			invitedUsers = append(invitedUsers, userIDs...)
			return nil
		},
	}
	creator := NewChannelCreator(mockClient)
	ctx := context.Background()

	_, err := creator.CreateConversationChannel(ctx, "U123456")
	if err != nil {
		t.Errorf("CreateConversationChannel() error = %v", err)
	}

	if len(invitedUsers) != 1 {
		t.Errorf("Expected 1 user to be invited, got %d", len(invitedUsers))
	}

	if invitedUsers[0] != "U123456" {
		t.Errorf("Expected user U123456 to be invited, got %s", invitedUsers[0])
	}
}

func TestChannelCreatorWithCancelledContext(t *testing.T) {
	mockClient := &MockSlackClient{
		CreateConversationFunc: func(ctx context.Context, channelName string) (string, error) {
			return "C123456", nil
		},
	}
	creator := NewChannelCreator(mockClient)

	ctx, cancel := context.WithCancel(context.Background())
	cancel() // Cancel immediately

	// Should still work (context isn't enforced in implementation)
	id, err := creator.CreateConversationChannel(ctx, "U123456")
	if err != nil {
		t.Errorf("CreateConversationChannel() with cancelled context error = %v", err)
	}

	if id != "C123456" {
		t.Errorf("CreateConversationChannel() returned = %s, want C123456", id)
	}
}
