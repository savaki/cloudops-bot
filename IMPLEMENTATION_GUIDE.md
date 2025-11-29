# CloudOps Bot Implementation Guide

This guide walks you through implementing the agent container that will interact with your Claude API.

## Architecture Overview

```
Slack (@mention) → Lambda Handler → DynamoDB → Step Function → ECS Agent Container
                                                                   ↓
                                                            Your Claude API Integration
                                                                   ↓
                                                            Slack (private channel)
```

## What's Already Built (Foundation)

✅ **Infrastructure**
- VPC with public subnets
- DynamoDB tables (conversations + history)
- IAM roles with proper permissions
- ECR repository for container images
- ECS cluster and task definition
- Step Functions state machine
- CloudFormation templates (01-06)

✅ **Stubs & Scaffolding**
- Go project structure
- Configuration management (`pkg/config/config.go`)
- Data models (`pkg/models/`)
- DynamoDB repository interface (`pkg/dynamodb/conversation_repo.go`)
- Slack event models
- Handler interface stubs

## What You Need to Implement

### Priority 1: Agent Container (cmd/agent/main.go)

This is the core of the system. Your implementation should:

1. **Initialize Slack Socket Mode Connection**
   ```go
   import "github.com/slack-go/slack"
   import "github.com/slack-go/slack/socketmode"

   // Use cfg.SlackBotToken and cfg.SlackAppToken
   // Get tokens from Secrets Manager
   ```

2. **Load Conversation Context**
   ```go
   // Get CONVERSATION_ID, CHANNEL_ID, USER_ID from environment
   // Load conversation history from DynamoDB if available
   ```

3. **Main Event Loop**
   ```go
   // Listen for messages in the private Slack channel
   // For each message:
   //   - Call your Claude API with conversation history
   //   - Post Claude's response to Slack
   //   - Save message to DynamoDB history
   //   - Update heartbeat
   //   - Check for exit conditions
   ```

4. **Exit Conditions**
   - User types "done" or "exit"
   - 30 minutes of inactivity
   - Step Function timeout (1 hour) - task will be killed
   - Context cancellation (graceful shutdown)

### Priority 2: Lambda Handler (cmd/slack-handler/main.go)

Receives Slack mentions and initiates conversations:

1. **Validate Slack Signature**
   ```go
   // Verify request came from Slack
   // Implement in pkg/handler/validator.go
   ```

2. **Handle Events**
   - URL verification (Slack setup)
   - app_mention events (user mentions bot)
   - message events (if not using Socket Mode)

3. **Create Private Channel**
   ```go
   // Use slack-go library to create private channel
   // Name format: incident-YYYYMMDD-HHMMSS-XXXX
   ```

4. **Save to DynamoDB & Start Step Function**
   ```go
   // Create Conversation record
   // Start Step Function execution with conversation context
   // Post acknowledgment to private channel
   ```

### Priority 3: Supporting Packages

Implement as needed:

**pkg/dynamodb/conversation_repo.go**
- Save/Load conversation records
- Update status and heartbeat
- Query by channel ID or status
- Save/Load conversation history

**pkg/handler/event_handler.go**
- Parse Slack events
- Route to appropriate handlers

**pkg/handler/validator.go**
- Validate Slack request signatures

**pkg/handler/channel_creator.go** (optional)
- Create private Slack channels
- Invite users to channels

**pkg/stepfunctions/client.go**
- Start Step Function executions
- Check execution status

## Implementation Steps

### Step 1: Set Up Your Claude API Integration

Choose how you'll call Claude:

**Option A: Anthropic SDK**
```bash
go get github.com/anthropics/anthropic-sdk-go
```

```go
import "github.com/anthropics/anthropic-sdk-go"

client := anthropic.NewClient(
    anthropic.WithAPIKey(os.Getenv("ANTHROPIC_API_KEY")),
)

message, err := client.Messages.New(ctx, &anthropic.MessageNewParams{
    Model: anthropic.ModelClaudeOpus,
    Messages: []anthropic.MessageParam{
        anthropic.NewUserMessage(userInput),
    },
})
```

**Option B: HTTP Requests**
```go
import "net/http"

// Make direct HTTP requests to Claude API
// https://docs.anthropic.com/claude/reference/getting-started-with-the-api
```

### Step 2: Implement Agent Container

Edit `cmd/agent/main.go`:

1. Initialize Slack Socket Mode client
2. Load conversation ID/channel ID from environment
3. Connect to DynamoDB to load history
4. Start event loop:
   - Receive messages from Slack
   - Send to Claude API with history
   - Post responses back to Slack
   - Update DynamoDB

### Step 3: Implement Lambda Handler

Edit `cmd/slack-handler/main.go`:

