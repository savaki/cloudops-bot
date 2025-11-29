package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/savaki/cloudops-bot/pkg/bedrock"
	appconfig "github.com/savaki/cloudops-bot/pkg/config"
	"github.com/savaki/cloudops-bot/pkg/dynamodb"
	slackclient "github.com/savaki/cloudops-bot/pkg/slack"
	"github.com/slack-go/slack"
)

func main() {
	ctx := context.Background()

	// Get conversation ID from environment (passed by Step Functions)
	conversationID := os.Getenv("CONVERSATION_ID")
	if conversationID == "" {
		log.Fatal("CONVERSATION_ID environment variable not set")
	}

	log.Printf("Starting agent for conversation: %s", conversationID)

	// Load application configuration
	cfg, err := appconfig.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Initialize AWS SDK
	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		log.Fatalf("Failed to load AWS config: %v", err)
	}

	// Initialize clients
	ddbClient := dynamodb.NewClientWithConfig(awsCfg)
	convRepo := dynamodb.NewConversationRepository(ddbClient, cfg.ConversationsTable)
	slackClient := slackclient.NewClient(cfg.SlackBotToken)
	_ = bedrock.NewClient(awsCfg) // TODO: Use in conversation handling

	// Get conversation from DynamoDB
	conversation, err := convRepo.GetByID(ctx, conversationID)
	if err != nil {
		log.Fatalf("Failed to get conversation: %v", err)
	}

	log.Printf("Retrieved conversation for channel %s, user %s", conversation.ChannelID, conversation.UserID)

	// TODO: Implement conversation handling logic
	// 1. Get message history from DynamoDB
	// 2. Process user's initial message with Claude
	// 3. Implement Claude tool calling for AWS operations:
	//    - EC2: Describe instances, get console output
	//    - RDS: Describe databases, check status
	//    - CloudWatch: Query logs, get metrics
	//    - Lambda: List functions, get configurations
	//    - ECS: Describe services and tasks
	// 4. Post Claude's response to Slack
	// 5. Listen for follow-up messages (poll Slack API or use RTM)
	// 6. Handle multi-turn conversation with context
	// 7. Exit gracefully when conversation is idle (e.g., 30 minutes)
	// 8. Update conversation status in DynamoDB before exiting

	// Example placeholder response
	message := "🤖 CloudOps assistant is ready! I can help you with AWS operations. Ask me anything about your infrastructure."
	if _, err := slackClient.PostMessage(ctx, conversation.ChannelID, slack.MsgOptionText(message, false)); err != nil {
		log.Printf("Failed to post message: %v", err)
	}

	// TODO: Replace this with actual conversation loop
	fmt.Println("Agent stub executed successfully. Implement conversation handling here.")
	log.Printf("Agent completed for conversation: %s", conversationID)
}
