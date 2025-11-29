package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/config"
	appconfig "github.com/savaki/cloudops-bot/pkg/config"
	"github.com/savaki/cloudops-bot/pkg/dynamodb"
	"github.com/savaki/cloudops-bot/pkg/handler"
	"github.com/savaki/cloudops-bot/pkg/models"
	slackclient "github.com/savaki/cloudops-bot/pkg/slack"
	"github.com/savaki/cloudops-bot/pkg/stepfunctions"
	"github.com/slack-go/slack"
)

// Handler is the Lambda handler for Slack events
func Handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	log.Printf("Received Slack event")

	// Load configuration
	cfg, err := appconfig.Load()
	if err != nil {
		return internalError("Failed to load config", err)
	}

	// Validate Lambda-specific configuration
	if err := cfg.ValidateLambda(); err != nil {
		return internalError("Invalid Lambda config", err)
	}

	// Validate Slack request signature
	if !handler.ValidateSlackRequest(
		[]byte(request.Body),
		request.Headers["X-Slack-Request-Timestamp"],
		request.Headers["X-Slack-Signature"],
		cfg.SlackSigningKey,
	) {
		log.Printf("Invalid Slack signature")
		return badRequest("Invalid signature"), nil
	}

	// Parse Slack event
	var slackEvent models.SlackEventCallback
	if err := json.Unmarshal([]byte(request.Body), &slackEvent); err != nil {
		log.Printf("Failed to parse Slack event: %v", err)
		return badRequest("Invalid event format"), nil
	}

	// Handle URL verification challenge
	if slackEvent.Type == "url_verification" {
		log.Printf("Responding to Slack URL verification challenge")
		return events.APIGatewayProxyResponse{
			StatusCode: 200,
			Body:       fmt.Sprintf(`{"challenge":"%s"}`, slackEvent.Challenge),
			Headers:    map[string]string{"Content-Type": "application/json"},
		}, nil
	}

	// Handle app mention events (spawn ECS task for conversation)
	if slackEvent.Type == "event_callback" && slackEvent.Event.Type == "app_mention" {
		if err := handleAppMention(ctx, cfg, slackEvent.Event); err != nil {
			log.Printf("Failed to handle app mention: %v", err)
			return internalError("Failed to process mention", err)
		}
		return okResponse(map[string]bool{"ok": true}), nil
	}

	log.Printf("Ignoring event type: %s", slackEvent.Type)
	return okResponse(map[string]bool{"ok": true}), nil
}

// handleAppMention spawns an ECS task to handle the conversation
func handleAppMention(ctx context.Context, cfg *appconfig.Config, event models.SlackEventBody) error {
	log.Printf("Handling app mention from user %s in channel %s", event.User, event.Channel)

	// Initialize AWS SDK
	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load aws config: %w", err)
	}

	// Initialize clients
	slackClient := slackclient.NewClient(cfg.SlackBotToken)
	ddbClient := dynamodb.NewClientWithConfig(awsCfg)
	convRepo := dynamodb.NewConversationRepository(ddbClient, cfg.ConversationsTable)
	sfClient := stepfunctions.NewClient(awsCfg)

	// Create new conversation
	conversation := models.NewConversation(event.Channel, event.User, event.Text)
	log.Printf("Created conversation: %s", conversation.ConversationID)

	// Save to DynamoDB
	if err := convRepo.Save(ctx, conversation); err != nil {
		return fmt.Errorf("save conversation: %w", err)
	}
	log.Printf("Saved conversation to DynamoDB")

	// Post acknowledgment message
	msg := "🚀 Starting CloudOps assistant... I'll respond in a moment."
	if _, err := slackClient.PostMessage(ctx, event.Channel, slack.MsgOptionText(msg, false)); err != nil {
		log.Printf("Warning: failed to post acknowledgment: %v", err)
	}

	// Start Step Function execution (which will spawn ECS task)
	executionArn, err := sfClient.StartConversation(ctx, cfg.StepFunctionArn, conversation)
	if err != nil {
		// Try to notify user of failure
		slackClient.PostMessage(ctx, event.Channel, slack.MsgOptionText("❌ Failed to start assistant. Please try again.", false))
		return fmt.Errorf("start step function: %w", err)
	}
	log.Printf("Started Step Function execution: %s", executionArn)

	// Update conversation with execution ARN
	conversation.ExecutionArn = executionArn
	conversation.UpdateStatus(models.StatusPending)
	if err := convRepo.Save(ctx, conversation); err != nil {
		log.Printf("Warning: failed to update conversation with execution ARN: %v", err)
	}

	return nil
}

// internalError returns a 500 error response
func internalError(message string, err error) (events.APIGatewayProxyResponse, error) {
	log.Printf("ERROR: %s: %v", message, err)
	return events.APIGatewayProxyResponse{
		StatusCode: 500,
		Body:       fmt.Sprintf(`{"error":"%s"}`, message),
		Headers:    map[string]string{"Content-Type": "application/json"},
	}, nil
}

// badRequest returns a 400 error response
func badRequest(message string) events.APIGatewayProxyResponse {
	return events.APIGatewayProxyResponse{
		StatusCode: 400,
		Body:       fmt.Sprintf(`{"error":"%s"}`, message),
		Headers:    map[string]string{"Content-Type": "application/json"},
	}
}

// okResponse returns a successful response
func okResponse(body interface{}) events.APIGatewayProxyResponse {
	data, _ := json.Marshal(body)
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(data),
		Headers:    map[string]string{"Content-Type": "application/json"},
	}
}

func main() {
	lambda.Start(Handler)
}
