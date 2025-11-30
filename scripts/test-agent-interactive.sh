#!/bin/bash
set -e

# Interactive agent testing - simulates back-and-forth conversation
# This script helps you test the agent with multiple messages

ENDPOINT="http://localhost:8000"
REGION="us-east-1"
CONVERSATIONS_TABLE="cloudops-conversations-local"
HISTORY_TABLE="cloudops-conversation-history-local"

echo "======================================================================"
echo "CloudOps Bot - Interactive Agent Testing"
echo "======================================================================"
echo ""

# Check prerequisites
if ! curl -s ${ENDPOINT} > /dev/null 2>&1; then
  echo "❌ DynamoDB Local is not running"
  echo "   Start with: docker-compose up -d && ./scripts/setup-local-dynamodb.sh"
  exit 1
fi

if [ -z "$SLACK_BOT_TOKEN" ]; then
  echo "⚠️  SLACK_BOT_TOKEN not set. Messages won't actually post to Slack."
  echo "   Set it with: export SLACK_BOT_TOKEN=xoxb-..."
  echo ""
fi

# Create a test conversation
echo "Creating test conversation..."
CHANNEL_ID="C01234567"
USER_ID="U01234567"

TIMESTAMP=$(date +%s)
RANDOM_PART=$(openssl rand -hex 10)
CONVERSATION_ID="conv-${TIMESTAMP}${RANDOM_PART}"
TTL=$(($(date +%s) + 604800))
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

aws dynamodb put-item \
  --endpoint-url ${ENDPOINT} \
  --region ${REGION} \
  --table-name ${CONVERSATIONS_TABLE} \
  --item "{
    \"conversation_id\": {\"S\": \"${CONVERSATION_ID}\"},
    \"channel_id\": {\"S\": \"${CHANNEL_ID}\"},
    \"user_id\": {\"S\": \"${USER_ID}\"},
    \"status\": {\"S\": \"active\"},
    \"initial_command\": {\"S\": \"Start testing\"},
    \"created_at\": {\"S\": \"${CREATED_AT}\"},
    \"last_heartbeat\": {\"S\": \"${CREATED_AT}\"},
    \"ttl\": {\"N\": \"${TTL}\"}
  }" \
  --no-cli-pager > /dev/null

echo "✅ Conversation created: ${CONVERSATION_ID}"
echo ""

# Function to add a message to conversation history
add_message() {
  local role=$1
  local content=$2
  local timestamp=$(date +%s%N | cut -b1-13)  # Milliseconds

  aws dynamodb put-item \
    --endpoint-url ${ENDPOINT} \
    --region ${REGION} \
    --table-name ${HISTORY_TABLE} \
    --item "{
      \"conversation_id\": {\"S\": \"${CONVERSATION_ID}\"},
      \"timestamp\": {\"N\": \"${timestamp}\"},
      \"role\": {\"S\": \"${role}\"},
      \"content\": {\"S\": \"${content}\"},
      \"ttl\": {\"N\": \"${TTL}\"}
    }" \
    --no-cli-pager > /dev/null
}

# Function to view conversation history
view_history() {
  echo ""
  echo "Conversation History:"
  echo "======================================================================"

  aws dynamodb query \
    --endpoint-url ${ENDPOINT} \
    --region ${REGION} \
    --table-name ${HISTORY_TABLE} \
    --key-condition-expression "conversation_id = :conv_id" \
    --expression-attribute-values "{\":conv_id\": {\"S\": \"${CONVERSATION_ID}\"}}" \
    --query 'Items[*].[role.S, content.S]' \
    --output text | while read -r role content; do
      if [ "$role" == "user" ]; then
        echo "👤 User: $content"
      else
        echo "🤖 Assistant: $content"
      fi
    done

  echo "======================================================================"
  echo ""
}

# Interactive loop
echo "Interactive Testing Mode"
echo "Commands:"
echo "  - Type a message to add as user input"
echo "  - Type 'run' to run the agent"
echo "  - Type 'history' to view conversation history"
echo "  - Type 'exit' to quit"
echo ""

while true; do
  echo -n "> "
  read -r input

  case "$input" in
    exit|quit)
      echo "Exiting..."
      break
      ;;

    history)
      view_history
      ;;

    run)
      echo ""
      echo "Running agent..."
      export CONVERSATION_ID="${CONVERSATION_ID}"
      export AWS_ENDPOINT_URL="${ENDPOINT}"
      export CONVERSATIONS_TABLE="${CONVERSATIONS_TABLE}"
      export CONVERSATION_HISTORY_TABLE="${HISTORY_TABLE}"
      export AWS_REGION="${REGION}"

      go run ./cmd/agent
      echo ""
      ;;

    "")
      continue
      ;;

    *)
      add_message "user" "$input"
      echo "✅ Added user message: $input"
      ;;
  esac
done

echo ""
echo "Test conversation ID: ${CONVERSATION_ID}"
echo "View in DynamoDB Admin: http://localhost:8001"
