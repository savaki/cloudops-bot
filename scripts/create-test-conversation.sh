#!/bin/bash
set -e

# Create a test conversation in local DynamoDB
# Usage: ./create-test-conversation.sh [channel-id] [user-id] [initial-command]

ENDPOINT="http://localhost:8000"
REGION="us-east-1"
TABLE_NAME="cloudops-conversations-local"

CHANNEL_ID=${1:-"C01234567"}
USER_ID=${2:-"U01234567"}
INITIAL_COMMAND=${3:-"What EC2 instances are running?"}

# Generate conversation ID (simplified ULID)
TIMESTAMP=$(date +%s)
RANDOM_PART=$(openssl rand -hex 10)
CONVERSATION_ID="conv-${TIMESTAMP}${RANDOM_PART}"

# Calculate TTL (7 days from now)
TTL=$(($(date +%s) + 604800))

# Current timestamp in ISO 8601
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "======================================================================"
echo "Creating Test Conversation"
echo "======================================================================"
echo "Conversation ID: ${CONVERSATION_ID}"
echo "Channel ID: ${CHANNEL_ID}"
echo "User ID: ${USER_ID}"
echo "Initial Command: ${INITIAL_COMMAND}"
echo ""

# Create conversation item
aws dynamodb put-item \
  --endpoint-url ${ENDPOINT} \
  --region ${REGION} \
  --table-name ${TABLE_NAME} \
  --item "{
    \"conversation_id\": {\"S\": \"${CONVERSATION_ID}\"},
    \"channel_id\": {\"S\": \"${CHANNEL_ID}\"},
    \"user_id\": {\"S\": \"${USER_ID}\"},
    \"status\": {\"S\": \"pending\"},
    \"initial_command\": {\"S\": \"${INITIAL_COMMAND}\"},
    \"created_at\": {\"S\": \"${CREATED_AT}\"},
    \"last_heartbeat\": {\"S\": \"${CREATED_AT}\"},
    \"ttl\": {\"N\": \"${TTL}\"}
  }" \
  --no-cli-pager > /dev/null

echo "✅ Test conversation created"
echo ""
echo "To run the agent with this conversation:"
echo "  export CONVERSATION_ID=${CONVERSATION_ID}"
echo "  ./scripts/run-agent-local.sh"
echo ""
echo "Or in one command:"
echo "  ./scripts/run-agent-local.sh ${CONVERSATION_ID}"
echo ""
echo "======================================================================"
echo "Conversation ID: ${CONVERSATION_ID}"
echo "======================================================================"
