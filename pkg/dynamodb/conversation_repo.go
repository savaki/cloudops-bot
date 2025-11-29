package dynamodb

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/savaki/cloudops-bot/pkg/models"
)

// ConversationRepository handles DynamoDB operations for conversations
type ConversationRepository struct {
	client    *dynamodb.Client
	tableName string
}

// NewConversationRepository creates a new conversation repository
func NewConversationRepository(client *dynamodb.Client, tableName string) *ConversationRepository {
	return &ConversationRepository{
		client:    client,
		tableName: tableName,
	}
}

// Save stores a conversation record in DynamoDB
func (r *ConversationRepository) Save(ctx context.Context, conv *models.Conversation) error {
	item, err := attributevalue.MarshalMap(conv)
	if err != nil {
		return fmt.Errorf("marshal conversation: %w", err)
	}

	_, err = r.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: &r.tableName,
		Item:      item,
	})
	if err != nil {
		return fmt.Errorf("put item: %w", err)
	}

	log.Printf("Saved conversation %s to DynamoDB", conv.ConversationID)
	return nil
}

// GetByID retrieves a conversation by ID
func (r *ConversationRepository) GetByID(ctx context.Context, conversationID string) (*models.Conversation, error) {
	result, err := r.client.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: &r.tableName,
		Key: map[string]types.AttributeValue{
			"conversation_id": &types.AttributeValueMemberS{Value: conversationID},
		},
	})
	if err != nil {
		return nil, fmt.Errorf("get item: %w", err)
	}

	if result.Item == nil {
		return nil, fmt.Errorf("conversation not found: %s", conversationID)
	}

	var conv models.Conversation
	err = attributevalue.UnmarshalMap(result.Item, &conv)
	if err != nil {
		return nil, fmt.Errorf("unmarshal conversation: %w", err)
	}

	return &conv, nil
}

// UpdateStatus updates the conversation status
func (r *ConversationRepository) UpdateStatus(ctx context.Context, conversationID string, status string) error {
	updateExpr := "SET #status = :status"
	exprAttrNames := map[string]string{
		"#status": "status",
	}
	exprAttrVals := map[string]types.AttributeValue{
		":status": &types.AttributeValueMemberS{Value: status},
	}

	// Add completed_at if status is terminal
	if status == models.StatusCompleted || status == models.StatusFailed || status == models.StatusTimeout {
		updateExpr += ", completed_at = :now"
		exprAttrVals[":now"] = &types.AttributeValueMemberS{
			Value: time.Now().Format(time.RFC3339),
		}
	}

	_, err := r.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: &r.tableName,
		Key: map[string]types.AttributeValue{
			"conversation_id": &types.AttributeValueMemberS{Value: conversationID},
		},
		UpdateExpression:          &updateExpr,
		ExpressionAttributeNames:  exprAttrNames,
		ExpressionAttributeValues: exprAttrVals,
	})
	if err != nil {
		return fmt.Errorf("update item: %w", err)
	}

	log.Printf("Updated conversation %s status to %s", conversationID, status)
	return nil
}

// UpdateHeartbeat updates the last activity timestamp
func (r *ConversationRepository) UpdateHeartbeat(ctx context.Context, conversationID string, timestamp time.Time) error {
	updateExpr := "SET last_heartbeat = :now"
	_, err := r.client.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: &r.tableName,
		Key: map[string]types.AttributeValue{
			"conversation_id": &types.AttributeValueMemberS{Value: conversationID},
		},
		UpdateExpression: &updateExpr,
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":now": &types.AttributeValueMemberS{Value: timestamp.Format(time.RFC3339)},
		},
	})
	if err != nil {
		return fmt.Errorf("update heartbeat: %w", err)
	}

	return nil
}

