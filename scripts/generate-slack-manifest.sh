#!/bin/bash
set -e

# Generate Slack app manifest from deployed CloudOps Bot instance
# Usage: ./scripts/generate-slack-manifest.sh [environment] [output-file]
#
# This script:
# - Reads the webhook URL from deployed CloudFormation stack
# - Generates a complete Slack app manifest
# - Outputs to slack-app-manifest-{env}.yaml

ENV=${1:-dev}
OUTPUT_FILE=${2:-slack-app-manifest-${ENV}.yaml}
STACK_NAME="cloudops-${ENV}"
AWS_REGION=${AWS_REGION:-us-east-1}

echo "======================================================================"
echo "Generating Slack App Manifest"
echo "======================================================================"
echo "Environment: ${ENV}"
echo "Stack: ${STACK_NAME}"
echo "Region: ${AWS_REGION}"
echo "Output: ${OUTPUT_FILE}"
echo ""

# Check if stack exists and get webhook URL
echo "Checking CloudFormation stack..."
if ! aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${AWS_REGION} &>/dev/null; then
  echo "⚠️  Stack ${STACK_NAME} not found in ${AWS_REGION}"
  echo ""
  echo "Options:"
  echo "  1. Deploy first: ./deployments/deploy-stack.sh ${ENV}"
  echo "  2. Generate manifest without webhook URL (manual configuration needed)"
  echo ""
  read -p "Generate manifest without webhook URL? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
  WEBHOOK_URL=""
else
  echo "✅ Stack found"

  # Get webhook URL from CloudFormation outputs
  WEBHOOK_URL=$(aws cloudformation describe-stacks \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`SlackWebhookUrl`].OutputValue' \
    --output text 2>/dev/null || echo "")

  if [ -n "$WEBHOOK_URL" ] && [ "$WEBHOOK_URL" != "None" ]; then
    echo "✅ Webhook URL: ${WEBHOOK_URL}"
  else
    echo "⚠️  Webhook URL not found in stack outputs"
    WEBHOOK_URL=""
  fi
fi

echo ""

# Prompt for app configuration (with defaults)
echo "App Configuration (press Enter for defaults):"
echo ""

read -p "App Name [CloudOps Bot (${ENV})]: " APP_NAME
APP_NAME=${APP_NAME:-"CloudOps Bot (${ENV})"}

read -p "Display Name [CloudOps Bot]: " DISPLAY_NAME
DISPLAY_NAME=${DISPLAY_NAME:-"CloudOps Bot"}

read -p "Short Description [AI-powered AWS troubleshooting assistant]: " SHORT_DESC
SHORT_DESC=${SHORT_DESC:-"AI-powered AWS troubleshooting assistant that helps debug cloud infrastructure issues"}

read -p "Background Color [#2c3e50]: " BG_COLOR
BG_COLOR=${BG_COLOR:-"#2c3e50"}

echo ""
echo "Generating manifest..."

# Generate the manifest YAML
cat > "${OUTPUT_FILE}" <<EOF
display_information:
  name: ${APP_NAME}
  description: ${SHORT_DESC}
  background_color: "${BG_COLOR}"
  long_description: |-
    CloudOps Bot is an intelligent assistant that helps you troubleshoot AWS infrastructure
    issues directly from Slack. Ask questions about EC2 instances, RDS databases, CloudWatch
    logs, Lambda functions, ECS services, and more.

    Powered by Claude AI with read-only AWS access for safe operations.

    Environment: ${ENV}

    Features:
    - Natural language queries about AWS resources
    - CloudWatch log analysis
    - EC2 instance status and troubleshooting
    - RDS database health checks
    - Lambda function monitoring
    - ECS task and service diagnostics
    - Conversational interface with context retention
    - Secure read-only AWS access

features:
  app_home:
    home_tab_enabled: true
    messages_tab_enabled: true
    messages_tab_read_only_enabled: false
  bot_user:
    display_name: ${DISPLAY_NAME}
    always_online: true

oauth_config:
  scopes:
    bot:
      - app_mentions:read
      - channels:history
      - channels:read
      - chat:write
      - im:history
      - users:read

settings:
  event_subscriptions:
EOF

# Add webhook URL if available
if [ -n "$WEBHOOK_URL" ]; then
  cat >> "${OUTPUT_FILE}" <<EOF
    request_url: ${WEBHOOK_URL}
EOF
else
  cat >> "${OUTPUT_FILE}" <<EOF
    # Add your webhook URL after deployment
    # Get it with: aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs[?OutputKey==\`SlackWebhookUrl\`].OutputValue' --output text
    request_url: ""
EOF
fi

# Add bot events
cat >> "${OUTPUT_FILE}" <<EOF
    bot_events:
      - app_mention
  interactivity:
    is_enabled: false
  org_deploy_enabled: false
  socket_mode_enabled: false
  token_rotation_enabled: false
EOF

echo ""
echo "======================================================================"
echo "✅ Manifest Generated"
echo "======================================================================"
echo "File: ${OUTPUT_FILE}"
echo ""

if [ -n "$WEBHOOK_URL" ]; then
  echo "✅ Webhook URL is pre-configured"
  echo ""
  echo "Next steps:"
  echo "  1. Go to https://api.slack.com/apps"
  echo "  2. 'Create New App' → 'From an app manifest'"
  echo "  3. Paste contents of ${OUTPUT_FILE}"
  echo "  4. Click 'Create'"
  echo "  5. Install to workspace"
  echo "  6. Copy Bot Token and Signing Secret"
  echo "  7. Store credentials:"
  echo "     ./deployments/setup-secrets.sh ${ENV} \\"
  echo "       --slack-bot-token 'xoxb-...' \\"
  echo "       --slack-signing-key '...'"
else
  echo "⚠️  Webhook URL not set (will need manual configuration)"
  echo ""
  echo "Next steps:"
  echo "  1. Deploy infrastructure: ./deployments/deploy-stack.sh ${ENV}"
  echo "  2. Re-run this script to get webhook URL"
  echo "  3. Or manually add webhook URL to manifest after deployment"
fi

echo ""
echo "Manifest contents:"
echo "======================================================================"
cat "${OUTPUT_FILE}"
echo "======================================================================"
echo ""
