#!/bin/bash
set -e

# Deploy CloudOps Bot complete infrastructure stack
# Usage: ./deploy-stack.sh [environment]

ENV=${1:-dev}
AWS_REGION=${AWS_REGION:-us-east-1}
STACK_NAME="cloudops-${ENV}"

# Get the script directory to use absolute paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATE_PATH="${PROJECT_ROOT}/infrastructure/cloudformation/cloudops-stack.yaml"

echo "======================================================================"
echo "CloudOps Bot Deployment"
echo "======================================================================"
echo "Environment: ${ENV}"
echo "Region: ${AWS_REGION}"
echo "Stack Name: ${STACK_NAME}"
echo "Template: ${TEMPLATE_PATH}"
echo ""

# Validate template exists
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "❌ CloudFormation template not found: ${TEMPLATE_PATH}"
  exit 1
fi

echo "======================================================================"
echo "Checking Prerequisites"
echo "======================================================================"

# Check if parameters exist
echo "Checking AWS Systems Manager Parameter Store..."
for param in /cloudops/${ENV}/slack-bot-token /cloudops/${ENV}/slack-signing-key; do
  if aws ssm get-parameter --name ${param} --region ${AWS_REGION} >/dev/null 2>&1; then
    echo "   ✅ ${param}"
  else
    echo "   ❌ ${param} - NOT FOUND"
    echo ""
    echo "Please create the parameters with:"
    echo "  ./deployments/setup-secrets.sh ${ENV} --interactive"
    echo ""
    echo "Or manually:"
    echo "  aws ssm put-parameter --name ${param} --value 'your-value' --type SecureString --region ${AWS_REGION}"
    exit 1
  fi
done

echo ""
echo "Checking Bedrock Model Access..."
BEDROCK_MODEL="anthropic.claude-3-5-sonnet-20241022-v2:0"
if aws bedrock list-foundation-models --region ${AWS_REGION} --query "modelSummaries[?modelId=='${BEDROCK_MODEL}'].modelId" --output text 2>/dev/null | grep -q "${BEDROCK_MODEL}"; then
  echo "   ✅ ${BEDROCK_MODEL} is available"
else
  echo "   ⚠️  ${BEDROCK_MODEL} - Model not found or access not enabled"
  echo ""
  echo "You may need to request model access in the Bedrock console:"
  echo "   1. Go to https://console.aws.amazon.com/bedrock/home?region=${AWS_REGION}#/modelaccess"
  echo "   2. Click 'Modify model access'"
  echo "   3. Enable 'Claude 3.5 Sonnet v2' from Anthropic"
  echo "   4. Submit and wait for approval (usually instant)"
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo ""
echo "======================================================================"
echo "Deploying CloudFormation Stack"
echo "======================================================================"

# Check if stack exists and its status
STACK_STATUS=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --region ${AWS_REGION} \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "DOES_NOT_EXIST")

if [ "$STACK_STATUS" == "DOES_NOT_EXIST" ]; then
  echo "Stack does not exist. Creating..."
  OPERATION="create-stack"
elif [ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ]; then
  echo "❌ Stack is in ROLLBACK_COMPLETE state. You must delete it first:"
  echo "   aws cloudformation delete-stack --stack-name ${STACK_NAME} --region ${AWS_REGION}"
  echo "   aws cloudformation wait stack-delete-complete --stack-name ${STACK_NAME} --region ${AWS_REGION}"
  exit 1
elif [[ "$STACK_STATUS" == *"IN_PROGRESS"* ]]; then
  echo "❌ Stack operation already in progress (${STACK_STATUS}). Please wait for it to complete."
  exit 1
else
  echo "Stack exists (${STACK_STATUS}). Updating..."
  OPERATION="update-stack"
fi

# Deploy stack
if [ "$OPERATION" == "create-stack" ]; then
  aws cloudformation create-stack \
    --stack-name ${STACK_NAME} \
    --template-body file://${TEMPLATE_PATH} \
    --parameters \
      ParameterKey=Environment,ParameterValue=${ENV} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region ${AWS_REGION}

  echo ""
  echo "Waiting for stack creation to complete..."
  aws cloudformation wait stack-create-complete \
    --stack-name ${STACK_NAME} \
    --region ${AWS_REGION}
else
  # Try to update, but handle "No updates" gracefully
  UPDATE_OUTPUT=$(aws cloudformation update-stack \
    --stack-name ${STACK_NAME} \
    --template-body file://${TEMPLATE_PATH} \
    --parameters \
      ParameterKey=Environment,ParameterValue=${ENV} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region ${AWS_REGION} 2>&1) || UPDATE_EXIT_CODE=$?

  if [ ${UPDATE_EXIT_CODE:-0} -ne 0 ]; then
    if echo "$UPDATE_OUTPUT" | grep -q "No updates are to be performed"; then
      echo ""
      echo "✅ No updates needed - stack is already up to date"
    else
      echo "❌ Update failed:"
      echo "$UPDATE_OUTPUT"
      exit ${UPDATE_EXIT_CODE}
    fi
  else
    echo ""
    echo "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete \
      --stack-name ${STACK_NAME} \
      --region ${AWS_REGION}
  fi
fi

echo ""
echo "======================================================================"
echo "Deployment Complete!"
echo "======================================================================"

# Get outputs
echo ""
echo "Stack Outputs:"
aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table \
  --region ${AWS_REGION}

echo ""
echo "======================================================================"
echo "Next Steps"
echo "======================================================================"
echo ""
echo "1. Build and push the agent Docker image:"
echo "   ./deployments/build-agent.sh ${ENV} ${AWS_REGION}"
echo ""
echo "2. Deploy the Lambda function code:"
echo "   ./deployments/package-lambda.sh ${ENV} slack-handler"
echo ""
echo "3. Configure Slack webhook URL:"
WEBHOOK_URL=$(aws cloudformation describe-stacks \
  --stack-name ${STACK_NAME} \
  --query 'Stacks[0].Outputs[?OutputKey==`SlackWebhookUrl`].OutputValue' \
  --output text \
  --region ${AWS_REGION} 2>/dev/null)

if [ -n "$WEBHOOK_URL" ] && [ "$WEBHOOK_URL" != "None" ]; then
  echo "   ${WEBHOOK_URL}"
else
  echo "   ⚠️  Could not retrieve webhook URL. Check stack outputs manually."
fi
echo ""
