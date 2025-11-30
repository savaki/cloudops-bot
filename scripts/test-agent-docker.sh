#!/bin/bash
set -e

# Test the agent Docker container locally with local DynamoDB
# Usage: ./scripts/test-agent-docker.sh [conversation-id]
#
# If no conversation-id is provided, creates a new test conversation

DOCKER_NETWORK="cloudops-bot_cloudops-local"
IMAGE_NAME="cloudops-agent:test"
ENDPOINT="http://localhost:8000"

echo "======================================================================"
echo "Testing Agent Docker Container Locally"
echo "======================================================================"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "❌ Docker is not running"
  echo ""
  echo "Please start Docker and retry:"
  echo "  - macOS: Start Docker Desktop"
  echo "  - Linux: sudo systemctl start docker"
  echo ""
  exit 1
fi

# Check if DynamoDB Local is running
if ! curl -s ${ENDPOINT} > /dev/null 2>&1; then
  echo "❌ DynamoDB Local is not running"
  echo ""
  echo "Start it with:"
  echo "  make local-setup"
  echo ""
  exit 1
fi

echo "✅ Prerequisites met"
echo ""

# Build Docker image
echo "======================================================================"
echo "Building Docker Image"
echo "======================================================================"
echo ""

docker build -f deployments/Dockerfile.agent -t ${IMAGE_NAME} .

echo ""
echo "✅ Docker image built: ${IMAGE_NAME}"
echo ""

# Get or create conversation ID
if [ -n "$1" ]; then
  CONVERSATION_ID="$1"
  echo "Using provided conversation ID: ${CONVERSATION_ID}"
else
  echo "======================================================================"
  echo "Creating Test Conversation"
  echo "======================================================================"
  echo ""

  # Extract conversation ID from the script output
  CONV_OUTPUT=$(./scripts/create-test-conversation.sh)
  CONVERSATION_ID=$(echo "$CONV_OUTPUT" | grep "Conversation ID:" | tail -1 | awk '{print $3}')

  if [ -z "$CONVERSATION_ID" ]; then
    echo "❌ Failed to create test conversation"
    exit 1
  fi

  echo "✅ Created conversation: ${CONVERSATION_ID}"
fi

echo ""

# Check for Slack credentials
if [ -z "$SLACK_BOT_TOKEN" ]; then
  echo "⚠️  SLACK_BOT_TOKEN not set"
  echo "   Messages won't actually post to Slack"
  echo ""
  echo "Set it with:"
  echo "  export SLACK_BOT_TOKEN=xoxb-..."
  echo ""
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
  echo ""
fi

# Run the container
echo "======================================================================"
echo "Running Agent Container"
echo "======================================================================"
echo ""
echo "Configuration:"
echo "  Image: ${IMAGE_NAME}"
echo "  Network: ${DOCKER_NETWORK}"
echo "  Conversation ID: ${CONVERSATION_ID}"
echo "  DynamoDB Endpoint: http://dynamodb-local:8000"
echo "  Slack Token: ${SLACK_BOT_TOKEN:0:15}..."
echo ""

docker run --rm \
  --network ${DOCKER_NETWORK} \
  -e CONVERSATION_ID="${CONVERSATION_ID}" \
  -e AWS_ENDPOINT_URL="http://dynamodb-local:8000" \
  -e CONVERSATIONS_TABLE="cloudops-conversations-local" \
  -e CONVERSATION_HISTORY_TABLE="cloudops-conversation-history-local" \
  -e SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN}" \
  -e SLACK_SIGNING_KEY="${SLACK_SIGNING_KEY}" \
  -e AWS_REGION="${AWS_REGION:-us-east-1}" \
  -e AWS_ACCESS_KEY_ID="local" \
  -e AWS_SECRET_ACCESS_KEY="local" \
  ${IMAGE_NAME}

echo ""
echo "======================================================================"
echo "✅ Container Execution Complete"
echo "======================================================================"
echo ""
echo "View conversation in DynamoDB Admin: http://localhost:8001"
echo "Conversation ID: ${CONVERSATION_ID}"
echo ""
