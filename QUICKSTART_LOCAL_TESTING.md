# Quick Start: Local Agent Testing

Test the CloudOps agent locally with simulated back-and-forth conversations.

## Prerequisites

- Docker installed and running
- Go 1.21+ installed
- AWS CLI configured
- Slack bot token (optional for full testing)

## 1. Start Local Infrastructure

```bash
make local-setup
```

This starts local DynamoDB and creates the required tables.

**What it does:**
- Starts DynamoDB Local on http://localhost:8000
- Starts DynamoDB Admin UI on http://localhost:8001
- Creates `cloudops-conversations-local` table
- Creates `cloudops-conversation-history-local` table

## 2. Set Slack Credentials

**First time?** See [docs/SLACK_SETUP.md](docs/SLACK_SETUP.md) for how to create a Slack app and get these credentials.

```bash
# Option A: Load from AWS Parameter Store (if already deployed)
ENV=dev
export SLACK_BOT_TOKEN=$(aws ssm get-parameter \
  --name "/cloudops/${ENV}/slack-bot-token" \
  --with-decryption --query 'Parameter.Value' --output text)

export SLACK_SIGNING_KEY=$(aws ssm get-parameter \
  --name "/cloudops/${ENV}/slack-signing-key" \
  --with-decryption --query 'Parameter.Value' --output text)

# Option B: Set manually (get these from Slack app settings)
export SLACK_BOT_TOKEN="xoxb-your-token-here"
export SLACK_SIGNING_KEY="your-signing-secret"
```

**Where to get these:**
- **SLACK_BOT_TOKEN**: Slack App → OAuth & Permissions → Bot User OAuth Token
- **SLACK_SIGNING_KEY**: Slack App → Basic Information → Signing Secret

See the [Slack Setup Guide](docs/SLACK_SETUP.md) for detailed instructions.

## 3. Run Interactive Testing

```bash
make local-test
```

This opens an interactive shell for testing:

```
> What EC2 instances are running in us-east-1?
✅ Added user message: What EC2 instances are running in us-east-1?

> run
Running agent...
[Agent executes and processes the message]

> Show me CloudWatch logs for instance i-1234567
✅ Added user message: Show me CloudWatch logs for instance i-1234567

> run
Running agent...
[Agent executes with full conversation history]

> history
Conversation History:
======================================================================
👤 User: What EC2 instances are running in us-east-1?
🤖 Assistant: [Response]
👤 User: Show me CloudWatch logs for instance i-1234567
🤖 Assistant: [Response]
======================================================================

> exit
```

## Alternative: Manual Testing

### Step 1: Create a test conversation

```bash
./scripts/create-test-conversation.sh "C01234567" "U01234567" "List EC2 instances"
```

This outputs a `CONVERSATION_ID` like `conv-1234567890abcdef`.

### Step 2: Run the agent

```bash
./scripts/run-agent-local.sh conv-1234567890abcdef
```

## Testing the Docker Container

### Option 1: Automated Script (Recommended)

```bash
# Build, create conversation, and run container - all in one command
make local-docker
```

Or use the script directly:
```bash
./scripts/test-agent-docker.sh
```

### Option 2: Rebuild and Test (for rapid iteration)

```bash
# Quick rebuild and test - perfect for development
make local-rebuild
```

This is faster than `make local-docker` because it builds quietly and reuses the previous conversation.

### Option 3: Manual Steps

```bash
# Build the container
docker build -f deployments/Dockerfile.agent -t cloudops-agent:test .

# Create a test conversation
CONV_ID=$(./scripts/create-test-conversation.sh | grep "Conversation ID:" | tail -1 | awk '{print $3}')

# Run the container
docker run --rm \
  --network cloudops-bot_cloudops-local \
  -e CONVERSATION_ID="${CONV_ID}" \
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

### Test with Existing Conversation

```bash
# Run with specific conversation ID
./scripts/test-agent-docker.sh conv-1234567890abcdef
```

## View Data in DynamoDB

### Web UI
Visit http://localhost:8001 to browse tables and data visually.

### CLI
```bash
# List all conversations
aws dynamodb scan \
  --endpoint-url http://localhost:8000 \
  --table-name cloudops-conversations-local

# View specific conversation
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

## Simulating Back-and-Forth Conversations

The interactive testing mode (`make local-test`) is the easiest way:

1. **Type a user message** - adds to conversation history as user
2. **Type `run`** - executes the agent with all history
3. **Agent processes and responds** - adds response to history
4. **Type another message** - continues the conversation
5. **Type `history`** - view full conversation thread
6. **Repeat** - simulate multi-turn conversations

### Example Session

```bash
$ make local-test

> Check if RDS database prod-mysql is running
✅ Added user message

> run
🤖 Processing...
✅ Agent posted response to Slack

> What's the current CPU usage?
✅ Added user message

> run
🤖 Processing with conversation context...
✅ Agent posted response to Slack

> history
👤 User: Check if RDS database prod-mysql is running
🤖 Assistant: The database prod-mysql is running with status "available"...
👤 User: What's the current CPU usage?
🤖 Assistant: Current CPU usage for prod-mysql is 23.4%...
```

## Testing with Real AWS (Not Local DynamoDB)

To test with real AWS DynamoDB and Bedrock:

```bash
# Don't set AWS_ENDPOINT_URL
unset AWS_ENDPOINT_URL

# Use real table names
export CONVERSATIONS_TABLE="cloudops-conversations-dev"
export CONVERSATION_HISTORY_TABLE="cloudops-conversation-history-dev"

# Run agent
./scripts/run-agent-local.sh conv-real-conversation-id
```

## Clean Up

```bash
# Stop local services
make local-stop

# Stop and remove all data
make local-clean
```

## Troubleshooting

**Agent exits immediately**: The current agent is a stub. You need to implement the conversation loop in `cmd/agent/main.go`.

**Can't connect to DynamoDB**: Run `make local-start` to ensure DynamoDB Local is running.

**Slack authentication fails**: Check that `SLACK_BOT_TOKEN` is set and valid.

**Bedrock access denied**: Make sure you have real AWS credentials and Bedrock model access enabled.

## Next Steps

1. **Implement the agent logic** - Edit `cmd/agent/main.go:54-78` to add conversation handling
2. **Add Bedrock integration** - Use the bedrock client to process messages with Claude
3. **Implement tool calling** - Add AWS operation tools (EC2, RDS, CloudWatch, etc.)
4. **Add unit tests** - Create tests for conversation handling
5. **Test in ECS** - Deploy and test with Step Functions

## Full Documentation

See [docs/LOCAL_TESTING.md](docs/LOCAL_TESTING.md) for complete details, advanced workflows, and debugging tips.