1. Validate Slack signature
2. Parse Slack events
3. Handle app_mention events
4. Create private channel
5. Save conversation to DynamoDB
6. Start Step Function
7. Post acknowledgment

### Step 4: Test Locally

```bash
# Set environment variables
export SLACK_BOT_TOKEN="xoxb-..."
export SLACK_APP_TOKEN="xapp-..."
export AWS_REGION="us-east-1"
export CONVERSATIONS_TABLE="cloudops-conversations-dev"
export ANTHROPIC_API_KEY="sk-ant-..."

# Build
go build -o bin/agent ./cmd/agent
go build -o bin/slack-handler ./cmd/slack-handler

# Test agent stub
./bin/agent
```

### Step 5: Build & Deploy Container

```bash
# Build and push to ECR
chmod +x deployments/build-agent.sh
./deployments/build-agent.sh dev

# Update ECS task definition with new image
# Update ECS service to use new task definition
```

### Step 6: Deploy Lambda

```bash
# Package Lambda
chmod +x deployments/package-lambda.sh
./deployments/package-lambda.sh

# Deploy via CloudFormation or manually
aws lambda update-function-code \
  --function-name cloudops-slack-handler-dev \
  --zip-file fileb://lambda.zip
```

## Key Considerations

### Slack Socket Mode vs Events API

The stub assumes **Socket Mode** (WebSocket connection):
- ✅ No webhook/inbound URL needed
- ✅ Real-time bidirectional communication
- ✅ Simpler firewall rules
- ❌ Requires persistent connection

If you prefer **Events API**:
- Use API Gateway + Lambda for webhook
- Simpler stateless design
- Agent would need to poll DynamoDB for messages

### Error Handling

The agent should:
- Catch Claude API errors and inform user
- Handle Slack API errors gracefully
- Update DynamoDB on errors
- Not crash on transient failures
- Log all errors to CloudWatch

### Conversation History Management

1. **Load on startup**: Get history from DynamoDB
2. **Save each turn**: Store user message + Claude response
3. **Trim if needed**: Manage tokens for long conversations
4. **Clean up on exit**: Mark conversation as completed

### Security Notes

- Store API keys in Secrets Manager, not in code
- Agent task role has read-only AWS permissions
- Never log sensitive data
- Validate Slack signatures before processing
- Encrypt conversation history at rest

## Dependencies You'll Need

```bash
go get github.com/slack-go/slack
go get github.com/anthropics/anthropic-sdk-go  # or your chosen SDK
go get github.com/aws/aws-sdk-go-v2/...
```

## Testing the Full Flow

1. **Deploy infrastructure**
   ```bash
   # Run all CloudFormation stacks (see README.md)
   ```

2. **Build and push agent container**
   ```bash
   ./deployments/build-agent.sh dev
   ```

3. **Deploy Lambda**
   ```bash
   ./deployments/package-lambda.sh
   ```

4. **Test in Slack**
   - Go to #cloudops channel
   - Type: `@cloudops-bot hello`
   - Bot should create private channel
   - Check CloudWatch logs for errors

## CloudWatch Logs

**Agent logs**: `/ecs/cloudops-agent-dev`
**Lambda logs**: `/aws/lambda/cloudops-slack-handler-dev`
**Step Function logs**: View in AWS Step Functions console

## Common Issues

**Agent not connecting to Slack**
- Check Slack token in Secrets Manager
- Verify Socket Mode is enabled in Slack app
- Check security group egress rules (should allow 443 HTTPS)

**DynamoDB errors**
- Verify table name in environment
- Check IAM permissions
- Ensure table exists and is accessible

**Claude API errors**
- Verify ANTHROPIC_API_KEY is set
- Check API rate limits
- Verify model name is correct

**Slack errors**
- Verify bot token and app token
- Check Slack app scopes are correct
- Verify bot is installed in workspace

## Next Steps

1. Implement agent container (Priority 1)
2. Implement Lambda handler (Priority 2)
3. Test locally with mock Slack messages
4. Deploy and test in actual Slack workspace
5. Add error handling and logging
6. Set up CloudWatch alarms
7. Document your Claude integration

## Resources

- [Slack API Reference](https://api.slack.com/)
- [Claude API Docs](https://docs.anthropic.com/)
- [AWS SDK for Go v2](https://aws.github.io/aws-sdk-go-v2/)
- [socket-mode (slack-go)](https://github.com/slack-go/slack/tree/master/socketmode)

## Getting Help

If you get stuck:
1. Check CloudWatch logs for detailed error messages
2. Review the Slack API documentation
3. Verify all environment variables are set correctly
4. Test individual components separately
5. Use the stubs as templates - they have comments explaining what's needed
