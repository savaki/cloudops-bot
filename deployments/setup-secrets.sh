#!/bin/bash
set -e

# Setup AWS Systems Manager Parameter Store parameters for CloudOps Bot
# Usage: ./setup-secrets.sh [environment] [options]
#
# Options:
#   --slack-bot-token <token>     Slack bot token (xoxb-...)
#   --slack-signing-key <key>     Slack signing secret
#   --interactive                 Prompt for missing values
#   --update                      Update existing parameters instead of failing

Env=${1:-dev}
AWS_REGION=${AWS_REGION:-us-east-1}
INTERACTIVE=false
UPDATE=false
SLACK_BOT_TOKEN=""
SLACK_SIGNING_KEY=""

# Parse arguments
shift || true
while [[ $# -gt 0 ]]; do
  case $1 in
    --slack-bot-token)
      SLACK_BOT_TOKEN="$2"
      shift 2
      ;;
    --slack-signing-key)
      SLACK_SIGNING_KEY="$2"
      shift 2
      ;;
    --interactive)
      INTERACTIVE=true
      shift
      ;;
    --update)
      UPDATE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "======================================================================"
echo "CloudOps Bot - Parameter Store Setup"
echo "======================================================================"
echo "Environment: ${Env}"
echo "Region: ${AWS_REGION}"
echo ""

# Function to read secret interactively
read_secret() {
  local prompt=$1
  local var_name=$2
  local current_value="${!var_name}"

  if [ -n "$current_value" ]; then
    return
  fi

  if [ "$INTERACTIVE" = true ]; then
    echo -n "${prompt}: "
    read -r value
    eval "${var_name}='${value}'"
  fi
}

# Interactive mode - prompt for missing values
if [ "$INTERACTIVE" = true ]; then
  echo "Enter secrets (or press Enter to skip):"
  echo ""

  read_secret "Slack Bot Token (xoxb-...)" SLACK_BOT_TOKEN
  read_secret "Slack Signing Secret" SLACK_SIGNING_KEY

  echo ""
fi

# Function to create or update parameter
manage_parameter() {
  local param_name=$1
  local param_value=$2
  local description=$3

  if [ -z "$param_value" ]; then
    echo "⏭️  Skipping ${param_name} (no value provided)"
    return
  fi

  # Check if parameter exists
  if aws ssm get-parameter \
    --name "${param_name}" \
    --region ${AWS_REGION} >/dev/null 2>&1; then

    if [ "$UPDATE" = true ]; then
      echo "🔄 Updating ${param_name}..."
      aws ssm put-parameter \
        --name "${param_name}" \
        --value "${param_value}" \
        --type "SecureString" \
        --overwrite \
        --region ${AWS_REGION} >/dev/null
      echo "   ✅ Updated"
    else
      echo "⚠️  ${param_name} already exists (use --update to overwrite)"
    fi
  else
    echo "➕ Creating ${param_name}..."
    aws ssm put-parameter \
      --name "${param_name}" \
      --description "${description}" \
      --value "${param_value}" \
      --type "SecureString" \
      --region ${AWS_REGION} >/dev/null
    echo "   ✅ Created"
  fi
}

echo "======================================================================"
echo "Managing Parameters"
echo "======================================================================"

# Create/update parameters
manage_parameter \
  "/cloudops/${Env}/slack-bot-token" \
  "${SLACK_BOT_TOKEN}" \
  "Slack bot OAuth token for CloudOps Bot"

manage_parameter \
  "/cloudops/${Env}/slack-signing-key" \
  "${SLACK_SIGNING_KEY}" \
  "Slack signing secret for webhook validation"

echo ""
echo "======================================================================"
echo "Verification"
echo "======================================================================"

# Verify all required parameters exist
ALL_EXIST=true
for param in /cloudops/${Env}/slack-bot-token /cloudops/${Env}/slack-signing-key; do
  if aws ssm get-parameter \
    --name ${param} \
    --region ${AWS_REGION} >/dev/null 2>&1; then
    echo "✅ ${param}"
  else
    echo "❌ ${param} - NOT FOUND"
    ALL_EXIST=false
  fi
done

echo ""

if [ "$ALL_EXIST" = true ]; then
  echo "======================================================================"
  echo "Success! All parameters are configured."
  echo "======================================================================"
  echo ""
  echo "💰 Cost savings: Using Parameter Store (FREE) instead of Secrets Manager (~\$1.20/month)"
  echo ""
  echo "Next steps:"
  echo "  1. Deploy infrastructure: ./deployments/deploy-stack.sh ${Env}"
  echo "  2. Build agent image: ./deployments/build-agent.sh ${Env}"
  echo ""
else
  echo "======================================================================"
  echo "Some parameters are missing!"
  echo "======================================================================"
  echo ""
  echo "Run this script again with one of these options:"
  echo ""
  echo "Option 1 - Interactive mode:"
  echo "  ./deployments/setup-secrets.sh ${Env} --interactive"
  echo ""
  echo "Option 2 - Command line arguments:"
  echo "  ./deployments/setup-secrets.sh ${Env} \\"
  echo "    --slack-bot-token xoxb-your-token \\"
  echo "    --slack-signing-key your-signing-secret"
  echo ""
  echo "Option 3 - Environment variables:"
  echo "  export SLACK_BOT_TOKEN=xoxb-..."
  echo "  export SLACK_SIGNING_KEY=..."
  echo "  ./deployments/setup-secrets.sh ${Env} \\"
  echo "    --slack-bot-token \"\$SLACK_BOT_TOKEN\" \\"
  echo "    --slack-signing-key \"\$SLACK_SIGNING_KEY\""
  echo ""
  exit 1
fi
