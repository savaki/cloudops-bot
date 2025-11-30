#!/bin/bash
set -e

# Setup local DynamoDB tables for testing
# Run this after starting docker-compose up

ENDPOINT="http://localhost:8000"
REGION="us-east-1"

echo "======================================================================"
echo "Setting up Local DynamoDB Tables"
echo "======================================================================"
echo "Endpoint: ${ENDPOINT}"
echo ""

# Check if DynamoDB is running
if ! curl -s ${ENDPOINT} > /dev/null 2>&1; then
  echo "❌ DynamoDB Local is not running"
  echo ""
  echo "Start it with:"
  echo "  docker-compose up -d"
  echo ""
  exit 1
fi

echo "✅ DynamoDB Local is running"
echo ""

# Create Conversations table
echo "Creating cloudops-conversations-local table..."
aws dynamodb create-table \
  --endpoint-url ${ENDPOINT} \
  --region ${REGION} \
  --table-name cloudops-conversations-local \
  --attribute-definitions \
    AttributeName=conversation_id,AttributeType=S \
    AttributeName=channel_id,AttributeType=S \
    AttributeName=status,AttributeType=S \
  --key-schema \
    AttributeName=conversation_id,KeyType=HASH \
  --global-secondary-indexes \
    '[
      {
        "IndexName": "channel-index",
        "KeySchema": [
          {"AttributeName": "channel_id", "KeyType": "HASH"}
        ],
        "Projection": {"ProjectionType": "ALL"},
        "ProvisionedThroughput": {
          "ReadCapacityUnits": 5,
          "WriteCapacityUnits": 5
        }
      },
      {
        "IndexName": "status-index",
        "KeySchema": [
          {"AttributeName": "status", "KeyType": "HASH"}
        ],
        "Projection": {"ProjectionType": "ALL"},
        "ProvisionedThroughput": {
          "ReadCapacityUnits": 5,
          "WriteCapacityUnits": 5
        }
      }
    ]' \
  --provisioned-throughput \
    ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --no-cli-pager > /dev/null 2>&1

echo "✅ Conversations table created"

# Create Conversation History table
echo "Creating cloudops-conversation-history-local table..."
aws dynamodb create-table \
  --endpoint-url ${ENDPOINT} \
  --region ${REGION} \
  --table-name cloudops-conversation-history-local \
  --attribute-definitions \
    AttributeName=conversation_id,AttributeType=S \
    AttributeName=timestamp,AttributeType=N \
  --key-schema \
    AttributeName=conversation_id,KeyType=HASH \
    AttributeName=timestamp,KeyType=RANGE \
  --provisioned-throughput \
    ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --no-cli-pager > /dev/null 2>&1

echo "✅ Conversation History table created"

echo ""
echo "======================================================================"
echo "✅ Local DynamoDB Setup Complete"
echo "======================================================================"
echo ""
echo "Tables created:"
echo "  - cloudops-conversations-local"
echo "  - cloudops-conversation-history-local"
echo ""
echo "DynamoDB Admin UI: http://localhost:8001"
echo ""
echo "Next steps:"
echo "  1. Create test conversation: ./scripts/create-test-conversation.sh"
echo "  2. Run agent locally: ./scripts/run-agent-local.sh <conversation-id>"
echo ""
