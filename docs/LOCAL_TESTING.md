# Local Agent Testing Guide

Complete guide for building and testing the CloudOps agent container locally with simulated conversations.

## Architecture Overview

The agent expects to be triggered by Step Functions with:
- `CONVERSATION_ID` environment variable
- AWS credentials for DynamoDB and Bedrock access
- Slack bot token for posting messages
- DynamoDB tables for conversation state and history

## Quick Start

### 1. Start Local Infrastructure

```bash
# Start local DynamoDB
docker-compose up -d

# Create tables
./scripts/setup-local-dynamodb.sh
```

This starts:
- **DynamoDB Local** on http://localhost:8000
- **DynamoDB Admin UI** on http://localhost:8001

### 2. Set Slack Credentials

```bash
# Option A: Load from Parameter Store (if deployed)
ENV=dev
export SLACK_BOT_TOKEN=$(aws ssm get-parameter \
  --name "/cloudops/${ENV}/slack-bot-token" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

export SLACK_SIGNING_KEY=$(aws ssm get-parameter \
  --name "/cloudops/${ENV}/slack-signing-key" \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

# Option B: Set manually
export SLACK_BOT_TOKEN="xoxb-your-token-here"
export SLACK_SIGNING_KEY="your-signing-secret"
```

### 3. Run Interactive Testing

```bash
./scripts/test-agent-interactive.sh
```

This opens an interactive shell where you can:
- Type messages as a user
- Type `run` to execute the agent
- Type `history` to view conversation history
- Type `exit` to quit

## Testing Workflows

### Workflow 1: Quick Test (Single Message)

```bash
# Create a test conversation
./scripts/create-test-conversation.sh "C01234567" "U01234567" "List EC2 instances"

# Copy the conversation ID from output
export CONVERSATION_ID="conv-..."

# Run the agent
./scripts/run-agent-local.sh
```

### Workflow 2: Multi-Turn Conversation

```bash
# Start interactive testing
./scripts/test-agent-interactive.sh

# In the interactive prompt:
> What EC2 instances are running?
✅ Added user message: What EC2 instances are running?

> run
Running agent...
[Agent executes and responds]

> Show me the CloudWatch logs for i-1234567
✅ Added user message: Show me the CloudWatch logs for i-1234567

> run
Running agent...
[Agent executes with full conversation context]

> history
Conversation History:
======================================================================
👤 User: What EC2 instances are running?
🤖 Assistant: [Agent's response]
👤 User: Show me the CloudWatch logs for i-1234567
🤖 Assistant: [Agent's response]
======================================================================

> exit
```

### Workflow 3: Build and Test Container Locally

```bash
# Build the Docker image
docker build -f deployments/Dockerfile.agent -t cloudops-agent:test .

# Run with local DynamoDB
docker run --rm \
  --network cloudops-bot_cloudops-local \
  -e CONVERSATION_ID="conv-..." \
  -e AWS_ENDPOINT_URL="http://dynamodb-local:8000" \
  -e CONVERSATIONS_TABLE="cloudops-conversations-local" \
  -e CONVERSATION_HISTORY_TABLE="cloudops-conversation-history-local" \
  -e SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN}" \
  -e SLACK_SIGNING_KEY="${SLACK_SIGNING_KEY}" \
  -e AWS_REGION="us-east-1" \
  -e AWS_ACCESS_KEY_ID="local" \
  -e AWS_SECRET_ACCESS_KEY="local" \
  cloudops-agent:test
```

**Note**: For Bedrock API calls, you'll need real AWS credentials instead of `local` values.

### Workflow 4: Test with Real AWS Resources

```bash
# Use real AWS DynamoDB and Bedrock (not local)
export CONVERSATION_ID="conv-..."
export CONVERSATIONS_TABLE="cloudops-conversations-dev"
export CONVERSATION_HISTORY_TABLE="cloudops-conversation-history-dev"
# Don't set AWS_ENDPOINT_URL to use real AWS

./scripts/run-agent-local.sh
```

## Testing Without Slack

If you don't have Slack credentials or want to test without posting to Slack:

### Option 1: Mock Slack Client

Modify `pkg/slack/client.go` temporarily to log instead of posting:

```go
func (c *Client) PostMessage(ctx context.Context, channelID string, options ...slack.MsgOption) (*slack.Message, error) {
    // Extract message text for logging
    log.Printf("MOCK: Would post to channel %s: %+v", channelID, options)
    return &slack.Message{Timestamp: time.Now().String()}, nil
}
```

### Option 2: Use Environment Flag

Add a test mode to your config:

```bash
export CLOUDOPS_TEST_MODE=true
```

Then check this in the agent code to skip Slack calls.

## Debugging Tips

### View DynamoDB Data

1. **Web UI**: Visit http://localhost:8001
2. **AWS CLI**:
   ```bash
   # List conversations
   aws dynamodb scan \
     --endpoint-url http://localhost:8000 \
     --table-name cloudops-conversations-local

   # Get specific conversation
   aws dynamodb get-item \
     --endpoint-url http://localhost:8000 \
     --table-name cloudops-conversations-local \
     --key '{"conversation_id": {"S": "conv-..."}}'

   # View conversation history
   aws dynamodb query \
     --endpoint-url http://localhost:8000 \
     --table-name cloudops-conversation-history-local \
     --key-condition-expression "conversation_id = :id" \
     --expression-attribute-values '{":id": {"S": "conv-..."}}'
   ```

### Enable Debug Logging

```bash
export LOG_LEVEL=debug
go run ./cmd/agent
```

### Test Bedrock Locally

```bash
# Test if Bedrock is accessible
aws bedrock list-foundation-models \
  --query 'modelSummaries[?contains(modelId, `claude`)].modelId'

# Test invoke
aws bedrock-runtime invoke-model \
  --model-id anthropic.claude-3-5-sonnet-20241022-v2:0 \
  --body '{"anthropic_version":"bedrock-2023-05-31","messages":[{"role":"user","content":"Hello"}],"max_tokens":100}' \
  --region us-east-1 \
  /tmp/response.json

cat /tmp/response.json | jq .
```

## Common Issues

### Agent Exits Immediately

**Problem**: Agent completes but doesn't handle conversation.

**Solution**: The agent code has TODOs - you need to implement the conversation loop. Check `cmd/agent/main.go:54-67`.

### Can't Connect to DynamoDB

**Problem**: `connection refused` error.

**Solution**: Make sure docker-compose is running:
```bash
docker-compose ps
docker-compose up -d
```

### Slack Token Invalid

**Problem**: `invalid_auth` from Slack API.

**Solution**:
1. Check token starts with `xoxb-`
2. Verify bot is installed in workspace
3. Check token hasn't expired

### Bedrock Access Denied

**Problem**: `AccessDeniedException` from Bedrock.

**Solution**:
1. Enable model in AWS Console → Bedrock → Model Access
2. Check IAM permissions include `bedrock:InvokeModel`
3. Verify you're in a supported region

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CONVERSATION_ID` | Yes | - | ID of conversation to process |
| `AWS_REGION` | No | `us-east-1` | AWS region |
| `AWS_ENDPOINT_URL` | No | - | DynamoDB endpoint (use for local) |
| `CONVERSATIONS_TABLE` | No | `cloudops-conversations` | Conversations table name |
| `CONVERSATION_HISTORY_TABLE` | No | `cloudops-conversation-history` | History table name |
| `SLACK_BOT_TOKEN` | Yes | - | Slack bot OAuth token |
| `SLACK_SIGNING_KEY` | Yes | - | Slack signing secret |
| `BEDROCK_MODEL_ID` | No | `anthropic.claude-3-5-sonnet-20241022-v2:0` | Bedrock model to use |
| `INACTIVITY_TIMEOUT_MINUTES` | No | `30` | Minutes before timeout |

## Next Steps

1. **Implement Conversation Loop**: Edit `cmd/agent/main.go` to handle multi-turn conversations
2. **Add Bedrock Integration**: Use the bedrock client to process messages with Claude
3. **Implement Tool Calling**: Add AWS operation tools (EC2, RDS, CloudWatch, etc.)
4. **Add Tests**: Create unit tests for conversation handling
5. **Test in ECS**: Deploy to dev environment and test with Step Functions

## Clean Up

```bash
# Stop local services
docker-compose down

# Remove test data (optional - it's in-memory anyway)
docker-compose down -v
```