// GetByChannelID retrieves the most recent active conversation for a specific Slack channel
func (r *ConversationRepository) GetByChannelID(ctx context.Context, channelID string) (*models.Conversation, error) {
	result, err := r.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              &r.tableName,
		IndexName:              stringPtr("ChannelIndex"),
		KeyConditionExpression: stringPtr("channel_id = :channelId"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":channelId": &types.AttributeValueMemberS{Value: channelID},
		},
		ScanIndexForward: boolPtr(false), // Most recent first
		Limit:            int32Ptr(1),    // Only need the latest
	})
	if err != nil {
		return nil, fmt.Errorf("query by channel: %w", err)
	}

	if len(result.Items) == 0 {
		return nil, fmt.Errorf("no conversation found for channel %s", channelID)
	}

	var conv models.Conversation
	err = attributevalue.UnmarshalMap(result.Items[0], &conv)
	if err != nil {
		return nil, fmt.Errorf("unmarshal conversation: %w", err)
	}

	return &conv, nil
}

// GetByStatus retrieves conversations with a specific status
func (r *ConversationRepository) GetByStatus(ctx context.Context, status string) ([]*models.Conversation, error) {
	result, err := r.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              &r.tableName,
		IndexName:              stringPtr("StatusIndex"),
		KeyConditionExpression: stringPtr("#status = :status"),
		ExpressionAttributeNames: map[string]string{
			"#status": "status",
		},
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":status": &types.AttributeValueMemberS{Value: status},
		},
	})
	if err != nil {
		return nil, fmt.Errorf("query by status: %w", err)
	}

	var conversations []*models.Conversation
	err = attributevalue.UnmarshalListOfMaps(result.Items, &conversations)
	if err != nil {
		return nil, fmt.Errorf("unmarshal conversations: %w", err)
	}

	return conversations, nil
}

// SaveMessage stores a message in the conversation history
func (r *ConversationRepository) SaveMessage(ctx context.Context, conversationID, role, content string) error {
	// Get current message count to determine index
	messages, _ := r.GetMessageHistory(ctx, conversationID)
	messageIndex := len(messages)

	historyItem := models.ConversationHistoryItem{
		ConversationID: conversationID,
		MessageIndex:   messageIndex,
		Role:           role,
		Content:        content,
		CreatedAt:      time.Now(),
		TTL:            time.Now().AddDate(0, 0, 7).Unix(),
	}

	item, err := attributevalue.MarshalMap(historyItem)
	if err != nil {
		return fmt.Errorf("marshal message: %w", err)
	}

	_, err = r.client.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: stringPtr(r.tableName + "-history"),
		Item:      item,
	})
	if err != nil {
		return fmt.Errorf("put message: %w", err)
	}

	log.Printf("Saved message %d for conversation %s", messageIndex, conversationID)
	return nil
}

// GetMessageHistory retrieves conversation history for a conversation
func (r *ConversationRepository) GetMessageHistory(ctx context.Context, conversationID string) ([]models.Message, error) {
	result, err := r.client.Query(ctx, &dynamodb.QueryInput{
		TableName:              stringPtr(r.tableName + "-history"),
		KeyConditionExpression: stringPtr("conversation_id = :convId"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":convId": &types.AttributeValueMemberS{Value: conversationID},
		},
		ScanIndexForward: boolPtr(true), // Sort by message_index ascending
	})
	if err != nil {
		return nil, fmt.Errorf("query messages: %w", err)
	}

	var items []models.ConversationHistoryItem
	err = attributevalue.UnmarshalListOfMaps(result.Items, &items)
	if err != nil {
		return nil, fmt.Errorf("unmarshal messages: %w", err)
	}

	// Convert to Message array (without pointers)
	messages := make([]models.Message, len(items))
	for i, item := range items {
		messages[i] = models.Message{
			Role:    item.Role,
			Content: item.Content,
		}
	}

	return messages, nil
}

// Helper functions
func stringPtr(s string) *string {
	return &s
}

func boolPtr(b bool) *bool {
	return &b
}

func int32Ptr(i int32) *int32 {
	return &i
}
