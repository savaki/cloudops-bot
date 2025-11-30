#!/bin/bash
set -e

# Run the agent locally with local DynamoDB
# Usage: ./run-agent-local.sh [conversation-id]

CONVERSATION_ID=${1:-$CONVERSATION_ID}

if [ -z "$CONVERSATION_ID" ]; then
  echo "❌ CONVERSATION_ID required"
  echo ""
  echo "Usage:"
  echo "  ./scripts/run-agent-local.sh <conversation-id>"
  echo ""
  echo "Or create a test conversation first:"
  echo "  ./scripts/create-test-conversation.sh"
  echo ""
  exit 1
fi

echo "======================================================================"
echo "Running Agent Locally"
echo "======================================================================"
echo "Conversation ID: ${CONVERSATION_ID}"
echo ""

# Check if local DynamoDB is running
if ! curl -s http://localhost:8000 > /dev/null 2>&1; then
  echo "❌ DynamoDB Local is not running"
  echo ""
  echo "Start it with:"
  echo "  docker-compose up -d"
  echo "  ./scripts/setup-local-dynamodb.sh"
  echo ""
  exit 1
fi

# Load Slack credentials from Parameter Store (or use env vars)
if [ -z "$SLACK_BOT_TOKEN" ]; then
  echo "Getting Slack credentials from Parameter Store..."
  ENV=${ENV:-dev}
  export SLACK_BOT_TOKEN=$(aws ssm get-parameter \
    --name "/cloudops/${ENV}/slack-bot-token" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

  export SLACK_SIGNING_KEY=$(aws ssm get-parameter \
    --name "/cloudops/${ENV}/slack-signing-key" \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text 2>/dev/null || echo "")

  if [ -z "$SLACK_BOT_TOKEN" ]; then
    echo "⚠️  SLACK_BOT_TOKEN not found in Parameter Store"
    echo "    Set it manually: export SLACK_BOT_TOKEN=xoxb-..."
    echo ""
  fi
fi

# Set environment variables for local testing
export CONVERSATION_ID="${CONVERSATION_ID}"
export AWS_ENDPOINT_URL="http://localhost:8000"  # For local DynamoDB
export CONVERSATIONS_TABLE="cloudops-conversations-local"
export CONVERSATION_HISTORY_TABLE="cloudops-conversation-history-local"
export AWS_REGION="${AWS_REGION:-us-east-1}"

# Build and run the agent
echo "Building agent..."
go build -o bin/agent ./cmd/agent

echo ""
echo "======================================================================"
echo "Starting Agent"
echo "======================================================================"
echo ""
echo "Environment:"
echo "  CONVERSATION_ID: ${CONVERSATION_ID}"
echo "  AWS_ENDPOINT_URL: ${AWS_ENDPOINT_URL}"
echo "  CONVERSATIONS_TABLE: ${CONVERSATIONS_TABLE}"
echo "  CONVERSATION_HISTORY_TABLE: ${CONVERSATION_HISTORY_TABLE}"
echo "  SLACK_BOT_TOKEN: ${SLACK_BOT_TOKEN:0:15}..."
echo ""

./bin/agent
